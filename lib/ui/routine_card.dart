// ═══════════════════════════════════════════════════════════════════
// routine_card.dart — карточка рутины.
//
// Сверху — редактируемое имя (сохранение при уходе внимания).
// Ниже — шесть блоков в рамках со сглаженными углами и тонкою
// обводкою. В каждом блоке: надпись слева вверху приглушённым
// текстом, под нею — время блока слева же; приглушено, коли блок
// на паузе, сигнальным — коли идёт. Пульс — в правом-нижнем углу,
// уменьшен на треть; на паузе приглушён, при ходе сигнальный.
// Сводка устроена проще: надпись и время, без пульта.
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

  // Рамка со сглаженными углами и тонкою обводкою. Внутри: надпись
  // слева вверху, под нею — содержимое (обыкновенно время), в правом-
  // нижнем углу — необязательный пульс.
  Widget _frame({
    required String title,
    required Widget child,
    required Widget? corner,
    required Color dim,
    required double titleSize,
    required double reserveBottom,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: dim, width: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + reserveBottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: dim, fontSize: titleSize),
                ),
                const SizedBox(height: 6),
                child,
              ],
            ),
          ),
          if (corner != null)
            Positioned(
              right: 8,
              bottom: 8,
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

    final pultSide = side * 2 / 3;
    final blockNumberSize = side * 0.4;
    final summaryNumberSize = side * 0.5;
    final titleSize = side * 0.4;

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final ms = DateTime.now().millisecond;
    final colonVisible = ms < 333;

    final blocks = <Widget>[];
    for (final k in RoutineBlock.kinds) {
      final b = r.blockOf(k);
      final running = b?.isRunning ?? false;
      final seconds = b?.secondsNowAt(now) ?? 0;

      blocks.add(
        _frame(
          title: i18n.t('routine.block.$k'),
          dim: dim,
          titleSize: titleSize,
          reserveBottom: pultSide,
          child: TimerText(
            seconds: seconds,
            running: running,
            fg: fg,
            dim: dim,
            signal: signal,
            numberSize: blockNumberSize,
            colonVisible: colonVisible,
          ),
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

    blocks.add(
      _frame(
        title: i18n.t('routine.summary'),
        dim: dim,
        titleSize: titleSize,
        reserveBottom: 0,
        child: TimerText(
          seconds: r.totalSeconds,
          running: false,
          fg: fg,
          dim: dim,
          signal: signal,
          numberSize: summaryNumberSize,
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
