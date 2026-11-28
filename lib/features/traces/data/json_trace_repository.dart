import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:polyrutina/core/data/atomic_json.dart';
import 'package:polyrutina/features/traces/application/trace_repository.dart';
import 'package:polyrutina/features/traces/domain/trace.dart';

class JsonTraceRepository implements TraceRepository {
  static const int _schemaVersion = 1;

  final File? _testFile;

  JsonTraceRepository({File? file}) : _testFile = file;

  Future<File> _targetFile() async {
    final testFile = _testFile;
    if (testFile != null) return testFile;
    final directory = await getApplicationDocumentsDirectory();
    return File(p.join(directory.path, 'trace_layer.json'));
  }

  @override
  Future<TraceCache> load() async {
    final file = await _targetFile();
    if (!await file.exists()) {
      return const TraceCache.empty(needsJournalReplay: true);
    }

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid trace cache');
      }

      final schema = (decoded['schema'] as num?)?.toInt() ?? 0;
      if (schema < _schemaVersion) {
        return const TraceCache.empty(needsJournalReplay: true);
      }

      final traces = <Trace>[];
      final rawTraces = decoded['traces'];
      if (rawTraces is List) {
        for (final rawTrace in rawTraces) {
          final traceData = Map<String, dynamic>.from(rawTrace as Map);
          final id = (traceData['id'] as num).toInt();
          traces.add(Trace.fromJson(id, traceData));
        }
      }
      return TraceCache(
        traces: traces,
        needsJournalReplay: false,
        lastJournalId: (decoded['last_journal_id'] as num?)?.toInt() ?? 0,
      );
    } on FormatException catch (error) {
      return _invalidCache(error);
    } on TypeError catch (error) {
      return _invalidCache(error);
    } on FileSystemException catch (error) {
      return _invalidCache(error);
    }
  }

  @override
  Future<void> save({
    required List<Trace> traces,
    required int lastJournalId,
  }) async {
    final data = {
      'schema': _schemaVersion,
      'last_journal_id': lastJournalId,
      'traces': traces
          .map((trace) => {'id': trace.id, ...trace.toJson()})
          .toList(),
    };
    final file = await _targetFile();
    await atomicWriteJson(file, data);
  }

  TraceCache _invalidCache(Object error) {
    debugPrint('Failed to read trace cache; replaying journal: $error');
    return const TraceCache.empty(needsJournalReplay: true);
  }
}
