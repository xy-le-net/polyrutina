// ═══════════════════════════════════════════════════════════════════
// routine_layer.dart — routine layer.
//
// Holds the list of routines and their blocks.
//
// Journal. Registered in JournalLayer for the routine kind.
//
// Cache invalidation. _loadFromFile returns true when the file
// exists but its schema is older than the required version (or the
// file is malformed). In that case the layer has no data, and the
// persisted journal mark for it would short-circuit pump — the
// routine list would stay empty forever. To avoid that, init calls
// journal.clearMark('routine') after register, so the next pump
// replays the journal for this layer only. Other layers keep their
// marks and are not re-processed.
//
// Transactions. Actions producing several entries at once
// (completing a routine, starting a block while stopping the others,
// switching blocks between routines, clearing the date together with
// the notice) are wrapped in journal.transaction.
//
// Cache. Written with a 200 ms debounce. currentRoutineId is
// reconstructed on startup from the first running block. Cache
// writes go through atomicWriteJson.
//
// Notice interval. Stored as noticeBeforeSec + noticeSet, journalled
// as `set_notice` and `clear_notice`. Clearing the date clears the
// notice in the same transaction. Old caches that carried
// planned_seconds are dropped by the schema bump (cache schema 2)
// and rebuilt from the journal.
//
// Overdue scheduler. The layer does not format notifications and
// does not talk to the platform. Instead it exposes a slot of type
// OverdueScheduler; main.dart attaches a real implementation after
// init. Every mutation that can affect the deferred notice — date
// change, notice change, completion, deletion — calls _refreshSchedule
// or _cancelSchedule. When the slot is null, these calls are no-ops;
// the next application startup scans every routine and reschedules
// from scratch.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'atomic_json.dart';
import 'database.dart';
import 'field_layer.dart';
import 'journal_layer.dart';
import 'journal_types.dart';
import 'routine.dart';
import 'trace_layer.dart';

/// Hook for the deferred-notice scheduler.
abstract class OverdueScheduler {
  void refresh(Routine routine);
  void cancel(int routineId);
}

class RoutineLayer extends ChangeNotifier {
  static const int _schemaVersion = 2;

  List<Routine> routines = [];

  int? currentRoutineId;
  String? lastActiveBlockKind;

  OverdueScheduler? _scheduler;

  set scheduler(OverdueScheduler? s) => _scheduler = s;

  final Map<String, int> _sourceKeyIndex = {};
  final Map<int, Set<int>> _nodeRoutinesIndex = {};
  final Set<int> _runningRoutineIds = {};

  TraceLayer? _traces;
  FieldLayer? _field;

  File? _file;
  Timer? _saveTimer;

  List<Routine> get routinesNewestFirst {
    final copy = List<Routine>.from(routines);
    copy.sort((a, b) => b.id.compareTo(a.id));
    return copy;
  }

  bool get anyRunning => _runningRoutineIds.isNotEmpty;

  bool get anyOverdue {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (final r in routines) {
      if (r.isOverdueAt(now)) return true;
    }
    return false;
  }

  ({List<Routine> active, List<Routine> done}) get groupedByTicker {
    final active = <Routine>[];
    final done = <Routine>[];
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (final r in routines) {
      if (r.completed) {
        done.add(r);
      } else {
        active.add(r);
      }
    }

    int sortPulse(Routine r) => r.lastPulseAt ?? r.lastActionAt;

    active.sort((a, b) {
      final aOd = a.isOverdueAt(now);
      final bOd = b.isOverdueAt(now);
      if (aOd && !bOd) return -1;
      if (!aOd && bOd) return 1;
      final aRun = a.runningBlock != null;
      final bRun = b.runningBlock != null;
      if (aRun && !bRun) return -1;
      if (!aRun && bRun) return 1;
      if (aRun && bRun) {
        final at = a.runningBlock?.startedAt ?? 0;
        final bt = b.runningBlock?.startedAt ?? 0;
        return bt.compareTo(at);
      }
      return sortPulse(b).compareTo(sortPulse(a));
    });
    done.sort((a, b) => sortPulse(b).compareTo(sortPulse(a)));
    return (active: active, done: done);
  }

