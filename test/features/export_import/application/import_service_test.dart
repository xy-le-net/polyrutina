import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:polyrutina/core/data/journal_layer.dart';
import 'package:polyrutina/features/export_import/application/export_context.dart';
import 'package:polyrutina/features/export_import/application/import_archive_reader.dart';
import 'package:polyrutina/features/export_import/application/import_media_repository.dart';
import 'package:polyrutina/features/export_import/application/import_service.dart';
import 'package:polyrutina/features/fields/application/field_access.dart';
import 'package:polyrutina/features/fields/domain/field_node.dart';
import 'package:polyrutina/features/routines/application/routine_layer.dart';
import 'package:polyrutina/features/routines/application/routine_repository.dart';
import 'package:polyrutina/features/routines/domain/routine.dart';
import 'package:polyrutina/features/settings/application/operational_access.dart';
import 'package:polyrutina/features/settings/domain/time_series.dart';
import 'package:polyrutina/features/traces/application/trace_access.dart';
import 'package:polyrutina/features/traces/domain/trace.dart';
import '../../../support/memory_journal_repository.dart';

void main() {
  test(
    'imports manifest data and stores referenced media through ports',
    () async {
      final journal = JournalLayer(MemoryJournalRepository());
      final routines = RoutineLayer(
        repository: _MemoryRoutineRepository(),
        fieldContext: () => (activeFieldId: null, rootId: 9),
        copyTraces: (journal, sourceId, targetId, slots) async {},
      );
      final traces = _MemoryTraceAccess();
      final media = _MemoryMediaRepository();
      final manifest = {
        'routines': [
          {
            'schema': 1,
            'source_device': 'source',
            'source_first_run': 10,
            'source_routine_id': 3,
            'name': 'Imported',
            'traces': [
              {
                'kind': TraceKind.text,
                'slot': 'note',
                'text': 'A field observation',
                'files': [
                  {'kind': MediaKind.photo, 'name': 'photo.jpg'},
                ],
              },
            ],
          },
        ],
      };
      final service = ArchiveImportService(
        archiveReader: _MemoryArchiveReader([
          ImportArchiveEntry(
            name: 'data.json',
            isFile: true,
            content: utf8.encode(jsonEncode(manifest)),
          ),
          const ImportArchiveEntry(
            name: 'media/photo.jpg',
            isFile: true,
            content: [1, 2, 3],
          ),
        ]),
        mediaRepository: media,
      );
      final context = ExportContext(
        journal: journal,
        fieldLayer: _MemoryFieldAccess(),
        routineLayer: routines,
        settings: _MemoryOperationalAccess(),
        traceLayer: traces,
      );
      addTearDown(journal.dispose);
      addTearDown(routines.dispose);
      await routines.init(journal);

      final result = await service.importArchives(
        app: context,
        paths: ['input'],
      );

      expect(result.routines, 1);
      expect(result.media, 1);
      expect(result.bytes, 3);
      final routine = routines.findRoutineBySourceKey('source/10/3');
      expect(routine?.name, 'Imported');
      expect(routine?.fieldParents, [9]);
      expect(
        traces.traces.values.single.files.single.path,
        startsWith('memory:'),
      );
      expect(media.files.values.single, [1, 2, 3]);
    },
  );
}

class _MemoryArchiveReader implements ImportArchiveReader {
  _MemoryArchiveReader(this.entries);

  final List<ImportArchiveEntry> entries;

  @override
  Future<List<ImportArchiveEntry>> read(String path) async => entries;
}

class _MemoryMediaRepository implements ImportMediaRepository {
  final Map<String, List<int>> files = {};
  int _nextId = 0;

  @override
  Future<String> save(String fileName, List<int> bytes) async {
    final path = 'memory:${_nextId++}/$fileName';
    files[path] = List.of(bytes);
    return path;
  }

  @override
  Future<void> delete(String path) async {
    files.remove(path);
  }
}

class _MemoryFieldAccess implements FieldAccess {
  @override
  final Map<int, FieldNode> nodes = {};

  @override
  int? get rootId => 9;
}

class _MemoryOperationalAccess implements OperationalAccess {
  int _nextMediaIndex = 0;

  @override
  String get deviceId => 'target';

  @override
  int get firstRunUnixSec => 20;

  @override
  final Map<String, TimeSeries> series = {};

  @override
  void applySeriesMonth(
    String kind,
    int fieldId,
    int year,
    int month,
    Map<int, int> days,
  ) {}

  @override
  int nextExportIndex(String objectKey) => 0;

  @override
  int nextMediaIndex() => _nextMediaIndex++;

  @override
  void setLastExportId(int id) {}

  @override
  void setLastRereadId(int id) {}
}

class _MemoryTraceAccess implements TraceAccess {
  int _nextId = 100;

  @override
  final Map<int, Trace> traces = {};

  @override
  Future<void> attachFile(
    JournalLayer journal, {
    required int objectId,
    required String slot,
    required TraceFile file,
  }) async {
    final trace = traces.values.firstWhere(
      (trace) => trace.slot == slot && trace.parents.contains(objectId),
    );
    trace.files.add(file);
  }

  @override
  Future<int> createChecklist(
    JournalLayer journal, {
    String slot = '',
    List<String> items = const [],
    List<int> parents = const [],
    List<int> fieldParents = const [],
  }) async {
    final id = _nextId++;
    traces[id] = Trace(
      id: id,
      kind: TraceKind.checklist,
      slot: slot,
      items: [for (final item in items) TraceItem(text: item)],
      parents: List.of(parents),
      fieldParents: List.of(fieldParents),
    );
    return id;
  }

  @override
  Future<int> createText(
    JournalLayer journal, {
    String slot = '',
    String text = '',
    List<int> parents = const [],
    List<int> fieldParents = const [],
  }) async {
    final id = _nextId++;
    traces[id] = Trace(
      id: id,
      slot: slot,
      text: text,
      parents: List.of(parents),
      fieldParents: List.of(fieldParents),
    );
    return id;
  }

  @override
  Future<void> updateItems(
    JournalLayer journal,
    int traceId,
    List<TraceItem> items,
  ) async {
    traces[traceId]?.items = items;
  }
}

class _MemoryRoutineRepository implements RoutineRepository {
  @override
  Future<RoutineCache> load() async =>
      const RoutineCache.empty(needsJournalReplay: true);

  @override
  Future<void> save({
    required List<Routine> routines,
    required String? lastActiveBlockKind,
  }) async {}
}
