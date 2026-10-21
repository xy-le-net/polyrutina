// ═══════════════════════════════════════════════════════════════════
// pulse.dart — pulse: a pult with a timer.
//
// Pulse is a row: timer (TimerText) on the left, pult (Pult) on the right.
//
// Colors come from the passed quartet (bg, dim, fg, signal).
// The translator t is needed for time-unit labels.
//
// Running state. The pulse does not invert its colors itself: the
// caller (RoutineBlockView, RoutinePlate) already supplies inverted
// fg/bg when the slot is running. The pulse merely drops the
// selected flag so that the pult renders coreColor = fg,
// iconColor = bg — which, given the swapped inputs, yields a dark
// pult on a light block, or a light pult on a dark block. That is
// the «reversed» look requested by the UX review.
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

    // Running: drop selected so the pult renders with coreColor = fg
    // and iconColor = bg. The caller has already inverted fg/bg, so
    // this yields the reversed look.
    final PultSpec effectiveSpec;
    if (running) {
      effectiveSpec = PultSpec(
        id: spec.id,
        icon: spec.icon,
        confirmIcon: spec.confirmIcon,
        label: spec.label,
        labelBg: spec.labelBg,
        centerText: spec.centerText,
        selected: false,
        subsBuilder: spec.subsBuilder,
        longSubs: spec.longSubs,
        confirm: spec.confirm,
        onTap: spec.onTap,
        onLongPress: spec.onLongPress,
        stayOpen: spec.stayOpen,
        compactLabel: spec.compactLabel,
      );
    } else {
      effectiveSpec = spec;
    }

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
          spec: effectiveSpec,
          fg: fg,
          bg: bg,
          signal: signal,
          overrideSize: pultSide,
        ),
      ],
    );
  }
}
