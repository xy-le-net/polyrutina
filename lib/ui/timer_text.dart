// ═══════════════════════════════════════════════════════════════════
// timer_text.dart — вид таймера по единому образцу.
//
// Три единицы: дни, часы, минуты. Показываются две старшие, что
// ненулевые. Исключение — идущий меньше минуты: показывает секунды.
//
// Оформление:
//   числа — цветом fg;
//   подписи «д», «ч», «м», «с» — приглушённым, две трети кегля,
//     слитно с числом, без точки;
//   разделитель — пробел у покоящегося, мерцающее двоеточие
//     у идущего. Двоеточие ставится ПЕРЕД последним числом: «9ч :03м»,
//     «:3с». Ежели число одно — перед ним. Сие даёт единообразие
//     вида: где бы ни стояло двоеточие, оно всегда перед младшей
//     частью.
//   мелькание — от единого тикера: colonVisible истина — видно,
//     ложь — нет. Период пятьсот миллисекунд (полсекунды видно,
//     полсекунды нет).
//   ведущих нулей нет у дней, часов, секунд; у минут — есть.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

class TimerText extends StatelessWidget {
  final int seconds;
  final bool running;
  final Color fg;
  final Color dim;
  final Color signal;
  final double numberSize;
  final bool colonVisible;

  const TimerText({
    super.key,
    required this.seconds,
    required this.running,
    required this.fg,
    required this.dim,
    required this.signal,
    required this.numberSize,
    this.colonVisible = true,
  });

  // ─── Разбор на две старшие единицы ───
  // Возвращает список пар. Пусто — коли всё нуль. Идущий меньше
  // минуты — одна пара секунд.
  static List<(String, String)> parts(int sec, {required bool running}) {
    if (sec < 0) sec = 0;
    const daySec = 86400;
    const hourSec = 3600;

    final days = sec ~/ daySec;
    final hours = (sec % daySec) ~/ hourSec;
    final minutes = (sec % hourSec) ~/ 60;
    final secs = sec % 60;

    String mm(int n) => n.toString().padLeft(2, '0');

    // Идущий меньше минуты: секунды.
    if (running && days == 0 && hours == 0 && minutes == 0) {
      if (secs == 0) return [('0', 'с')];
      return [('$secs', 'с')];
    }

    final out = <(String, String)>[];
    if (days > 0) {
      out.add(('$days', 'д'));
      if (hours > 0) out.add(('$hours', 'ч'));
    } else if (hours > 0) {
      out.add(('$hours', 'ч'));
      out.add((mm(minutes), 'м'));
    } else if (minutes > 0) {
      out.add((mm(minutes), 'м'));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final primary = fg;
    final secondary = dim;
    final unitSize = numberSize * 2 / 3;
    final partsList = parts(seconds, running: running);

    if (partsList.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[];
    for (var i = 0; i < partsList.length; i++) {
      final (numText, unit) = partsList[i];

      // Двоеточие — ПЕРЕД последним числом. У покоящегося — пробел.
      // У идущего — мерцающее двоеточие (см. правило в шапке файла).
      final isLast = i == partsList.length - 1;
      if (isLast) {
        if (running) {
          children.add(Opacity(
            opacity: colonVisible ? 1.0 : 0.0,
            child: Text(':',
                style: TextStyle(
                    color: primary,
                    fontFamily: 'monospace',
                    fontSize: numberSize)),
          ));
        } else {
          // Пробел между парами.
          if (i > 0) children.add(const SizedBox(width: 4));
        }
      } else {
        // Между числами — пробел (только у покоящегося).
        if (i > 0 || true) {
          children.add(const SizedBox(width: 4));
        }
      }

      children.add(Text(numText,
          style: TextStyle(
              color: primary, fontFamily: 'monospace', fontSize: numberSize)));
      children.add(Text(unit,
          style: TextStyle(
              color: secondary, fontFamily: 'monospace', fontSize: unitSize)));
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: children,
    );
  }
}
