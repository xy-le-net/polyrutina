import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:polyrutina/core/data/journal_layer.dart';
import 'package:polyrutina/core/domain/journal_types.dart';
import 'package:polyrutina/features/traces/application/trace_layer.dart';
import 'package:polyrutina/features/traces/application/trace_repository.dart';
import '../../../support/memory_journal_repository.dart';

void main() {
  test('replays trace entries when the cache is missing', () async {
    final journalRepository = MemoryJournalRepository();
    await journalRepository.insert(
      type: JournalType.trace,
      body: jsonEncode({
        'kind': TraceKind.text,
        'slot': 'note',
        'text': 'Restored',
        'parents': [42],
      }),
    );
    final journal = JournalLayer(journalRepository);
    final layer = TraceLayer(_MissingTraceRepository());
    addTearDown(journal.dispose);
    addTearDown(layer.dispose);

    await layer.init(journal);

    expect(layer.traces.values.single.text, 'Restored');
    expect(layer.traces.values.single.parents, [42]);
  });
}

class _MissingTraceRepository implements TraceRepository {
  @override
  Future<TraceCache> load() async =>
      const TraceCache.empty(needsJournalReplay: true);

  @override
  Future<void> save({required List<Trace> traces}) async {}
}
