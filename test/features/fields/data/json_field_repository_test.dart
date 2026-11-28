import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:polyrutina/features/fields/data/json_field_repository.dart';
import 'package:polyrutina/features/fields/domain/field_node.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('field-repository-test-');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('missing cache requests journal replay', () async {
    final repository = JsonFieldRepository(
      file: File(p.join(directory.path, 'field_layer.json')),
    );

    final cache = await repository.load();

    expect(cache.needsJournalReplay, isTrue);
    expect(cache.nodes, isEmpty);
  });

  test('round trips the existing field cache shape', () async {
    final file = File(p.join(directory.path, 'field_layer.json'));
    final repository = JsonFieldRepository(file: file);
    final node = FieldNode(id: 8, name: 'Root', children: [9], isRoot: true);

    await repository.save(activeFieldId: 8, nodes: [node], lastJournalId: 17);
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final restored = await repository.load();

    expect(
      raw.keys,
      containsAll(['active_field_id', 'nodes', 'last_journal_id']),
    );
    expect(restored.lastJournalId, 17);
    expect(restored.needsJournalReplay, isFalse);
    expect(restored.activeFieldId, 8);
    expect(restored.nodes.single.toJson(), node.toJson());
  });

  test('an empty cache requests replay to restore the default root', () async {
    final file = File(p.join(directory.path, 'field_layer.json'));
    final repository = JsonFieldRepository(file: file);
    await file.writeAsString(
      jsonEncode({
        'active_field_id': null,
        'nodes': <dynamic>[],
        'last_journal_id': 99,
      }),
    );

    expect((await repository.load()).needsJournalReplay, isTrue);
  });

  test(
    'skips malformed nodes but requests replay for an invalid cache',
    () async {
      final file = File(p.join(directory.path, 'field_layer.json'));
      final repository = JsonFieldRepository(file: file);

      await file.writeAsString(
        jsonEncode({
          'active_field_id': 8,
          'nodes': [
            {'id': 8, 'name': 'Root', 'is_root': true},
            {'id': 'invalid'},
          ],
        }),
      );
      final partialCache = await repository.load();
      expect(partialCache.nodes.map((node) => node.id), [8]);
      expect(partialCache.needsJournalReplay, isFalse);

      await file.writeAsString('{invalid');
      final invalidCache = await repository.load();
      expect(invalidCache.needsJournalReplay, isTrue);
    },
  );
}
