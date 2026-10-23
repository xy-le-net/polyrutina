// ═══════════════════════════════════════════════════════════════════
// lib/ui/services/journal_compactor.dart — journal compaction.
//
// Collapses the journal into a compact form: erases all entries,
// writes routine snapshots (action "snapshot"), rewrites traces
// with remapped trace-to-trace references, saves a single monthly
// shift record, and resets the export and reread marks.
//
// CompactResult. Every run returns a CompactResult carrying the
// entry count and the database byte size, measured before and
// after the reclaim step. The rubka compares the two and reports
// either «journal optimal» (entriesAfter == entriesBefore and
// bytesAfter == bytesBefore) or «dropped N entries, freed K» to
// the user.
//
// Order of operations:
//   1. Capture routine snapshots in memory (ids preserved).
//   2. Capture trace snapshots in memory (non-deleted only,
//      with their ids).
//   3. Capture the most recent month of daily shift totals
//      from ShiftHistory.
//   4. Single transaction: delete all, write routine snapshots,
//      write trace entries, write trace correction entries for
//      remapped parents/children, write the monthly shift record.
//   5. Reread the journal to refill layer memory.
//   6. Reset marks (export to 0, reread to the current last id).
//   7. Outside the transaction: PRAGMA wal_checkpoint(TRUNCATE),
//      VACUUM, PRAGMA optimize — to actually reclaim file space.
//      If any of these fail, the journal remains valid; only the
//      file stays larger.
//
// VACUUM cannot run inside a transaction (SQLite restriction);
// splitting it out trades atomicity of the space reclamation
// for journal integrity. WAL checkpoint before VACUUM ensures
// the WAL is flushed and truncated, so the main file reflects
// the compacted state.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/journal_layer.dart';
import '../../data/journal_types.dart';
import '../../data/operational_layer.dart';
import '../../data/routine_layer.dart';
import '../../data/trace_layer.dart';

// Result of a compaction pass: before/after numbers for entries and
// the database file. Callers compare before vs after to decide what
// (if anything) to report to the user.
class CompactResult {
  final int entriesBefore;
  final int entriesAfter;
  final int bytesBefore;
  final int bytesAfter;

  const CompactResult({
    required this.entriesBefore,
    required this.entriesAfter,
    required this.bytesBefore,
    required this.bytesAfter,
  });

  int get entriesDropped => entriesBefore - entriesAfter;
  int get bytesFreed => bytesBefore - bytesAfter;

  // True when neither entries nor bytes changed — the journal was
  // already in its compact form.
  bool get unchanged => entriesDropped <= 0 && bytesFreed <= 0;
}

