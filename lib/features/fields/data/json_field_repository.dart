import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:polyrutina/core/data/atomic_json.dart';
import 'package:polyrutina/features/fields/application/field_repository.dart';
import 'package:polyrutina/features/fields/domain/field_node.dart';

class JsonFieldRepository implements FieldRepository {
  final File? _testFile;

  JsonFieldRepository({File? file}) : _testFile = file;

  Future<File> _targetFile() async {
    final testFile = _testFile;
    if (testFile != null) return testFile;
    final directory = await getApplicationDocumentsDirectory();
    return File(p.join(directory.path, 'field_layer.json'));
  }

  @override
  Future<FieldCache> load() async {
    final file = await _targetFile();
    if (!await file.exists()) {
      return const FieldCache.empty(needsJournalReplay: true);
    }

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid field cache');
      }

      final nodes = <FieldNode>[];
      final rawNodes = decoded['nodes'];
      if (rawNodes is List) {
        for (final rawNode in rawNodes) {
          if (rawNode is! Map) continue;
          try {
            nodes.add(FieldNode.fromJson(Map<String, dynamic>.from(rawNode)));
          } on FormatException catch (error) {
            _logMalformedNode(error);
          } on TypeError catch (error) {
            _logMalformedNode(error);
          }
        }
      }

      return FieldCache(
        activeFieldId: (decoded['active_field_id'] as num?)?.toInt(),
        nodes: nodes,
        needsJournalReplay: false,
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
    required int? activeFieldId,
    required List<FieldNode> nodes,
  }) async {
    final data = {
      'active_field_id': activeFieldId,
      'nodes': nodes.map((node) => node.toJson()).toList(),
    };
    final file = await _targetFile();
    await atomicWriteJson(file, data);
  }

  FieldCache _invalidCache(Object error) {
    debugPrint('Failed to read field cache; replaying journal: $error');
    return const FieldCache.empty(needsJournalReplay: true);
  }

  void _logMalformedNode(Object error) {
    debugPrint('Skipping malformed field node in cache: $error');
  }
}
