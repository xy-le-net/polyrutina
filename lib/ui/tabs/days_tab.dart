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
// the remainder. To prevent excessive compression, the row is
// given a generous width, letting FittedBox scale down only
// when absolutely necessary.
//
// Grid. Strictly seven columns (GridView.builder) with equal
// cell proportions. The cell content (number with optional
// borders) is centered within a fixed-size container to prevent
// visual jitter.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

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
    // Total cells to render: complete weeks covering the month.
    final totalCells = (((firstWeekday - 1) + daysInMonth + 6) ~/ 7) * 7;

    final rootSide = side * 2 / 3;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: side * 0.3),
          child: ControlRow(
            rootSide: rootSide,
            // Generous width to give the month switchers breathing
            // room. FittedBox in ControlRow will scale it down if
            // the screen is too narrow.
            child: SizedBox(
              width: side * 6,
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
                  Text(
                    '${_month.year}.'
                    '${_month.month.toString().padLeft(2, '0')}',
                    style: TextStyle(color: bort.fg, fontSize: side * 0.5),
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
        ),
        Expanded(
          // Strict seven-column grid with uniform cell proportions.
          child: GridView.builder(
            padding: EdgeInsets.all(side * 0.3),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1,
            ),
            itemCount: totalCells,
            itemBuilder: (context, i) {
              final dayNum = i - (firstWeekday - 1) + 1;
              if (dayNum < 1 || dayNum > daysInMonth) {
                return const SizedBox.shrink();
              }
              final list = cells[dayNum] ?? const <Routine>[];
              return _cell(dayNum, list, side, bort);
            },
          ),
        ),
      ],
    );
  }

  Widget _cell(
    int day,
    List<Routine> routines,
    double side,
    OperationalLayer bort,
  ) {
    final m = _marksOf(day, routines);

    final dayColor = m.hasSignalIncomplete ? bort.signal : bort.fg;
    final TextStyle style = TextStyle(
      color: dayColor,
      fontSize: side * 0.4,
      decoration: m.completed ? TextDecoration.underline : TextDecoration.none,
      decorationColor: bort.dim,
    );

    // Fixed-size container ensures perfect centering and uniform
    // border sizes across all cells, eliminating visual jitter.
    Widget content = Container(
      width: side * 0.8,
      height: side * 0.8,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: m.pulse ? BoxShape.circle : BoxShape.rectangle,
        border: (m.pulse || m.scheduled)
            ? Border.all(
                color: m.signalPulse || m.signalScheduled
                    ? bort.signal
                    : bort.fg,
                width: side * 0.04,
              )
            : null,
        borderRadius: (m.scheduled && !m.pulse)
            ? BorderRadius.circular(side * 0.05)
            : null,
      ),
      child: Text('$day', style: style),
    );

    return GestureDetector(
      onTap: routines.isEmpty ? null : () => _openDay(routines),
      child: Center(child: content),
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
