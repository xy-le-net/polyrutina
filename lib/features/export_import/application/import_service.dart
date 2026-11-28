import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:polyrutina/core/data/journal_layer.dart';
import 'package:polyrutina/core/domain/journal_types.dart';
import 'package:polyrutina/features/routines/application/routine_access.dart';
import 'package:polyrutina/features/traces/application/trace_layer.dart';
import 'package:polyrutina/features/export_import/application/export_context.dart';
import 'package:polyrutina/shared/application/format.dart';
import 'package:polyrutina/features/export_import/application/report_json.dart';

class ImportResult {
  final int routines;
  final int media;
  final int bytes;
  final int skipped;
  final bool cancelled;
  final bool empty;

  const ImportResult({
    this.routines = 0,
    this.media = 0,
    this.bytes = 0,
    this.skipped = 0,
    this.cancelled = false,
    this.empty = false,
  });

  ImportResult merge(ImportResult other) => ImportResult(
    routines: routines + other.routines,
    media: media + other.media,
    bytes: bytes + other.bytes,
    skipped: skipped + other.skipped,
    cancelled: cancelled || other.cancelled,
    empty: routines + other.routines + media + other.media == 0,
  );
}

Future<ImportResult> importFromPicker({
  required ExportContext app,
  ValueChanged<double>? onProgress,
}) async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['zip'],
    allowMultiple: true,
  );
  if (picked == null || picked.files.isEmpty) {
    return const ImportResult(cancelled: true);
  }

  var total = const ImportResult();
  for (var i = 0; i < picked.files.length; i++) {
    final f = picked.files[i];
    if (f.path == null) continue;
    onProgress?.call(i / picked.files.length);
    try {
      total = total.merge(await _importZip(app, f.path!));
    } catch (error, stackTrace) {
      debugPrint('archive import skipped for ${f.path}: $error\n$stackTrace');
      total = total.merge(const ImportResult(skipped: 1));
    }
  }
  onProgress?.call(1.0);
  return total;
}