  Future<void> init(
    JournalLayer journal,
    TraceLayer traces,
    FieldLayer field,
  ) async {
    _traces = traces;
    _field = field;
    final dir = await getApplicationDocumentsDirectory();
    _file = File(p.join(dir.path, 'routine_layer.json'));

    // Cache may be stale, malformed, or empty; in every such case
    // the journal has to be replayed for this layer.
    final needsRebuild = await _loadFromFile();

    journal.register(
      name: 'routine',
      types: [JournalType.routine],
      apply: _applyEntry,
      reset: _resetMemory,
    );

    if (needsRebuild) {
      journal.clearMark('routine');
      // Explicit pump, awaited here: watchAll's initial emission
      // would also trigger pump, but the UI asks for routines right
      // after init, and a scheduled pump may run a frame later. This
      // await guarantees the list is populated before the first
      // build sees it.
      await journal.pump();
    }

    notifyListeners();
  }

  // ─── Scheduler refresh helpers ───
  void _refreshSchedule(Routine r) {
    try {
      _scheduler?.refresh(r);
    } catch (_) {}
  }

  void _cancelSchedule(int routineId) {
    try {
      _scheduler?.cancel(routineId);
    } catch (_) {}
  }

  void _rebuildIndices() {
    _sourceKeyIndex.clear();
    _nodeRoutinesIndex.clear();
    _runningRoutineIds.clear();

    for (final r in routines) {
      if (r.sourceKey.isNotEmpty) {
        _sourceKeyIndex[r.sourceKey] = r.id;
      }
      for (final nodeId in r.fieldParents) {
        _nodeRoutinesIndex.putIfAbsent(nodeId, () => {}).add(r.id);
      }
      if (r.runningBlock != null) {
        _runningRoutineIds.add(r.id);
      }
    }
  }

  void _indexAdd(Routine r) {
    if (r.sourceKey.isNotEmpty) {
      _sourceKeyIndex[r.sourceKey] = r.id;
    }
    for (final nodeId in r.fieldParents) {
      _nodeRoutinesIndex.putIfAbsent(nodeId, () => {}).add(r.id);
    }
    if (r.runningBlock != null) {
      _runningRoutineIds.add(r.id);
    }
  }

  void _indexRemove(Routine r) {
    if (r.sourceKey.isNotEmpty && _sourceKeyIndex[r.sourceKey] == r.id) {
      _sourceKeyIndex.remove(r.sourceKey);
    }
    for (final nodeId in r.fieldParents) {
      final set = _nodeRoutinesIndex[nodeId];
      if (set != null) {
        set.remove(r.id);
        if (set.isEmpty) _nodeRoutinesIndex.remove(nodeId);
      }
    }
    _runningRoutineIds.remove(r.id);
  }

