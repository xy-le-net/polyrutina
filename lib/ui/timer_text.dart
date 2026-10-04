// ═══════════════════════════════════════════════════════════════════
// timer_text.dart — вид таймера по единому образцу.
//
// Две старшие единицы из четырёх (месяц, день, час, минута).
// Числа крупно, подписи единиц уменьшены на треть и приглушены.
// Двоеточие меж числами мелькает: треть секунды видно, две трети нет.
// Таймер идущий — сигнальным цветом, покоящийся — приглушённым.
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

  // Две старшие единицы из четырёх.
  static (String, String, String, String) parts(int sec) {
    if (sec < 0) sec = 0;
    const monthSec = 2629746;
    const daySec = 86400;
    const hourSec = 3600;

    String two(int n) => n.toString().padLeft(2, '0');

    final month = sec ~/ monthSec;
    final day = (sec % monthSec) ~/ daySec;
    final hour = (sec % daySec) ~/ hourSec;
    final minute = (sec % hourSec) ~/ 60;

    if (month > 0) return (two(month), 'мес', two(day), 'дн');
    if (day > 0) return (two(day), 'дн', two(hour), 'ч');
    return (two(hour), 'ч', two(minute), 'мин');
  }

  @override
  Widget build(BuildContext context) {
    final primary = running ? signal : fg;
    final secondary = running ? signal.withValues(alpha: 0.6) : dim;
    final unitSize = numberSize * 2 / 3;

    final (a, ua, b, ub) = parts(seconds);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(a,
            style: TextStyle(
                color: primary, fontFamily: 'monospace', fontSize: numberSize)),
        Text(ua,
            style: TextStyle(
                color: secondary, fontFamily: 'monospace', fontSize: unitSize)),
        Opacity(
          // Мигание — токмо у идущего таймера. Покоящийся двоеточие
          // держит постоянно: идущий блок один, оттого и мигает один.
          opacity: (!running || colonVisible) ? 1.0 : 0.0,
          child: Text(':',
              style: TextStyle(
                  color: primary,
                  fontFamily: 'monospace',
                  fontSize: numberSize)),
        ),
        Text(b,
            style: TextStyle(
                color: primary, fontFamily: 'monospace', fontSize: numberSize)),
        Text(ub,
            style: TextStyle(
                color: secondary, fontFamily: 'monospace', fontSize: unitSize)),
      ],
    );
  }
}