class JournalCompactor {
  /// Compacts the journal.
  ///
  /// [journal] — the journal layer.
  /// [routineLayer] — the routine layer (for snapshots).
  /// [traceLayer] — the trace layer (for re-written traces).
  /// [bort] — the operational layer (for shift history and marks).
  /// [onProgress] — progress callback (0..1).
  static Future<CompactResult> compact({
    required JournalLayer journal,
    required RoutineLayer routineLayer,
    required TraceLayer traceLayer,
    required OperationalLayer bort,
    ValueChanged<double>? onProgress,
  }) async {
    onProgress?.call(0.02);

    // Snapshot the «before» numbers.
    final entriesBefore = await journal.countEntries();
    final bytesBefore = await _databaseBytes();

    onProgress?.call(0.05);

    // 1. Capture routine snapshots in memory. Ids are preserved
    // inside the JSON, so routine ids survive compaction.
    final routineSnapshots = <Map<String, dynamic>>[];
    for (final r in routineLayer.routines) {
      routineSnapshots.add(r.toJson());
    }
    onProgress?.call(0.10);

    // 2. Capture trace snapshots in memory. Deleted traces are
    // dropped; the rest keep their ids.
    final traceSnapshots = <Map<String, dynamic>>[];
    for (final t in traceLayer.traces.values) {
      if (t.deleted) continue;
      traceSnapshots.add({'id': t.id, ...t.toJson()});
    }
    onProgress?.call(0.18);

    // 3. Capture the most recent month of shift totals.
    final month = bort.shiftHistory.lastMonth();
    onProgress?.call(0.25);

    // 4. Single transaction.
    await journal.transaction(() async {
      // Delete all journal entries.
      await journal.db.delete(journal.db.journal).go();

      // Write routine snapshots. Each carries full routine state;
      // the routine layer refills from it via the "snapshot" branch.
      for (final s in routineSnapshots) {
        await journal.log(
          type: JournalType.routine,
          body: jsonEncode({'action': 'snapshot', 'routine': s}),
        );
      }

      // Write trace entries (first pass) and build the id map.
      final idMap = <int, int>{};
      for (final t in traceSnapshots) {
        final oldId = (t['id'] as num).toInt();
        final body = Map<String, dynamic>.from(t)..remove('id');
        final newId = await journal.log(
          type: JournalType.trace,
          body: jsonEncode(body),
        );
        idMap[oldId] = newId;
      }

      // Second pass: correction entries for remapped parents/children.
      // References to routines stay as they are (routine ids are
      // preserved by the snapshots); references to other traces are
      // remapped to their new ids.
      for (final t in traceSnapshots) {
        final oldId = (t['id'] as num).toInt();
        final newId = idMap[oldId]!;
        final oldParents =
            (t['parents'] as List?)?.map((e) => (e as num).toInt()).toList() ??
            const <int>[];
        final oldChildren =
            (t['children'] as List?)?.map((e) => (e as num).toInt()).toList() ??
            const <int>[];
        final newParents = oldParents.map((p) => idMap[p] ?? p).toList();
        final newChildren = oldChildren.map((c) => idMap[c] ?? c).toList();
        if (_sameList(oldParents, newParents) &&
            _sameList(oldChildren, newChildren)) {
          continue;
        }
        final body = Map<String, dynamic>.from(t)
          ..remove('id')
          ..['target'] = newId
          ..['parents'] = newParents
          ..['children'] = newChildren;
        await journal.log(
          type: JournalType.trace,
          body: jsonEncode(body),
          flags: JournalFlag.correction,
        );
      }

      // Write the monthly shift record.
      if (month != null && month.days.isNotEmpty) {
        await journal.log(
          type: JournalType.actor,
          body: jsonEncode({
            'action': 'shift_month',
            'year': month.year,
            'month': month.month,
            'days': month.days,
          }),
        );
      }
    });
    onProgress?.call(0.55);

    // Prune old shift history — keep only the last month.
    if (month != null) {
      bort.shiftHistory.pruneBefore(month);
    }
    onProgress?.call(0.65);

    // 5. Reread the journal — refill layer memory from the
    // compacted state.
    await journal.reread();
    onProgress?.call(0.75);

    // 6. Reset marks.
    bort.setLastExportId(0);
    bort.setLastRereadId(await journal.lastEntryId());
    onProgress?.call(0.85);

    // 7. Reclaim space — outside the transaction.
    try {
      await journal.db.customSelect('PRAGMA wal_checkpoint(TRUNCATE)').get();
      onProgress?.call(0.90);
      await journal.db.customStatement('VACUUM');
      onProgress?.call(0.96);
      await journal.db.customStatement('PRAGMA optimize');
    } catch (_) {
      // Space reclamation failed; the journal itself is intact.
    }
    onProgress?.call(1.0);

    // Snapshot the «after» numbers.
    final entriesAfter = await journal.countEntries();
    final bytesAfter = await _databaseBytes();

    return CompactResult(
      entriesBefore: entriesBefore,
      entriesAfter: entriesAfter,
      bytesBefore: bytesBefore,
      bytesAfter: bytesAfter,
    );
  }

  // Total on-disk size of the journal's SQLite files (main, wal,
  // shm). Missing files count as zero.
  static Future<int> _databaseBytes() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      var total = 0;
      for (final name in const [
        'polyrutina.sqlite',
        'polyrutina.sqlite-wal',
        'polyrutina.sqlite-shm',
      ]) {
        final f = File(p.join(dir.path, name));
        if (await f.exists()) total += await f.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  static bool _sameList(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
