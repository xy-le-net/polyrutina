// ═══════════════════════════════════════════════════════════════════
// days_tab.dart — «days» tab. Month calendar.
//
// The routine's day is determined as follows: completedAt, otherwise
// lastPulseAt, otherwise scheduledAt, otherwise createdAt. The priority
// is exactly this: completion > pulse > schedule. One routine — exactly
// one mark.
//
// Marks in the cell:
//   — completed (completedAt on this day) — underlined number;
//   — with pulse (lastPulseAt on this day) — round border;
//   — scheduled (scheduledAt on this day) — square border.
// Different routines of the day bring different marks; they combine.
//
// Color coordination.
//   — underline (completed) — dimmed (dim);
//   — circle and square — normal (fg), if the routine has no flags
//     or is completed;
//   — signal (signal) highlights only the circle and square
//     of an uncompleted routine with flags;
//   — the day number is signal-colored if and only if there is
//     an uncompleted routine with flags on this day.
//
// Control row. Month switchers are rendered via ControlRow:
// the root pult on the left, the row's content is centered in
// the remainder (and scaled down if too wide).
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

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
    if (r.lastPulseAt != null) return _sameMonth(r.lastPulseAt!);
    if (r.scheduledAt != null) return _sameMonth(r.scheduledAt!);
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
    if (r.lastPulseAt != null && _sameMonth(r.lastPulseAt!) == day) {
      return _Mark.pulse;
    }
    if (r.scheduledAt != null && _sameMonth(r.scheduledAt!) == day) {
      return _Mark.scheduled;
    }
    return _Mark.none;
  }

  // ─── Mark set for the cell ───
  // Collects flags:
  //   completed, pulse, scheduled — which marks exist;
  //   signalPulse, signalScheduled — there is an uncompleted routine
  //     with flags and with pulse/schedule respectively;
  //   hasSignalIncomplete — there is at least one uncompleted with flags
  //     (the month number is signal-colored).
  ({
    bool completed,
    bool pulse,
    bool scheduled,
    bool signalPulse,
    bool signalScheduled,
    bool hasSignalIncomplete,
  })
  _marksOf(int day, List<Routine> routines) {
    var completed = false;
    var pulse = false;
    var scheduled = false;
    var signalPulse = false;
    var signalScheduled = false;
    var hasSignalIncomplete = false;
    for (final r in routines) {
      final mark = _markOfRoutine(r, day);
      final hasFlags = r.flags != 0;
      if (!r.completed && hasFlags) hasSignalIncomplete = true;
      switch (mark) {
        case _Mark.completed:
          completed = true;
          break;
        case _Mark.pulse:
          pulse = true;
          if (!r.completed && hasFlags) signalPulse = true;
          break;
        case _Mark.scheduled:
          scheduled = true;
          if (!r.completed && hasFlags) signalScheduled = true;
          break;
        case _Mark.none:
          break;
      }
    }
    return (
      completed: completed,
      pulse: pulse,
      scheduled: scheduled,
      signalPulse: signalPulse,
      signalScheduled: signalScheduled,
      hasSignalIncomplete: hasSignalIncomplete,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final side = PultScope.of(context).smallSide;

    final cells = <int, List<Routine>>{};
    for (final r in app.routineLayer.routines) {
      final day = _dayOf(r);
      if (day == null) continue;
      cells.putIfAbsent(day, () => []).add(r);
    }

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
      grid.add(_cell(dayNum, list, side, bort));
    }

    final rootSide = side * 2 / 3;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: side * 0.3),
          child: ControlRow(
            rootSide: rootSide,
            child: Row(
              mainAxisSize: MainAxisSize.min,
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
                SizedBox(width: side * 0.6),
                Text(
                  '${_month.year}.'
                  '${_month.month.toString().padLeft(2, '0')}',
                  style: TextStyle(color: bort.fg, fontSize: side * 0.5),
                ),
                SizedBox(width: side * 0.6),
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
          child: GridView.count(
            padding: EdgeInsets.all(side * 0.3),
            crossAxisCount: 7,
            childAspectRatio: 1,
            children: grid,
          ),
        ),
      ],
    );
  }

  Widget _cell(int day, List<Routine> routines, double side, dynamic bort) {
    final m = _marksOf(day, routines);

    final dayColor = m.hasSignalIncomplete ? bort.signal : bort.fg;
    final TextStyle style = TextStyle(
      color: dayColor,
      fontSize: side * 0.4,
      decoration: m.completed ? TextDecoration.underline : TextDecoration.none,
      decorationColor: bort.dim,
    );

    Widget content = Text('$day', style: style);

    if (m.pulse) {
      content = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: m.signalPulse ? bort.signal : bort.fg,
            width: side * 0.04,
          ),
        ),
        alignment: Alignment.center,
        child: content,
      );
    }

    if (m.scheduled) {
      content = Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: m.signalScheduled ? bort.signal : bort.fg,
            width: side * 0.04,
          ),
          borderRadius: BorderRadius.circular(side * 0.05),
        ),
        alignment: Alignment.center,
        child: content,
      );
    }

    return GestureDetector(
      onTap: routines.isEmpty ? null : () => _openDay(routines),
      child: Padding(padding: EdgeInsets.all(side * 0.1), child: content),
    );
  }

  void _openDay(List<Routine> routines) {
    final app = AppScope.of(context);
    showPultSheet(
      context: context,
      subs: [
        for (final r in routines)
          PultSpec(
            id: 'r_${r.id}',
            icon: r.completed ? Icons.check : Icons.circle_outlined,
            label: r.name.isEmpty ? '—' : r.name,
            onTap: () => app.openRoutine(r.id),
          ),
      ],
      fg: app.bort.fg,
      bg: app.bort.bg,
      signal: app.bort.signal,
      side: PultScope.of(context).smallSide,
    );
  }
}

enum _Mark { none, scheduled, pulse, completed }
