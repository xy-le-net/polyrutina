import 'package:polyrutina/features/fields/domain/field_node.dart';

class FieldCache {
  final int? activeFieldId;
  final List<FieldNode> nodes;
  final bool needsJournalReplay;

  const FieldCache({
    required this.activeFieldId,
    required this.nodes,
    required this.needsJournalReplay,
  });

  const FieldCache.empty({this.needsJournalReplay = false})
    : activeFieldId = null,
      nodes = const [];
}

abstract interface class FieldRepository {
  Future<FieldCache> load();
  Future<void> save({
    required int? activeFieldId,
    required List<FieldNode> nodes,
  });
}
