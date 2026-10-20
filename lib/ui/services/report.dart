// ═══════════════════════════════════════════════════════════════════
// report.dart — routine report and zip packaging.
//
// The report is textual, human-readable. Each routine is a separate
// section:
//   — a completion mark before the name: ✓ or ○;
//   — the routine name;
//   — below it: «(completed)» or «(in progress)»;
//   — creation time (weekday and unit labels — from the dictionary);
//   — blocks in order: name, time (if non-zero);
//   — below the block — a text trace (comment), if any;
//   — checklist: items, each with ✓ (checked) or ○ (not);
//   — the line «attached:» — counters by media kind, dimmed.
//
// For the «geo» kind, coordinates (latitude, longitude, accuracy) are
// output line by line — there is no separate json file.
//
// Packaging. Each report is put into a zip archive:
//   report.txt — human-readable report;
//   data.json — the routine as a whole (universal format);
//   media/ — media files with original names.
//
// Archive name:
//   general  — polyrutina_YY_MM_DD_index.zip
//   specific — polyrutina_<routinename>_YY_MM_DD_index.zip
// where index is the export iteration of this object on this day;
// forbidden characters are replaced with an uppercase «X»; an unnamed
// routine is «noname».
//
// Upon completion — the system «share» sheet (share_plus).
//
// Strict typing: dynamic i18n parameters are replaced with the
// explicit I18n type, eliminating runtime type errors and clarifying
// method contracts.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

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

class ReportBuilder {
  // ─── Replacement of forbidden characters in a file name ───
  static String _safe(String s) {
    final bad = RegExp(r'[\\/:*?"<>|]');
    final out = s.replaceAllMapped(bad, (_) => 'X');
    return out.trim().isEmpty ? 'noname' : out;
  }

  // ─── Date stamp for the file name ───
  static String _stamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year.toString().padLeft(4, '0')}_'
        '${two(n.month)}_${two(n.day)}';
  }

  // ─── General report (all routines) ───
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
      uiContext: uiContext,
    );
  }

  // ─── Specific report (one routine) ───
  static Future<String?> buildSingle(
    AppContext app,
    I18n i18n,
    int routineId, {
    BuildContext? uiContext,
  }) async {
    final r = app.routineLayer.findRoutine(routineId);
    if (r == null) return null;
    final name = r.name.isEmpty ? 'noname' : _safe(r.name);
    return _buildAndShare(
      app,
      i18n,
      [r],
      objectKey: 'routine_$routineId',
      routineLabel: name,
      uiContext: uiContext,
    );
  }

  // ─── Selective report by a list of ids ───
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
      uiContext: uiContext,
    );
  }

  // ─── Assembly, packaging, sending ───
  // Progress. During long stages (attachment collection, packaging,
  // writing) a pop-up frame with a circular indicator and the «cancel»
  // link-word is displayed. The token value is updated as progress is
  // made; if token.cancelled — the work is interrupted, the file is
  // not given away.
  static Future<String?> _buildAndShare(
    AppContext app,
    I18n i18n,
    List<Routine> routines, {
    required String objectKey,
    String? routineLabel,
    BuildContext? uiContext,
  }) async {
    routines.sort((a, b) {
      if (a.completed != b.completed) {
        return a.completed ? 1 : -1;
      }
      return b.lastActionAt.compareTo(a.lastActionAt);
    });

    // Progress. Token, dialog, display — if a UI context exists.
    final token = ProgressToken();
    if (uiContext != null && uiContext.mounted) {
      showDialog<void>(
        context: uiContext,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.2),
        builder: (_) =>
            ProgressDialog(token: token, title: i18n.t('export.prep')),
      );
    }
    void report(double v) => token.report(v);

    // ─── Report text ───
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

    // ─── Archive: texts ───
    report(0.05);
    final archive = Archive();
    final reportBytes = utf8.encode(buf.toString());
    archive.addFile(ArchiveFile('report.txt', reportBytes.length, reportBytes));

    final jsonObj = routines.length == 1
        ? ReportJson.buildRoutine(app, routines.first)
        : {
            'schema': ReportJson.schemaVersion,
            'routines': [
              for (final r in routines) ReportJson.buildRoutine(app, r),
            ],
          };
    final jsonBytes = utf8.encode(jsonEncode(jsonObj));
    archive.addFile(ArchiveFile('data.json', jsonBytes.length, jsonBytes));
    if (token.cancelled) return null;

    // ─── Media: collect the list ───
    // Collection takes the main share of progress (0.1 → 0.8).
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

    // Include files with progress growth.
    if (mediaFiles.isNotEmpty) {
      for (var i = 0; i < mediaFiles.length; i++) {
        if (token.cancelled) return null;
        final m = mediaFiles[i];
        final bytes = await m.file.readAsBytes();
        archive.addFile(ArchiveFile('media/${m.name}', bytes.length, bytes));
        report(0.1 + 0.7 * ((i + 1) / mediaFiles.length));
      }
    }
    if (token.cancelled) return null;

    // ─── Writing the zip ───
    report(0.85);
    final dir = await getApplicationDocumentsDirectory();
    final idx = app.bort.nextExportIndex(objectKey);
    final stamp = _stamp();
    final name = routineLabel == null
        ? 'polyrutina_${stamp}_$idx.zip'
        : 'polyrutina_${routineLabel}_${stamp}_$idx.zip';

    final zipFile = File(p.join(dir.path, name));
    final zipBytes = ZipEncoder().encode(archive);
    if (token.cancelled) return null;
    if (zipBytes == null) return null;
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

  // ─── One routine (text) ───
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

      // ─── Geo coordinates — line by line ───
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

  // ─── «attached: N audio, M photo.» ───
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
