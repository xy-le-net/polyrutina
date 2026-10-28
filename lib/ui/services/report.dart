// ═══════════════════════════════════════════════════════════════════
// lib/ui/services/report.dart — routines report and zip packing.
//
// The report is textual and human-readable. Each routine is a
// section: completion mark, name, state, creation date, scheduled
// date, blocks with time, all traces (text, checklists, geo, files).
//
// The archive contains report.txt, data.json, and media/.
//
// data.json has ONE shape: {"schema": 1, "routines": [...]}.
//
// File names. The zip follows one template:
//   polyrutina_<label>_<stamp>_<idx>_<deviceId>_<firstRun>.zip
//
// Isolate. Zip compression and media reading are offloaded to a
// background isolate (Isolate.run) to keep the UI thread responsive.
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

    // Append deviceId and firstRun to the filename
    final name =
        'polyrutina_${label}_${stamp}_${idx}_${app.bort.deviceId}_${app.bort.firstRunUnixSec}.zip';

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
    buf.writeln(
      '   ${i18n.t('routine.block.note')}: ${fmtDateFull(r.createdAt, i18n.t)}',
    );

    if (r.scheduledAt != null) {
      buf.writeln(
        '   ${i18n.t('routine.planned_title')}: ${fmtDateFull(r.scheduledAt!, i18n.t)}',
      );
    }
    buf.writeln();

    // Iterate over 'note' plus standard block kinds
    final slots = ['note', ...RoutineBlock.kinds];

    for (final kind in slots) {
      final b = r.blockOf(kind);
      final sec = b?.accumulatorSeconds ?? 0;
      final title = i18n.t('routine.block.$kind');

      // Gather all traces for this slot
      final traces =
          app.traceLayer.traces.values
              .where(
                (t) => !t.deleted && t.parents.contains(r.id) && t.slot == kind,
              )
              .toList()
            ..sort((a, b) => a.id.compareTo(b.id));

      // Check if there's any content
      bool hasContent = sec > 0;
      for (final t in traces) {
        if (t.kind == TraceKind.text && t.text.trim().isNotEmpty) {
          hasContent = true;
        }
        if (t.files.isNotEmpty) {
          hasContent = true;
        }
        if (t.kind == TraceKind.checklist &&
            t.items.any((it) => it.text.trim().isNotEmpty)) {
          hasContent = true;
        }
      }

      if (!hasContent && kind != 'note') continue;
      if (!hasContent && kind == 'note' && traces.isEmpty) continue;

      if (sec > 0) {
        buf.writeln('   $title: ${fmtTime(sec, i18n.t)}');
      } else {
        buf.writeln('   $title');
      }

      // Print all texts
      for (final t in traces) {
        if (t.kind == TraceKind.text && t.text.trim().isNotEmpty) {
          for (final line in t.text.split('\n')) {
            buf.writeln('      $line');
          }
        }
      }

      // Attached media summary
      final allFiles = traces.expand((t) => t.files).toList();
      if (allFiles.isNotEmpty) {
        final counts = <String, int>{};
        for (final f in allFiles) {
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
        if (parts.isNotEmpty) {
          buf.writeln(
            '      ${i18n.t('media.attached')}: ${parts.join(', ')}.',
          );
        }
      }

      // Geo coordinates
      for (final g in allFiles.where((f) => f.kind == MediaKind.geo)) {
        final lat = g.lat?.toStringAsFixed(6) ?? '?';
        final lon = g.lon?.toStringAsFixed(6) ?? '?';
        final acc = g.acc?.toStringAsFixed(1) ?? '?';
        buf.writeln('      $lat, $lon (±$acc ${i18n.t('time.m')})');
      }

      // Checklists (all of them)
      for (final t in traces) {
        if (t.kind == TraceKind.checklist) {
          for (final it in t.items) {
            if (it.text.trim().isEmpty) continue;
            final m = it.done ? '✓' : '○';
            buf.writeln('      $m ${it.text}');
          }
        }
      }

      buf.writeln();
    }
  }
}
