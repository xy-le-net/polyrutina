// ═══════════════════════════════════════════════════════════════════
// report.dart — текстовый отчёт по рутинам.
//
// Каждая рутина — отдельным разделом. Содержание:
//   — знак завершённости перед именем: ✓ завершено, ○ в процессе;
//   — имя рутины;
//   — под именем: «(завершено)» либо «(в процессе)»;
//   — время создания с днём недели;
//   — блоки по порядку родов: имя, время (ежели ненулевое);
//   — под блоком — текстовый след (комментарий), ежели есть;
//   — чек-лист: пункты, у каждого знак ✓ (отмечено) либо ○ (нет).
//
// Файл кладётся в папку документов приложения. Имя:
// journal_ГГГГММДД_ЧЧММСС.txt. Кодировка — UTF-8.
//
// По завершении шлётся запись в борте: lastExportId = последняя
// запись журнала.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/routine.dart';
import '../data/trace_layer.dart';
import 'format.dart';

class ReportBuilder {
  // ─── Сборка и сохранение ───
  // Возвращает путь к сохранённому файлу либо null, коли рутин нет.
  static Future<String?> build(dynamic app, dynamic i18n) async {
    final routines = <Routine>[];
    for (final r in app.routineLayer.routines) {
      routines.add(r as Routine);
    }
    if (routines.isEmpty) return null;

    // Сортировка: активные сверху, завершённые внизу.
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
    final now = DateTime.now();
    final name =
        'journal_'
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}.txt';

    final file = File(p.join(dir.path, name));
    await file.writeAsString(buf.toString(), encoding: utf8);

    // Метка экспорта.
    final lastId = await app.journal.lastEntryId() as int;
    app.bort.setLastExportId(lastId);

    return file.path;
  }

  // ─── Одна рутина ───
  static void _writeRoutine(
    StringBuffer buf,
    dynamic app,
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
    buf.writeln('   ${fmtDateFull(r.createdAt)}');
    buf.writeln();

    // Блоки.
    for (final kind in RoutineBlock.kinds) {
      final b = r.blockOf(kind);
      if (b == null) continue;
      final sec = b.accumulatorSeconds;
      final title = i18n.t('routine.block.$kind') as String;

      if (sec > 0) {
        buf.writeln('   $title: ${fmtTime(sec)}');
      } else {
        buf.writeln('   $title');
      }

      // Текстовый след (комментарий).
      final text = _textOf(app, r.id, kind);
      if (text != null) {
        for (final line in text.split('\n')) {
          buf.writeln('      $line');
        }
      }

      // Чек-лист.
      final t = app.traceLayer.findFirstByKindSlot(
        r.id,
        TraceKind.checklist,
        kind,
      );
      if (t != null) {
        for (final it in t.items) {
          final s = (it.text as String);
          if (s.trim().isEmpty) continue;
          final m = (it.done as bool) ? '✓' : '○';
          buf.writeln('      $m $s');
        }
      }

      buf.writeln();
    }
  }

  // ─── Текстовый след блока ───
  static String? _textOf(dynamic app, int routineId, String slot) {
    final t = app.traceLayer.findFirstByKindSlot(
      routineId,
      TraceKind.text,
      slot,
    );
    if (t == null) return null;
    final s = t.text as String;
    return s.isEmpty ? null : s;
  }
}
