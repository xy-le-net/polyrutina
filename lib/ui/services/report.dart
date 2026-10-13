// ═══════════════════════════════════════════════════════════════════
// report.dart — текстовый отчёт по рутинам.
//
// Каждая рутина — отдельным разделом:
//   — знак завершённости перед именем: ✓ либо ○;
//   — имя рутины;
//   — под ним: «(завершено)» либо «(в процессе)»;
//   — время создания (день недели и подписи единиц — из словаря);
//   — блоки по порядку: имя, время (ежели ненулевое);
//   — под блоком — текстовый след (комментарий), ежели есть;
//   — чек-лист: пункты, у каждого ✓ (отмечено) либо ○ (нет);
//   — строка «прикреплено:» — счётчики по родам медиа, приглушённо.
//
// Файл кладётся в папку документов приложения. Имя:
//   общий  — polyrutina_ГГ_ММ_ДД_индекс.txt
//   частный — polyrutina_<имярутины>_ГГ_ММ_ДД_индекс.txt
// где индекс — итерация экспорта данного объекта в этот день;
// запретные знаки заменены заглавным «X»; рутина без имени — noname.
//
// По завершении — системный лист «поделиться» (share_plus).
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/routine.dart';
import '../../data/trace_layer.dart';
import '../core/app_scope.dart';
import '../core/format.dart';

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
  static Future<String?> build(AppContext app, dynamic i18n) async {
    final routines = <Routine>[];
    for (final r in app.routineLayer.routines) {
      routines.add(r);
    }
    if (routines.isEmpty) return null;
    return _buildAndShare(app, i18n, routines, objectKey: 'all');
  }

  // ─── Частный отчёт (одна рутина) ───
  static Future<String?> buildSingle(
    AppContext app,
    dynamic i18n,
    int routineId,
  ) async {
    final r = app.routineLayer.findRoutine(routineId);
    if (r == null) return null;
    final name = r.name.isEmpty ? 'noname' : _safe(r.name);
    return _buildAndShare(
      app,
      i18n,
      [r],
      objectKey: 'routine_$routineId',
      routineLabel: name,
    );
  }

  // ─── Выборочный отчёт по списку id ───
  static Future<String?> buildSelected(
    AppContext app,
    dynamic i18n,
    List<int> ids,
  ) async {
    final routines = <Routine>[];
    for (final id in ids) {
      final r = app.routineLayer.findRoutine(id);
      if (r != null) routines.add(r);
    }
    if (routines.isEmpty) return null;
    return _buildAndShare(app, i18n, routines, objectKey: 'selected');
  }

  // ─── Сборка, сохранение, отправка ───
  static Future<String?> _buildAndShare(
    AppContext app,
    dynamic i18n,
    List<Routine> routines, {
    required String objectKey,
    String? routineLabel,
  }) async {
    routines.sort((a, b) {
      if (a.completed != b.completed) {
        return a.completed ? 1 : -1;
      }
      return b.lastActionAt.compareTo(a.lastActionAt);
    });

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

    final dir = await getApplicationDocumentsDirectory();
    final idx = app.bort.nextExportIndex(objectKey);
    final stamp = _stamp();
    final name = routineLabel == null
        ? 'polyrutina_${stamp}_$idx.txt'
        : 'polyrutina_${routineLabel}_${stamp}_$idx.txt';

    final file = File(p.join(dir.path, name));
    await file.writeAsString(buf.toString(), encoding: utf8);

    final lastId = await app.journal.lastEntryId();
    app.bort.setLastExportId(lastId);

    // Системный лист «поделиться».
    try {
      await Share.shareXFiles([XFile(file.path)], subject: name);
    } catch (_) {}

    return file.path;
  }

  // ─── Одна рутина ───
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

      // Пустой этап (ни времени, ни следа, ни медиа, ни чек-листа)
      // в отчёт не попадает.
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