  void migrateFieldParents() {
    final rootId = _field?.rootId;
    if (rootId == null) return;
    var changed = false;
    for (final r in routines) {
      if (r.fieldParents.isEmpty) {
        r.fieldParents = [rootId];
        changed = true;
      }
    }
    if (changed) {
      _rebuildIndices();
      _scheduleSave();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  // ─── Cache ───
  // Returns true when the journal must be replayed for this layer.
  //
  // Three cases yield true: stale schema, malformed file, and — the
  // subtle one — an EMPTY routine list in a valid cache. The last
  // case handles the failure loop seen in the field: a failed start
  // wrote a schema-valid cache with no routines; on every next
  // launch that cache was trusted, the mark from journal_layer.json
  // pointed at the end of the journal, the pump found nothing to
  // read, and the routines stayed empty forever, even after an
  // import. Treating an empty cache as «needs replay» breaks the
  // loop: the cost is one full journal pass on a genuinely empty
  // state, which is bounded by journal size and harmless.
  Future<bool> _loadFromFile() async {
    if (_file == null || !await _file!.exists()) return false;
    try {
      final raw = await _file!.readAsString();
      final data = jsonDecode(raw) as Map<String, dynamic>;

      final schema = (data['schema'] as num?)?.toInt() ?? 0;
      if (schema < _schemaVersion) {
        return true;
      }

      final r = data['routines'];
      if (r is List) {
        final loaded = <Routine>[];
        for (final e in r) {
          if (e is! Map) continue;
          try {
            loaded.add(Routine.fromJson(Map<String, dynamic>.from(e)));
          } catch (_) {}
        }
        routines = loaded;
      }
      lastActiveBlockKind = data['last_active_block_kind'] as String?;

      for (final r in routines) {
        if (r.runningBlock != null) {
          currentRoutineId = r.id;
          break;
        }
      }
      _rebuildIndices();
      // Empty but schema-valid cache is treated as «needs replay».
      return routines.isEmpty;
    } catch (_) {
      // Malformed cache — rebuild from journal.
      return true;
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 200), () {
      _saveToFile();
    });
  }

  Future<void> _saveToFile() async {
    final target = _file;
    if (target == null) return;
    final data = <String, dynamic>{
      'schema': _schemaVersion,
      'routines': routines.map((r) => r.toJson()).toList(),
      'last_active_block_kind': lastActiveBlockKind,
    };
    await atomicWriteJson(target, data);
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _saveToFile();
  }

  void _applyEntry(JournalData e) {
    try {
      final data = jsonDecode(e.body) as Map<String, dynamic>;
      final action = data['action'] as String?;
      switch (action) {
        case 'reset':
          routines = [];
          currentRoutineId = null;
          lastActiveBlockKind = null;
          _sourceKeyIndex.clear();
          _nodeRoutinesIndex.clear();
          _runningRoutineIds.clear();
          break;
        case 'snapshot':
          final raw = data['routine'];
          if (raw is Map<String, dynamic>) {
            try {
              final r = Routine.fromJson(raw);
              final idx = routines.indexWhere((x) => x.id == r.id);
              if (idx >= 0) {
                _indexRemove(routines[idx]);
                routines[idx] = r;
                _indexAdd(r);
              } else {
                routines.add(r);
                _indexAdd(r);
              }
            } catch (_) {}
          }
          break;
        case 'create':
          final bodyId = (data['routine'] as num?)?.toInt();
          final id = bodyId ?? e.id;
          final sourceKey = data['source_key'] as String? ?? '';
          final createdAt = (data['created_at'] as num?)?.toInt();
          final fieldParents =
              (data['field_parents'] as List?)
                  ?.map((x) => (x as num).toInt())
                  .toList() ??
              [];
          if (findRoutine(id) == null) {
            final r = Routine.create(
              id,
              at: e.time,
              sourceKey: sourceKey,
              createdAt: createdAt,
              fieldParents: fieldParents,
            );
            routines.add(r);
            _indexAdd(r);
          }
          break;
        case 'rename':
          final id = (data['routine'] as num).toInt();
          final r = findRoutine(id);
          if (r != null) {
            r.name = data['name'] as String? ?? '';
            r.lastActionAt = e.time;
          }
          break;
        case 'delete':
          final id = (data['routine'] as num).toInt();
          final r = findRoutine(id);
          if (r != null) _indexRemove(r);
          routines.removeWhere((r) => r.id == id);
          if (currentRoutineId == id) currentRoutineId = null;
          break;
        case 'flags':
          final id = (data['routine'] as num).toInt();
          final r = findRoutine(id);
          if (r != null) {
            r.flags = (data['value'] as num?)?.toInt() ?? r.flags;
            r.lastActionAt = e.time;
          }
          break;
        case 'complete':
          final id = (data['routine'] as num).toInt();
          final v = data['value'] as bool? ?? true;
          final r = findRoutine(id);
          if (r != null) {
            r.completed = v;
            r.completedAt = v ? e.time : null;
            r.lastActionAt = e.time;
            if (v) _runningRoutineIds.remove(id);
          }
          break;
        case 'set_schedule':
          final id = (data['routine'] as num).toInt();
          final r = findRoutine(id);
          if (r != null) {
            final at = (data['at'] as num?)?.toInt();
            r.scheduledAt = at;
            if (at == null) {
              r.noticeBeforeSec = 0;
              r.noticeSet = false;
            }
            r.lastActionAt = e.time;
          }
          break;
        case 'set_notice':
          final id = (data['routine'] as num).toInt();
          final r = findRoutine(id);
          if (r != null) {
            r.noticeBeforeSec = (data['seconds'] as num?)?.toInt() ?? 0;
            r.noticeSet = true;
            r.lastActionAt = e.time;
          }
          break;
        case 'clear_notice':
          final id = (data['routine'] as num).toInt();
          final r = findRoutine(id);
          if (r != null) {
            r.noticeBeforeSec = 0;
            r.noticeSet = false;
            r.lastActionAt = e.time;
          }
          break;
        case 'attach_field':
          final id = (data['routine'] as num).toInt();
          final nodeId = (data['node'] as num).toInt();
          final r = findRoutine(id);
          if (r != null && !r.fieldParents.contains(nodeId)) {
            r.fieldParents.add(nodeId);
            _nodeRoutinesIndex.putIfAbsent(nodeId, () => {}).add(id);
            r.lastActionAt = e.time;
          }
          break;
        case 'detach_field':
          final id = (data['routine'] as num).toInt();
          final nodeId = (data['node'] as num).toInt();
          final r = findRoutine(id);
          if (r != null) {
            r.fieldParents.remove(nodeId);
            final set = _nodeRoutinesIndex[nodeId];
            if (set != null) {
              set.remove(id);
              if (set.isEmpty) _nodeRoutinesIndex.remove(nodeId);
            }
            r.lastActionAt = e.time;
          }
          break;
        case 'start_block':
          final id = (data['routine'] as num).toInt();
          final kind = data['block'] as String?;
          final at = (data['at'] as num?)?.toInt() ?? e.time;
          final r = findRoutine(id);
          if (r != null && kind != null) {
            r.blockOf(kind)?.start(at: at);
            r.lastActionAt = at;
            r.lastPulseAt = at;
            r.lastBlockKind = kind;
            r.completed = false;
            r.completedAt = null;
            currentRoutineId = id;
            lastActiveBlockKind = kind;
            _runningRoutineIds.add(id);
          }
          break;
        case 'pause_block':
          final id = (data['routine'] as num).toInt();
          final kind = data['block'] as String?;
          final at = (data['at'] as num?)?.toInt() ?? e.time;
          final r = findRoutine(id);
          if (r != null && kind != null) {
            r.blockOf(kind)?.pause(at: at);
            r.lastActionAt = at;
            r.lastPulseAt = at;
            if (r.runningBlock == null) {
              _runningRoutineIds.remove(id);
              if (currentRoutineId == id) currentRoutineId = null;
            }
          }
          break;
        case 'set_block_time':
          final id = (data['routine'] as num).toInt();
          final kind = data['block'] as String?;
          final secs = (data['seconds'] as num?)?.toInt();
          final r = findRoutine(id);
          if (r != null && kind != null && secs != null) {
            r.blockOf(kind)?.setEditedTime(secs);
            r.lastActionAt = e.time;
          }
          break;
      }
    } catch (_) {}
  }

  void _resetMemory() {
    routines = [];
    currentRoutineId = null;
    lastActiveBlockKind = null;
    _sourceKeyIndex.clear();
    _nodeRoutinesIndex.clear();
    _runningRoutineIds.clear();
    notifyListeners();
  }

  Future<Routine?> duplicateRoutine(JournalLayer journal, int sourceId) async {
    final src = findRoutine(sourceId);
    if (src == null) return null;

    int? newId;
    await journal.transaction(() async {
      final r = await createRoutine(journal, fieldParents: src.fieldParents);
      newId = r.id;

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final snapshot = Routine(
        id: r.id,
        name: src.name,
        createdAt: now,
        lastActionAt: now,
        blocks: RoutineBlock.kinds.map((k) => RoutineBlock(kind: k)).toList(),
        flags: src.flags,
        scheduledAt: src.scheduledAt,
        noticeBeforeSec: src.noticeBeforeSec,
        noticeSet: src.noticeSet,
        fieldParents: src.fieldParents,
      );

      await journal.log(
        type: JournalType.routine,
        body: jsonEncode({'action': 'snapshot', 'routine': snapshot.toJson()}),
      );

      final traces = _traces;
      if (traces != null) {
        const copySlots = ['note', 'prep', 'closeout'];
        for (final slot in copySlots) {
          final t = traces.findFirstBySlot(src.id, slot);
          if (t == null) continue;

          if (t.kind == TraceKind.text && t.text.isNotEmpty) {
            await traces.createText(
              journal,
              slot: slot,
              text: t.text,
              parents: [r.id],
            );
          }

          if (t.kind == TraceKind.checklist) {
            final items = t.items
                .where((e) => e.text.trim().isNotEmpty)
                .map((e) => e.text)
                .toList();
            if (items.isNotEmpty) {
              await traces.createChecklist(
                journal,
                slot: slot,
                items: items,
                parents: [r.id],
              );
            }
          }
        }
      }
    });

    if (newId == null) return null;
    final result = findRoutine(newId!);
    if (result != null) _refreshSchedule(result);
    return result;
  }

  Future<Routine> createRoutine(
    JournalLayer journal, {
    String sourceKey = '',
    int? createdAt,
    List<int>? fieldParents,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    List<int> parentList = fieldParents ?? [];
    if (parentList.isEmpty) {
      final active = _field?.activeFieldId;
      final root = _field?.rootId;
      final target = active ?? root;
      if (target != null) parentList = [target];
    }

    final bodyMap = <String, dynamic>{
      'action': 'create',
      'field_parents': parentList,
    };
    if (sourceKey.isNotEmpty) bodyMap['source_key'] = sourceKey;
    if (createdAt != null) bodyMap['created_at'] = createdAt;
    final id = await journal.log(
      type: JournalType.routine,
      body: jsonEncode(bodyMap),
    );
    if (findRoutine(id) == null) {
      final r = Routine.create(
        id,
        sourceKey: sourceKey,
        createdAt: createdAt,
        fieldParents: parentList,
      );
      r.lastActionAt = now;
      routines.add(r);
      _indexAdd(r);
    }
    _scheduleSave();
    notifyListeners();
    return findRoutine(id)!;
  }

  Future<void> writeSnapshot(JournalLayer journal, Routine r) async {
    await journal.log(
      type: JournalType.routine,
      body: jsonEncode({'action': 'snapshot', 'routine': r.toJson()}),
    );
    _scheduleSave();
    notifyListeners();
  }

  Future<void> renameRoutine(JournalLayer journal, int id, String name) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final r = findRoutine(id);
    if (r == null) return;
    r.name = name;
    r.lastActionAt = now;
    await journal.log(
      type: JournalType.routine,
      body: '{"action":"rename","routine":$id,"name":${jsonEncode(name)}}',
    );
    _scheduleSave();
    notifyListeners();
  }

  Future<void> deleteRoutine(JournalLayer journal, int id) async {
    final r = findRoutine(id);
    if (r != null) _indexRemove(r);
    routines.removeWhere((r) => r.id == id);
    if (currentRoutineId == id) currentRoutineId = null;
    await journal.log(
      type: JournalType.routine,
      body: '{"action":"delete","routine":$id}',
    );
    _cancelSchedule(id);
    _scheduleSave();
    notifyListeners();
  }

  Future<void> setFlags(JournalLayer journal, int id, int flags) async {
    final r = findRoutine(id);
    if (r == null) return;
    r.flags = flags;
    r.lastActionAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await journal.log(
      type: JournalType.routine,
      body: '{"action":"flags","routine":$id,"value":$flags}',
    );
    _scheduleSave();
    notifyListeners();
  }

  Future<void> setSchedule(JournalLayer journal, int id, int? at) async {
    final r = findRoutine(id);
    if (r == null) return;
    if (r.scheduledAt == at) return;

    await journal.transaction(() async {
      r.scheduledAt = at;
      r.lastActionAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await journal.log(
        type: JournalType.routine,
        body: '{"action":"set_schedule","routine":$id,"at":${at ?? 'null'}}',
      );
      if (at == null) {
        r.noticeBeforeSec = 0;
        r.noticeSet = false;
        await journal.log(
          type: JournalType.routine,
          body: '{"action":"clear_notice","routine":$id}',
        );
      }
    });
    _refreshSchedule(r);
    _scheduleSave();
    notifyListeners();
  }

  Future<void> setNotice(JournalLayer journal, int id, int seconds) async {
    final r = findRoutine(id);
    if (r == null) return;
    if (r.scheduledAt == null) return;
    if (r.noticeSet && r.noticeBeforeSec == seconds) return;
    r.noticeBeforeSec = seconds;
    r.noticeSet = true;
    r.lastActionAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await journal.log(
      type: JournalType.routine,
      body: '{"action":"set_notice","routine":$id,"seconds":$seconds}',
    );
    _refreshSchedule(r);
    _scheduleSave();
    notifyListeners();
  }

  Future<void> clearNotice(JournalLayer journal, int id) async {
    final r = findRoutine(id);
    if (r == null) return;
    if (!r.noticeSet) return;
    r.noticeBeforeSec = 0;
    r.noticeSet = false;
    r.lastActionAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await journal.log(
      type: JournalType.routine,
      body: '{"action":"clear_notice","routine":$id}',
    );
    _refreshSchedule(r);
    _scheduleSave();
    notifyListeners();
  }

  Future<void> attachToField(
    JournalLayer journal,
    int routineId,
    int nodeId,
  ) async {
    final r = findRoutine(routineId);
    if (r == null) return;
    if (r.fieldParents.contains(nodeId)) return;
    r.fieldParents.add(nodeId);
    _nodeRoutinesIndex.putIfAbsent(nodeId, () => {}).add(routineId);
    r.lastActionAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await journal.log(
      type: JournalType.routine,
      body: '{"action":"attach_field","routine":$routineId,"node":$nodeId}',
    );
    _scheduleSave();
    notifyListeners();
  }

  Future<void> detachFromField(
    JournalLayer journal,
    int routineId,
    int nodeId,
  ) async {
    final r = findRoutine(routineId);
    if (r == null) return;
    if (!r.fieldParents.contains(nodeId)) return;
    r.fieldParents.remove(nodeId);
    final set = _nodeRoutinesIndex[nodeId];
    if (set != null) {
      set.remove(routineId);
      if (set.isEmpty) _nodeRoutinesIndex.remove(nodeId);
    }
    r.lastActionAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await journal.log(
      type: JournalType.routine,
      body: '{"action":"detach_field","routine":$routineId,"node":$nodeId}',
    );
    _scheduleSave();
    notifyListeners();
  }

  Future<void> setCompleted(JournalLayer journal, int id, bool value) async {
    final r = findRoutine(id);
    if (r == null) return;
    if (r.completed == value) return;

    if (value) {
      await journal.transaction(() async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        for (final b in r.blocks) {
          if (b.isRunning) {
            b.pause(at: now);
            await journal.log(
              type: JournalType.routine,
              body:
                  '{"action":"pause_block","routine":$id,'
                  '"block":"${b.kind}","at":$now}',
            );
          }
        }
        if (currentRoutineId == id) currentRoutineId = null;
        _runningRoutineIds.remove(id);
        r.completed = true;
        r.completedAt = now;
        r.lastActionAt = now;
        await journal.log(
          type: JournalType.routine,
          body: '{"action":"complete","routine":$id,"value":true}',
        );
      });
    } else {
      r.completed = false;
      r.completedAt = null;
      r.lastActionAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await journal.log(
        type: JournalType.routine,
        body: '{"action":"complete","routine":$id,"value":false}',
      );
    }
    _refreshSchedule(r);
    _scheduleSave();
    notifyListeners();
  }

