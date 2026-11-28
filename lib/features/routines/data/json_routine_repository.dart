import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:polyrutina/core/data/atomic_json.dart';
import 'package:polyrutina/features/routines/application/routine_repository.dart';
import 'package:polyrutina/features/routines/domain/routine.dart';

class JsonRoutineRepository implements RoutineRepository {
  static const int _schemaVersion = 2;

  final File? _testFile;

  JsonRoutineRepository({File? file}) : _testFile = file;

  Future<File> _targetFile() async {
    final testFile = _testFile;
    if (testFile != null) return testFile;
    final directory = await getApplicationDocumentsDirectory();
    return File(p.join(directory.path, 'routine_layer.json'));
  }

  @override
  Future<RoutineCache> load() async {
    final file = await _targetFile();
    if (!await file.exists()) {
      return const RoutineCache.empty(needsJournalReplay: true);
    }

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid routine cache');
      }

      final schema = (decoded['schema'] as num?)?.toInt() ?? 0;
      if (schema < _schemaVersion) {
        return const RoutineCache.empty(needsJournalReplay: true);
      }

      final routines = <Routine>[];
      final rawRoutines = decoded['routines'];
      if (rawRoutines is List) {
        for (final rawRoutine in rawRoutines) {
          if (rawRoutine is! Map) continue;
          try {
            routines.add(
              Routine.fromJson(Map<String, dynamic>.from(rawRoutine)),
            );
          } on FormatException catch (error) {
            _logMalformedRoutine(error);
          } on TypeError catch (error) {
            _logMalformedRoutine(error);
          }
        }
      }
      return RoutineCache(
        routines: routines,
        lastActiveBlockKind: decoded['last_active_block_kind'] as String?,
        needsJournalReplay: routines.isEmpty,
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
    required List<Routine> routines,
    required String? lastActiveBlockKind,
    required int lastJournalId,
  }) async {
    final data = {
      'schema': _schemaVersion,
      'routines': routines.map((routine) => routine.toJson()).toList(),
      'last_active_block_kind': lastActiveBlockKind,
      'last_journal_id': lastJournalId,
    };
    final file = await _targetFile();
    await atomicWriteJson(file, data);
  }

  RoutineCache _invalidCache(Object error) {
    debugPrint('Failed to read routine cache; replaying journal: $error');
    return const RoutineCache.empty(needsJournalReplay: true);
  }

  void _logMalformedRoutine(Object error) {
    debugPrint('Skipping malformed routine in cache: $error');
  }
}
