// ═══════════════════════════════════════════════════════════════════
// routine_layer.dart — routines layer.
//
// Holds the list of routines and their blocks.
//
// Journal. Registers with JournalLayer for the routine kind.
//
// Transactions. Actions that birth several entries at once
// (completing a routine, starting a block while quenching others,
// switching blocks when changing routines) are wrapped in
// journal.transaction.
//
// Cache. Written deferred (200 ms). currentRoutineId — in memory;
// lastActiveBlockKind — in cache (for scrolling after restart).
//
// Completion. Setting quenches the running block and sets
// completedAt; unsetting clears completedAt.
//
// Time editing. setBlockTime sets the timeEdited flag; when a block
// is started, the flag is cleared.
//
// lastPulseAt. Moves on block start and stop. Other actions (rename,
// flags change, plan edit) do not touch it — otherwise the day in
// the «days» calendar would shift without cause.
//
// Scheduled date and planned man-hours. Edited in the card; stored
// as Unix seconds and seconds respectively.
//
// Duplication. Copied: name, flags, scheduled date, planned
// man-hours, traces of the note, prep, closeout blocks (text and
// checklist). Traces of transit, work, idle are not transferred —
// they belong to a specific job.
//
// Snapshot action. The compactor writes a single «snapshot» entry per
// routine containing the full state (name, flags, dates, plan,
// blocks). _applyEntry rebuilds the Routine object in one go.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database.dart';
import 'journal_layer.dart';
import 'journal_types.dart';
import 'routine.dart';
import 'trace_layer.dart';

class RoutineLayer extends ChangeNotifier {
  // ─── Current state ───
  List<Routine> routines = [];

  int? currentRoutineId;
  String? lastActiveBlockKind;

  // Reference to the trace layer — needed for duplication.
  TraceLayer? _traces;

  File? _file;
  Timer? _saveTimer;

  List<Routine> get routinesNewestFirst {
    final copy = List<Routine>.from(routines);
    copy.sort((a, b) => b.id.compareTo(a.id));
    return copy;
  }

