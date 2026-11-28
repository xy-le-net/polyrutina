import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:polyrutina/features/routines/data/json_routine_repository.dart';
import 'package:polyrutina/features/routines/domain/routine.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'routine-repository-test-',
    );
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('missing cache requests journal replay', () async {
    final repository = JsonRoutineRepository(
      file: File(p.join(directory.path, 'routine_layer.json')),
    );

    expect((await repository.load()).needsJournalReplay, isTrue);
  });

  test('round trips the current routine cache schema and metadata', () async {
    final file = File(p.join(directory.path, 'routine_layer.json'));
    final repository = JsonRoutineRepository(file: file);
    final routine = Routine.create(4, createdAt: 123)..name = 'Morning';

    await repository.save(routines: [routine], lastActiveBlockKind: 'work');
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final restored = await repository.load();

    expect(raw['schema'], 2);
    expect(restored.needsJournalReplay, isFalse);
    expect(restored.lastActiveBlockKind, 'work');
    expect(restored.routines.single.toJson(), routine.toJson());
  });

  test('replays the journal for empty or malformed caches', () async {
    final file = File(p.join(directory.path, 'routine_layer.json'));
    final repository = JsonRoutineRepository(file: file);

    await file.writeAsString(
      jsonEncode({
        'schema': 2,
        'routines': <dynamic>[],
        'last_active_block_kind': null,
      }),
    );
    expect((await repository.load()).needsJournalReplay, isTrue);

    await file.writeAsString('{invalid');
    expect((await repository.load()).needsJournalReplay, isTrue);
  });
}
