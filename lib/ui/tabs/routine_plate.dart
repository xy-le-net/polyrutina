// ═══════════════════════════════════════════════════════════════════
// routine_plate.dart — плитка одной рутины в списке.
//
// Вынесена из routines_tab. Содержит: рамку, имя, дату, таймер,
// пульс рутины (пуск/пауза/открыть) с подпультом действий
// (дублировать, отметить завершённой, удалить), чекбокс режима
// выбора.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/routine.dart';
import '../core/app_scope.dart';
import '../core/format.dart';
import '../core/timer_text.dart';
import '../pults/pult_core.dart';
import '../pults/pult_tick.dart';

class RoutinePlate extends StatelessWidget {
  final Routine routine;
  final bool selectMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onSelectToggle;
  final VoidCallback onChanged;

  const RoutinePlate({
    super.key,
    required this.routine,
    required this.selectMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onSelectToggle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    final side = PultScope.of(context).smallSide;
    final running = routine.runningBlock != null;

    final Color plateBg;
    final Color textMain;
    final Color textSoft;
    final Color accent;
    if (running) {
      final opposite = bort.colorsForOpposite();
      if (opposite != null) {
        plateBg = opposite['bg']!;
        textMain = opposite['fg']!;
        textSoft = opposite['dim']!;
        accent = opposite['signal']!;
      } else {
        plateBg = bort.signal;
        textMain = bort.bg;
        textSoft = bort.bgdim;
        accent = bort.bg;
      }
    } else {
      plateBg = bort.bg;
      textMain = bort.fg;
      textSoft = bort.dim;
      accent = bort.signal;
    }

    final nameSize = side * bort.kName;
    final dateSize = side * bort.kTitle * 0.7;
    final numberSize = side * bort.kNumberSmall;
    final pultSide = side * bort.kPultSmall;
    final strokeW = side * bort.kStroke;
    final radiusW = side * bort.kRadius;
    final framePad = side * bort.kFramePad * 0.6;

    final IconData pulseIcon;
    final VoidCallback? pulseTap;
    if (routine.completed) {
      pulseIcon = Icons.check_box_outlined;
      pulseTap = () => app.openRoutine(routine.id);
    } else if (running) {
      pulseIcon = Icons.pause;
      pulseTap = () async {
        for (final b in routine.blocks) {
          if (b.isRunning) {
            await app.routineLayer.pauseBlock(app.journal, routine.id, b.kind);
          }
        }
        onChanged();
      };
    } else {
      pulseIcon = Icons.play_arrow;
      pulseTap = () async {
        await app.toggleBlockWithShift(routine.id, RoutineBlock.work);
        onChanged();
      };
    }

    final subs = <PultSpec>[];
    subs.add(
      PultSpec(
        id: 'dup_${routine.id}',
        icon: Icons.copy,
        label: i18n.t('bort.duplicate'),
        onTap: () async {
          await app.routineLayer.duplicateRoutine(app.journal, routine.id);
          onChanged();
        },
      ),
    );
    if (!routine.completed && !running) {
      subs.add(
        PultSpec(
          id: 'complete_${routine.id}',
          icon: Icons.check_circle_outline,
          label: i18n.t('routine.mark_completed'),
          confirm: true,
          onTap: () {
            app.routineLayer.setCompleted(app.journal, routine.id, true);
          },
        ),
      );
    }
    subs.add(
      PultSpec(
        id: 'del_${routine.id}',
        icon: Icons.delete_outline,
        label: i18n.t('bort.delete'),
        confirm: true,
        onTap: () {
          app.routineLayer.deleteRoutine(app.journal, routine.id);
        },
      ),
    );

    final rightControl = Pult(
      spec: PultSpec(
        id: 'routine_${routine.id}',
        icon: pulseIcon,
        selected: running,
        onTap: pulseTap,
        longSubs: () => subs,
      ),
      fg: textMain,
      bg: plateBg,
      signal: accent,
      overrideSize: pultSide,
    );

    final body = Row(
      children: [
        if (selectMode) ...[
          PultTick(
            id: 'sel_${routine.id}',
            value: selected,
            binary: true,
            fg: textMain,
            bg: plateBg,
            signal: accent,
            overrideSize: pultSide,
            onTap: onSelectToggle,
          ),
          SizedBox(width: side * 0.15),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (routine.name.isNotEmpty)
                Text(
                  routine.name,
                  style: TextStyle(color: textMain, fontSize: nameSize),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 10),
              Text(
                fmtDate(routine.createdAt, i18n.t),
                style: TextStyle(color: textSoft, fontSize: dateSize),
              ),
              if (routine.totalSeconds > 0) ...[
                SizedBox(height: dateSize * 0.4),
                TimerText(
                  seconds: routine.totalSeconds,
                  running: running,
                  fg: textMain,
                  dim: textSoft,
                  numberSize: numberSize,
                  colonVisible: app.ticker.colonVisible,
                  t: i18n.t,
                  ticker: app.ticker,
                ),
              ],
            ],
          ),
        ),
        SizedBox(width: side * 0.15),
        rightControl,
      ],
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: plateBg,
          border: Border.all(color: textSoft, width: strokeW),
          borderRadius: BorderRadius.circular(radiusW),
        ),
        padding: EdgeInsets.all(framePad),
        child: body,
      ),
    );
  }
}
