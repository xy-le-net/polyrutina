import 'package:polyrutina/features/traces/domain/trace.dart';

class TraceCache {
  final List<Trace> traces;
  final bool needsJournalReplay;
  // The cache snapshot only covers journal entries through this ID.
  final int lastJournalId;

  const TraceCache({
    required this.traces,
    required this.needsJournalReplay,
    this.lastJournalId = 0,
  });

  const TraceCache.empty({
    this.needsJournalReplay = false,
    this.lastJournalId = 0,
  }) : traces = const [];
}

abstract interface class TraceRepository {
  Future<TraceCache> load();
  Future<void> save({required List<Trace> traces, required int lastJournalId});
}
