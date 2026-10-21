// ═══════════════════════════════════════════════════════════════════
// journal_compactor.dart — journal compaction.
//
// Reads all entries, replays them to the current state (already in
// memory in the layers), then rewrites the journal as a set of
// snapshot entries — one per routine, one per trace. The history of
// changes is discarded; only the final states remain. This reduces
// the journal size and speeds up startup.
//
// IDs. The id of a journal entry serves as the object identifier:
// traces reference routines via parents. On compaction, new ids are
// assigned; a map old -> new is built for routines and traces, and
// all parents are rewritten. Children are dropped (rarely used and
// not queried).
//
// Shift history. Actor entries are dropped on compaction. Should a
// monthly shift history be present (see shift_history.dart), it is
// preserved via a fresh shift_month entry per month; this module
// accepts an optional provider for that purpose.
//
// Process:
//   1. Snapshot the current routines and traces from the layers.
//   2. Inside a single transaction, delete all entries and insert
//      fresh snapshots. Progress is reported via ProgressToken.
//   3. VACUUM the database file.
//   4. Reset lastRereadId and lastExportId to zero.
//
// Cancellation. If the token is cancelled mid-flight, an exception
// is thrown, the transaction rolls back, and the database is
// untouched.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'dart:convert';

import '../../data/journal_layer.dart';
import '../../data/journal_types.dart';
import '../../data/operational_layer.dart';
import '../../data/routine.dart';
import '../../data/routine_layer.dart';
import '../../data/trace_layer.dart';
import '../core/progress_dialog.dart';

// Provides monthly shift totals as { 'YYYY-MM': { 'YYYY-MM-DD': seconds } }.
typedef MonthlyShiftsProvider =
    Future<Map<String, Map<String, int>>> Function();

class JournalCompactor {
  static Future<void> compress({
    required JournalLayer journal,
    required RoutineLayer routines,
    required TraceLayer traces,
    required OperationalLayer bort,
    required ProgressToken token,
    // Optional provider for monthly shift data (pending shift_history).
    MonthlyShiftsProvider? shiftHistory,
  }) async {
    // ─── Snapshot the current state ───
    final rs = List<Routine>.from(routines.routines);
    final ts = traces.traces.values.where((t) => !t.deleted).toList();
    final total = rs.length + ts.length;

    if (total == 0) {
      // Nothing to compress; still vacuum and reset marks.
      try {
        await journal.db.customStatement('VACUUM');
      } catch (_) {}
      bort.setLastRereadId(0);
      bort.setLastExportId(0);
      return;
    }

    // ─── Maps old -> new ids ───
    final routineIdMap = <int, int>{};
    final traceIdMap = <int, int>{};

    int progress = 0;
    void reportProgress() {
      progress++;
      token.report(progress / total);
    }

    // Read shift history before the transaction (async safety).
    Map<String, Map<String, int>>? monthlyShifts;
    if (shiftHistory != null) {
      monthlyShifts = await shiftHistory();
    }

    // ─── Transaction: delete all, insert snapshots ───
    try {
      await journal.transaction(() async {
        await journal.db.delete(journal.db.journal).go();

        // Insert routines as snapshots.
        for (final r in rs) {
          if (token.cancelled) throw _Cancelled();
          final newId = await journal.log(
            type: JournalType.routine,
            body: jsonEncode({
              'action': 'snapshot',
              'name': r.name,
              'flags': r.flags,
              'completed': r.completed,
              'completed_at': r.completedAt,
              'scheduled_at': r.scheduledAt,
              'planned_seconds': r.plannedSeconds,
              'created_at': r.createdAt,
              'last_action_at': r.lastActionAt,
              'last_pulse_at': r.lastPulseAt,
              'blocks': [
                for (final b in r.blocks)
                  {
                    'kind': b.kind,
                    'accumulator': b.accumulatorSeconds,
                    'started_at': b.startedAt,
                    'time_edited': b.timeEdited,
                  },
              ],
            }),
          );
          routineIdMap[r.id] = newId;
          reportProgress();
        }

        // Insert traces sorted by old id. Parents mapped through
        // routineIdMap; children dropped.
        ts.sort((a, b) => a.id.compareTo(b.id));
        for (final t in ts) {
          if (token.cancelled) throw _Cancelled();
          final newParents = t.parents
              .map((id) => routineIdMap[id] ?? traceIdMap[id])
              .whereType<int>()
              .toList();
          final newId = await journal.log(
            type: JournalType.trace,
            body: jsonEncode({
              'kind': t.kind,
              'slot': t.slot,
              'text': t.text,
              'items': t.items.map((e) => e.toJson()).toList(),
              'parents': newParents,
              'children': <int>[],
              'files': t.files.map((e) => e.toJson()).toList(),
              'deleted': false,
            }),
          );
          traceIdMap[t.id] = newId;
          reportProgress();
        }

        // Preserve monthly shift history if a provider was given.
        if (monthlyShifts != null) {
          for (final monthKey in monthlyShifts.keys) {
            final days = monthlyShifts[monthKey]!;
            await journal.log(
              type: JournalType.actor,
              body: jsonEncode({
                'action': 'shift_month',
                'month': monthKey,
                'days': days,
              }),
            );
          }
        }
      });
    } on _Cancelled {
      // Rolled back; database untouched.
      return;
    }

    if (token.cancelled) return;

    // ─── VACUUM and reread ───
    try {
      await journal.db.customStatement('VACUUM');
    } catch (_) {}

    // Reload layers from the fresh entries.
    await journal.reread();

    // Reset marks: old ids are gone.
    bort.setLastRereadId(0);
    bort.setLastExportId(0);
  }
}

// Marker exception for token cancellation.
class _Cancelled implements Exception {}
