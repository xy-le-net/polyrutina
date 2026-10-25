// ═══════════════════════════════════════════════════════════════════
// lib/ui/services/report.dart — routines report and zip packing.
//
// The report is textual and human-readable. Each routine is a
// section: completion mark, name, state, creation date, blocks with
// time, text trace, geo coordinates, checklist, and an attached
// media line.
//
// The archive contains report.txt, data.json, and media/.
//
// data.json has ONE shape: {"schema": 1, "routines": [...]}. This
// holds whether the export covers a single routine, a selection, or
// the entire journal.
//
// File names. The zip follows one template:
//   polyrutina_<label>_<stamp>_<idx>.zip
// where <label> is:
//   — safeFileNameOr(r.name) for a single routine;
//   — 'all' for every routine;
//   — 'selected' for a selection.
//
// Media. Each media file carried by a routine's traces is packed
// under its basename; duplicate names are disambiguated with a
// numeric suffix, so an archive never holds two entries under the
// same name.
//
// Isolate. Zip compression and media reading are offloaded to a
// background isolate (Isolate.run) to keep the UI thread responsive.
// Progress is reported at coarse steps (prepare → isolate → save).
//
// Exports folder. Archives are saved into the `exports/` subfolder
// of the application documents directory, keeping them separate
// from media and the database.
//
// Focus. Any active IME composing underline is cleared by unfocusing
// before the dialog is shown.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';

import '../../data/i18n.dart';
import '../../data/routine.dart';
import '../../data/trace_layer.dart';
import '../core/app_scope.dart';
import '../core/format.dart';
import '../core/progress_dialog.dart';
import 'report_json.dart';

// ─── Isolate helper ───
Future<Uint8List?> _buildArchiveIsolate(Map<String, dynamic> args) async {
  final reportBytes = args['report'] as List<int>;
  final jsonBytes = args['json'] as List<int>;
  final mediaList = (args['media'] as List).cast<Map<String, String>>();

  final archive = Archive();
  archive.addFile(ArchiveFile('report.txt', reportBytes.length, reportBytes));
  archive.addFile(ArchiveFile('data.json', jsonBytes.length, jsonBytes));

  for (final m in mediaList) {
    final f = File(m['path']!);
    if (await f.exists()) {
      final bytes = await f.readAsBytes();
      archive.addFile(ArchiveFile('media/${m['name']}', bytes.length, bytes));
    }
  }

  final encoded = ZipEncoder().encode(archive);
  return encoded != null ? Uint8List.fromList(encoded) : null;
}

