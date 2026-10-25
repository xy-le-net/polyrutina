// ═══════════════════════════════════════════════════════════════════
// lib/ui/tabs/routines_tab.dart — routines tab.
//
// Above — the shift row (ShiftRow). Below — the list of routines
// (RoutinePlate). At the bottom — two pults: create/cancel (left)
// and, in select mode, actions for the selected (center).
//
// Export has moved to the rubka («data» block): the routines list
// no longer carries a report pult. The former _hasNewEntries signal
// lamp and its _refreshExportState helper are removed with it —
// the rubka's export pult fires on demand, regardless of the
// journal tail.
//
// Select mode: a long press on a routine enables it. Checkboxes
// appear to the left of the block.
//
// Wide screen (mosaic). Active ones — in a grid. The «completed»
// band spans the full width with hairline dividers. Then — the
// completed ones, also in a grid.
//
// The timer repaints on a visible-unit change.
//
// Scopes. Dependencies are read from point scopes: RoutineScope
// (the layer), BortScope (theme and shift state), I18nScope
// (strings), TickerScope (playback cadence). AppScope is consulted
// only for the journal and for openRoutine.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/routine.dart';
import '../../data/ticker.dart';
import '../core/app_scope.dart';
import '../pults/pult_core.dart';
import 'routine_plate.dart';
import 'shift_row.dart';

class RoutinesTab extends StatefulWidget {
  const RoutinesTab({super.key});

  @override
  State<RoutinesTab> createState() => _RoutinesTabState();
}

class _RoutinesTabState extends State<RoutinesTab> {
  AppTicker? _ticker;

  bool _selectMode = false;
  final Set<int> _selected = {};

