// ═══════════════════════════════════════════════════════════════════
// actor_tab.dart — вкладка актора.
//
// Первый полевой пульс: «на смене / пауза».
// На пульсе — ОБЩЕЕ время работы за всю историю, две старшие единицы
// из четырёх (месяцы, дни, часы, минуты). Рядом с каждым числом —
// приглушённая подпись единицы (на треть меньше).
// Двоеточие мигает: треть секунды горит, две трети — нет.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/journal_repository.dart';
import 'app_scope.dart';
import 'pult.dart';

class ActorTab extends StatefulWidget {
  const ActorTab({super.key});

  @override
  State<ActorTab> createState() => _ActorTabState();
}

class _ActorTabState extends State<ActorTab> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      final app = AppScope.of(context);
      if (app.bort.onShift) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  // ─── Формат: две старшие единицы ───
  (String, String, String, String) _fmtParts(int sec) {
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

  Future<void> _toggle() async {
    final app = AppScope.of(context);
    final bort = app.bort;
    final going = !bort.onShift;

    await app.journal.log(
      type: JournalType.actor,
      body: '{"action":"${going ? 'shift_start' : 'shift_stop'}"}',
    );

    if (going) {
      bort.startShift();
    } else {
      bort.stopShift();
    }

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final brightness = Theme.of(context).brightness;
    final fg = bort.currentFg(brightness);
    final bg = bort.currentBg(brightness);
    final signal = bort.currentSignal(brightness);
    final side = PultScope.of(context).side;

    final onShift = bort.onShift;
    final icon = onShift ? Icons.pause : Icons.play_arrow;

    final (a, ua, b, ub) = _fmtParts(bort.shiftSecondsNow);

    // Текст пульта — цветом знака, то есть цветом подложки.
    // Сие обратный цвет к фону пульта (фон = цвет текста).
    final primaryColor = bg;
    // Второстепенные подписи — тем же цветом, но приглушённые.
    final secondaryColor = bg.withValues(alpha: 0.6);

    final numberSize = side * 0.35;
    final unitSize = numberSize * 2 / 3;

    final ms = DateTime.now().millisecond;
    final colonVisible = onShift && (ms < 333);

    final labelWidget = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(a,
            style: TextStyle(
                color: primaryColor,
                fontFamily: 'monospace',
                fontSize: numberSize)),
        const SizedBox(width: 2),
        Text(ua,
            style: TextStyle(
                color: secondaryColor,
                fontFamily: 'monospace',
                fontSize: unitSize)),
        Opacity(
          opacity: colonVisible ? 1.0 : 0.0,
          child: Text(':',
              style: TextStyle(
                  color: primaryColor,
                  fontFamily: 'monospace',
                  fontSize: numberSize)),
        ),
        Text(b,
            style: TextStyle(
                color: primaryColor,
                fontFamily: 'monospace',
                fontSize: numberSize)),
        const SizedBox(width: 2),
        Text(ub,
            style: TextStyle(
                color: secondaryColor,
                fontFamily: 'monospace',
                fontSize: unitSize)),
      ],
    );

    return Center(
      child: Pult(
        spec: PultSpec(
          id: 'shift',
          icon: icon,
          labelWidget: labelWidget,
          selected: onShift,
          onTap: _toggle,
        ),
        fg: fg,
        bg: bg,
        signal: signal,
        overrideSize: side,
      ),
    );
  }
}
