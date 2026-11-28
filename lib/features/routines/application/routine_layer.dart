import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:polyrutina/core/data/journal_layer.dart';
import 'package:polyrutina/core/domain/journal_types.dart';
import 'package:polyrutina/core/domain/journal_entry.dart';
import 'package:polyrutina/features/routines/application/routine_access.dart';
import 'package:polyrutina/features/routines/application/routine_dependencies.dart';
import 'package:polyrutina/features/routines/application/routine_repository.dart';
import 'package:polyrutina/features/routines/domain/routine.dart';

/// Refreshes or cancels a routine's deferred notice.
abstract class OverdueScheduler {
  void refresh(Routine routine);
  void cancel(int routineId);
}

class RoutineLayer extends ChangeNotifier implements RoutineAccess {
  RoutineLayer({
    required RoutineRepository repository,
    required RoutineFieldContextReader fieldContext,
    required RoutineTraceCopier copyTraces,
  }) : _repository = repository,
       _fieldContext = fieldContext,
       _copyTraces = copyTraces;

  final RoutineRepository _repository;
  final RoutineFieldContextReader _fieldContext;
  final RoutineTraceCopier _copyTraces;

  @override
  List<Routine> routines = [];

  @override
  int? currentRoutineId;
  @override
  String? lastActiveBlockKind;

  OverdueScheduler? _scheduler;

  set scheduler(OverdueScheduler? s) => _scheduler = s;

  final Map<String, int> _sourceKeyIndex = {};
  final Map<int, Set<int>> _nodeRoutinesIndex = {};
  final Map<int, Routine> _routineIndex = {};
  final Set<int> _runningRoutineIds = {};

  Timer? _saveTimer;

  List<Routine> get routinesNewestFirst {
    final copy = List<Routine>.from(routines);
    copy.sort((a, b) => b.id.compareTo(a.id));
    return copy;
  }

  @override
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

  Future<void> init(JournalLayer journal) async {
    final cache = await _repository.load();
    routines = cache.routines.toList();
    lastActiveBlockKind = cache.lastActiveBlockKind;
    for (final routine in routines) {
      if (routine.runningBlock != null) {
        currentRoutineId = routine.id;
        break;
      }
    }
    _rebuildIndices();

    journal.register(
      name: 'routine',
      types: [JournalType.routine],
      apply: _applyEntry,
      reset: _resetMemory,
    );

    if (cache.needsJournalReplay) {
      journal.clearMark('routine');
      await journal.pump();
    }

    notifyListeners();
  }

  void _refreshSchedule(Routine r) {
    try {
      _scheduler?.refresh(r);
    } catch (e, st) {
      debugPrint('Failed to refresh notification for routine ${r.id}: $e\n$st');
    }
  }

  void _cancelSchedule(int routineId) {
    try {
      _scheduler?.cancel(routineId);
    } catch (e, st) {
      debugPrint(
        'Failed to cancel notification for routine $routineId: $e\n$st',
      );
    }
  }

