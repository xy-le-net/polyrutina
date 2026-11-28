import 'package:polyrutina/features/traces/domain/trace.dart';

class TraceCache {
  final List<Trace> traces;
  final bool needsJournalReplay;

  const TraceCache({required this.traces, required this.needsJournalReplay});

  const TraceCache.empty({this.needsJournalReplay = false}) : traces = const [];
}

abstract interface class TraceRepository {
  Future<TraceCache> load();
  Future<void> save({required List<Trace> traces});
}
