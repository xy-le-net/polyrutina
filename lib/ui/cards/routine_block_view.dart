// ═══════════════════════════════════════════════════════════════════
// routine_block_view.dart — widget of one routine slot.
//
// Extracted from routine_card: frame, title, time pulse, content
// (TraceField or summary in «total»), corner pults.
//
// Background. The dimming (dimmed) is set from outside: background
// alternation by the order of shown blocks, starting from dimmed.
// The text input field is not subject to dimming: it is placed on
// the normal background (bg), regardless of whether the block is
// dimmed.
//
// Block «note». In the top right row — four pults left to right:
// assigned date, planned duration, show all slots, flags. Date pult
// and duration pult moved here from the page start (the manual plan
// input field is gone).
//
// Corners. Top right and bottom right — one right edge, one size
// (pultSide). The export button in «total» does not stick to the
// completion pult.
//
// Strict typing is enforced for the AppContext and I18n parameters
// in subpult builders to prevent runtime type errors.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/i18n.dart';
import '../../data/journal_types.dart';
import '../../data/routine.dart';
import '../core/app_scope.dart';
import '../core/block.dart';
import '../core/format.dart';
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

  // ─── External signs and handlers ───
  // Is the block dimmed — set from outside, from the display order.
  final bool dimmed;
  // Is there an assigned date (for the marked pult).
  final bool scheduledActive;
  // Open date picker; if null — date block is not rendered.
  final VoidCallback? onPickDate;
  // Open planned duration drum; null — not rendered.
  final VoidCallback? onPickPlanned;

  final VoidCallback onToggleCollapsed;
  final VoidCallback? onStartEdit;
  final VoidCallback? onConfirmEdit;
  final VoidCallback? onToggleCompleted;
  final VoidCallback? onExport;
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
    required this.onToggleShowAll,
    this.dimmed = false,
    this.scheduledActive = false,
    this.onPickDate,
    this.onPickPlanned,
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
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    final side = PultScope.of(context).smallSide;
    final colonVisible = app.ticker.colonVisible;

    // ─── Colors ───
    // Running block takes the opposite theme colors. Resting — normal
    // background or dimmed, by display order.
    final Color bg;
    final Color dim;
    final Color fg;
    final Color signal;
    if (running) {
      final opp = bort.colorsForOpposite();
      if (opp != null) {
        bg = opp['bg']!;
        dim = opp['dim']!;
        fg = opp['fg']!;
        signal = opp['signal']!;
      } else {
        bg = bort.signal;
        dim = bort.dim;
        fg = bort.bg;
        signal = bort.bg;
      }
    } else {
      bg = dimmed ? bort.bgdim : bort.bg;
      dim = bort.dim;
      fg = bort.fg;
      signal = bort.signal;
    }

    final titleSize = side * bort.kTitle;
    final pad = side * bort.kFramePad;
    final gap = side * bort.kBlockGap;
    final strokeW = side * bort.kStroke;
    final radiusW = side * bort.kRadius;
    final numberSize = side * bort.kNumber;
    final pultSide = side * bort.kPultSmall;

    Widget? cornerTop;

    if (showPulse) {
      if (editingKind == kind) {
        // Time editing mode: text field with a confirmation pult.
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
                  hintText: 'дд:чч:мм:сс',
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
        // Normal mode: running timer with start/pause pult.
        Widget pulse = Pulse(
          spec: PultSpec(
            id: 'block_$kind',
            icon: _blockIcon(kind),
            selected: running,
            onTap: () => app.toggleBlockWithShift(routine.id, kind),
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
          ticker: app.ticker,
        );
        // Underline indicates manually edited time.
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
      // Summary mode: total time and completion tick.
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
      // Static time display for non-running blocks.
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
      // Summary block: breakdown of time by slots.
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
      // Input field — on the normal background (bg), even if the
      // block is dimmed (bgdim): the field itself is not darkened.
      body = TraceField(
        objectId: routine.id,
        slot: kind,
        fg: fg,
        dim: dim,
        bg: bg,
        signal: signal,
        fieldBg: bort.bg,
        side: side,
        blockTitle: title,
        routineTitle: routine.name.isEmpty
            ? i18n.t('routine.no_name')
            : routine.name,
      );
    }

    final bool canCollapse = kind != 'summary';
    final bool showFlags = kind == 'note';
    final bool showExport = kind == 'summary';

    Widget? topRight = cornerTop;

    if (showFlags) {
      // Note block: top right row with date, plan, show all, and flags.
      final datePult = onPickDate == null
          ? null
          : Pult(
              spec: PultSpec(
                id: 'date_${routine.id}',
                icon: Icons.event,
                selected: scheduledActive,
                onTap: onPickDate,
              ),
              fg: fg,
              bg: bg,
              signal: signal,
              overrideSize: pultSide,
            );
      final plannedPult = onPickPlanned == null
          ? null
          : Pult(
              spec: PultSpec(
                id: 'planned_${routine.id}',
                icon: Icons.schedule,
                selected: routine.plannedSeconds > 0,
                onTap: onPickPlanned,
              ),
              fg: fg,
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
          selected: routine.flags != 0,
          subsBuilder: () => _flagSubs(app, routine, i18n),
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
          if (plannedPult != null) ...[
            plannedPult,
            SizedBox(width: side * 0.15),
          ],
          showAllPult,
          SizedBox(width: side * 0.15),
          flagsPult,
          if (cornerTop != null) SizedBox(width: side * 0.15),
          if (cornerTop != null) cornerTop,
        ],
      );
    }

    Widget? cornerBottom;
    if (showExport) {
      cornerBottom = Pult(
        spec: PultSpec(
          id: 'export_${routine.id}',
          icon: Icons.ios_share,
          onTap: onExport,
        ),
        fg: fg,
        bg: bg,
        signal: signal,
        overrideSize: pultSide,
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
      reserveBottom: showExport ? pultSide + side * 0.15 : 0,
      child: body,
    );
  }

  // ─── Five senior bits that are edited from the card ───
  static const List<int> _flagBits = [
    JournalFlag.urgent,
    JournalFlag.emergency,
    JournalFlag.important,
    JournalFlag.disputable,
    JournalFlag.complexOp,
  ];

  static const List<String> _flagKeys = [
    'flag.urgent',
    'flag.emergency',
    'flag.important',
    'flag.disputable',
    'flag.complexOp',
  ];

  static const List<IconData> _flagIcons = [
    Icons.access_time,
    Icons.warning_amber,
    Icons.star_border,
    Icons.help_outline,
    Icons.fitness_center,
  ];

  // Generates subpults for flag selection. Strictly typed parameters
  // (AppContext, I18n) replace the former dynamic types.
  List<PultSpec> _flagSubs(AppContext app, Routine routine, I18n i18n) {
    final out = <PultSpec>[];
    final cur = routine.flags;
    for (var i = 0; i < _flagBits.length; i++) {
      final f = _flagBits[i];
      out.add(
        PultSpec(
          id: 'flag_$i',
          icon: _flagIcons[i],
          label: i18n.t(_flagKeys[i]),
          selected: (cur & f) != 0,
          stayOpen: true,
          onTap: () {
            final newVal = cur ^ f;
            app.routineLayer.setFlags(app.journal, routine.id, newVal);
          },
        ),
      );
    }
    return out;
  }
}