Future<ImportResult> _importZip(ExportContext app, String path) async {
  final inputStream = InputFileStream(path);
  late final Archive archive;
  try {
    archive = ZipDecoder().decodeBuffer(inputStream);
  } catch (_) {
    await inputStream.close();
    rethrow;
  }
  await inputStream.close();

  final dataFile = archive.findFile('data.json');
  if (dataFile == null) {
    return const ImportResult(skipped: 1);
  }

  final dataStr = utf8.decode(dataFile.content as List<int>);
  final Object? decoded = jsonDecode(dataStr);

  final list = <Map<String, dynamic>>[];
  List<dynamic>? fieldList;
  List<ParsedMonth> months = const [];
  if (decoded is Map) {
    final routines = decoded['routines'];
    if (routines is List) {
      for (final Object? e in routines) {
        if (e is Map) list.add(Map<String, dynamic>.from(e));
      }
    }
    if (decoded['fields'] is List) {
      fieldList = decoded['fields'] as List;
    }
    months = ReportJson.parseSeries(Map<String, dynamic>.from(decoded));
  }
  if (list.isEmpty && months.isEmpty) {
    return const ImportResult(skipped: 1);
  }

  // Phase 1: parse and skip already-present routines.
  final toImport = <ParsedRoutine>[];
  var skipped = 0;
  for (final raw in list) {
    final parsed = ReportJson.parseRoutine(raw);
    if (parsed == null) continue;
    if (app.routineLayer.findRoutineBySourceKey(parsed.key) != null) {
      skipped++;
      continue;
    }
    toImport.add(parsed);
  }

  // Phase 2: extract media — only the files referenced by the
  // routines we are about to import.
  final needed = <String>{};
  for (final r in toImport) {
    for (final t in r.traces) {
      for (final f in t.files) {
        if (f.kind == MediaKind.geo) continue;
        if (f.name.isNotEmpty) needed.add(f.name);
      }
    }
  }

  final dir = await getApplicationDocumentsDirectory();
  final mediaDir = Directory(p.join(dir.path, 'media'));
  if (!await mediaDir.exists()) await mediaDir.create(recursive: true);

  final written = <String>[];
  final extracted = <String, String>{};
  var mediaBytes = 0;
  try {
    for (final file in archive.files) {
      if (!file.isFile) continue;
      if (!file.name.startsWith('media/')) continue;
      final rel = file.name.substring('media/'.length);
      final baseName = p.basename(rel);
      if (!needed.contains(baseName)) continue;

      final idx = app.settings.nextMediaIndex();
      final ext = p.extension(baseName);
      final safe = safeFileName(
        'media_${idx}_${app.settings.deviceId}_${app.settings.firstRunUnixSec}$ext',
      );
      final target = File(p.join(mediaDir.path, safe));

      final outputStream = OutputFileStream(target.path);
      file.writeContent(outputStream);
      outputStream.closeSync();

      written.add(target.path);
      extracted[baseName] = target.path;
      mediaBytes += await target.length();
    }
  } catch (error, stackTrace) {
    debugPrint('archive media extraction failed: $error\n$stackTrace');
    await _rollback(written);
    return ImportResult(skipped: skipped + 1);
  }

  // Phase 3: apply in a single transaction; roll back media on
  // failure so that no orphan file survives.
  var imported = 0;
  try {
    await app.journal.transaction(() async {
      final fieldIdMap = <int, int>{};

      // 3a. Restore field tree topology, if present.
      if (fieldList != null && toImport.isNotEmpty) {
        final fields = fieldList;
        int? defaultRootOldId;
        for (final f in fields) {
          if (f is! Map || f['is_root'] != true) continue;
          final oldId = (f['id'] as num?)?.toInt();
          if (oldId == null) continue;
          if (f['default_root'] == true) {
            defaultRootOldId = oldId;
            break;
          }
          defaultRootOldId ??= oldId;
        }

        for (final f in fields) {
          if (f is! Map) continue;
          final oldId = (f['id'] as num?)?.toInt();
          if (oldId == null) continue;
          if (oldId == defaultRootOldId && app.fieldLayer.rootId != null) {
            fieldIdMap[oldId] = app.fieldLayer.rootId!;
            continue;
          }
          final name = f['name'] as String? ?? '';
          final isRoot = f['is_root'] as bool? ?? false;

          final newId = await app.journal.log(
            type: JournalType.fieldNode,
            body: jsonEncode({
              'action': 'create',
              'name': name,
              'is_root': isRoot,
            }),
          );
          fieldIdMap[oldId] = newId;
        }

        for (final f in fields) {
          if (f is! Map) continue;
          final oldId = (f['id'] as num?)?.toInt();
          final newId = fieldIdMap[oldId];
          if (oldId == null || newId == null) continue;

          final oldParents =
              (f['parents'] as List?)
                  ?.map((e) => (e as num).toInt())
                  .toList() ??
              [];
          for (final oldParentId in oldParents) {
            final newParentId = fieldIdMap[oldParentId];
            if (newParentId != null) {
              await app.journal.log(
                type: JournalType.fieldNode,
                body: jsonEncode({
                  'action': 'attach',
                  'id': newId,
                  'parent': newParentId,
                }),
              );
            }
          }
        }
      }

      // 3b. Apply series months.
      // The unified shift lives under field 0; the bort series too.
      // collapsed under 0 here — the last entry for a (year, month)
      // wins, which mirrors the single-state semantics of the
      // unified shift. A non-zero field id from the archive is
      // ignored for shift and bort kinds alike.
      for (final m in months) {
        final isUnified = m.kind == 'shift' || m.kind == 'bort';
        final targetFieldId = isUnified ? 0 : m.fieldId;
        app.settings.applySeriesMonth(
          m.kind,
          targetFieldId,
          m.year,
          m.month,
          m.days,
        );
      }

      // 3c. Apply routines, binding them to the new field IDs.
      for (final parsed in toImport) {
        await _applyParsed(app, parsed, extracted, fieldIdMap);
      }
    });
    imported = toImport.length;
  } catch (error, stackTrace) {
    debugPrint('archive journal import failed: $error\n$stackTrace');
    await _rollback(written);
    return ImportResult(skipped: skipped + 1);
  }

  return ImportResult(
    routines: imported,
    media: extracted.length,
    bytes: mediaBytes,
    skipped: skipped,
  );
}

