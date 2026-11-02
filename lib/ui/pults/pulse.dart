// ═══════════════════════════════════════════════════════════════════
// pulse.dart — pulse: a pult with a timer.
//
// Pulse is a row: timer (TimerText) on the left, pult (Pult) on the
// right.
//
// Colors come from the passed quartet (bg, dim, fg, signal).
// The translator t is needed for time-unit labels.
//
// Running state. The caller supplies the pult with `selected: true`
// when the slot is running, which automatically applies the signal
// palette (coreColor = fgsignal, iconColor = bg). This ensures the
// running pult is clearly visible against the inverted block
// background. The pulse no longer overrides the selected flag.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/ticker.dart';
import '../core/format.dart';
import '../core/timer_text.dart';
import 'pult_core.dart';

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
  final Translate t;
  final AppTicker? ticker;

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
    required this.t,
    this.colonVisible = true,
    this.pultSize,
    this.ticker,
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
          t: t,
          ticker: ticker,
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
