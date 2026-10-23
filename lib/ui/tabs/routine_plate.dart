// ═══════════════════════════════════════════════════════════════════
// lib/ui/tabs/routine_plate.dart — one routine tile in the list.
//
// Extracted from routines_tab. Contains: frame, name, date, timer,
// the routine pulse (start/pause/open) with an action subpult
// (duplicate, mark completed, delete), and a select-mode checkbox.
//
// Running palette. When the routine has a running block, the plate
// takes the opposite theme's roles via OperationalLayer.runningColors
// — the same method RoutineBlockView uses, so the two views cannot
// drift apart on the fallback.
//
// Scopes. Dependencies are read from point scopes: BortScope (theme,
// colors, opposite palette), I18nScope (strings), TickerScope (colon
// blink), RoutineScope (layer mutations). AppScope is consulted only
// for the journal and for toggleBlockWithShift (an AppContext method).
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/routine.dart';
import '../core/app_scope.dart';
import '../core/format.dart';
import '../core/routine_flags.dart';
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
    final bort = BortScope.of(context);
    final i18n = I18nScope.of(context);
    final ticker = TickerScope.of(context);
    final routineLayer = RoutineScope.of(context);
    final app = AppScope.of(context);
    final side = PultScope.of(context).smallSide;
    final running = routine.runningBlock != null;

    final Color plateBg;
    final Color textMain;
    final Color textSoft;
    final Color accent;
    if (running) {
      // Running palette — from the shared OperationalLayer method,
      // the same as RoutineBlockView.
      final c = bort.runningColors();
      plateBg = c.bg;
      textMain = c.fg;
      textSoft = c.dim;
      accent = c.signal;
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
            await routineLayer.pauseBlock(app.journal, routine.id, b.kind);
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

    // Flags sit in a vertical column on the left strip of the plate,
    // occupying its full height. Glyphs share one inverted plate
    // (accent background, plate-colored glyphs, no frame) and are
    // enlarged by a quarter against the former inline size.
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

    // IntrinsicHeight + stretch lets the flags column occupy the
    // plate's full height while the middle column keeps its natural
    // size; everything else is centered by Align.
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
                    // Assigned date — rectangular frame, uniformly
                    // with the «days» tab calendar (there the mark is
                    // a square).
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
          // Routine time — placed to the left of the pult.
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
          // Frame follows flags: signal-colored when the routine
          // carries any flag bit, neutral textSoft otherwise.
          border: Border.all(
            color: routine.flags != 0 ? accent : textSoft,
            width: strokeW,
          ),
          borderRadius: BorderRadius.circular(radiusW),
        ),
        padding: EdgeInsets.all(framePad),
        child: body,
      ),
    );
  }
}
