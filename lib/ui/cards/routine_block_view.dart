// ═══════════════════════════════════════════════════════════════════
// routine_block_view.dart — widget of one routine slot.
//
// Extracted from routine_card: frame, title, time pulse, content
// (TraceField or summary in «total»), corner pults.
//
// Layout tuning. Padding inside blocks and gaps between them are
// the halved kFramePad / kBlockGap (see operational_layer); the
// previous extra 0.75 multiplication is dropped, since the base is
// already half of what it used to be. The title font is slightly
// smaller to save space; the text trace (TraceField) occupies the
// remaining width.
//
// Notice interval. The pult that used to set a planned duration now
// sets a lead time — how long before the due date to remind. It is
// shown ONLY when a date is assigned (onPickNotice != null); the
// caller enforces this in routine_card. When a notice is actually
// set, a long-press subpult «снять предуведомление» clears it.
//
// Delete. The summary block gains a delete pult next to export and
// move, with confirmation. Deleting from the summary is the second
// route to routine removal (the first being the long-press menu in
// the list).
//
// Field awareness. The toggleBlockWithShift call requires the
// active field's ID to properly associate the shift.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/routine.dart';
import '../core/app_scope.dart';
import '../core/block.dart';
import '../core/format.dart';
import '../core/routine_flags.dart';
import '../core/timer_text.dart';
import '../core/trace_field.dart';
import '../pults/pulse.dart';
import '../pults/pult_core.dart';
import '../pults/pult_tick.dart';

class RoutineBlockView extends StatelessWidget {
  final Routine routine;
  final String kind;
  final String title;
  final bool running;
  final int seconds;
  final bool showPulse;
  final bool showCompletion;
  final bool timeEdited;
  final bool collapsed;
  final bool showAllSlots;
  final String? editingKind;
  final TextEditingController? editCtrl;
  final FocusNode? editFocus;

  final int parity;
  final bool scheduledActive;
  final VoidCallback? onPickDate;
  final VoidCallback? onClearDate;
  // Notice interval: picker only when a date is assigned; clearing
  // only when a notice is set.
  final VoidCallback? onPickNotice;
  final VoidCallback? onClearNotice;

  final VoidCallback onToggleCollapsed;
  final VoidCallback? onStartEdit;
  final VoidCallback? onConfirmEdit;
  final VoidCallback? onToggleCompleted;
  final VoidCallback? onExport;
  final VoidCallback? onMove;
  final VoidCallback? onDelete;
  final VoidCallback onToggleShowAll;

  const RoutineBlockView({
    super.key,
    required this.routine,
    required this.kind,
    required this.title,
    required this.running,
    required this.seconds,
    required this.showPulse,
    required this.showCompletion,
    required this.timeEdited,
    required this.collapsed,
    required this.showAllSlots,
    required this.editingKind,
    required this.editCtrl,
    required this.editFocus,
    required this.onToggleCollapsed,
    this.onStartEdit,
    this.onConfirmEdit,
    this.onToggleCompleted,
    this.onExport,
    this.onMove,
    this.onDelete,
    required this.onToggleShowAll,
    this.parity = 0,
    this.scheduledActive = false,
    this.onPickDate,
    this.onClearDate,
    this.onPickNotice,
    this.onClearNotice,
  });

