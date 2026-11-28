import 'package:polyrutina/features/fields/domain/field_node.dart';

class FieldCache {
  final int? activeFieldId;
  final List<FieldNode> nodes;
  final bool needsJournalReplay;
  // The cache snapshot only covers journal entries through this ID.
  final int lastJournalId;

  const FieldCache({
    required this.activeFieldId,
    required this.nodes,
    required this.needsJournalReplay,
    this.lastJournalId = 0,
  });

  const FieldCache.empty({
    this.needsJournalReplay = false,
    this.lastJournalId = 0,
  }) : activeFieldId = null,
       nodes = const [];
}

abstract interface class FieldRepository {
  Future<FieldCache> load();
  Future<void> save({
    required int? activeFieldId,
    required List<FieldNode> nodes,
    required int lastJournalId,
  });
}
