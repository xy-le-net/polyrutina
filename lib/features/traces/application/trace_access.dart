import 'package:polyrutina/core/data/journal_layer.dart';
import 'package:polyrutina/features/traces/domain/trace.dart';

abstract interface class TraceAccess {
  Map<int, Trace> get traces;

  Future<int> createText(
    JournalLayer journal, {
    String slot,
    String text,
    List<int> parents,
    List<int> fieldParents,
  });

  Future<int> createChecklist(
    JournalLayer journal, {
    String slot,
    List<String> items,
    List<int> parents,
    List<int> fieldParents,
  });

  Future<void> updateItems(
    JournalLayer journal,
    int traceId,
    List<TraceItem> items,
  );

  Future<void> attachFile(
    JournalLayer journal, {
    required int objectId,
    required String slot,
    required TraceFile file,
  });
}
