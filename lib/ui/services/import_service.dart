// ═══════════════════════════════════════════════════════════════════
// import_service.dart — receiving routines from zip.
//
// Opened from the rubka's «import» pult: the system file sheet
// (FileType.custom, *.zip, multiple). Each archive is read:
//   data.json — routines, the field tree, and the series block;
//   media/<name> — media files, matched by name against the traces.
//
// Streaming. The archive is decoded using a stream (InputFileStream)
// rather than loading the entire file into memory, preventing OOM
// errors on large archives. Media files are also streamed directly
// to disk.
//
// data.json shape. ONE shape is accepted:
//   {"schema": 1, "fields": [...], "series": {...}, "routines": [ ... ]}
// The `series` block is optional; archives without it simply import
// no series. Both the new `notice_before_sec` + `notice_set` pair
// and the old `planned_seconds` field are accepted; see
// report_json.dart for the mapping.
//
// Unified shift in archives. Newer exports carry shift series only
// under field 0. Older archives may carry per-field entries. On
// import, any shift month is collapsed under field 0 — the field
// id in the archive is ignored for the shift kind. Totals are not
// added: the last entry for a given (year, month) wins, mirroring
// the way the unified shift keeps a single state rather than a sum.
// The bort series is already field 0 by construction.
//
// Notice interval. The routine is applied via setNotice when the
// imported archive carries a notice interval. If the routine has a
// date and the notice is set, setNotice is called AFTER setSchedule
// so that the layer does not reject it (setNotice bails when there
// is no date). If the archive carries no notice, nothing is called;
// the routine keeps its defaults.
//
// Deduplication. The source key of each parsed routine is
// «deviceId/firstRun/routineId»; re-importing the same archive is
// idempotent.
//
// Media orphan prevention. Media files are copied into media/ ONLY
// for routines that are actually going to be imported, under fresh
// monotone names (via nextMediaIndex). If the transaction fails,
// every file written during the attempt is removed.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/journal_layer.dart';
import '../../data/journal_types.dart';
import '../../data/routine_layer.dart';
import '../../data/trace_layer.dart';
import '../core/app_scope.dart';
import '../core/format.dart';
import 'report_json.dart';

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
  required AppContext app,
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
    } catch (_) {}
  }
  onProgress?.call(1.0);
  return total;
}

Future<ImportResult> _importZip(AppContext app, String path) async {
  final inputStream = InputFileStream(path);
  final archive = ZipDecoder().decodeBuffer(inputStream);

  final dataFile = archive.findFile('data.json');
  if (dataFile == null) {
    await inputStream.close();
    return const ImportResult();
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
    await inputStream.close();
    return const ImportResult();
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

      final idx = app.bort.nextMediaIndex();
      final ext = p.extension(baseName);
      final safe = safeFileName(
        'media_${idx}_${app.bort.deviceId}_${app.bort.firstRunUnixSec}$ext',
      );
      final target = File(p.join(mediaDir.path, safe));

      final outputStream = OutputFileStream(target.path);
      file.writeContent(outputStream);
      outputStream.closeSync();

      written.add(target.path);
      extracted[baseName] = target.path;
      mediaBytes += await target.length();
    }
  } catch (_) {
    await _rollback(written);
    await inputStream.close();
    return ImportResult(skipped: skipped);
  }

  await inputStream.close();

  // Phase 3: apply in a single transaction; roll back media on
  // failure so that no orphan file survives.
  var imported = 0;
  try {
    await app.journal.transaction(() async {
      final fieldIdMap = <int, int>{};

      // 3a. Restore field tree topology, if present.
      if (fieldList != null) {
        final fields = fieldList;
        for (final f in fields) {
          if (f is! Map) continue;
          final oldId = (f['id'] as num?)?.toInt();
          if (oldId == null) continue;
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
      // Old archives that carried per-field shift entries are
      // collapsed under 0 here — the last entry for a (year, month)
      // wins, which mirrors the single-state semantics of the
      // unified shift. A non-zero field id from the archive is
      // ignored for shift and bort kinds alike.
      for (final m in months) {
        final isUnified = m.kind == 'shift' || m.kind == 'bort';
        final targetFieldId = isUnified ? 0 : m.fieldId;
        app.bort.applySeriesMonth(
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
  } catch (_) {
    await _rollback(written);
    return ImportResult(skipped: skipped);
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
    } catch (_) {}
  }
}

Future<void> _applyParsed(
  AppContext app,
  ParsedRoutine p,
  Map<String, String> extracted,
  Map<int, int> fieldIdMap,
) async {
  final RoutineLayer routineLayer = app.routineLayer;
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
