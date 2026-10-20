// ═══════════════════════════════════════════════════════════════════
// timer_text.dart — timer view according to a unified pattern.
//
// Colon blinking — from the ticker, regardless of the parent's
// redraw frequency. The parent may redraw rarely (on minute change),
// while the blinking goes twice a second.
//
// Leading zero — only on the second number in a pair: «1h 05m»,
// «3d 07h». A standalone number — without a zero: «7m», «5s».
//
// Transparency is not applied.
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

  // Pads a single-digit number with a leading zero.
  String _two(int n) => n.toString().padLeft(2, '0');

  List<(String, String)> _parts(int sec, {required bool running}) {
    if (sec < 0) sec = 0;
    const daySec = 86400;
    const hourSec = 3600;

    final days = sec ~/ daySec;
    final hours = (sec % daySec) ~/ hourSec;
    final minutes = (sec % hourSec) ~/ 60;
    final secs = sec % 60;

    if (running && days == 0 && hours == 0 && minutes == 0) {
      return [('$secs', 's')];
    }

    final out = <(String, String)>[];
    if (days > 0) {
      out.add(('$days', 'd'));
      if (hours > 0) out.add((_two(hours), 'h'));
    } else if (hours > 0) {
      out.add(('$hours', 'h'));
      out.add((_two(minutes), 'm'));
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
        // Blinking — from the ticker, if given; otherwise from the
        // passed flag.
        if (ticker != null) {
          children.add(
            AnimatedBuilder(
              animation: ticker!,
              builder: (_, __) => Opacity(
                opacity: ticker!.colonVisible ? 1.0 : 0.0,
                child: Text(
                  ':',
                  style: TextStyle(
                    color: primary,
                    fontFamily: 'monospace',
                    fontSize: numberSize,
                  ),
                ),
              ),
            ),
          );
        } else {
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