Future<void> _rollback(List<String> written) async {
  for (final w in written) {
    try {
      final f = File(w);
      if (await f.exists()) await f.delete();
    } catch (error, stackTrace) {
      debugPrint('failed to roll back imported media $w: $error\n$stackTrace');
    }
  }
}

Future<void> _applyParsed(
  ExportContext app,
  ParsedRoutine p,
  Map<String, String> extracted,
  Map<int, int> fieldIdMap,
) async {
  final RoutineAccess routineLayer = app.routineLayer;
  final TraceLayer traceLayer = app.traceLayer;
  final JournalLayer journal = app.journal;

  final newFieldParents = <int>[];
  for (final oldParentId in p.fieldParents) {
    final newId = fieldIdMap[oldParentId];
    if (newId != null) newFieldParents.add(newId);
  }
  if (newFieldParents.isEmpty) {
    final rootId = app.fieldLayer.rootId;
    if (rootId != null) newFieldParents.add(rootId);
  }

  final r = await routineLayer.createRoutine(
    journal,
    sourceKey: p.key,
    createdAt: p.createdAt > 0 ? p.createdAt : null,
    fieldParents: newFieldParents,
  );
  if (p.name.isNotEmpty) {
    await routineLayer.renameRoutine(journal, r.id, p.name);
  }
  if (p.flags != 0) {
    await routineLayer.setFlags(journal, r.id, p.flags);
  }

  for (final b in p.blocks) {
    if (b.accumulator > 0) {
      await routineLayer.setBlockTime(journal, r.id, b.kind, b.accumulator);
    }
  }

  // Schedule first, then notice: setNotice refuses to act when
  // there is no date, and the import must not depend on ordering
  // tricks in the layer.
  if (p.scheduledAt != null) {
    await routineLayer.setSchedule(journal, r.id, p.scheduledAt);
  }
  if (p.noticeSet) {
    await routineLayer.setNotice(journal, r.id, p.noticeBeforeSec);
  }
  if (p.completed) {
    await routineLayer.setCompleted(journal, r.id, true);
  }

  for (final t in p.traces) {
    if (t.kind == TraceKind.checklist) {
      final items = t.items
          .where((it) => it.text.trim().isNotEmpty)
          .map((it) => it.text)
          .toList();
      if (items.isNotEmpty) {
        final id = await traceLayer.createChecklist(
          journal,
          slot: t.slot,
          items: items,
          parents: [r.id],
        );
        final full = <TraceItem>[];
        for (var i = 0; i < items.length; i++) {
          final done = i < t.items.length ? t.items[i].done : false;
          full.add(TraceItem(text: items[i], done: done));
        }
        if (full.any((e) => e.done)) {
          await traceLayer.updateItems(journal, id, full);
        }
      }
    } else if (t.text.isNotEmpty) {
      await traceLayer.createText(
        journal,
        slot: t.slot,
        text: t.text,
        parents: [r.id],
      );
    }

    for (final f in t.files) {
      String path = '';
      if (f.kind == MediaKind.geo) {
        // Geo: no file, only coordinates.
      } else {
        path = extracted[f.name] ?? '';
        if (path.isEmpty) continue;
      }
      await traceLayer.attachFile(
        journal,
        objectId: r.id,
        slot: t.slot,
        file: TraceFile(
          kind: f.kind,
          path: path,
          name: f.name,
          lat: f.lat,
          lon: f.lon,
          acc: f.acc,
        ),
      );
    }
  }

  final live = routineLayer.findRoutine(r.id);
  if (live != null) {
    if (p.lastPulseAt != null) live.lastPulseAt = p.lastPulseAt;
    if (p.completedAt != null) live.completedAt = p.completedAt;
    await routineLayer.writeSnapshot(journal, live);
  }
}
