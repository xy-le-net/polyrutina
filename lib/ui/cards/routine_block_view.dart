// ═══════════════════════════════════════════════════════════════════
// routine_block_view.dart — виджет одного слота рутины.
//
// Вынесен из routine_card: рамка, заголовок, пульс времени,
// содержимое (TraceField либо сводка в «итоге»), угловые пульты
// (флаг, показать все, завершение, экспорт).
//
// Все слои берутся из AppScope. Состояние правки времени (какой
// слот правится, контроллер, фокус) — снаружи, дабы на карточку
// было одно поле правки.
//
// Углы. Правый верхний и правый нижний — по одному правому краю,
// один размер (pultSide). Кнопка экспорта в «итоге» не слипается
// с пультом завершения.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

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

  static bool _dimBg(String kind) =>
      kind == 'note' ||
      kind == RoutineBlock.transit ||
      kind == RoutineBlock.idle ||
      kind == 'summary';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    final side = PultScope.of(context).smallSide;
    final colonVisible = app.ticker.colonVisible;

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
      bg = _dimBg(kind) ? bort.bgdim : bort.bg;
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
      // Резерв снизу — под кнопку экспорта, дабы не слипалась
      // с пультом завершения.
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

  List<PultSpec> _flagSubs(dynamic app, Routine routine, dynamic i18n) {
    const keys = [
      'flag.urgent',
      'flag.emergency',
      'flag.important',
      'flag.disputable',
      'flag.complexOp',
      'flag.local',
      'flag.synced',
      'flag.correction',
    ];
    const icons = [
      Icons.access_time,
      Icons.warning_amber,
      Icons.star_border,
      Icons.help_outline,
      Icons.fitness_center,
      Icons.phone_android,
      Icons.cloud_done,
      Icons.edit,
    ];
    final out = <PultSpec>[];
    final cur = routine.flags;
    for (var i = 0; i < JournalFlag.all.length; i++) {
      final f = JournalFlag.all[i];
      out.add(
        PultSpec(
          id: 'flag_$i',
          icon: icons[i],
          label: i18n.t(keys[i]),
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