  Future<void> init(JournalLayer journal, TraceLayer traces) async {
    _traces = traces;
    final dir = await getApplicationDocumentsDirectory();
    _file = File(p.join(dir.path, 'routine_layer.json'));
    await _loadFromFile();

    journal.register(
      name: 'routine',
      types: [JournalType.routine],
      apply: _applyEntry,
      reset: _resetMemory,
    );

    notifyListeners();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  // ─── Cache ───
  Future<void> _loadFromFile() async {
    if (_file == null || !await _file!.exists()) return;
    try {
      final raw = await _file!.readAsString();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final r = data['routines'];
      if (r is List) {
        routines = r
            .map((e) => Routine.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      lastActiveBlockKind = data['last_active_block_kind'] as String?;
    } catch (_) {}
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 200), () {
      _saveToFile();
    });
  }

  Future<void> _saveToFile() async {
    if (_file == null) return;
    final data = <String, dynamic>{
      'routines': routines.map((r) => r.toJson()).toList(),
      'last_active_block_kind': lastActiveBlockKind,
    };
    await _file!.writeAsString(jsonEncode(data));
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _saveToFile();
  }

  // ─── Applying a journal entry ───
  void _applyEntry(JournalData e) {
    try {
      final data = jsonDecode(e.body) as Map<String, dynamic>;
      final action = data['action'] as String?;
      switch (action) {
        case 'reset':
          routines = [];
          currentRoutineId = null;
          lastActiveBlockKind = null;
          break;
        case 'create':
          final bodyId = (data['routine'] as num?)?.toInt();
          final id = bodyId ?? e.id;
          if (findRoutine(id) == null) {
            routines.add(Routine.create(id, at: e.time));
          }
          break;
        case 'snapshot':
          // Full routine state from the compactor.
          final id = e.id; // The entry id is the routine id.
          final blocksData = data['blocks'] as List? ?? [];
          final blocks = <RoutineBlock>[];
          for (final b in blocksData) {
            if (b is Map) {
              blocks.add(
                RoutineBlock.fromJson({
                  'kind': b['kind'],
                  'accumulator': b['accumulator'],
                  'started_at': b['started_at'],
                  'time_edited': b['time_edited'],
                }),
              );
            }
          }
          final r = Routine(
            id: id,
            name: data['name'] as String? ?? '',
            createdAt: (data['created_at'] as num?)?.toInt() ?? e.time,
            blocks: blocks,
            lastActionAt: (data['last_action_at'] as num?)?.toInt(),
            lastPulseAt: (data['last_pulse_at'] as num?)?.toInt(),
            completedAt: (data['completed_at'] as num?)?.toInt(),
            scheduledAt: (data['scheduled_at'] as num?)?.toInt(),
            plannedSeconds: (data['planned_seconds'] as num?)?.toInt() ?? 0,
            flags: (data['flags'] as num?)?.toInt() ?? 0,
            completed: data['completed'] as bool? ?? false,
          );
          routines.removeWhere((x) => x.id == id);
          routines.add(r);
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
          }
          break;
        case 'set_schedule':
          final id = (data['routine'] as num).toInt();
          final r = findRoutine(id);
          if (r != null) {
            r.scheduledAt = (data['at'] as num?)?.toInt();
            r.lastActionAt = e.time;
          }
          break;
        case 'set_planned':
          final id = (data['routine'] as num).toInt();
          final r = findRoutine(id);
          if (r != null) {
            r.plannedSeconds = (data['seconds'] as num?)?.toInt() ?? 0;
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
            r.completed = false;
            r.completedAt = null;
            currentRoutineId = id;
            lastActiveBlockKind = kind;
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
            if (r.runningBlock == null && currentRoutineId == id) {
              currentRoutineId = null;
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
    notifyListeners();
  }

  // ─── Duplication ───
  // Copied: name, flags, scheduled date, planned man-hours, traces
  // of the note, prep, closeout blocks (text and checklist).
  // Traces of transit, work, idle are not transferred — they belong
  // to a specific job.
  //
  // All copying — in a single transaction: several journal entries
  // are born (routine creation, name, flags, date, plan, a trace per
  // slot). On failure in the middle — neither routine nor traces.
  Future<Routine?> duplicateRoutine(JournalLayer journal, int sourceId) async {
    final src = findRoutine(sourceId);
    if (src == null) return null;

    int? newId;
    await journal.transaction(() async {
      final r = await createRoutine(journal);
      newId = r.id;
      if (src.name.isNotEmpty) {
        await renameRoutine(journal, r.id, src.name);
      }
      if (src.flags != 0) {
        await setFlags(journal, r.id, src.flags);
      }
      if (src.scheduledAt != null) {
        await setSchedule(journal, r.id, src.scheduledAt);
      }
      if (src.plannedSeconds > 0) {
        await setPlanned(journal, r.id, src.plannedSeconds);
      }

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
    return findRoutine(newId!);
  }

  // ─── Mutations ───
  Future<Routine> createRoutine(JournalLayer journal) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final id = await journal.log(
      type: JournalType.routine,
      body: '{"action":"create"}',
    );
    if (findRoutine(id) == null) {
      final r = Routine.create(id);
      r.lastActionAt = now;
      routines.add(r);
    }
    _scheduleSave();
    notifyListeners();
    return findRoutine(id)!;
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
    routines.removeWhere((r) => r.id == id);
    if (currentRoutineId == id) currentRoutineId = null;
    await journal.log(
      type: JournalType.routine,
      body: '{"action":"delete","routine":$id}',
    );
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
    r.scheduledAt = at;
    r.lastActionAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await journal.log(
      type: JournalType.routine,
      body: '{"action":"set_schedule","routine":$id,"at":${at ?? 'null'}}',
    );
    _scheduleSave();
    notifyListeners();
  }

  Future<void> setPlanned(JournalLayer journal, int id, int seconds) async {
    final r = findRoutine(id);
    if (r == null) return;
    if (r.plannedSeconds == seconds) return;
    r.plannedSeconds = seconds;
    r.lastActionAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await journal.log(
      type: JournalType.routine,
      body: '{"action":"set_planned","routine":$id,"seconds":$seconds}',
    );
    _scheduleSave();
    notifyListeners();
  }

  Future<void> setCompleted(JournalLayer journal, int id, bool value) async {
    final r = findRoutine(id);
    if (r == null) return;
    if (r.completed == value) return;

    if (value) {
      // Pause all running blocks + completion mark — in one
      // transaction: either all or nothing.
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
    String kind,
  ) async {
    final r = findRoutine(routineId);
    if (r == null) return;
    final b = r.blockOf(kind);
    if (b == null) return;
    if (b.isRunning) {
      await pauseBlock(journal, routineId, kind);
    } else {
      await startBlock(journal, routineId, kind);
    }
  }

  // ─── Start block ───
  // Quenches running blocks (in this routine and in another), starts
  // the target — all in a single transaction.
  Future<void> startBlock(
    JournalLayer journal,
    int routineId,
    String kind,
  ) async {
    final r = findRoutine(routineId);
    if (r == null) return;

    await journal.transaction(() async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      if (currentRoutineId != null && currentRoutineId != routineId) {
        final other = findRoutine(currentRoutineId!);
        if (other != null) {
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
        }
      }

      for (final b in r.blocks) {
        if (b.isRunning && b.kind != kind) {
          b.pause(at: now);
          await journal.log(
            type: JournalType.routine,
            body:
                '{"action":"pause_block","routine":$routineId,'
                '"block":"${b.kind}","at":$now}',
          );
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
      r.completed = false;
      r.completedAt = null;
      currentRoutineId = routineId;
      lastActiveBlockKind = kind;
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
    if (r.runningBlock == null && currentRoutineId == routineId) {
      currentRoutineId = null;
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

  Future<void> resetAll() async {
    if (_file != null && await _file!.exists()) {
      await _file!.delete();
    }
    routines = [];
    currentRoutineId = null;
    lastActiveBlockKind = null;
    await _saveToFile();
    notifyListeners();
  }
}
