// ═══════════════════════════════════════════════════════════════════
// timer_text.dart — вид таймера по единому образцу.
//
// Ведущий ноль — только у второго числа в паре. Одиночное число —
// без нуля.
//
// Поля signal нет: цвета числа и подписей — fg и dim.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

class TimerText extends StatelessWidget {
  final int seconds;
  final bool running;
  final Color fg;
  final Color dim;
  final double numberSize;
  final bool colonVisible;

  const TimerText({
    super.key,
    required this.seconds,
    required this.running,
    required this.fg,
    required this.dim,
    required this.numberSize,
    this.colonVisible = true,
  });

  static List<(String, String)> parts(int sec, {required bool running}) {
    if (sec < 0) sec = 0;
    const daySec = 86400;
    const hourSec = 3600;

    final days = sec ~/ daySec;
    final hours = (sec % daySec) ~/ hourSec;
    final minutes = (sec % hourSec) ~/ 60;
    final secs = sec % 60;

    String two(int n) => n.toString().padLeft(2, '0');

    if (running && days == 0 && hours == 0 && minutes == 0) {
      return [('$secs', 'с')];
    }

    final out = <(String, String)>[];
    if (days > 0) {
      out.add(('$days', 'д'));
      if (hours > 0) out.add((two(hours), 'ч'));
    } else if (hours > 0) {
      out.add(('$hours', 'ч'));
      out.add((two(minutes), 'м'));
    } else if (minutes > 0) {
      out.add(('$minutes', 'м'));
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

      final isLast = i == partsList.length - 1;
      if (isLast && running) {
        children.add(
          Opacity(
            opacity: colonVisible ? 1.0 : 0.0,
            child: Text(
              ':',
              style: TextStyle(
                color: primary,
                fontFamily: 'monospace',
                fontSize: numberSize,
              ),
            ),
          ),
        );
      } else if (i > 0) {
        children.add(const SizedBox(width: 4));
      }

      children.add(
        Text(
          numText,
          style: TextStyle(
            color: primary,
            fontFamily: 'monospace',
            fontSize: numberSize,
          ),
        ),
      );
      children.add(
        Text(
          unit,
          style: TextStyle(
            color: secondary,
            fontFamily: 'monospace',
            fontSize: unitSize,
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: children,
    );
  }
}
