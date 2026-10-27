// ═══════════════════════════════════════════════════════════════════
// lib/ui/tabs/days_tab.dart — «days» tab. Month calendar.
//
// The routine's day is determined as follows: completedAt, otherwise
// scheduledAt, otherwise lastPulseAt, otherwise createdAt.
//
// Marks in the cell:
//   — completed — underlined number;
//   — scheduled — square border;
//   — unfinished — round border.
//
// Scheduling midnight. When a routine is scheduled to a specific
// day, the time is set to the bort's «midnight» setting.
//
// Layout. On narrow screens, the grid and the legend are stacked
// vertically. On wide screens, they are split into two columns.
// Crucially, the grid's width is constrained based on the available
// HEIGHT (at most 6 rows), ensuring the entire month fits on the
// screen without vertical scrolling even in landscape mode.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/i18n.dart';
import '../../data/operational_layer.dart';
import '../../data/routine.dart';
import '../core/app_scope.dart';
import '../core/control_row.dart';
import '../pults/pult_core.dart';
import '../pults/pult_sheet.dart';

class DaysTab extends StatefulWidget {
  const DaysTab({super.key});

  @override
  State<DaysTab> createState() => _DaysTabState();
}

class _DaysTabState extends State<DaysTab> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _month = DateTime(n.year, n.month, 1);
  }

  void _shift(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
    });
  }

  int? _dayOf(Routine r) {
    if (r.completed && r.completedAt != null) {
      return _sameMonth(r.completedAt!);
    }
    if (r.scheduledAt != null) return _sameMonth(r.scheduledAt!);
    if (r.lastPulseAt != null) return _sameMonth(r.lastPulseAt!);
    return _sameMonth(r.createdAt);
  }

  int? _sameMonth(int unixSec) {
    final d = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000);
    if (d.year != _month.year || d.month != _month.month) return null;
    return d.day;
  }

  _Mark _markOfRoutine(Routine r, int day) {
    if (r.completed &&
        r.completedAt != null &&
        _sameMonth(r.completedAt!) == day) {
      return _Mark.completed;
    }
    if (r.scheduledAt != null && _sameMonth(r.scheduledAt!) == day) {
      return _Mark.scheduled;
    }
    if (!r.completed) {
      return _Mark.unfinished;
    }
    return _Mark.none;
  }

  ({
    bool completed,
    bool completedSignal,
    bool unfinished,
    bool unfinishedSignal,
    bool scheduled,
    bool scheduledSignal,
    bool anySignal,
  })
  _marksOf(int day, List<Routine> routines) {
    var completed = false;
    var completedSignal = false;
    var unfinished = false;
    var unfinishedSignal = false;
    var scheduled = false;
    var scheduledSignal = false;
    var anySignal = false;
    for (final r in routines) {
      final mark = _markOfRoutine(r, day);
      final sig = r.flags != 0;
      if (sig) anySignal = true;
      switch (mark) {
        case _Mark.completed:
          completed = true;
          if (sig) completedSignal = true;
          break;
        case _Mark.unfinished:
          unfinished = true;
          if (sig) unfinishedSignal = true;
          break;
        case _Mark.scheduled:
          scheduled = true;
          if (sig) scheduledSignal = true;
          break;
        case _Mark.none:
          break;
      }
    }
    return (
      completed: completed,
      completedSignal: completedSignal,
      unfinished: unfinished,
      unfinishedSignal: unfinishedSignal,
      scheduled: scheduled,
      scheduledSignal: scheduledSignal,
      anySignal: anySignal,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bort = BortScope.of(context);
    final routineLayer = RoutineScope.of(context);
    final i18n = I18nScope.of(context);
    final side = PultScope.of(context).smallSide;

    final cells = <int, List<Routine>>{};
    var scheduledCount = 0;
    var unfinishedCount = 0;
    var completedCount = 0;
    for (final r in routineLayer.routines) {
      final day = _dayOf(r);
      if (day == null) continue;
      cells.putIfAbsent(day, () => []).add(r);
      switch (_markOfRoutine(r, day)) {
        case _Mark.scheduled:
          scheduledCount++;
          break;
        case _Mark.unfinished:
          unfinishedCount++;
          break;
        case _Mark.completed:
          completedCount++;
          break;
        case _Mark.none:
          break;
      }
    }

    final now = DateTime.now();
    final int? todayDay = (now.year == _month.year && now.month == _month.month)
        ? now.day
        : null;

    final firstWeekday = _month.weekday;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final totalCells = (((firstWeekday - 1) + daysInMonth + 6) ~/ 7) * 7;

    final grid = <Widget>[];
    for (var i = 0; i < totalCells; i++) {
      final dayNum = i - (firstWeekday - 1) + 1;
      if (dayNum < 1 || dayNum > daysInMonth) {
        grid.add(const SizedBox.shrink());
        continue;
      }
      final list = cells[dayNum] ?? const <Routine>[];
      grid.add(_cell(dayNum, list, side, bort, isToday: dayNum == todayDay));
    }

    final gridWidget = GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 7,
      childAspectRatio: 1,
      children: grid,
    );

    final legendWidget = _legend(
      side,
      bort,
      i18n,
      scheduled: scheduledCount,
      unfinished: unfinishedCount,
      completed: completedCount,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, right: 12),
          child: ControlRow(
            rootSide: side,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Pult(
                  spec: PultSpec(
                    id: 'prev_month',
                    icon: Icons.chevron_left,
                    onTap: () => _shift(-1),
                  ),
                  fg: bort.fg,
                  bg: bort.bg,
                  signal: bort.fgsignal,
                  overrideSize: side,
                ),
                Flexible(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: side * 0.15),
                    child: Text(
                      '${_month.year}.'
                      '${_month.month.toString().padLeft(2, '0')}',
                      style: TextStyle(color: bort.fg, fontSize: side * 0.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                Pult(
                  spec: PultSpec(
                    id: 'next_month',
                    icon: Icons.chevron_right,
                    onTap: () => _shift(1),
                  ),
                  fg: bort.fg,
                  bg: bort.bg,
                  signal: bort.fgsignal,
                  overrideSize: side,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 640;

              // In wide layout, constrain grid width based on available height
              // so that 6 rows fit without vertical scrolling.
              double maxGridWidth = 600.0;
              if (wide) {
                final availableHeight =
                    constraints.maxHeight - 40; // padding margin
                final maxCellSize = availableHeight / 6;
                maxGridWidth = (maxCellSize * 7).clamp(200.0, 600.0);
              }

              if (!wide) {
                return SingleChildScrollView(
                  padding: EdgeInsets.all(side * 0.3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      gridWidget,
                      SizedBox(height: side * 0.8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: legendWidget,
                      ),
                    ],
                  ),
                );
              }

              return SingleChildScrollView(
                padding: EdgeInsets.all(side * 0.6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: maxGridWidth, child: gridWidget),
                    SizedBox(width: side * 1.0),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: legendWidget,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _legend(
    double side,
    OperationalLayer bort,
    I18n i18n, {
    required int scheduled,
    required int unfinished,
    required int completed,
  }) {
    final color = bort.mid;
    final itemSize = side * 0.9;
    final markStroke = side * 0.04;
    final fontSize = side * 0.4;
    final gap = side * 0.3;

    Widget item(Widget mark, int count, String label) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: itemSize,
            height: itemSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                mark,
                Text(
                  '$count',
                  style: TextStyle(
                    color: color,
                    fontSize: fontSize,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: side * 0.1),
          Text(
            label,
            style: TextStyle(color: color, fontSize: fontSize),
          ),
        ],
      );
    }

    final items = <Widget>[];
    if (scheduled > 0) {
      items.add(
        item(
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: color, width: markStroke),
                borderRadius: BorderRadius.circular(side * 0.05),
              ),
            ),
          ),
          scheduled,
          i18n.t('days.legend.scheduled'),
        ),
      );
    }
    if (unfinished > 0) {
      items.add(
        item(
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: markStroke),
              ),
            ),
          ),
          unfinished,
          i18n.t('days.legend.unfinished'),
        ),
      );
    }
    if (completed > 0) {
      items.add(
        item(
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: EdgeInsets.only(bottom: itemSize * 0.1),
              height: markStroke,
              width: itemSize * 0.6,
              color: color,
            ),
          ),
          completed,
          i18n.t('days.legend.completed'),
        ),
      );
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Wrap(
      alignment: WrapAlignment.start,
      spacing: gap,
      runSpacing: gap,
      children: items,
    );
  }

  Widget _cell(
    int day,
    List<Routine> routines,
    double side,
    OperationalLayer bort, {
    required bool isToday,
  }) {
    final m = _marksOf(day, routines);

    final numberColor = m.anySignal ? bort.fgsignal : bort.mid;
    final underlineColor = m.completedSignal ? bort.fgsignal : bort.mid;
    final scheduledColor = m.scheduledSignal ? bort.fgsignal : bort.mid;
    final unfinishedColor = m.unfinishedSignal ? bort.fgsignal : bort.mid;

    final TextStyle style = TextStyle(
      color: numberColor,
      fontSize: side * 0.4,
      height: 1.0,
      decoration: m.completed ? TextDecoration.underline : TextDecoration.none,
      decorationColor: underlineColor,
    );

    final boxSide = side * 0.9;
    final circleSide = boxSide;
    final markStroke = side * 0.04;

    final layers = <Widget>[];

    if (isToday) {
      layers.add(
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bort.bgsignal,
              borderRadius: BorderRadius.circular(side * 0.12),
            ),
          ),
        ),
      );
    }

    if (m.scheduled) {
      layers.add(
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: scheduledColor, width: markStroke),
              borderRadius: BorderRadius.circular(side * 0.05),
            ),
          ),
        ),
      );
    }
    if (m.unfinished) {
      layers.add(
        Center(
          child: SizedBox(
            width: circleSide,
            height: circleSide,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: unfinishedColor, width: markStroke),
              ),
            ),
          ),
        ),
      );
    }
    layers.add(Text('$day', style: style));

    return GestureDetector(
      onTap: routines.isEmpty ? null : () => _openDay(routines),
      onLongPress: () => _createOnDay(day),
      child: Center(
        child: SizedBox(
          width: boxSide,
          height: boxSide,
          child: Stack(alignment: Alignment.center, children: layers),
        ),
      ),
    );
  }

  void _openDay(List<Routine> routines) {
    final bort = BortScope.of(context);
    final openRoutine = AppScope.of(context).openRoutine;
    showPultSheet(
      context: context,
      subs: [
        for (final r in routines)
          PultSpec(
            id: 'r_${r.id}',
            icon: _statusIcon(r),
            label: r.name.isEmpty ? '—' : r.name,
            selected: r.flags != 0,
            onTap: () => openRoutine(r.id),
          ),
      ],
      fg: bort.fg,
      bg: bort.bg,
      signal: bort.fgsignal,
      side: PultScope.of(context).smallSide,
    );
  }

  Future<void> _createOnDay(int day) async {
    final app = AppScope.of(context);
    final routineLayer = RoutineScope.of(context);
    final r = await routineLayer.createRoutine(app.journal);
    final dt = DateTime(_month.year, _month.month, day);

    final parts = app.bort.midnight.split(':');
    final hh = int.tryParse(parts.isNotEmpty ? parts[0] : '0') ?? 0;
    final mm = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    final withMidnight = DateTime(dt.year, dt.month, dt.day, hh, mm);

    await routineLayer.setSchedule(
      app.journal,
      r.id,
      withMidnight.millisecondsSinceEpoch ~/ 1000,
    );
    if (!mounted) return;
    await app.openRoutine(r.id);
  }

  IconData _statusIcon(Routine r) {
    if (r.completed) return Icons.check;
    if (r.scheduledAt != null) return Icons.crop_square;
    return Icons.circle_outlined;
  }
}

enum _Mark { none, scheduled, unfinished, completed }
