// ═══════════════════════════════════════════════════════════════════
// timer_text.dart — вид таймера по единому образцу.
//
// Единый вид отсчёта времени (в списке рутин, в карточке, на пульсе
// смены). Три единицы: дни, часы, минуты. Показываются две старшие,
// что ненулевые:
//   есть дни  → «3д 5ч»;
//   есть часы → «9ч 3м»;
//   только минуты → «3м»;
//   всё нуль → пусто (таймер не выводится, места не занимает).
//
// Оформление:
//   числа — обычным цветом (при ходе — сигнальным);
//   подписи «д», «ч», «м» — приглушённым, две трети от кегля числа,
//     слитно с числом, без точки;
//   между двумя парами — пробел у покоящегося, мерцающее двоеточие
//     у идущего (треть секунды видно, две трети нет);
//   двоеточие — сигнального цвета, как и число;
//   ведущих нулей нет у дней и часов; у минут — есть («03м»).
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
  // Фаза мелькания — вычисляется вызывающим по системным часам.
  // Применяется только при running.
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
  // Возвращает список пар: [(число, подпись), ...].
  // Пусто, коли всё нуль. Одна пара, коли младшая нулевая.
  // Две пары — старшая и следующая ненулевая.
  // showSeconds — истина токмо у идущего таймера: до первой минуты
  // показываются секунды, без ведущего нуля, с приглушённой «с».
  // У покоящегося секунды не показываются вовсе.
  static List<(String, String)> parts(int sec, {bool showSeconds = false}) {
    if (sec < 0) sec = 0;
    const daySec = 86400;
    const hourSec = 3600;

    final days = sec ~/ daySec;
    final hours = (sec % daySec) ~/ hourSec;
    final minutes = (sec % hourSec) ~/ 60;
    final secs = sec % 60;

    // Минуты — двузначные с ведущим нулём; дни, часы, секунды — без.
    String mm(int n) => n.toString().padLeft(2, '0');

    final out = <(String, String)>[];
    if (days > 0) {
      out.add(('$days', 'д'));
      if (hours > 0) out.add(('$hours', 'ч'));
    } else if (hours > 0) {
      out.add(('$hours', 'ч'));
      out.add((mm(minutes), 'м'));
    } else if (minutes > 0) {
      out.add((mm(minutes), 'м'));
    } else if (showSeconds && secs > 0) {
      // Секунды — токмо у идущего, до первой минуты.
      out.add(('$secs', 'с'));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final primary = running ? signal : fg;
    final secondary = dim;
    final unitSize = numberSize * 2 / 3;
    final partsList = parts(seconds, showSeconds: running);

    // Всё нуль — пусто.
    if (partsList.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[];
    for (var i = 0; i < partsList.length; i++) {
      final (numText, unit) = partsList[i];

      // Разделитель перед второй парой: пробел у покоящегося,
      // мерцающее двоеточие у идущего.
      if (i > 0) {
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
