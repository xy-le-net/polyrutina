// ═══════════════════════════════════════════════════════════════════
// routine_card.dart — карточка рутины.
//
// Назначение: работа с одной рутиной. Сверху — редактируемое имя.
// Ниже — шесть блоков в рамках со сглаженными углами и тонкою
// обводкою:
//   пять родов (подготовка, переход туда, работа, переход обратно,
//   закрытие) — взаимоисключающие, логика в routine_layer;
//   шестой — сводка: сумма времени всех блоков, без пульта.
//
// Внутри блока рода: надпись слева вверху приглушённым текстом;
// под нею — число времени блока слева же; пульс — в правом-нижнем
// углу. Пульс уменьшен на треть против обычного (kPultSmall).
// На паузе пульс и число приглушены; при ходе — сигнальный цвет,
// двоеточие мелькает.
//
// Блоки переходов (trans1, trans2) — второстепенные: их фон
// берётся из роли bgDim, что визуально отличает их от основных
// блоков без введения лишних сущностей.
//
// Размеры берутся из коэффициентов борта: kBlockGap, kFramePad,
// kTitle, kNumber, kPultSmall, kStroke, kRadius. Правка любого
// коэффициента в рубке меняет вид карточки согласованно.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/routine.dart';
import 'app_scope.dart';
import 'bort_field.dart';
import 'pult.dart';
import 'timer_text.dart';

class RoutineCard extends StatefulWidget {
  final int routineId;
  const RoutineCard({super.key, required this.routineId});

  @override
  State<RoutineCard> createState() => _RoutineCardState();
}

