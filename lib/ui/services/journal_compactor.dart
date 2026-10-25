// ═══════════════════════════════════════════════════════════════════
// lib/ui/services/journal_compactor.dart — journal compaction.
//
// Collapses the journal into a compact form: erases all entries,
// writes routine snapshots (action "snapshot"), writes field node
// snapshots, rewrites traces with remapped trace-to-trace references,
// saves one monthly record per registered TimeSeries, and resets
// the export and reread marks.
//
// CompactResult. Every run returns a CompactResult carrying the
// entry count and the database byte size, measured before and
// after the reclaim step.
//
// Order of operations:
//   1. Capture routine snapshots in memory (ids preserved).
//   2. Capture field node snapshots in memory (ids preserved).
//   3. Capture trace snapshots in memory (non-deleted only).
//   4. Capture the most recent month of daily totals.
//   5. Single transaction: delete all, write routine snapshots,
//      write field snapshots, write trace entries, write trace
//      correction entries for remapped parents/children.
//   6. Reread the journal to refill layer memory.
//   7. Reset marks.
//   8. PRAGMA wal_checkpoint(TRUNCATE), VACUUM, PRAGMA optimize.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/field_layer.dart';
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
  static Future<CompactResult> compact({
    required JournalLayer journal,
    required RoutineLayer routineLayer,
    required TraceLayer traceLayer,
    required FieldLayer fieldLayer,
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

    // 2. Capture field node snapshots.
    final fieldSnapshots = <Map<String, dynamic>>[];
    for (final n in fieldLayer.nodes.values) {
      fieldSnapshots.add(n.toJson());
    }
    onProgress?.call(0.15);

    // 3. Capture trace snapshots in memory. Deleted traces are
    // dropped; the rest keep their ids.
    final traceSnapshots = <Map<String, dynamic>>[];
    for (final t in traceLayer.traces.values) {
      if (t.deleted) continue;
      traceSnapshots.add({'id': t.id, ...t.toJson()});
    }
    onProgress?.call(0.18);

    // 4. Capture the most recent month of daily totals.
    final months = <String, MonthTotals>{};
    for (final entry in bort.series.entries) {
      final m = entry.value.lastMonth();
      if (m != null) months[entry.key] = m;
    }
    onProgress?.call(0.25);

    // 5. Single transaction.
    await journal.transaction(() async {
      // Delete all journal entries.
      await journal.db.delete(journal.db.journal).go();

      // Write routine snapshots.
      for (final s in routineSnapshots) {
        await journal.log(
          type: JournalType.routine,
          body: jsonEncode({'action': 'snapshot', 'routine': s}),
        );
      }

      // Write field snapshots.
      for (final s in fieldSnapshots) {
        await journal.log(
          type: JournalType.fieldNode,
          body: jsonEncode({'action': 'create', ...s}),
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

      // Write the monthly records.
      for (final entry in months.entries) {
        final kind = entry.key;
        final m = entry.value;
        await journal.log(
          type: JournalType.actor,
          body: jsonEncode({
            'action': 'period_month',
            'kind': kind,
            'year': m.year,
            'month': m.month,
            'days': m.days,
          }),
        );
      }
    });
    onProgress?.call(0.55);

    // Prune old history.
    for (final entry in months.entries) {
      bort.series[entry.key]?.pruneBefore(entry.value);
    }
    onProgress?.call(0.65);

    // 6. Reread the journal.
    await journal.reread();
    onProgress?.call(0.75);

    // 7. Reset marks.
    bort.setLastExportId(0);
    bort.setLastRereadId(await journal.lastEntryId());
    onProgress?.call(0.85);

    // 8. Reclaim space — outside the transaction.
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

    final entriesAfter = await journal.countEntries();
    final bytesAfter = await _databaseBytes();

    return CompactResult(
      entriesBefore: entriesBefore,
      entriesAfter: entriesAfter,
      bytesBefore: bytesBefore,
      bytesAfter: bytesAfter,
    );
  }

  // Total on-disk size of the journal's SQLite files.
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
