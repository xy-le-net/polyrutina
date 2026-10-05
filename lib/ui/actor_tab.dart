// ═══════════════════════════════════════════════════════════════════
// actor_tab.dart — вкладка актора.
//
// Назначение: полевой пульс «на смене / пауза». Один пульт во весь
// экран: икона (играть либо пауза) и рядом — общее время работы
// за всю историю, двумя старшими единицами из четырёх.
//
// Время смены считается по журналу: записи рода actor с телами
// «shift_start» и «shift_stop» образуют пары; незакрытый старт
// означает идущую смену. При перезапуске состояние восстанавливается
// из журнала — сие делает operational_layer._recomputeShiftFromJournal.
//
// Таймер берётся из общего вида TimerText: две старшие единицы,
// подписи единиц уменьшены на треть, двоеточие мелькает.
// Тик — сто миллисекунд, но перерисовка зовётся токмо когда смена
// идёт; в покое тиканий нет.
//
// Цвет подписи пульта: bg — ибо подпись сидит на ядре, окрашенном
// в fg (покой) либо signal (ход). Оба цвета ядра читаются токмо
// с цветом фона. Полутон для подписей единиц изгнан вместе
// с прозрачностью: различие делается кеглем.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/journal_repository.dart';
import 'app_scope.dart';
import 'pult.dart';
import 'timer_text.dart';

class ActorTab extends StatefulWidget {
  const ActorTab({super.key});

  @override
  State<ActorTab> createState() => _ActorTabState();
}

class _ActorTabState extends State<ActorTab> {
  // Тик для мелькания двоеточия. Перерисовка зовётся токмо покуда
  // смена идёт: в покое тик молчит, и лишней работы нет.
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

  // Пуск либо остановка смены. Запись в журнал кладётся первою —
  // дабы при всяком сбое состояние смены было восстановимо.
  // Локальное состояние борта меняется после записи.
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
    // side — полный размер пульта (не smallSide): пульс актора —
    // главный на своей вкладке и стоит в полную величину.
    final side = PultScope.of(context).side;

    final onShift = bort.onShift;
    final icon = onShift ? Icons.pause : Icons.play_arrow;

    // Кегль числа — от коэффициента борта. Подписи единиц будут
    // на треть меньше — сие делает TimerText сам.
    final numberSize = side * bort.kNumber;

    // Мелькание двоеточия: треть секунды видно, две трети нет.
    final ms = DateTime.now().millisecond;
    final colonVisible = ms < 333;

    // ─── Подпись пульта ───
    // Три цвета ролей — все равны bg. Обоснование: подпись сидит
    // на ядре пульта, кое окрашено в fg (покой) либо signal (ход);
    // при обоих цветах ядра читается токмо цвет фона.
    final labelWidget = TimerText(
      seconds: bort.shiftSecondsNow,
      running: onShift,
      fg: bg,
      dim: bg,
      signal: bg,
      numberSize: numberSize,
      colonVisible: colonVisible,
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
