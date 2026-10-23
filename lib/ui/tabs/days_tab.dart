// ═══════════════════════════════════════════════════════════════════
// lib/ui/tabs/days_tab.dart — «days» tab. Month calendar.
//
// The routine's day is determined as follows: completedAt, otherwise
// scheduledAt, otherwise lastPulseAt, otherwise createdAt. The
// priority is exactly this: completion > schedule > pulse > creation.
// One routine — exactly one mark.
//
// Marks in the cell:
//   — completed (completedAt on this day) — underlined number;
//   — with pulse (lastPulseAt on this day) — round border;
//   — scheduled (scheduledAt on this day) — square border.
// Different routines of the day bring different marks; they combine.
//
// Color coordination.
//   — all marks default to dim (underline, circle, square);
//   — any routine with flags (completed or not) makes its own mark
//     signal-colored; the day number turns signal if and only if at
//     least one routine of that day carries flags.
//
// Today. The current day carries a medium-tone square plate
// (bort.bgdim) with soft corners, drawn underneath all marks. The
// plate does not replace any of the three mark layers; it merely
// signals «this is today» without competing with them.
//
// Cell layout. Flat Stack: square (scheduled), circle (pulse), and
// the number are independent layers of a fixed-size box. The former
// nested wrapping (square padding over circle padding over text)
// shrank the inner circle whenever the outer square was present,
// shifting the digit off-center. The fixed-size Stack keeps the
// circle's diameter constant regardless of which marks are active.
//
// Control row. The month switcher occupies the full remaining width
// after the root pult. The row stretches edge to edge with
// spaceEvenly, so the prev/next buttons sit closer to the screen
// edges and the month label is centered.
//
// Scopes. Dependencies are read from point scopes: BortScope (theme),
// RoutineScope (the layer), I18nScope (strings). AppScope is
// consulted only for openRoutine.
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

  // Priority: completed > scheduled > pulse > created. The scheduled
  // date, when set, takes precedence over the pulse: a routine
  // assigned to a particular day must appear on that day, not on the
  // day it happened to be started. If the schedule lies outside the
  // displayed month, the routine is hidden for that month.
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
    if (r.lastPulseAt != null && _sameMonth(r.lastPulseAt!) == day) {
      return _Mark.pulse;
    }
    return _Mark.none;
  }

  ({
    bool completed,
    bool pulse,
    bool scheduled,
    bool signalCompleted,
    bool signalPulse,
    bool signalScheduled,
    bool hasSignal,
  })
  _marksOf(int day, List<Routine> routines) {
    var completed = false;
    var pulse = false;
    var scheduled = false;
    var signalCompleted = false;
    var signalPulse = false;
    var signalScheduled = false;
    var hasSignal = false;
    for (final r in routines) {
      final mark = _markOfRoutine(r, day);
      final hasFlags = r.flags != 0;
      if (hasFlags) hasSignal = true;
      switch (mark) {
        case _Mark.completed:
          completed = true;
          if (hasFlags) signalCompleted = true;
          break;
        case _Mark.pulse:
          pulse = true;
          if (hasFlags) signalPulse = true;
          break;
        case _Mark.scheduled:
          scheduled = true;
          if (hasFlags) signalScheduled = true;
          break;
        case _Mark.none:
          break;
      }
    }
    return (
      completed: completed,
      pulse: pulse,
      scheduled: scheduled,
      signalCompleted: signalCompleted,
      signalPulse: signalPulse,
      signalScheduled: signalScheduled,
      hasSignal: hasSignal,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bort = BortScope.of(context);
    final routineLayer = RoutineScope.of(context);
    final side = PultScope.of(context).smallSide;

    final cells = <int, List<Routine>>{};
    for (final r in routineLayer.routines) {
      final day = _dayOf(r);
      if (day == null) continue;
      cells.putIfAbsent(day, () => []).add(r);
    }

    // The current day (if the displayed month is the current one).
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

    // rootSide equals the small pult side: the compass is drawn at
    // 2/3 of the base side, which is exactly smallSide.
    final rootSide = side;

    // The month row sits flush with the root pult: its height is
    // pinned to rootSide and the previous extra vertical padding is
    // dropped, so the prev/next pults line up with the compass in
    // the top-left corner. The month label is wrapped in Flexible
    // and ellipsized, so a long title cannot push the next pult out.
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8, right: 12),
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

  Widget _cell(
    int day,
    List<Routine> routines,
    double side,
    OperationalLayer bort, {
    required bool isToday,
  }) {
    final m = _marksOf(day, routines);

    final dayColor = m.hasSignal ? bort.signal : bort.dim;
    final underlineColor = m.signalCompleted ? bort.signal : bort.dim;
    final TextStyle style = TextStyle(
      color: dayColor,
      fontSize: side * 0.4,
      // Normalize line height: otherwise the text sits lower than the
      // circle or square, because the baseline offset of the default
      // font metrics is asymmetric.
      height: 1.0,
      decoration: m.completed ? TextDecoration.underline : TextDecoration.none,
      decorationColor: underlineColor,
    );

    // Flat layout: square and circle are independent layers of a
    // Stack with a fixed footprint, and the day number sits on top.
    // The former nested wrapping (square padding over circle
    // padding over text) shrank the inner circle whenever the outer
    // square was present, shifting the digit off-center; the
    // fixed-size Stack keeps the circle's diameter constant
    // regardless of which marks are active.
    final double boxSide = side * 0.9;
    final double circleSide = side * 0.65;
    final double markStroke = side * 0.04;

    final layers = <Widget>[];

    // Today plate — a soft square underneath all marks. Its radius
    // matches the scheduled square so the two shapes read as one
    // family; its fill is bgdim (medium tone), which stands out from
    // the page without competing with signal-colored marks.
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
              border: Border.all(
                color: m.signalScheduled ? bort.signal : bort.dim,
                width: markStroke,
              ),
              borderRadius: BorderRadius.circular(side * 0.05),
            ),
          ),
        ),
      );
    }
    if (m.pulse) {
      // Circle border uses the same color as the underline (dim by
      // default, signal when the day's completion carries flags),
      // so the two marks read as one family and the circle stays
      // visible on top of the today plate (bgdim) rather than
      // blending into it.
      layers.add(
        Center(
          child: SizedBox(
            width: circleSide,
            height: circleSide,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: underlineColor, width: markStroke),
              ),
            ),
          ),
        ),
      );
    }
    layers.add(Text('$day', style: style));

    return GestureDetector(
      onTap: routines.isEmpty ? null : () => _openDay(routines),
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
            icon: r.completed ? Icons.check : Icons.circle_outlined,
            label: r.name.isEmpty ? '—' : r.name,
            onTap: () => openRoutine(r.id),
          ),
      ],
      fg: bort.fg,
      bg: bort.bg,
      signal: bort.signal,
      side: PultScope.of(context).smallSide,
    );
  }
}

enum _Mark { none, scheduled, pulse, completed }
