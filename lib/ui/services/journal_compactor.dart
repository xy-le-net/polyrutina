// ═══════════════════════════════════════════════════════════════════
// journal_compactor.dart — journal compaction.
//
// Collapses the journal into a compact form: erases all entries,
// writes routine snapshots (action "snapshot"), writes field node
// snapshots, rewrites traces with remapped trace-to-trace references,
// saves ALL monthly records for every registered TimeSeries (per
// field for shifts, global for bort), and resets the export and
// reread marks.
//
// Unified shift. The shift now lives under the zero-field key; the
// compactor no longer enumerates `bort.shifts.keys` and writes one
// snapshot per field. Only field 0 is written for the shift series,
// matching the single-state semantics. Historical per-field entries
// that may still exist in older series files are left untouched but
// are not emitted: the unified view does not read them.
//
// Notice interval. Routine snapshots carry notice_before_sec and
// notice_set verbatim (via Routine.toJson); the compactor does not
// interpret or normalize them. Date and notice are stored
// independently, so a snapshot preserves the pair exactly as the
// layer holds it. The layer's invariant — no notice without a date —
// is enforced at mutation time (setSchedule clears the notice) and
// therefore holds in the snapshots too.
//
// CompactResult. Every run returns a CompactResult carrying the
// entry count and the database byte size, measured before and
// after the reclaim step.
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

  bool get unchanged => entriesDropped <= 0 && bytesFreed <= 0;
}

class JournalCompactor {
  static Future<CompactResult> compact({
    required JournalLayer journal,
    required RoutineLayer routineLayer,
    required TraceLayer traceLayer,
    required FieldLayer fieldLayer,
    required OperationalLayer bort,
    ValueChanged<double>? onProgress,
  }) async {
    onProgress?.call(0.02);

    final entriesBefore = await journal.countEntries();
    final bytesBefore = await _databaseBytes();

    onProgress?.call(0.05);

    // 1. Capture routine snapshots. Routine.toJson carries the
    // notice pair (notice_before_sec, notice_set) verbatim; the
    // compactor does not interpret it.
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

    // 3. Capture trace snapshots (non-deleted only).
    final traceSnapshots = <Map<String, dynamic>>[];
    for (final t in traceLayer.traces.values) {
      if (t.deleted) continue;
      traceSnapshots.add({'id': t.id, ...t.toJson()});
    }
    onProgress?.call(0.18);

    // 4. Capture ALL months for every registered series.
    // The shift is unified under field 0; no per-field enumeration.
    final seriesSnapshots =
        <
          ({String kind, int fieldId, int year, int month, Map<int, int> days})
        >[];
    for (final entry in bort.series.entries) {
      final kind = entry.key;
      final series = entry.value;
      for (final m in series.allMonths(0)) {
        seriesSnapshots.add((
          kind: kind,
          fieldId: 0,
          year: m.year,
          month: m.month,
          days: m.days,
        ));
      }
    }
    onProgress?.call(0.22);

    onProgress?.call(0.25);

    // 5. Single transaction.
    await journal.transaction(() async {
      await journal.db.delete(journal.db.journal).go();

      // Write routine snapshots. Notice pair is inside the snapshot
      // body; no separate set_notice entries are emitted, and none
      // are needed: the snapshot fully reconstructs the routine.
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

      // Write trace entries and build id map.
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

      // Second pass for trace parents/children.
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

      // Write ALL monthly records for every series under field 0.
      for (final s in seriesSnapshots) {
        final out = <String, int>{};
        for (final e in s.days.entries) {
          out[e.key.toString()] = e.value;
        }
        await journal.log(
          type: JournalType.actor,
          body: jsonEncode({
            'action': 'period_month',
            'kind': s.kind,
            'field_id': 0,
            'year': s.year,
            'month': s.month,
            'days': out,
          }),
        );
      }
    });
    onProgress?.call(0.55);

    onProgress?.call(0.65);

    // 6. Reread the journal.
    await journal.reread();
    onProgress?.call(0.75);

    // 7. Reset marks.
    bort.setLastExportId(0);
    bort.setLastRereadId(await journal.lastEntryId());
    onProgress?.call(0.85);

    // 8. Reclaim space.
    try {
      await journal.db.customSelect('PRAGMA wal_checkpoint(TRUNCATE)').get();
      onProgress?.call(0.90);
      await journal.db.customStatement('VACUUM');
      onProgress?.call(0.96);
      await journal.db.customStatement('PRAGMA optimize');
    } catch (_) {}

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
