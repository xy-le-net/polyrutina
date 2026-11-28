import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:polyrutina/core/data/journal_layer.dart';
import 'package:polyrutina/core/domain/journal_types.dart';
import 'package:polyrutina/features/routines/application/routine_layer.dart';
import 'package:polyrutina/features/routines/application/routine_repository.dart';
import 'package:polyrutina/features/routines/domain/routine.dart';
import '../../../support/memory_journal_repository.dart';

void main() {
  test(
    'replays journal entries newer than the routine cache checkpoint',
    () async {
      final journalRepository = MemoryJournalRepository();
      await journalRepository.insert(
        type: JournalType.routine,
        body: jsonEncode({'action': 'create', 'routine': 1}),
      );
      await journalRepository.insert(
        type: JournalType.routine,
        body: jsonEncode({'action': 'rename', 'routine': 1, 'name': 'Updated'}),
      );
      final journal = JournalLayer(journalRepository);
      final cached = Routine.create(1, at: 100)..name = 'Cached';
      final repository = _MemoryRoutineRepository(
        RoutineCache(
          routines: [cached],
          lastActiveBlockKind: null,
          needsJournalReplay: false,
          lastJournalId: 1,
        ),
      );
      final layer = RoutineLayer(
        repository: repository,
        fieldContext: () => (activeFieldId: null, rootId: null),
        copyTraces: (journal, sourceId, targetId, slots) async {},
      );
      addTearDown(journal.dispose);
      addTearDown(layer.dispose);

      await layer.init(journal);
      expect(layer.findRoutine(1)?.name, 'Cached');

      await journal.pump();
      await layer.saveNow();

      expect(layer.findRoutine(1)?.name, 'Updated');
      expect(repository.lastJournalId, 2);
    },
  );

  test('uses injected field context and trace-copy contract', () async {
    final journalRepository = MemoryJournalRepository();
    await journalRepository.insert(
      type: JournalType.routine,
      body: jsonEncode({
        'action': 'create',
        'field_parents': [5],
      }),
    );
    final journal = JournalLayer(journalRepository);
    final repository = _MemoryRoutineRepository();
    int? copiedFrom;
    int? copiedTo;
    List<String>? copiedSlots;
    final layer = RoutineLayer(
      repository: repository,
      fieldContext: () => (activeFieldId: 12, rootId: 3),
      copyTraces: (journal, sourceId, targetId, slots) async {
        copiedFrom = sourceId;
        copiedTo = targetId;
        copiedSlots = slots;
      },
    );
    addTearDown(journal.dispose);
    addTearDown(layer.dispose);

    await layer.init(journal);
    expect(layer.routines.single.fieldParents, [5]);
    final source = await layer.createRoutine(journal);
    final duplicate = await layer.duplicateRoutine(journal, source.id);

    expect(source.fieldParents, [12]);
    expect(duplicate, isNotNull);
    expect(copiedFrom, source.id);
    expect(copiedTo, duplicate!.id);
    expect(copiedSlots, ['note', 'prep', 'closeout']);
  });
}

class _MemoryRoutineRepository implements RoutineRepository {
  _MemoryRoutineRepository([
    this.cache = const RoutineCache.empty(needsJournalReplay: true),
  ]);

  RoutineCache cache;
  int? lastJournalId;

  @override
  Future<RoutineCache> load() async => cache;

  @override
  Future<void> save({
    required List<Routine> routines,
    required String? lastActiveBlockKind,
    required int lastJournalId,
  }) async {
    this.lastJournalId = lastJournalId;
  }
}
