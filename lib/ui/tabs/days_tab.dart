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
// Color. Every element of a cell — the digit, the underline, the
// circle, and the square — uses one uniform cellColor:
//   — signal when any routine of that day carries flags;
//   — fg on the today cell (the plate fill would otherwise hide
//     dim marks);
//   — dim elsewhere (subtle but contrasty against bg).
//
// Today. The current day carries a medium-tone square plate
// (bort.bgdim) with soft corners, drawn underneath all marks. The
// plate does not replace any of the three mark layers; it merely
// signals «this is today» without competing with them.
//
// Circle stroke. The circle's stroke equals the square's stroke:
// both marks live at the same visual weight, so a day that carries
// both reads as one shape family rather than two competing
// outlines. Earlier the circle was drawn twice as thick on the
// theory that a thin ring would be invisible on the today plate;
// in practice the doubled stroke dominated the digit, so the
// strokes are now equal.
//
// Legend + stats. Under the calendar grid sits a short legend that
// doubles as monthly statistics: [square with count inside] word,
// [circle with count inside] word, [count with underline] word —
// one item per mark kind, only for kinds with a non-zero count this
// month. Counts are computed from the same _markOfRoutine logic
// that populates the grid, so the legend and the marks agree. The
// legend is left-aligned and its shapes are sized to match the
// calendar cells (same frame size, same stroke, same font as the
// day numbers), so the legend reads as a continuation of the grid
// rather than as a footnote.
//
// Cell layout. Flat Stack: square (scheduled), circle (unfinished),
// and the number are independent layers of a fixed-size box. The
// former nested wrapping shrank the inner circle whenever the outer
// square was present, shifting the digit off-center. The fixed-size
// Stack keeps the circle's diameter at boxSide — the square's side
// — so the two marks read as the same size (the ring is inscribed
// in the square, both strokes centred on the same boundary).
//
// Control row. The month switcher occupies the full remaining
// width after the root pult. The row stretches edge to edge with
// spaceEvenly, so the prev/next buttons sit closer to the screen
// edges and the month label is centered.
//
// Day sub-pult. Tapping a number opens a pult sheet listing that
// day's routines, each carrying its status icon (check for
// completed, square for scheduled, circle for unfinished); a
// routine carrying flags renders signal-colored. The sheet
// dismisses on a tap outside, like every other pult sheet.
//
// Scopes. Dependencies are read from point scopes: BortScope
// (theme), RoutineScope (the layer), I18nScope (strings). AppScope
// is consulted only for openRoutine.
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
    if (!r.completed) {
      return _Mark.unfinished;
    }
    return _Mark.none;
  }

  ({bool completed, bool unfinished, bool scheduled, bool hasSignal}) _marksOf(
    int day,
    List<Routine> routines,
  ) {
    var completed = false;
    var unfinished = false;
    var scheduled = false;
    var hasSignal = false;
    for (final r in routines) {
      final mark = _markOfRoutine(r, day);
      if (r.flags != 0) hasSignal = true;
      switch (mark) {
        case _Mark.completed:
          completed = true;
          break;
        case _Mark.unfinished:
          unfinished = true;
          break;
        case _Mark.scheduled:
          scheduled = true;
          break;
        case _Mark.none:
          break;
      }
    }
    return (
      completed: completed,
      unfinished: unfinished,
      scheduled: scheduled,
      hasSignal: hasSignal,
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
          child: GridView.count(
            padding: EdgeInsets.all(side * 0.3),
            crossAxisCount: 7,
            childAspectRatio: 1,
            children: grid,
          ),
        ),
        _legend(
          side,
          bort,
          i18n,
          scheduled: scheduledCount,
          unfinished: unfinishedCount,
          completed: completedCount,
        ),
      ],
    );
  }

  // ─── Legend + stats under the calendar grid ───
  // One item per mark kind (square, circle, underline) with the
  // monthly count printed inside the shape, followed by the word.
  // Only non-zero counts are shown, so an empty month carries no
  // legend at all. Colors are dim — a legend should inform, not
  // compete with the grid. Left-aligned; the shapes are sized to
  // match the calendar cells (same frame side, stroke, and font as
  // the day numbers), so the legend reads as a continuation of the
  // grid rather than as a footnote.
  Widget _legend(
    double side,
    OperationalLayer bort,
    I18n i18n, {
    required int scheduled,
    required int unfinished,
    required int completed,
  }) {
    final color = bort.dim;
    // Match the calendar cell's box side, font, and stroke so that
    // legend shapes and numbers have the same visual weight as the
    // grid above.
    final itemSize = side * 0.9;
    final markStroke = side * 0.04;
    final fontSize = side * 0.4;

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

    return Padding(
      padding: EdgeInsets.fromLTRB(
        side * 0.4,
        side * 0.15,
        side * 0.4,
        side * 0.3,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          alignment: WrapAlignment.start,
          spacing: side * 0.4,
          runSpacing: side * 0.15,
          children: items,
        ),
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

    // Uniform color: the digit, underline, circle, and square all
    // share cellColor. Signal overrides everything. On the today
    // cell, fg (bright) replaces dim (subtle), so thin strokes are
    // not swallowed by the plate fill.
    final cellColor = m.hasSignal
        ? bort.signal
        : (isToday ? bort.fg : bort.dim);

    final TextStyle style = TextStyle(
      color: cellColor,
      fontSize: side * 0.4,
      height: 1.0,
      decoration: m.completed ? TextDecoration.underline : TextDecoration.none,
      decorationColor: cellColor,
    );

    final boxSide = side * 0.9;
    // The circle's diameter equals the square's side, so the two
    // marks are visually the same size and the unfinished ring is
    // inscribed in the scheduled square (both strokes centred on
    // the same outer boundary).
    final circleSide = boxSide;
    // One stroke width for both marks: circle and square sit at the
    // same visual weight, and the digit is not overpowered by a
    // heavier ring.
    final markStroke = side * 0.04;

    final layers = <Widget>[];

    // Today plate — a soft square underneath all marks. Its radius
    // matches the scheduled square so the two shapes read as one
    // family; its fill is bgdim (medium tone), which stands out
    // from the page without competing with signal-colored marks.
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
              border: Border.all(color: cellColor, width: markStroke),
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
                border: Border.all(color: cellColor, width: markStroke),
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

  // Status icon for the day sub-pult: check for completed, square
  // for scheduled, circle for unfinished. Mirrors the calendar's
  // marks so the sheet speaks the same visual language.
  IconData _statusIcon(Routine r) {
    if (r.completed) return Icons.check;
    if (r.scheduledAt != null) return Icons.crop_square;
    return Icons.circle_outlined;
  }
}

enum _Mark { none, scheduled, unfinished, completed }