  int _lastMinute = 0;
  int _lastSecond = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ticker = TickerScope.of(context);
    _ticker?.removeListener(_onTick);
    _ticker = ticker;
    _ticker?.addListener(_onTick);
    final now = DateTime.now();
    _lastMinute = now.millisecondsSinceEpoch ~/ 60000;
    _lastSecond = now.millisecondsSinceEpoch ~/ 1000;
  }

  void _onTick() {
    if (!mounted) return;
    final routineLayer = RoutineScope.of(context);
    final bort = BortScope.of(context);
    final anyRunning =
        routineLayer.routines.any((r) => r.runningBlock != null) ||
        bort.onShift;
    if (!anyRunning) return;

    final sec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final min = sec ~/ 60;

    var subMinute = false;
    for (final r in routineLayer.routines) {
      final b = r.runningBlock;
      if (b != null && b.secondsNowAt(sec) < 60) {
        subMinute = true;
        break;
      }
    }
    if (bort.onShift && bort.shiftSecondsNow < 60) subMinute = true;

    if (subMinute) {
      if (sec != _lastSecond) {
        _lastSecond = sec;
        setState(() {});
      }
      return;
    }
    if (min != _lastMinute) {
      _lastMinute = min;
      _lastSecond = sec;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _ticker?.removeListener(_onTick);
    super.dispose();
  }

  Future<void> _create(BuildContext context) async {
    final routineLayer = RoutineScope.of(context);
    final journal = AppScope.of(context).journal;
    final openRoutine = AppScope.of(context).openRoutine;
    final r = await routineLayer.createRoutine(journal);
    if (context.mounted) {
      await openRoutine(r.id);
    }
  }

  void _enterSelectMode(int id) {
    setState(() {
      _selectMode = true;
      _selected.clear();
      _selected.add(id);
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
  }

  void _toggleSelect(int id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  bool get _hasUncompletedInSelection {
    final routineLayer = RoutineScope.of(context);
    for (final id in _selected) {
      final r = routineLayer.findRoutine(id);
      if (r == null) continue;
      if (!r.completed && r.runningBlock == null) return true;
    }
    return false;
  }

  // ─── Group deletion ───
  // All deletions — in one transaction: either the whole batch, or
  // nothing. Otherwise a failure mid-list would leave some routines.
  Future<void> _deleteSelected() async {
    final routineLayer = RoutineScope.of(context);
    final journal = AppScope.of(context).journal;
    final ids = _selected.toList();
    if (ids.isEmpty) {
      _exitSelectMode();
      return;
    }
    await journal.transaction(() async {
      for (final id in ids) {
        await routineLayer.deleteRoutine(journal, id);
      }
    });
    _exitSelectMode();
  }

  // ─── Group completion ───
  // Completing a routine itself stops running blocks and writes
  // several entries; the whole batch — inside one outer transaction.
  Future<void> _completeSelected() async {
    final routineLayer = RoutineScope.of(context);
    final journal = AppScope.of(context).journal;
    final ids = _selected.toList();
    if (ids.isEmpty) {
      _exitSelectMode();
      return;
    }
    await journal.transaction(() async {
      for (final id in ids) {
        final r = routineLayer.findRoutine(id);
        if (r == null) continue;
        if (r.completed) continue;
        await routineLayer.setCompleted(journal, id, true);
      }
    });
    _exitSelectMode();
  }

  ({List<Routine> active, List<Routine> done}) _sortedGroups() {
    final routineLayer = RoutineScope.of(context);
    final all = List<Routine>.from(routineLayer.routines);
    final active = <Routine>[];
    final done = <Routine>[];
    for (final r in all) {
      if (r.completed) {
        done.add(r);
      } else {
        active.add(r);
      }
    }
    active.sort((a, b) {
      final aRun = a.runningBlock != null;
      final bRun = b.runningBlock != null;
      if (aRun && !bRun) return -1;
      if (!aRun && bRun) return 1;
      if (aRun && bRun) {
        final at = a.runningBlock?.startedAt ?? 0;
        final bt = b.runningBlock?.startedAt ?? 0;
        return bt.compareTo(at);
      }
      return b.lastActionAt.compareTo(a.lastActionAt);
    });
    done.sort((a, b) => b.lastActionAt.compareTo(a.lastActionAt));
    return (active: active, done: done);
  }

  @override
  Widget build(BuildContext context) {
    final bort = BortScope.of(context);
    final i18n = I18nScope.of(context);
    final app = AppScope.of(context);
    final fg = bort.fg;
    final bg = bort.bg;
    final signal = bort.fgsignal;
    final dim = bort.mid;
    final side = PultScope.of(context).smallSide;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final mosaic = width >= 800;
        const maxCols = 3;
        final cols = mosaic ? (width / 400).floor().clamp(1, maxCols) : 1;

        final groups = _sortedGroups();

        Widget plateOf(Routine r) => Padding(
          padding: const EdgeInsets.all(4),
          child: RoutinePlate(
            routine: r,
            selectMode: _selectMode,
            selected: _selected.contains(r.id),
            onTap: () {
              if (_selectMode) {
                _toggleSelect(r.id);
              } else {
                app.openRoutine(r.id);
              }
            },
            onLongPress: () {
              if (_selectMode) return;
              FocusManager.instance.primaryFocus?.unfocus();
              _enterSelectMode(r.id);
            },
            onSelectToggle: () => _toggleSelect(r.id),
            onChanged: () {
              if (mounted) setState(() {});
            },
          ),
        );

        Widget body;

        if (groups.active.isEmpty && groups.done.isEmpty) {
          body = Center(
            child: Text(i18n.t('routine.none'), style: TextStyle(color: dim)),
          );
        } else if (!mosaic) {
          final items = <Widget>[];
          for (final r in groups.active) {
            items.add(plateOf(r));
          }
          if (groups.done.isNotEmpty) {
            items.add(
              Padding(
                padding: EdgeInsets.fromLTRB(8, side * 0.6, 8, side * 0.15),
                child: Text(
                  i18n.t('routine.completed'),
                  style: TextStyle(color: dim, fontSize: side * 0.4),
                ),
              ),
            );
            for (final r in groups.done) {
              items.add(plateOf(r));
            }
          }
          body = ListView(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 80),
            children: items,
          );
        } else {
          final children = <Widget>[];
          if (groups.active.isNotEmpty) {
            children.add(
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: cols,
                childAspectRatio: 2.5,
                children: groups.active.map(plateOf).toList(),
              ),
            );
          }
          if (groups.done.isNotEmpty) {
            children.add(
              Padding(
                padding: EdgeInsets.fromLTRB(4, side * 0.6, 4, side * 0.15),
                child: Row(
                  children: [
                    Expanded(child: Divider(color: dim, thickness: 1)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: side * 0.3),
                      child: Text(
                        i18n.t('routine.completed'),
                        style: TextStyle(color: dim, fontSize: side * 0.4),
                      ),
                    ),
                    Expanded(child: Divider(color: dim, thickness: 1)),
                  ],
                ),
              ),
            );
            children.add(
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: cols,
                childAspectRatio: 2.5,
                children: groups.done.map(plateOf).toList(),
              ),
            );
          }
          body = SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          );
        }

        return Stack(
          children: [
            Column(
              children: [
                ShiftRow(
                  onChanged: () {
                    if (mounted) setState(() {});
                  },
                ),
                Expanded(child: body),
              ],
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: Pult(
                spec: PultSpec(
                  id: _selectMode ? 'cancel_select' : 'create_routine',
                  icon: _selectMode ? Icons.close : Icons.add,
                  onTap: _selectMode ? _exitSelectMode : () => _create(context),
                ),
                fg: fg,
                bg: bg,
                signal: signal,
                overrideSize: side,
              ),
            ),
            if (_selectMode)
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: Center(
                  child: Pult(
                    spec: PultSpec(
                      id: 'selected_actions',
                      icon: Icons.more_horiz,
                      onTap: null,
                      longSubs: () {
                        final out = <PultSpec>[];
                        if (_hasUncompletedInSelection) {
                          out.add(
                            PultSpec(
                              id: 'sel_complete',
                              icon: Icons.check_circle_outline,
                              label: i18n.t('routine.mark_completed'),
                              confirm: true,
                              onTap: _completeSelected,
                            ),
                          );
                        }
                        out.add(
                          PultSpec(
                            id: 'sel_delete',
                            icon: Icons.delete_outline,
                            label: i18n.t('bort.delete'),
                            confirm: true,
                            onTap: _deleteSelected,
                          ),
                        );
                        return out;
                      },
                    ),
                    fg: fg,
                    bg: bg,
                    signal: signal,
                    overrideSize: side,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
