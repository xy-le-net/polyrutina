// ═══════════════════════════════════════════════════════════════════
// pulse.dart — пульс: пульт с таймером.
//
// Пульс — ряд: слева таймер (TimerText), справа пульт (Pult).
//
// Цвета берутся из переданной пятёрки (bg, dim, fg, signal).
// bgdim не передаётся — он не нужен.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import 'pult_core.dart';
import 'timer_text.dart';

class Pulse extends StatelessWidget {
  final PultSpec spec;
  final int seconds;
  final bool running;
  final Color bg;
  final Color dim;
  final Color fg;
  final Color signal;
  final double side;
  final bool colonVisible;
  final double? pultSize;

  const Pulse({
    super.key,
    required this.spec,
    required this.seconds,
    required this.running,
    required this.bg,
    required this.dim,
    required this.fg,
    required this.signal,
    required this.side,
    this.colonVisible = true,
    this.pultSize,
  });

  @override
  Widget build(BuildContext context) {
    final numberSize = side * 0.4;
    final pultSide = pultSize ?? side * 0.6667;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        TimerText(
          seconds: seconds,
          running: running,
          fg: fg,
          dim: dim,
          numberSize: numberSize,
          colonVisible: colonVisible,
        ),
        if (seconds > 0) SizedBox(width: side * 0.15),
        Pult(
          spec: spec,
          fg: fg,
          bg: bg,
          signal: signal,
          overrideSize: pultSide,
        ),
      ],
    );
  }
}
