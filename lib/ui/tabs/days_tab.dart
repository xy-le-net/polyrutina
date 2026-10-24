// ═══════════════════════════════════════════════════════════════════
// lib/ui/tabs/days_tab.dart — «days» tab. Month calendar.
//
// The routine's day is determined as follows: completedAt, otherwise
// scheduledAt, otherwise lastPulseAt, otherwise createdAt. The
// priority is exactly this: completion > schedule > pulse > creation.
// One routine — exactly one day, exactly one mark.
//
// Marks in the cell:
//   — completed (completedAt on this day) — underlined number;
//   — scheduled (scheduledAt on this day) — square border;
//   — unfinished (any remaining routine on this day: not completed,
//     not scheduled) — round border.
// Different routines of the day bring different marks; they combine.
//
// Color. Each mark is colored after the routine that produced it:
// signal if that routine carries any flag bit, dim otherwise. The
// day number is signal-colored when at least one routine on that day
// carries flags, dim otherwise. The today plate (bort.bgdim) marks
// «today» alone and does not alter any color. The legend at the
// bottom is always dim — it informs, not competes with the grid.
//
// Long press on a day number creates a routine scheduled on that
// day and opens its card immediately. Short tap opens the day
// sub-pult with that day's routines (dismissed on a tap outside; the
// sheet guard in pult_sheet.dart handles stale sheets).
//
// Legend + stats. Below the calendar grid, separated by a couple of
// text lines, sits a short legend that doubles as monthly
// statistics: [square with count inside] word, [circle with count
// inside] word, [count with underline] word — one item per mark
// kind, only for kinds with a non-zero count this month. The legend
// is left-aligned; its shapes are sized to match the calendar cells
// (same frame side, stroke, and font as the day numbers).
//
// Circle stroke. Equal to the square's stroke: both marks live at
// the same visual weight. The circle's diameter equals the square's
// side, so the two marks read as the same size.
//
// Scopes. BortScope (theme), RoutineScope (the layer), I18nScope
// (strings). AppScope is consulted for openRoutine and journal.
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

  // Priority: completed > scheduled > pulse > created. The scheduled
  // date, when set, takes precedence over the pulse: a routine
  // assigned to a particular day must appear on that day.
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

  // Per-kind marks with their own signal flags (from the producing
  // routine) and a global anySignal for the day number.
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

    final rootSide = side;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, right: 12),
          child: ControlRow(
            rootSide: rootSide,
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
                  signal: bort.signal,
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
                  signal: bort.signal,
                  overrideSize: side,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(side * 0.3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 7,
                  childAspectRatio: 1,
                  children: grid,
                ),
                SizedBox(height: side * 0.8),
                _legend(
                  side,
                  bort,
                  i18n,
                  scheduled: scheduledCount,
                  unfinished: unfinishedCount,
                  completed: completedCount,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── Legend + stats under the calendar grid ───
  // Always dim: the legend informs about the shapes, it does not
  // carry signal. Left-aligned; the shapes match the calendar cells
  // in size, stroke, and font, so the legend reads as a continuation
  // of the grid. Wrap spacing and run spacing are equal.
  Widget _legend(
    double side,
    OperationalLayer bort,
    I18n i18n, {
    required int scheduled,
    required int unfinished,
    required int completed,
  }) {
    final color = bort.dim;
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

    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        alignment: WrapAlignment.start,
        spacing: gap,
        runSpacing: gap,
        children: items,
      ),
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

    // Number and underline carry independent colors: the number is
    // signal when any routine on the day has flags, dim otherwise;
    // the underline (the completion mark) follows the color of the
    // completed routine(s) only. Each shape (square, circle) follows
    // its own mark's flag-bearing routine.
    final numberColor = m.anySignal ? bort.signal : bort.dim;
    final underlineColor = m.completedSignal ? bort.signal : bort.dim;
    final scheduledColor = m.scheduledSignal ? bort.signal : bort.dim;
    final unfinishedColor = m.unfinishedSignal ? bort.signal : bort.dim;

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
              color: bort.bgdim,
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

  // ─── Day sub-pult ───
  // Lists that day's routines with their status icon; flag-carrying
  // routines render signal-colored. Dismissed by the sheet guard on
  // a tap outside or on navigation.
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
      signal: bort.signal,
      side: PultScope.of(context).smallSide,
    );
  }

  // ─── Create a routine on this day ───
  // Long press on the day number: create an empty routine, stamp it
  // with scheduledAt = that day, and open its card immediately.
  Future<void> _createOnDay(int day) async {
    final app = AppScope.of(context);
    final routineLayer = RoutineScope.of(context);
    final r = await routineLayer.createRoutine(app.journal);
    final dt = DateTime(_month.year, _month.month, day);
    await routineLayer.setSchedule(
      app.journal,
      r.id,
      dt.millisecondsSinceEpoch ~/ 1000,
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
