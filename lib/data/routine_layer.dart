// ═══════════════════════════════════════════════════════════════════
// lib/data/routine_layer.dart — routine layer.
//
// Holds the list of routines and their blocks.
//
// Journal. Registered in JournalLayer for the routine kind.
//
// Transactions. Actions producing several entries at once
// (completing a routine, starting a block while stopping the others,
// switching blocks between routines) are wrapped in
// journal.transaction.
//
// Cache. Written with a 200 ms debounce. currentRoutineId is
// reconstructed on startup from the first running block, so that
// after a restart the app knows which routine is active. Cache
// writes go through a .tmp file and a rename.
//
// Completion. Setting it stops the running block and records
// completedAt; clearing it removes completedAt.
//
// Time editing. setBlockTime marks timeEdited; starting a block
// clears the mark.
//
// lastPulseAt. Advanced on block start and stop. Other actions
// (rename, flag change, plan edit) leave it alone.
//
// Scheduled date and planned man-hours. Edited in the card; stored
// as Unix seconds and seconds respectively.
//
// Duplication. Copied: name, flags, scheduled date, planned
// man-hours, traces of the note, prep, closeout blocks (text and
// checklist). Transit, work, and idle traces are not carried over.
// The copy's sourceKey is empty (it is not an import).
//
// Duplication writes ONE snapshot entry. The "snapshot" branch in
// _applyEntry replaces the routine in place. Trace copies remain
// separate entries.
//
// startBlock. Guarantees that only one block is active across the
// whole app: it pauses every running block in every routine before
// starting the target, regardless of currentRoutineId. This fixes
// the case where currentRoutineId was lost after a restart, yet a
// routine's block was still marked as running.
//
// sourceKey. createRoutine accepts an optional sourceKey; when
// non-empty it is written into the create entry body (so a reread
// restores it) and into the in-memory routine. findRoutineBySourceKey
// lets the importer skip routines already present — re-importing
// the same archive is idempotent.
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

  // Trace layer reference — needed for duplication.
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
      // Lenient reload: a single damaged record is skipped, the rest
      // load as usual. Routine.fromJson throws FormatException when
      // the mandatory fields (id, created_at) are missing, and any
      // other unexpected shape is caught here as well. Without this
      // guard, one bad entry would wipe the whole cache.
      final r = data['routines'];
      if (r is List) {
        final loaded = <Routine>[];
        for (final e in r) {
          if (e is! Map) continue;
          try {
            loaded.add(Routine.fromJson(Map<String, dynamic>.from(e)));
          } catch (_) {
            // Skip the damaged record; keep the rest.
          }
        }
        routines = loaded;
      }
      lastActiveBlockKind = data['last_active_block_kind'] as String?;

      // Reconstruct currentRoutineId from the first running block.
      for (final r in routines) {
        if (r.runningBlock != null) {
          currentRoutineId = r.id;
          break;
        }
      }
    } catch (_) {}
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
      'routines': routines.map((r) => r.toJson()).toList(),
      'last_active_block_kind': lastActiveBlockKind,
    };
    final tmp = File('${target.path}.tmp');
    try {
      await tmp.writeAsString(jsonEncode(data), flush: true);
      await tmp.rename(target.path);
    } catch (_) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
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
        case 'snapshot':
          final raw = data['routine'];
          if (raw is Map<String, dynamic>) {
            try {
              final r = Routine.fromJson(raw);
              final idx = routines.indexWhere((x) => x.id == r.id);
              if (idx >= 0) {
                routines[idx] = r;
              } else {
                routines.add(r);
              }
            } catch (_) {}
          }
          break;
        case 'create':
          final bodyId = (data['routine'] as num?)?.toInt();
          final id = bodyId ?? e.id;
          final sourceKey = data['source_key'] as String? ?? '';
          // Historical creation moment from the body; e.time is
          // the current fallback for routines created natively.
          final createdAt = (data['created_at'] as num?)?.toInt();
          if (findRoutine(id) == null) {
            routines.add(
              Routine.create(
                id,
                at: e.time,
                sourceKey: sourceKey,
                createdAt: createdAt,
              ),
            );
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
  Future<Routine?> duplicateRoutine(JournalLayer journal, int sourceId) async {
    final src = findRoutine(sourceId);
    if (src == null) return null;

    int? newId;
    await journal.transaction(() async {
      final r = await createRoutine(journal);
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
        plannedSeconds: src.plannedSeconds,
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
    return findRoutine(newId!);
  }

  // ─── Mutations ───
  Future<Routine> createRoutine(
    JournalLayer journal, {
    String sourceKey = '',
    int? createdAt,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // created_at is written into the create entry body so that a
    // reread restores the historical creation moment (the entry's
    // own time is always «now» — journal.log stamps it that way).
    final bodyMap = <String, dynamic>{'action': 'create'};
    if (sourceKey.isNotEmpty) bodyMap['source_key'] = sourceKey;
    if (createdAt != null) bodyMap['created_at'] = createdAt;
    final id = await journal.log(
      type: JournalType.routine,
      body: jsonEncode(bodyMap),
    );
    if (findRoutine(id) == null) {
      final r = Routine.create(id, sourceKey: sourceKey, createdAt: createdAt);
      r.lastActionAt = now;
      routines.add(r);
    }
    _scheduleSave();
    notifyListeners();
    return findRoutine(id)!;
  }

  // ─── Snapshot ───
  // Writes the routine's full in-memory state as one «snapshot»
  // entry. The _applyEntry handler replaces the routine in place on
  // reread, so every field — including those without dedicated
  // setters (lastPulseAt, completedAt) — is restored as-is. Used by
  // the importer after the per-field setters have been applied: it
  // is cheaper to patch the remaining historical timestamps in the
  // in-memory routine and snapshot once than to add a setter for
  // each. Mirrors the same «snapshot» mechanism used by
  // duplicateRoutine.
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

  // mutex: when true (the default), starting the target pauses every
  // other running block across the whole app. When false, blocks are
  // independent and may run concurrently. Pausing never mutexes — a
  // running block stops on its own.
  Future<void> toggleBlock(
    JournalLayer journal,
    int routineId,
    String kind, {
    bool mutex = true,
  }) async {
    final r = findRoutine(routineId);
    if (r == null) return;
    final b = r.blockOf(kind);
    if (b == null) return;
    if (b.isRunning) {
      await pauseBlock(journal, routineId, kind);
    } else {
      await startBlock(journal, routineId, kind, mutex: mutex);
    }
  }

  // ─── Block start ───
  // Pauses EVERY running block in EVERY routine, then starts the
  // target. This guarantees a single active block across the whole
  // app, even if currentRoutineId was lost after a restart.
  Future<void> startBlock(
    JournalLayer journal,
    int routineId,
    String kind, {
    bool mutex = true,
  }) async {
    final r = findRoutine(routineId);
    if (r == null) return;

    await journal.transaction(() async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Mutex branch: pause every other running block across all
      // routines. When mutex is off, other blocks keep running.
      if (mutex) {
        for (final other in routines) {
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

  // ─── Lookup by source key ───
  // Returns the routine whose sourceKey equals the given value, or
  // null. The importer uses this to skip routines that are already
  // present, so re-importing the same archive is idempotent.
  Routine? findRoutineBySourceKey(String key) {
    if (key.isEmpty) return null;
    for (final r in routines) {
      if (r.sourceKey == key) return r;
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