class ReportBuilder {
  static String _stamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year.toString().padLeft(4, '0')}_'
        '${two(n.month)}_${two(n.day)}';
  }

  static Future<String?> build(
    AppContext app,
    I18n i18n, {
    BuildContext? uiContext,
  }) async {
    final routines = <Routine>[];
    for (final r in app.routineLayer.routines) {
      routines.add(r);
    }
    if (routines.isEmpty) return null;
    return _buildAndShare(
      app,
      i18n,
      routines,
      objectKey: 'all',
      label: 'all',
      uiContext: uiContext,
    );
  }

  static Future<String?> buildSingle(
    AppContext app,
    I18n i18n,
    int routineId, {
    BuildContext? uiContext,
  }) async {
    final r = app.routineLayer.findRoutine(routineId);
    if (r == null) return null;
    return _buildAndShare(
      app,
      i18n,
      [r],
      objectKey: 'routine_$routineId',
      label: safeFileNameOr(r.name),
      uiContext: uiContext,
    );
  }

  static Future<String?> buildSelected(
    AppContext app,
    I18n i18n,
    List<int> ids, {
    BuildContext? uiContext,
  }) async {
    final routines = <Routine>[];
    for (final id in ids) {
      final r = app.routineLayer.findRoutine(id);
      if (r != null) routines.add(r);
    }
    if (routines.isEmpty) return null;
    return _buildAndShare(
      app,
      i18n,
      routines,
      objectKey: 'selected',
      label: 'selected',
      uiContext: uiContext,
    );
  }

  static Future<String?> _buildAndShare(
    AppContext app,
    I18n i18n,
    List<Routine> routines, {
    required String objectKey,
    required String label,
    BuildContext? uiContext,
  }) async {
    // Unfocus to remove any IME composing underline before showing
    // the dialog.
    FocusManager.instance.primaryFocus?.unfocus();

    routines.sort((a, b) {
      if (a.completed != b.completed) {
        return a.completed ? 1 : -1;
      }
      return b.lastActionAt.compareTo(a.lastActionAt);
    });

    final token = ProgressToken();
    if (uiContext != null && uiContext.mounted) {
      showDialog<void>(
        context: uiContext,
        barrierDismissible: false,
        barrierColor: Colors.transparent,
        builder: (_) =>
            ProgressDialog(token: token, title: i18n.t('export.prep')),
      );
    }
    void report(double v) => token.report(v);

    report(0.02);
    final buf = StringBuffer();
    bool first = true;
    for (final r in routines) {
      if (!first) {
        buf.writeln();
        buf.writeln('─' * 40);
        buf.writeln();
      }
      first = false;
      _writeRoutine(buf, app, i18n, r);
    }
    if (token.cancelled) return null;

    report(0.05);
    final reportBytes = utf8.encode(buf.toString());
    final jsonObj = <String, dynamic>{
      'schema': ReportJson.schemaVersion,
      'routines': [for (final r in routines) ReportJson.buildRoutine(app, r)],
    };
    final jsonBytes = utf8.encode(jsonEncode(jsonObj));
    if (token.cancelled) return null;

    final mediaFiles = <({String name, File file})>[];
    final seenNames = <String>{};
    for (final r in routines) {
      for (final t in app.traceLayer.traces.values) {
        if (t.deleted) continue;
        if (!t.parents.contains(r.id)) continue;
        for (final f in t.files) {
          if (f.path.isEmpty) continue;
          final file = File(f.path);
          if (!await file.exists()) continue;
          var name = f.name.isEmpty ? p.basename(f.path) : f.name;
          if (seenNames.contains(name)) {
            var i = 1;
            final base = p.basenameWithoutExtension(name);
            final ext = p.extension(name);
            while (seenNames.contains('${base}_$i$ext')) {
              i++;
            }
            name = '${base}_$i$ext';
          }
          seenNames.add(name);
          mediaFiles.add((name: name, file: file));
        }
      }
    }
    if (token.cancelled) return null;

    final mediaList = <Map<String, String>>[];
    for (final m in mediaFiles) {
      mediaList.add({'name': m.name, 'path': m.file.path});
    }

    report(0.2);
    Uint8List? zipBytes;
    try {
      zipBytes = await Isolate.run(
        () => _buildArchiveIsolate({
          'report': reportBytes,
          'json': jsonBytes,
          'media': mediaList,
        }),
      );
    } catch (_) {
      zipBytes = null;
    }
    if (token.cancelled) return null;
    if (zipBytes == null) return null;

    report(0.85);
    final dir = await getApplicationDocumentsDirectory();
    final exportsDir = Directory(p.join(dir.path, 'exports'));
    if (!await exportsDir.exists()) await exportsDir.create(recursive: true);

    final idx = app.bort.nextExportIndex(objectKey);
    final stamp = _stamp();
    final name = 'polyrutina_${label}_${stamp}_$idx.zip';

    final zipFile = File(p.join(exportsDir.path, name));
    await zipFile.writeAsBytes(zipBytes, flush: true);

    report(0.98);
    final lastId = await app.journal.lastEntryId();
    app.bort.setLastExportId(lastId);

    report(1.0);
    if (uiContext != null && uiContext.mounted) {
      Navigator.of(uiContext).pop();
    }

    if (token.cancelled) return null;

    try {
      await Share.shareXFiles([XFile(zipFile.path)], subject: name);
    } catch (_) {}

    return zipFile.path;
  }

  static void _writeRoutine(
    StringBuffer buf,
    AppContext app,
    I18n i18n,
    Routine r,
  ) {
    final mark = r.completed ? '✓' : '○';
    final name = r.name.isEmpty ? i18n.t('routine.no_name') : r.name;
    final stateText = r.completed
        ? i18n.t('report.completed')
        : i18n.t('report.in_progress');

    buf.writeln('$mark $name');
    buf.writeln('   ($stateText)');
    buf.writeln('   ${fmtDateFull(r.createdAt, i18n.t)}');
    buf.writeln();

    for (final kind in RoutineBlock.kinds) {
      final b = r.blockOf(kind);
      if (b == null) continue;
      final sec = b.accumulatorSeconds;
      final title = i18n.t('routine.block.$kind');

      final text = _textOf(app, r.id, kind);
      final attached = _attachedLine(app, r.id, kind, i18n);
      final t = app.traceLayer.findFirstByKindSlot(
        r.id,
        TraceKind.checklist,
        kind,
      );
      final hasChecklist =
          t != null && t.items.any((it) => it.text.trim().isNotEmpty);

      final empty =
          sec == 0 &&
          (text == null || text.trim().isEmpty) &&
          attached == null &&
          !hasChecklist;
      if (empty) continue;

      if (sec > 0) {
        buf.writeln('   $title: ${fmtTime(sec, i18n.t)}');
      } else {
        buf.writeln('   $title');
      }

      if (text != null) {
        for (final line in text.split('\n')) {
          buf.writeln('      $line');
        }
      }

      if (attached != null) buf.writeln('      $attached');

      final geoFiles = _geoFilesOf(app, r.id, kind);
      for (final g in geoFiles) {
        final lat = g.lat?.toStringAsFixed(6) ?? '?';
        final lon = g.lon?.toStringAsFixed(6) ?? '?';
        final acc = g.acc?.toStringAsFixed(1) ?? '?';
        buf.writeln('      $lat, $lon (±$acc ${i18n.t('time.m')})');
      }

      if (t != null) {
        for (final it in t.items) {
          final s = it.text;
          if (s.trim().isEmpty) continue;
          final m = it.done ? '✓' : '○';
          buf.writeln('      $m $s');
        }
      }

      buf.writeln();
    }
  }

  static String? _textOf(AppContext app, int routineId, String slot) {
    final t = app.traceLayer.findFirstByKindSlot(
      routineId,
      TraceKind.text,
      slot,
    );
    if (t == null) return null;
    final s = t.text;
    return s.isEmpty ? null : s;
  }

  static List<TraceFile> _geoFilesOf(
    AppContext app,
    int routineId,
    String slot,
  ) {
    final t = app.traceLayer.findFirstByKindSlot(
      routineId,
      TraceKind.text,
      slot,
    );
    if (t == null) return const [];
    return t.files.where((f) => f.kind == MediaKind.geo).toList();
  }

  static String? _attachedLine(
    AppContext app,
    int routineId,
    String slot,
    I18n i18n,
  ) {
    final t = app.traceLayer.findFirstByKindSlot(
      routineId,
      TraceKind.text,
      slot,
    );
    if (t == null || t.files.isEmpty) return null;
    final counts = <String, int>{};
    for (final f in t.files) {
      counts[f.kind] = (counts[f.kind] ?? 0) + 1;
    }
    final parts = <String>[];
    const order = [
      MediaKind.audio,
      MediaKind.photo,
      MediaKind.video,
      MediaKind.geo,
      MediaKind.file,
    ];
    for (final k in order) {
      final n = counts[k];
      if (n == null) continue;
      parts.add('$n ${i18n.t('media.$k')}');
    }
    if (parts.isEmpty) return null;
    return '${i18n.t('media.attached')}: ${parts.join(', ')}.';
  }
}
