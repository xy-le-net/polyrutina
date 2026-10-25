// ═══════════════════════════════════════════════════════════════════
// timer_text.dart — вид таймера по единому образцу.
//
// Мигание двоеточия — от тикера, независимо от частоты перерисовки
// родителя. Родитель может перерисовываться редко (по смене минуты),
// а мерцание идёт дважды в секунду.
//
// Ведущий ноль — только у второго числа в паре: «1ч 05м», «3д 07ч».
// Одиночное число — без нуля: «7м», «5с».
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/ticker.dart';
import 'format.dart';

class TimerText extends StatelessWidget {
  final int seconds;
  final bool running;
  final Color fg;
  final Color dim;
  final double numberSize;
  final bool colonVisible;
  final Translate t;
  final AppTicker? ticker;

  const TimerText({
    super.key,
    required this.seconds,
    required this.running,
    required this.fg,
    required this.dim,
    required this.numberSize,
    required this.t,
    this.colonVisible = true,
    this.ticker,
  });

  static List<(String, String)> _parts(int sec, {required bool running}) {
    if (sec < 0) sec = 0;
    const daySec = 86400;
    const hourSec = 3600;

    final days = sec ~/ daySec;
    final hours = (sec % daySec) ~/ hourSec;
    final minutes = (sec % hourSec) ~/ 60;
    final secs = sec % 60;

    String two(int n) => n.toString().padLeft(2, '0');

    if (running && days == 0 && hours == 0 && minutes == 0) {
      return [('$secs', 's')];
    }

    final out = <(String, String)>[];
    if (days > 0) {
      out.add(('$days', 'd'));
      if (hours > 0) out.add((two(hours), 'h'));
    } else if (hours > 0) {
      out.add(('$hours', 'h'));
      out.add((two(minutes), 'm'));
    } else if (minutes > 0) {
      out.add(('$minutes', 'm'));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final primary = fg;
    final secondary = dim;
    final unitSize = numberSize * 2 / 3;
    final partsList = _parts(seconds, running: running);

    if (partsList.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[];
    for (var i = 0; i < partsList.length; i++) {
      final (numText, unitKey) = partsList[i];
      final unitText = t('time.$unitKey');

      final isLast = i == partsList.length - 1;
      if (isLast && running) {
        // Мигание — от тикера, ежели дан; иначе от переданного флага.
        if (ticker != null) {
          children.add(
            AnimatedBuilder(
              animation: ticker!,
              builder: (_, __) => Text(
                ticker!.colonVisible ? ':' : ' ',
                style: TextStyle(
                  color: primary,
                  fontFamily: 'monospace',
                  fontSize: numberSize,
                ),
              ),
            ),
          );
        } else {
          children.add(
            Text(
              colonVisible ? ':' : ' ',
              style: TextStyle(
                color: primary,
                fontFamily: 'monospace',
                fontSize: numberSize,
              ),
            ),
          );
        }
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
          unitText,
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
