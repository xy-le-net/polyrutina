// ═══════════════════════════════════════════════════════════════════
// import_service.dart — receiving routines from zip.
//
// Opened from the rubka's «import» pult: the system file sheet
// (FileType.custom, *.zip, multiple). Each archive is read:
//   data.json — the routine(s) as a whole;
//   media/<name> — media files, matched by name against the traces.
//
// Streaming. The archive is decoded using a stream (InputFileStream)
// rather than loading the entire file into memory, preventing OOM
// errors on large archives. Media files are also streamed directly
// to disk.
//
// data.json shape. ONE shape is accepted:
//   {"schema": 1, "routines": [ ... ]}
// The former «bare object» form is abolished.
//
// Deduplication. The source key of each parsed routine is
// «deviceId/firstRun/routineId» of the exporting device; the routine
// layer stores it as Routine.sourceKey, so re-importing the same
// archive is idempotent — such routines are counted as «skipped»
// and produce no new entries, no media copies, no trace copies.
//
// Media orphan prevention. Media files are copied into media/ ONLY
// for routines that are actually going to be imported, and under
// fresh monotone names (via nextMediaIndex). If the transaction fails,
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
import '../../data/routine_layer.dart';
import '../../data/trace_layer.dart';
import '../core/app_scope.dart';
import '../core/format.dart';
import 'report_json.dart';

// ─── Aggregated result of one import session ───
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

// ─── Public entry: pick archives and import ───
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

    // Report progress per archive.
    onProgress?.call(i / picked.files.length);

    try {
      total = total.merge(await _importZip(app, f.path!));
    } catch (_) {
      // A single corrupt archive must not abort the whole session.
    }
  }
  onProgress?.call(1.0);
  return total;
}

// ─── One archive ───
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

  // ONE accepted shape: the wrapper object.
  final list = <Map<String, dynamic>>[];
  if (decoded is Map) {
    final routines = decoded['routines'];
    if (routines is List) {
      for (final Object? e in routines) {
        if (e is Map) list.add(Map<String, dynamic>.from(e));
      }
    }
  }
  if (list.isEmpty) {
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
  if (toImport.isEmpty) {
    await inputStream.close();
    return ImportResult(skipped: skipped);
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

      // Stream the file content to disk. writeContent is synchronous
      // in archive 3.x; OutputFileStream.closeSync() is used to
      // ensure the file handle is released.
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
      for (final parsed in toImport) {
        await _applyParsed(app, parsed, extracted);
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
) async {
  final RoutineLayer routineLayer = app.routineLayer;
  final TraceLayer traceLayer = app.traceLayer;
  final JournalLayer journal = app.journal;

  // Attach imported routines to the root field node so they appear
  // in the field tree immediately.
  final rootId = app.fieldLayer.rootId;
  final fieldParents = rootId != null ? [rootId] : <int>[];

  final r = await routineLayer.createRoutine(
    journal,
    sourceKey: p.key,
    createdAt: p.createdAt > 0 ? p.createdAt : null,
    fieldParents: fieldParents,
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

  if (p.scheduledAt != null) {
    await routineLayer.setSchedule(journal, r.id, p.scheduledAt);
  }
  if (p.plannedSeconds > 0) {
    await routineLayer.setPlanned(journal, r.id, p.plannedSeconds);
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