  Future<void> setBlockTime(
    JournalLayer journal,
    int routineId,
    String kind,
    int seconds,
  ) async {
    final r = findRoutine(routineId);
    if (r == null) return;
    final b = r.blockOf(kind);
    if (b == null || b.isRunning) return;
    b.setEditedTime(seconds);
    r.lastActionAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await journal.log(
      type: JournalType.routine,
      body:
          '{"action":"set_block_time","routine":$routineId,'
          '"block":"$kind","seconds":$seconds}',
    );
    _scheduleSave();
    notifyListeners();
  }

  Future<void> toggleBlock(
    JournalLayer journal,
    int routineId,
    String kind, {
    bool mutex = true,
    bool mutexSlots = true,
  }) async {
    final r = findRoutine(routineId);
    if (r == null) return;
    final b = r.blockOf(kind);
    if (b == null) return;
    if (b.isRunning) {
      await pauseBlock(journal, routineId, kind);
    } else {
      await startBlock(
        journal,
        routineId,
        kind,
        mutex: mutex,
        mutexSlots: mutexSlots,
      );
    }
  }

  Future<void> startBlock(
    JournalLayer journal,
    int routineId,
    String kind, {
    bool mutex = true,
    bool mutexSlots = true,
  }) async {
    final r = findRoutine(routineId);
    if (r == null) return;

    await journal.transaction(() async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      if (mutex) {
        final runningIds = List<int>.from(_runningRoutineIds);
        for (final rId in runningIds) {
          final other = findRoutine(rId);
          if (other == null) continue;
          for (final b in other.blocks) {
            if (b.isRunning) {
              b.pause(at: now);
              await journal.log(
                type: JournalType.routine,
                body:
                    '{"action":"pause_block","routine":${other.id},'
                    '"block":"${b.kind}","at":$now}',
              );
            }
          }
          _runningRoutineIds.remove(rId);
        }
      } else if (mutexSlots) {
        for (final b in r.blocks) {
          if (b.kind != kind && b.isRunning) {
            b.pause(at: now);
            await journal.log(
              type: JournalType.routine,
              body:
                  '{"action":"pause_block","routine":$routineId,'
                  '"block":"${b.kind}","at":$now}',
            );
          }
        }
        if (r.runningBlock == null) {
          _runningRoutineIds.remove(routineId);
        }
      }

      final target = r.blockOf(kind);
      if (target != null && !target.isRunning) {
        target.start(at: now);
        await journal.log(
          type: JournalType.routine,
          body:
              '{"action":"start_block","routine":$routineId,'
              '"block":"$kind","at":$now}',
        );
      }
      r.lastActionAt = now;
      r.lastPulseAt = now;
      r.lastBlockKind = kind;
      r.completed = false;
      r.completedAt = null;
      currentRoutineId = routineId;
      lastActiveBlockKind = kind;
      _runningRoutineIds.add(routineId);
    });
    _scheduleSave();
    notifyListeners();
  }

  Future<void> pauseBlock(
    JournalLayer journal,
    int routineId,
    String kind,
  ) async {
    final r = findRoutine(routineId);
    if (r == null) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final b = r.blockOf(kind);
    if (b == null || !b.isRunning) return;
    b.pause(at: now);
    r.lastActionAt = now;
    r.lastPulseAt = now;
    if (r.runningBlock == null) {
      _runningRoutineIds.remove(routineId);
      if (currentRoutineId == routineId) currentRoutineId = null;
    }
    await journal.log(
      type: JournalType.routine,
      body:
          '{"action":"pause_block","routine":$routineId,'
          '"block":"$kind","at":$now}',
    );
    _scheduleSave();
    notifyListeners();
  }

  Routine? findRoutine(int id) {
    for (final r in routines) {
      if (r.id == id) return r;
    }
    return null;
  }

  Routine? findRoutineBySourceKey(String key) {
    if (key.isEmpty) return null;
    final id = _sourceKeyIndex[key];
    return id != null ? findRoutine(id) : null;
  }

  List<Routine> routinesForNode(int nodeId) {
    final ids = _nodeRoutinesIndex[nodeId];
    if (ids == null || ids.isEmpty) return [];

    final out = <Routine>[];
    for (final r in routines) {
      if (ids.contains(r.id)) out.add(r);
    }
    return out;
  }

  Future<void> resetAll() async {
    if (_file != null && await _file!.exists()) {
      await _file!.delete();
    }
    routines = [];
    currentRoutineId = null;
    lastActiveBlockKind = null;
    _sourceKeyIndex.clear();
    _nodeRoutinesIndex.clear();
    _runningRoutineIds.clear();
    await _saveToFile();
    notifyListeners();
  }
}
