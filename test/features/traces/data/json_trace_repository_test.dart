import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:polyrutina/features/traces/data/json_trace_repository.dart';
import 'package:polyrutina/features/traces/domain/trace.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('trace-repository-test-');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('missing cache requests journal replay', () async {
    final repository = JsonTraceRepository(
      file: File(p.join(directory.path, 'trace_layer.json')),
    );

    expect((await repository.load()).needsJournalReplay, isTrue);
  });

  test('round trips traces using the current cache schema', () async {
    final file = File(p.join(directory.path, 'trace_layer.json'));
    final repository = JsonTraceRepository(file: file);
    final trace = Trace(id: 5, slot: 'note', text: 'Observation');

    await repository.save(traces: [trace], lastJournalId: 17);
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final restored = await repository.load();

    expect(raw['schema'], 1);
    expect(restored.lastJournalId, 17);
    expect(restored.needsJournalReplay, isFalse);
    expect(restored.traces.single.id, 5);
    expect(restored.traces.single.text, 'Observation');
  });

  test('replays the journal for an unsupported or malformed cache', () async {
    final file = File(p.join(directory.path, 'trace_layer.json'));
    final repository = JsonTraceRepository(file: file);

    await file.writeAsString(jsonEncode({'schema': 0, 'traces': <dynamic>[]}));
    expect((await repository.load()).needsJournalReplay, isTrue);

    await file.writeAsString('{invalid');
    expect((await repository.load()).needsJournalReplay, isTrue);
  });
}
