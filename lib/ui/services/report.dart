// ═══════════════════════════════════════════════════════════════════
// report.dart — отчёт по рутинам и упаковка в zip.
//
// Отчёт — текстовый, человекочитаемый. Рутина отдельным разделом:
//   — знак завершённости перед именем: ✓ либо ○;
//   — имя рутины;
//   — под ним: «(завершено)» либо «(в процессе)»;
//   — время создания (день недели и подписи единиц — из словаря);
//   — блоки по порядку: имя, время (ежели ненулевое);
//   — под блоком — текстовый след (комментарий), ежели есть;
//   — чек-лист: пункты, у каждого ✓ (отмечено) либо ○ (нет);
//   — строка «прикреплено:» — счётчики по родам медиа, приглушённо.
//
// Для рода «место» координаты (широта, долгота, точность) выводятся
// построчно — отдельного json-файла нет.
//
// Упаковка. Каждый отчёт кладётся в zip-архив:
//   report.txt — человекочитаемый отчёт;
//   data.json — рутина целиком (универсальный формат);
//   media/ — файлы медиа с исходными именами.
//
// Имя архива:
//   общий  — polyrutina_ГГ_ММ_ДД_индекс.zip
//   частный — polyrutina_<имярутины>_ГГ_ММ_ДД_индекс.zip
// где индекс — итерация экспорта данного объекта в этот день;
// запретные знаки заменены заглавным «X»; рутина без имени — noname.
//
// По завершении — системный лист «поделиться» (share_plus).
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:flutter/material.dart';

import '../../data/routine.dart';
import '../../data/trace_layer.dart';
import '../core/app_scope.dart';
import '../core/format.dart';
import '../core/progress_dialog.dart';
import 'report_json.dart';

class ReportBuilder {
  // ─── Замена запретных знаков в имени файла ───
  static String _safe(String s) {
    final bad = RegExp(r'[\\/:*?"<>|]');
    final out = s.replaceAllMapped(bad, (_) => 'X');
    return out.trim().isEmpty ? 'noname' : out;
  }

  // ─── Метка даты для имени файла ───
  static String _stamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year.toString().padLeft(4, '0')}_'
        '${two(n.month)}_${two(n.day)}';
  }

  // ─── Общий отчёт (все рутины) ───
  static Future<String?> build(
    AppContext app,
    dynamic i18n, {
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

  // ─── Частный отчёт (одна рутина) ───
  static Future<String?> buildSingle(
    AppContext app,
    dynamic i18n,
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

  // ─── Выборочный отчёт по списку id ───
  static Future<String?> buildSelected(
    AppContext app,
    dynamic i18n,
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

  // ─── Сборка, упаковка, отправка ───
  // Прогресс. Во время долгих стадий (сбор вложений, упаковка,
  // запись) выводится всплывающая рамка с круговым индикатором
  // и словом-ссылкою «отмена». Значение token обновляется по мере
  // продвижения; ежели token.cancelled — работа прерывается,
  // файл не отдаётся.
  static Future<String?> _buildAndShare(
    AppContext app,
    dynamic i18n,
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

    // Прогресс. Токен, диалог, показ — коли есть контекст UI.
    final token = ProgressToken();
    if (uiContext != null && uiContext.mounted) {
      showDialog<void>(
        context: uiContext,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.2),
        builder: (_) => ProgressDialog(
          token: token,
          title: i18n.t('export.prep') as String,
        ),
      );
    }
    void report(double v) => token.report(v);

    // ─── Текст отчёта ───
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

    // ─── Архив: тексты ───
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

    // ─── Медиа: собираем перечень ───
    // Сбор занимает основную долю прогресса (0.1 → 0.8).
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

    // Вкладываем файлы с ростом прогресса.
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

    // ─── Запись zip ───
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

  // ─── Одна рутина (текст) ───
  static void _writeRoutine(
    StringBuffer buf,
    AppContext app,
    dynamic i18n,
    Routine r,
  ) {
    final mark = r.completed ? '✓' : '○';
    final name = r.name.isEmpty ? i18n.t('routine.no_name') as String : r.name;
    final stateText = r.completed
        ? i18n.t('report.completed') as String
        : i18n.t('report.in_progress') as String;

    buf.writeln('$mark $name');
    buf.writeln('   ($stateText)');
    buf.writeln('   ${fmtDateFull(r.createdAt, i18n.t as Translate)}');
    buf.writeln();

    for (final kind in RoutineBlock.kinds) {
      final b = r.blockOf(kind);
      if (b == null) continue;
      final sec = b.accumulatorSeconds;
      final title = i18n.t('routine.block.$kind') as String;

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
        buf.writeln('   $title: ${fmtTime(sec, i18n.t as Translate)}');
      } else {
        buf.writeln('   $title');
      }

      if (text != null) {
        for (final line in text.split('\n')) {
          buf.writeln('      $line');
        }
      }

      if (attached != null) buf.writeln('      $attached');

      // ─── Гео-координаты — построчно ───
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

  // ─── «прикреплено: N аудио, M фото.» ───
  static String? _attachedLine(
    AppContext app,
    int routineId,
    String slot,
    dynamic i18n,
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
