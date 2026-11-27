import 'package:material_ui/material_ui.dart';

import 'package:polyrutina/core/application/ticker.dart';
import 'package:polyrutina/shared/application/format.dart';
import 'package:polyrutina/shared/presentation/timer_text.dart';
import 'package:polyrutina/shared/presentation/pults/pult_core.dart';

class Pulse extends StatelessWidget {
  final PultSpec spec;
  final int seconds;
  final bool running;
  final Color bg;
  final Color dim;
  final Color fg;
  final Color signal;
  final double side;
  final double? numberSize;
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
    this.numberSize,
    required this.t,
    this.colonVisible = true,
    this.pultSize,
    this.ticker,
  });

  @override
  Widget build(BuildContext context) {
    final timerSize = numberSize ?? side * 0.4;
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
          numberSize: timerSize,
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
