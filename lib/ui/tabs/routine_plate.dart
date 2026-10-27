// ═══════════════════════════════════════════════════════════════════
// lib/ui/tabs/routine_plate.dart — one routine tile in the list.
//
// Frame. Computed by borderFor (core/frame.dart).
//
// Running palette. When running, uses the opposite theme.
//
// Resume. The "play" button starts the last worked-on block
// (routine.lastBlockKind), falling back to "work" if none exists.
// It uses the active field's ID to correctly associate the shift.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/routine.dart';
import '../core/app_scope.dart';
import '../core/format.dart';
import '../core/frame.dart';
import '../core/routine_flags.dart';
import '../core/timer_text.dart';
import '../pults/pult_core.dart';
import '../pults/pult_tick.dart';

class RoutinePlate extends StatelessWidget {
  final Routine routine;
  final bool selectMode;
  final bool selected;
  final int parity;
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
    this.parity = 0,
  });

  @override
  Widget build(BuildContext context) {
    final bort = BortScope.of(context);
    final i18n = I18nScope.of(context);
    final ticker = TickerScope.of(context);
    final routineLayer = RoutineScope.of(context);
    final app = AppScope.of(context);
    final fieldId =
        FieldScope.of(context).activeFieldId ?? FieldScope.of(context).rootId;
    final side = PultScope.of(context).smallSide;
    final running = routine.runningBlock != null;

    final Color plateBg;
    final Color textMain;
    final Color textSoft;
    final Color accent;
    if (running) {
      final c = bort.runningColors();
      plateBg = c.bg;
      textMain = c.fg;
      textSoft = c.mid;
      accent = c.fgsignal;
    } else {
      plateBg = bort.bg;
      textMain = bort.fg;
      textSoft = bort.mid;
      accent = bort.fgsignal;
    }

    final nameSize = side * bort.kName;
    final dateSize = side * bort.kTitle * 0.7;
    final numberSize = side * bort.kNumberSmall;
    final pultSide = side * bort.kPultSmall;
    final strokeW = side * bort.kStroke;
    final radiusW = side * bort.kRadius;
    final framePad = side * bort.kFramePad * 0.6;

    final frame = borderFor(
      parity: parity,
      active: running,
      strokeW: strokeW,
      fg: textMain,
      mid: textSoft,
      fgsignal: accent,
    );

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
            await routineLayer.pauseBlock(app.journal, routine.id, b.kind);
          }
        }
        onChanged();
      };
    } else {
      pulseIcon = Icons.play_arrow;
      pulseTap = () async {
        if (fieldId != null) {
          final kind = routine.lastBlockKind ?? RoutineBlock.work;
          await app.toggleBlockWithShift(fieldId, routine.id, kind);
          onChanged();
        }
      };
    }

    final subs = <PultSpec>[];
    subs.add(
      PultSpec(
        id: 'dup_${routine.id}',
        icon: Icons.copy,
        label: i18n.t('bort.duplicate'),
        onTap: () async {
          await routineLayer.duplicateRoutine(app.journal, routine.id);
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
            routineLayer.setCompleted(app.journal, routine.id, true);
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
          routineLayer.deleteRoutine(app.journal, routine.id);
        },
      ),
    );

    final rightControl = Pult(
      spec: PultSpec(
        id: 'routine_${routine.id}',
        icon: pulseIcon,
        selected: false,
        onTap: pulseTap,
        longSubs: () => subs,
      ),
      fg: textMain,
      bg: plateBg,
      signal: accent,
      overrideSize: pultSide,
    );

    final Widget? flagsColumn = routine.flags == 0
        ? null
        : Container(
            padding: EdgeInsets.symmetric(
              horizontal: side * 0.1,
              vertical: side * 0.05,
            ),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(radiusW * 0.4),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < kFlagBits.length; i++)
                  if ((routine.flags & kFlagBits[i]) != 0)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: side * 0.03),
                      child: Icon(
                        kFlagIcons[i],
                        color: plateBg,
                        size: nameSize * 1.125,
                      ),
                    ),
              ],
            ),
          );

    final body = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (selectMode) ...[
            Center(
              child: PultTick(
                id: 'sel_${routine.id}',
                value: selected,
                binary: true,
                fg: textMain,
                bg: plateBg,
                signal: accent,
                overrideSize: pultSide,
                onTap: onSelectToggle,
              ),
            ),
            SizedBox(width: side * 0.15),
          ],
          if (flagsColumn != null) ...[
            flagsColumn,
            SizedBox(width: side * 0.15),
          ],
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    routine.name.isEmpty
                        ? i18n.t('routine.no_name')
                        : routine.name,
                    style: TextStyle(
                      color: routine.flags != 0 ? accent : textMain,
                      fontSize: nameSize,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  if (routine.scheduledAt != null)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: dateSize * 0.3,
                        vertical: dateSize * 0.1,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: accent, width: strokeW * 2),
                        borderRadius: BorderRadius.circular(radiusW * 0.3),
                      ),
                      child: Text(
                        fmtDate(routine.scheduledAt!, i18n.t),
                        style: TextStyle(color: accent, fontSize: dateSize),
                      ),
                    )
                  else
                    Text(
                      fmtDate(routine.createdAt, i18n.t),
                      style: TextStyle(color: textSoft, fontSize: dateSize),
                    ),
                ],
              ),
            ),
          ),
          if (routine.totalSeconds > 0) ...[
            SizedBox(width: side * 0.15),
            Center(
              child: TimerText(
                seconds: routine.totalSeconds,
                running: running,
                fg: textMain,
                dim: textSoft,
                numberSize: numberSize,
                colonVisible: ticker.colonVisible,
                t: i18n.t,
                ticker: ticker,
              ),
            ),
          ],
          SizedBox(width: side * 0.15),
          Center(child: rightControl),
        ],
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: plateBg,
          border: Border.all(color: frame.color, width: frame.width),
          borderRadius: BorderRadius.circular(radiusW),
        ),
        padding: EdgeInsets.all(framePad),
        child: body,
      ),
    );
  }
}