class _RoutineCardState extends State<RoutineCard> {
  // Тик для мелькания двоеточия у идущего блока. Перерисовка
  // зовётся токмо при наличии идущего блока; иначе тик молчит.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      final app = AppScope.of(context);
      final r = app.routineLayer.findRoutine(widget.routineId);
      if (r != null && r.runningBlock != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  // Иконы родов блоков. Подобраны так, чтобы подготовка и закрытие
  // читались как «начало» и «конец», а переходы — как стрелки.
  IconData _blockIcon(String kind) {
    switch (kind) {
      case RoutineBlock.prep:
        return Icons.build_outlined;
      case RoutineBlock.trans1:
        return Icons.arrow_forward;
      case RoutineBlock.work:
        return Icons.construction;
      case RoutineBlock.trans2:
        return Icons.arrow_back;
      case RoutineBlock.closeout:
        return Icons.check_circle_outline;
      default:
        return Icons.circle_outlined;
    }
  }

  // Роды блоков-переходов: у них фон берётся из роли bgDim.
  // Прочие — с фоном страницы. Сие делает переходы визуально
  // второстепенными без введения дополнительных коэффициентов
  // и без изменения состава самих блоков.
  bool _isTransition(String kind) =>
      kind == RoutineBlock.trans1 || kind == RoutineBlock.trans2;

  // Рамка блока. Внутри: надпись слева вверху приглушённым текстом,
  // под нею содержимое (обыкновенно время блока), в правом-нижнем
  // углу — необязательный пульс.
  //
  // Приём: Padding снизу увеличен на reserveBottom — запас под
  // пульс в углу. Пульс как Positioned в расчёте высоты не участвует,
  // потому запас задаётся вручную.
  Widget _frame({
    required String title,
    required Widget child,
    required Widget? corner,
    required Color fg,
    required Color dim,
    required Color frameBg,
    required double titleSize,
    required double pad,
    required double gap,
    required double strokeW,
    required double radiusW,
    required double reserveBottom,
  }) {
    return Container(
      // Промежуток снизу — меж блоками. Сим блоки разделяются
      // ровно на kBlockGap от базовой величины.
      margin: EdgeInsets.only(bottom: gap),
      decoration: BoxDecoration(
        // Фон блока: обычный либо приглушённый (для переходов).
        color: frameBg,
        // Обводка тонкая, приглушённая, скругление — от kRadius.
        border: Border.all(color: dim, width: strokeW),
        borderRadius: BorderRadius.circular(radiusW),
      ),
      child: Stack(
        children: [
          Padding(
            // Запас снизу — под пульс в углу; справа и слева — ровный.
            padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + reserveBottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Надпись рода — приглушённая, слева вверху.
                Text(
                  title,
                  style: TextStyle(color: dim, fontSize: titleSize),
                ),
                SizedBox(height: pad * 0.5),
                // Содержимое блока — обычно TimerText, слева.
                child,
              ],
            ),
          ),
          // Пульс — в правом-нижнем углу, поверх содержимого.
          if (corner != null)
            Positioned(
              right: pad * 0.5,
              bottom: pad * 0.5,
              child: corner,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    final brightness = Theme.of(context).brightness;
    final fg = bort.currentFg(brightness);
    final bg = bort.currentBg(brightness);
    final signal = bort.currentSignal(brightness);
    final dim = bort.currentDim(brightness);
    final bgDim = bort.currentBgDim(brightness);
    final side = PultScope.of(context).smallSide;

    final r = app.routineLayer.findRoutine(widget.routineId);
    if (r == null) {
      return Scaffold(
        backgroundColor: bg,
        body: Center(
          child: Text(
            i18n.t('routine.not_found'),
            style: TextStyle(color: dim),
          ),
        ),
      );
    }

    // Все размеры — производные от коэффициентов борта.
    // pultSide — уменьшенный пульс блока.
    // titleSize — кегль надписи рода.
    // numberSize — кегль числа времени.
    // pad — отбивка внутри рамки.
    // gap — промежуток меж блоками (0.2 по уговору).
    // strokeW, radiusW — обводка и скругление рамок.
    final pultSide = side * bort.kPultSmall;
    final titleSize = side * bort.kTitle;
    final numberSize = side * bort.kNumber;
    final pad = side * bort.kFramePad;
    final gap = side * bort.kBlockGap;
    final strokeW = side * bort.kStroke;
    final radiusW = side * bort.kRadius;

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final ms = DateTime.now().millisecond;
    final colonVisible = ms < 333;

    // ─── Пять блоков родов ───
    // Каждый — рамка с надписью, числом и пульсом. Переходы
    // получают фон bgDim, прочие — фон страницы.
    final blocks = <Widget>[];
    for (final k in RoutineBlock.kinds) {
      final b = r.blockOf(k);
      final running = b?.isRunning ?? false;
      final seconds = b?.secondsNowAt(now) ?? 0;
      final frameBg = _isTransition(k) ? bgDim : bg;

      blocks.add(
        _frame(
          title: i18n.t('routine.block.$k'),
          fg: fg,
          dim: dim,
          frameBg: frameBg,
          titleSize: titleSize,
          pad: pad,
          gap: gap,
          strokeW: strokeW,
          radiusW: radiusW,
          reserveBottom: pultSide * 0.5,
          // Число блока: при ходе — сигнальное, при паузе —
          // приглушённое. Двоеточие мелькает по уставу.
          child: TimerText(
            seconds: seconds,
            running: running,
            fg: fg,
            dim: dim,
            signal: signal,
            numberSize: numberSize,
            colonVisible: colonVisible,
          ),
          // Пульс блока: на паузе приглушён (fg: dim), при ходе
          // перебивается сигнальным (selected: true).
          corner: Pult(
            spec: PultSpec(
              id: 'block_$k',
              icon: _blockIcon(k),
              selected: running,
              onTap: () => app.routineLayer.toggleBlock(r.id, k),
            ),
            fg: dim,
            bg: bg,
            signal: signal,
            overrideSize: pultSide,
          ),
        ),
      );
    }

    // ─── Сводка ───
    // Последний блок без пульта: суммирует время всех блоков.
    // Число — тем же кеглем, что и блоки; надпись — приглушённая.
    // Отдельного пульта нет: сводка не нажимается.
    blocks.add(
      _frame(
        title: i18n.t('routine.summary'),
        fg: fg,
        dim: dim,
        frameBg: bg,
        titleSize: titleSize,
        pad: pad,
        gap: gap,
        strokeW: strokeW,
        radiusW: radiusW,
        reserveBottom: 0,
        child: TimerText(
          seconds: r.totalSeconds,
          running: false,
          fg: fg,
          dim: dim,
          signal: signal,
          numberSize: numberSize,
          colonVisible: colonVisible,
        ),
        corner: null,
      ),
    );

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: fg,
        elevation: 0,
        title: Text(
          r.name.isEmpty ? i18n.t('routine.no_name') : r.name,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ─── Имя рутины ───
              // Поле ввода: правка сохраняется при уходе внимания
              // либо по Enter (механизм в BortField). До сохранения
              // имя в заголовке окна прежнее; после — обновится
              // чрез уведомление слоя рутин.
              BortField(
                initial: r.name,
                fg: fg,
                readOnly: false,
                hint: i18n.t('routine.no_name'),
                onCommit: (v) async {
                  await app.routineLayer.renameRoutine(r.id, v);
                },
              ),
              const SizedBox(height: 16),
              ...blocks,
            ],
          ),
        ),
      ),
    );
  }
}
