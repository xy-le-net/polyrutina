// ═══════════════════════════════════════════════════════════════════
// lib/ui/services/import_service.dart — receiving routines from zip.
//
// Opened from the rubka's «import» pult: the system file sheet
// (FileType.custom, *.zip, multiple). Each archive is read:
//   data.json — the routine(s) as a whole;
//   media/<name> — media files, matched by name against the traces.
//
// Deduplication. The source key of each parsed routine is
// «deviceId/firstRun/routineId» of the exporting device; the routine
// layer stores it as Routine.sourceKey, so re-importing the same
// archive is idempotent — such routines are counted as «skipped»
// and produce no new entries, no media copies, no trace copies.
//
// Media orphan prevention. Media files are copied into media/ ONLY
// for routines that are actually going to be imported, and under
// fresh monotone names (via nextMediaIndex), so the archive's raw
// names never collide across imports. If the transaction fails,
// every file written during the attempt is removed; the trace
// layer's pre-insert (see trace_layer.dart) ensures each file is
// attached immediately, so no orphan file survives a success.
//
// Per-zip granularity. Each archive is processed in its own
// transaction; a failure in one archive rolls back only its own
// routine and media, leaving other archives untouched. The
// aggregate ImportResult sums across all archives.
//
// ImportResult. Aggregated counters — routines, media files, bytes,
// skipped routines — plus the sentinel flags cancelled (user
// dismissed the system sheet) and empty (nothing was imported).
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
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
Future<ImportResult> importFromPicker({required AppContext app}) async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['zip'],
    allowMultiple: true,
  );
  if (picked == null || picked.files.isEmpty) {
    return const ImportResult(cancelled: true);
  }

  var total = const ImportResult();
  for (final f in picked.files) {
    if (f.path == null) continue;
    try {
      total = total.merge(await _importZip(app, f.path!));
    } catch (_) {
      // A single corrupt archive must not abort the whole session.
    }
  }
  return total;
}

// ─── One archive ───
Future<ImportResult> _importZip(AppContext app, String path) async {
  final bytes = await File(path).readAsBytes();
  final archive = ZipDecoder().decodeBytes(bytes);

  final dataFile = archive.findFile('data.json');
  if (dataFile == null) return const ImportResult();

  final dataStr = utf8.decode(dataFile.content as List<int>);
  final Object? decoded = jsonDecode(dataStr);

  final list = <Map<String, dynamic>>[];
  if (decoded is List) {
    for (final Object? e in decoded) {
      if (e is Map) list.add(Map<String, dynamic>.from(e));
    }
  } else if (decoded is Map) {
    final routines = decoded['routines'];
    if (routines is List) {
      for (final Object? e in routines) {
        if (e is Map) list.add(Map<String, dynamic>.from(e));
      }
    } else {
      list.add(Map<String, dynamic>.from(decoded));
    }
  }
  if (list.isEmpty) return const ImportResult();

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
  if (toImport.isEmpty) return ImportResult(skipped: skipped);

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
      await target.writeAsBytes(file.content as List<int>, flush: true);
      written.add(target.path);
      extracted[baseName] = target.path;
      mediaBytes += await target.length();
    }
  } catch (_) {
    await _rollback(written);
    return ImportResult(skipped: skipped);
  }

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

  // Imported routines carry their historical creation moment from
  // the archive; without this, an old routine would look as if it
  // had just been created at the instant of import. A zero from the
  // schema is treated as «absent» and falls back to now.
  final r = await routineLayer.createRoutine(
    journal,
    sourceKey: p.key,
    createdAt: p.createdAt > 0 ? p.createdAt : null,
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
}
