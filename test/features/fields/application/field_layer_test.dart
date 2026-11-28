import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:polyrutina/core/data/journal_layer.dart';
import 'package:polyrutina/core/domain/journal_types.dart';
import 'package:polyrutina/features/fields/application/field_layer.dart';
import 'package:polyrutina/features/fields/application/field_repository.dart';
import '../../../support/memory_journal_repository.dart';

void main() {
  test('replays field entries newer than the field cache checkpoint', () async {
    final journalRepository = MemoryJournalRepository();
    await journalRepository.insert(
      type: JournalType.fieldNode,
      body: jsonEncode({'action': 'create', 'name': 'Root', 'is_root': true}),
    );
    await journalRepository.insert(
      type: JournalType.fieldNode,
      body: jsonEncode({'action': 'rename', 'id': 1, 'name': 'Updated'}),
    );
    final journal = JournalLayer(journalRepository);
    final repository = _MemoryFieldRepository(
      FieldCache(
        activeFieldId: 1,
        nodes: [FieldNode(id: 1, name: 'Cached', isRoot: true)],
        needsJournalReplay: false,
        lastJournalId: 1,
      ),
    );
    final layer = FieldLayer(repository);
    addTearDown(journal.dispose);
    addTearDown(layer.dispose);

    await layer.init(journal);
    await journal.pump();
    await layer.saveNow();

    expect(layer.nodes[1]?.name, 'Updated');
    expect(repository.lastJournalId, 2);
  });

  test('replays field entries when the cache is missing', () async {
    final journalRepository = MemoryJournalRepository();
    await journalRepository.insert(
      type: JournalType.fieldNode,
      body: jsonEncode({'action': 'create', 'name': 'Root', 'is_root': true}),
    );
    final journal = JournalLayer(journalRepository);
    final layer = FieldLayer(_MissingFieldRepository());
    addTearDown(journal.dispose);
    addTearDown(layer.dispose);

    await layer.init(journal);

    expect(layer.rootId, 1);
    expect(layer.activeFieldId, 1);
    expect(layer.nodes[1]?.name, 'Root');
  });
}

class _MissingFieldRepository implements FieldRepository {
  @override
  Future<FieldCache> load() async =>
      const FieldCache.empty(needsJournalReplay: true);

  @override
  Future<void> save({
    required int? activeFieldId,
    required List<FieldNode> nodes,
    required int lastJournalId,
  }) async {}
}

class _MemoryFieldRepository implements FieldRepository {
  _MemoryFieldRepository(this.cache);

  FieldCache cache;
  int? lastJournalId;

  @override
  Future<FieldCache> load() async => cache;

  @override
  Future<void> save({
    required int? activeFieldId,
    required List<FieldNode> nodes,
    required int lastJournalId,
  }) async {
    this.lastJournalId = lastJournalId;
  }
}