  static IconData _blockIcon(String kind) {
    switch (kind) {
      case RoutineBlock.prep:
        return Icons.build_outlined;
      case RoutineBlock.transit:
        return Icons.directions_walk;
      case RoutineBlock.work:
        return Icons.construction;
      case RoutineBlock.idle:
        return Icons.hourglass_empty;
      case RoutineBlock.closeout:
        return Icons.check_circle_outline;
      default:
        return Icons.circle_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bort = BortScope.of(context);
    final i18n = I18nScope.of(context);
    final colonVisible = TickerScope.of(context).colonVisible;
    final side = PultScope.of(context).smallSide;
    final fieldId =
        FieldScope.of(context).activeFieldId ?? FieldScope.of(context).rootId;

    final Color bg;
    final Color dim;
    final Color fg;
    final Color signal;
    if (running) {
      final c = bort.runningColors();
      bg = c.bg;
      dim = c.mid;
      fg = c.fg;
      signal = c.fgsignal;
    } else {
      bg = bort.bg;
      dim = bort.mid;
      fg = bort.fg;
      signal = bort.fgsignal;
    }

    // Padding is taken straight from the (now halved) coefficients:
    // the previous extra 0.75 multiplication would have produced
    // quarter-sized values, drifting away from the unified scale.
    final titleSize = side * bort.kTitle * 0.8;
    final pad = side * bort.kFramePad;
    final gap = side * bort.kBlockGap;

    final strokeW = side * bort.kStroke;
    final radiusW = side * bort.kRadius;
    final numberSize = side * bort.kNumber;
    final pultSide = side * bort.kPultSmall;

    Widget? cornerTop;

    if (showPulse) {
      if (editingKind == kind) {
        cornerTop = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: side * 2.6,
              child: TextField(
                controller: editCtrl,
                focusNode: editFocus,
                autofocus: true,
                style: TextStyle(color: fg, fontSize: numberSize),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: i18n.t('hint.time'),
                  hintStyle: TextStyle(color: dim, fontSize: numberSize * 0.7),
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: dim),
                    borderRadius: BorderRadius.circular(radiusW),
                  ),
                  contentPadding: EdgeInsets.all(side * 0.1),
                ),
                onSubmitted: (_) => onConfirmEdit?.call(),
              ),
            ),
            SizedBox(width: side * 0.1),
            Pult(
              spec: PultSpec(
                id: 'confirm_$kind',
                icon: Icons.check,
                onTap: onConfirmEdit,
              ),
              fg: fg,
              bg: bg,
              signal: signal,
              overrideSize: pultSide,
            ),
          ],
        );
      } else {
        Widget pulse = Pulse(
          spec: PultSpec(
            id: 'block_$kind',
            icon: _blockIcon(kind),
            selected: running,
            onTap: () {
              if (fieldId != null) {
                AppScope.of(
                  context,
                ).toggleBlockWithShift(fieldId, routine.id, kind);
              }
            },
            onLongPress: onStartEdit,
          ),
          seconds: seconds,
          running: running,
          fg: fg,
          dim: dim,
          bg: bg,
          signal: signal,
          side: side,
          colonVisible: colonVisible,
          pultSize: pultSide,
          t: i18n.t,
          ticker: TickerScope.of(context),
        );
        if (timeEdited) {
          pulse = Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: dim, width: strokeW * 2),
              ),
            ),
            child: pulse,
          );
        }
        cornerTop = pulse;
      }
    } else if (showCompletion) {
      cornerTop = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (seconds > 0)
            TimerText(
              seconds: seconds,
              running: false,
              fg: fg,
              dim: dim,
              numberSize: numberSize,
              colonVisible: colonVisible,
              t: i18n.t,
            ),
          SizedBox(width: side * 0.15),
          PultTick(
            id: 'complete_${routine.id}',
            value: routine.completed,
            binary: true,
            fg: fg,
            bg: bg,
            signal: signal,
            overrideSize: pultSide,
            onTap: onToggleCompleted,
          ),
        ],
      );
    } else if (seconds > 0) {
      cornerTop = TimerText(
        seconds: seconds,
        running: false,
        fg: fg,
        dim: dim,
        numberSize: numberSize,
        colonVisible: colonVisible,
        t: i18n.t,
      );
    }

    if (showCompletion && timeEdited && cornerTop != null) {
      cornerTop = Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: dim, width: strokeW * 2),
          ),
        ),
        child: cornerTop,
      );
    }

    Widget? body;
    if (kind == 'summary') {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final rows = <Widget>[];
      for (final b in routine.blocks) {
        final sec = b.secondsNowAt(now);
        if (sec > 0) {
          rows.add(
            Padding(
              padding: EdgeInsets.only(top: side * 0.1),
              child: Text(
                '${i18n.t('routine.block.${b.kind}')}: '
                '${fmtTime(sec, i18n.t)}.',
                style: TextStyle(
                  color: dim,
                  fontSize: side * bort.kNumberSmall,
                ),
              ),
            ),
          );
        }
      }
      body = rows.isEmpty
          ? SizedBox(height: pultSide + side * 0.15)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: rows,
            );
    } else {
      body = TraceField(
        objectId: routine.id,
        slot: kind,
        fg: fg,
        dim: dim,
        bg: bg,
        signal: signal,
        fieldBg: running ? bg : bort.bg,
        side: side,
        blockTitle: title,
        routineTitle: routine.name.isEmpty
            ? i18n.t('routine.no_name')
            : routine.name,
      );
    }

    final bool canCollapse = kind != 'summary';
    final bool showFlags = kind == 'note';
    final bool showSummaryPults = kind == 'summary';

    Widget? topRight = cornerTop;

    if (showFlags) {
      final hasFlags = routine.flags != 0;
      final datePult = onPickDate == null
          ? null
          : Pult(
              spec: PultSpec(
                id: 'date_${routine.id}',
                icon: Icons.event,
                selected: scheduledActive,
                onTap: onPickDate,
                longSubs: (scheduledActive && onClearDate != null)
                    ? () => [
                        PultSpec(
                          id: 'clear_date_${routine.id}',
                          icon: Icons.event_busy,
                          label: i18n.t('routine.clear_date'),
                          confirm: true,
                          onTap: onClearDate,
                        ),
                      ]
                    : null,
              ),
              fg: scheduledActive ? signal : fg,
              bg: bg,
              signal: signal,
              overrideSize: pultSide,
            );
      // Notice pult is shown only with a date; long press clears
      // the notice when one is set.
      final noticePult = onPickNotice == null
          ? null
          : Pult(
              spec: PultSpec(
                id: 'notice_${routine.id}',
                icon: Icons.notifications_active_outlined,
                selected: routine.noticeSet,
                onTap: onPickNotice,
                longSubs: (routine.noticeSet && onClearNotice != null)
                    ? () => [
                        PultSpec(
                          id: 'clear_notice_${routine.id}',
                          icon: Icons.notifications_off_outlined,
                          label: i18n.t('routine.clear_notice'),
                          confirm: true,
                          onTap: onClearNotice,
                        ),
                      ]
                    : null,
              ),
              fg: routine.noticeSet ? signal : fg,
              bg: bg,
              signal: signal,
              overrideSize: pultSide,
            );
      final showAllPult = Pult(
        spec: PultSpec(
          id: 'show_all_${routine.id}',
          icon: showAllSlots ? Icons.visibility : Icons.visibility_off,
          selected: showAllSlots,
          onTap: onToggleShowAll,
        ),
        fg: fg,
        bg: bg,
        signal: signal,
        overrideSize: pultSide,
      );
      final flagsPult = Pult(
        spec: PultSpec(
          id: 'flags_${routine.id}',
          icon: Icons.flag,
          selected: hasFlags,
          rebuildOn: RoutineScope.of(context),
          subsBuilder: () => buildFlagSubs(
            flags: routine.flags,
            i18n: i18n,
            onToggle: (newVal) => RoutineScope.of(
              context,
            ).setFlags(AppScope.of(context).journal, routine.id, newVal),
          ),
        ),
        fg: fg,
        bg: bg,
        signal: signal,
        overrideSize: pultSide,
      );
      topRight = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (datePult != null) ...[datePult, SizedBox(width: side * 0.15)],
          if (noticePult != null) ...[noticePult, SizedBox(width: side * 0.15)],
          showAllPult,
          SizedBox(width: side * 0.15),
          flagsPult,
          if (cornerTop != null) SizedBox(width: side * 0.15),
          if (cornerTop != null) cornerTop,
        ],
      );
    }

    Widget? cornerBottom;
    if (showSummaryPults) {
      cornerBottom = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onMove != null) ...[
            Pult(
              spec: PultSpec(
                id: 'move_${routine.id}',
                icon: Icons.drive_file_move,
                onTap: onMove,
              ),
              fg: fg,
              bg: bg,
              signal: signal,
              overrideSize: pultSide,
            ),
            SizedBox(width: side * 0.15),
          ],
          if (onExport != null) ...[
            Pult(
              spec: PultSpec(
                id: 'export_${routine.id}',
                icon: Icons.ios_share,
                onTap: onExport,
              ),
              fg: fg,
              bg: bg,
              signal: signal,
              overrideSize: pultSide,
            ),
            SizedBox(width: side * 0.15),
          ],
          if (onDelete != null)
            Pult(
              spec: PultSpec(
                id: 'delete_${routine.id}',
                icon: Icons.delete_outline,
                confirm: true,
                onTap: onDelete,
              ),
              fg: fg,
              bg: bg,
              signal: signal,
              overrideSize: pultSide,
            ),
        ],
      );
    }

    return Block(
      title: title,
      collapsed: collapsed,
      canCollapse: canCollapse,
      onToggleCollapsed: onToggleCollapsed,
      cornerRightTop: topRight,
      cornerRightBottom: cornerBottom,
      bg: bg,
      dim: dim,
      fg: fg,
      signal: signal,
      titleSize: titleSize,
      pad: pad,
      gap: gap,
      strokeW: strokeW,
      radiusW: radiusW,
      active: running,
      parity: parity,
      reserveBottom: showSummaryPults ? pultSide + side * 0.15 : 0,
      child: body,
    );
  }
}