  void _rebuildIndices() {
    _sourceKeyIndex.clear();
    _nodeRoutinesIndex.clear();
    _routineIndex.clear();
    _runningRoutineIds.clear();

    for (final r in routines) {
      _routineIndex[r.id] = r;
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
    _routineIndex[r.id] = r;
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
    _routineIndex.remove(r.id);
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
    final rootId = _fieldContext().rootId;
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

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 200), _saveToFile);
  }

  Future<void> _saveToFile() async {
    await _repository.save(
      routines: routines.toList(),
      lastActiveBlockKind: lastActiveBlockKind,
    );
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _saveToFile();
  }

  void _applyEntry(JournalEntry e) {
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
          _routineIndex.clear();
          _runningRoutineIds.clear();
          break;
        case 'snapshot':
          final raw = data['routine'];
          if (raw is Map<String, dynamic>) {
            try {
              final r = Routine.fromJson(raw);
              final idx = routines.indexWhere((x) => x.id == r.id);
              if (idx >= 0) {
                final old = routines[idx];
                _indexRemove(old);
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
            if (v) {
              r.completeAt(e.time);
            } else {
              r.reopenAt(e.time);
            }
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
            if (r.startBlockAt(kind, at)) {
              currentRoutineId = id;
              lastActiveBlockKind = kind;
              _runningRoutineIds.add(id);
            }
          }
          break;
        case 'pause_block':
          final id = (data['routine'] as num).toInt();
          final kind = data['block'] as String?;
          final at = (data['at'] as num?)?.toInt() ?? e.time;
          final r = findRoutine(id);
          if (r != null && kind != null) {
            if (r.pauseBlockAt(kind, at) && r.runningBlock == null) {
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
    _routineIndex.clear();
    _runningRoutineIds.clear();
    notifyListeners();
  }

  @override
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

      await _copyTraces(journal, src.id, r.id, const [
        'note',
        'prep',
        'closeout',
      ]);
    });

    if (newId == null) return null;
    final result = findRoutine(newId!);
    if (result != null) _refreshSchedule(result);
    return result;
  }

  @override
  Future<Routine> createRoutine(
    JournalLayer journal, {
    String sourceKey = '',
    int? createdAt,
    List<int>? fieldParents,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    List<int> parentList = fieldParents ?? [];
    if (parentList.isEmpty) {
      final fieldContext = _fieldContext();
      final active = fieldContext.activeFieldId;
      final root = fieldContext.rootId;
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

  @override
  Future<void> writeSnapshot(JournalLayer journal, Routine r) async {
    await journal.log(
      type: JournalType.routine,
      body: jsonEncode({'action': 'snapshot', 'routine': r.toJson()}),
    );
    _scheduleSave();
    notifyListeners();
  }

  @override
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

  @override
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

  @override
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

  @override
  Future<void> setSchedule(JournalLayer journal, int id, int? at) async {
    final r = findRoutine(id);
    if (r == null) return;
    if (r.scheduledAt == at) {
      _refreshSchedule(r);
      return;
    }

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

  @override
  Future<void> setNotice(JournalLayer journal, int id, int seconds) async {
    final r = findRoutine(id);
    if (r == null) return;
    if (r.scheduledAt == null) return;
    // Clear zero-valued notices so the journal and pult stay in sync.
    if (seconds <= 0) {
      await clearNotice(journal, id);
      return;
    }
    if (r.noticeSet && r.noticeBeforeSec == seconds) {
      _refreshSchedule(r);
      return;
    }
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

  @override
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

  @override
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

  @override
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

  @override
  Future<void> setCompleted(JournalLayer journal, int id, bool value) async {
    final r = findRoutine(id);
    if (r == null) return;
    if (r.completed == value) return;

    if (value) {
      await journal.transaction(() async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final pausedBlocks = r.pauseRunningBlocksAt(now);
        for (final kind in pausedBlocks) {
          await journal.log(
            type: JournalType.routine,
            body:
                '{"action":"pause_block","routine":$id,'
                '"block":"$kind","at":$now}',
          );
        }
        if (currentRoutineId == id) currentRoutineId = null;
        _runningRoutineIds.remove(id);
        r.completeAt(now);
        await journal.log(
          type: JournalType.routine,
          body: '{"action":"complete","routine":$id,"value":true}',
        );
      });
    } else {
      r.reopenAt(DateTime.now().millisecondsSinceEpoch ~/ 1000);
      await journal.log(
        type: JournalType.routine,
        body: '{"action":"complete","routine":$id,"value":false}',
      );
    }
    _refreshSchedule(r);
    _scheduleSave();
    notifyListeners();
  }

  @override
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

  @override
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
    final target = r.blockOf(kind);
    if (target == null || target.isRunning) return;

    await journal.transaction(() async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      if (mutex) {
        final runningIds = List<int>.from(_runningRoutineIds);
        for (final rId in runningIds) {
          final other = findRoutine(rId);
          if (other == null) continue;
          for (final b in other.blocks) {
            if (b.isRunning) {
              other.pauseBlockAt(b.kind, now);
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
            r.pauseBlockAt(b.kind, now);
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

      if (r.startBlockAt(kind, now)) {
        await journal.log(
          type: JournalType.routine,
          body:
              '{"action":"start_block","routine":$routineId,'
              '"block":"$kind","at":$now}',
        );
      }
      currentRoutineId = routineId;
      lastActiveBlockKind = kind;
      _runningRoutineIds.add(routineId);
    });
    _scheduleSave();
    notifyListeners();
  }

  @override
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
    r.pauseBlockAt(kind, now);
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

  @override
  Routine? findRoutine(int id) {
    final indexed = _routineIndex[id];
    if (indexed != null) return indexed;
    for (final r in routines) {
      if (r.id == id) {
        _routineIndex[id] = r;
        return r;
      }
    }
    return null;
  }

  @override
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
    routines = [];
    currentRoutineId = null;
    lastActiveBlockKind = null;
    _sourceKeyIndex.clear();
    _nodeRoutinesIndex.clear();
    _routineIndex.clear();
    _runningRoutineIds.clear();
    await _saveToFile();
    notifyListeners();
  }
}
