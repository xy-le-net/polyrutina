// ═══════════════════════════════════════════════════════════════════
// days_tab.dart — вкладка «дни». Календарь месяца.
//
// День рутины определяется так: completedAt, иначе lastPulseAt,
// иначе scheduledAt, иначе createdAt. Старшинство именно такое:
// завершённость > пульс > наметка.
//
// Помета в клетке:
//   — завершённая — подчёркнутое число;
//   — иначе с lastPulseAt — круглая рамка;
//   — иначе намеченная — квадратная рамка.
//
// Касание клетки с рутинами открывает единый левосторонний лист
// (pult_sheet.dart) со списком рутин того дня; касание рутины
// в листе открывает карточку.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/routine.dart';
import '../core/app_scope.dart';
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

  // ─── День месяца для рутины (нульозначие — вне месяца) ───
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

  // ─── Род пометы для клетки ───
  // Старшинство помет: завершённость > пульс > наметка.
  _Mark _markOf(int day, List<Routine> routines) {
    var hasCompleted = false;
    var hasPulse = false;
    var hasScheduled = false;
    for (final r in routines) {
      if (r.completed &&
          r.completedAt != null &&
          _sameMonth(r.completedAt!) == day) {
        hasCompleted = true;
        break;
      }
    }
    if (!hasCompleted) {
      for (final r in routines) {
        if (r.lastPulseAt != null && _sameMonth(r.lastPulseAt!) == day) {
          hasPulse = true;
          break;
        }
      }
    }
    if (!hasCompleted && !hasPulse) {
      for (final r in routines) {
        if (r.scheduledAt != null && _sameMonth(r.scheduledAt!) == day) {
          hasScheduled = true;
          break;
        }
      }
    }
    if (hasCompleted) return _Mark.completed;
    if (hasPulse) return _Mark.pulse;
    if (hasScheduled) return _Mark.scheduled;
    return _Mark.none;
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

    final firstWeekday = _month.weekday; // 1 = понедельник
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

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: side * 0.4,
            vertical: side * 0.3,
          ),
          child: Row(
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
              Expanded(
                child: Center(
                  child: Text(
                    '${_month.year}.'
                    '${_month.month.toString().padLeft(2, '0')}',
                    style: TextStyle(color: bort.fg, fontSize: side * 0.5),
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
    final mark = _markOf(day, routines);

    final TextStyle style = TextStyle(
      color: bort.fg,
      fontSize: side * 0.4,
      decoration: mark == _Mark.completed
          ? TextDecoration.underline
          : TextDecoration.none,
    );

    BoxDecoration deco;
    switch (mark) {
      case _Mark.pulse:
        deco = BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: bort.signal, width: side * 0.04),
        );
        break;
      case _Mark.scheduled:
        deco = BoxDecoration(
          border: Border.all(color: bort.dim, width: side * 0.04),
          borderRadius: BorderRadius.circular(side * 0.05),
        );
        break;
      default:
        deco = const BoxDecoration();
    }

    return GestureDetector(
      onTap: routines.isEmpty ? null : () => _openDay(routines),
      child: Padding(
        padding: EdgeInsets.all(side * 0.1),
        child: Container(
          decoration: deco,
          alignment: Alignment.center,
          child: Text('$day', style: style),
        ),
      ),
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
