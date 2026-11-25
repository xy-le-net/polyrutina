import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/routine.dart';
import '../core/app_scope.dart';
import '../core/format.dart';
import '../core/frame.dart';
import '../core/routine_flags.dart';
import '../core/timer_text.dart';
import '../pults/pult_core.dart';

class RoutinePlate extends StatelessWidget {
  final Routine routine;
  final int parity;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onChanged;

  const RoutinePlate({
    super.key,
    required this.routine,
    required this.onTap,
    required this.onLongPress,
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

    // Overdue is a visual state of its own: signal frame with doubled
    // stroke, normal palette. Running wins if both apply — its frame
    // is already signal-doubled and its palette is inverted, so the
    // doubled-signal rule is subsumed.
    final overdue = !running && routine.isOverdue;

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

    final nameSize = side * bort.kName * 0.8;
    final dateSize = side * bort.kTitle * 0.7 * 0.8;
    final numberSize = side * bort.kNumberSmall * 0.8;
    final pultSide = side * bort.kPultSmall;
    final strokeW = side * bort.kStroke;
    final radiusW = side * bort.kRadius;
    final framePad = side * bort.kFramePad * 0.6;

    final frame = borderFor(
      parity: parity,
      active: running || overdue,
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

    final rightControl = Pult(
      spec: PultSpec(
        id: 'routine_${routine.id}',
        icon: pulseIcon,
        selected: false,
        onTap: pulseTap,
        onLongPress: onLongPress,
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

    // right after the date line. The doubled frame already says the
    // routine demands attention; the word says why.
    final Widget? overdueLabel = overdue
        ? Padding(
            padding: EdgeInsets.only(top: dateSize * 0.3),
            child: Text(
              i18n.t('routine.overdue'),
              style: TextStyle(color: accent, fontSize: dateSize * 0.9),
            ),
          )
        : null;

    final body = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                  if (overdueLabel != null) overdueLabel,
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
      onSecondaryTap: defaultTargetPlatform == TargetPlatform.windows
          ? onLongPress
          : null,
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
