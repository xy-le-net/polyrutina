// ═══════════════════════════════════════════════════════════════════
// routines_tab.dart — вкладка рутин.
//
// Сверху — строка смены (ShiftRow). Под ней — список рутин
// (RoutinePlate). Низу — три пульта: создать/отмена, отчёт,
// действия для выбранных (в режиме выбора).
//
// Режим выбора: долгое нажатие на рутине включает. Слева за блоком
// появляются чекбоксы.
//
// Широкий экран (мозаика). Активные — сеткою. Полоса «завершено»
// на всю ширину с волосяными линиями. Затем — завершённые сеткою.
//
// Таймер перерисовывается по смене видимой единицы.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/routine.dart';
import '../../data/ticker.dart';
import '../core/app_scope.dart';
import '../pults/pult_core.dart';
import '../services/report.dart';
import 'routine_plate.dart';
import 'shift_row.dart';

class RoutinesTab extends StatefulWidget {
  const RoutinesTab({super.key});

  @override
  State<RoutinesTab> createState() => _RoutinesTabState();
}

class _RoutinesTabState extends State<RoutinesTab> {
  AppTicker? _ticker;
  bool _hasNewEntries = false;

  bool _selectMode = false;
  final Set<int> _selected = {};

  int _lastMinute = 0;
  int _lastSecond = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    _ticker?.removeListener(_onTick);
    _ticker = app.ticker;
    _ticker?.addListener(_onTick);
    final now = DateTime.now();
    _lastMinute = now.millisecondsSinceEpoch ~/ 60000;
    _lastSecond = now.millisecondsSinceEpoch ~/ 1000;
    _refreshExportState();
  }

  void _onTick() {
    if (!mounted) return;
    final app = AppScope.of(context);
    final anyRunning =
        app.routineLayer.routines.any((r) => r.runningBlock != null) ||
        app.bort.onShift;
    if (!anyRunning) return;

    final sec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final min = sec ~/ 60;

    var subMinute = false;
    for (final r in app.routineLayer.routines) {
      final b = r.runningBlock;
      if (b != null && b.secondsNowAt(sec) < 60) {
        subMinute = true;
        break;
      }
    }
    if (app.bort.onShift && app.bort.shiftSecondsNow < 60) subMinute = true;

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

  Future<void> _refreshExportState() async {
    final app = AppScope.of(context);
    final last = await app.journal.lastEntryId();
    final exported = app.bort.lastExportId;
    if (mounted && _hasNewEntries != (last > exported)) {
      setState(() => _hasNewEntries = last > exported);
    }
  }

  @override
  void dispose() {
    _ticker?.removeListener(_onTick);
    super.dispose();
  }

  Future<void> _create(BuildContext context) async {
    final app = AppScope.of(context);
    final r = await app.routineLayer.createRoutine(app.journal);
    if (context.mounted) {
      await app.openRoutine(r.id);
    }
  }

  Future<void> _export(BuildContext context) async {
    final app = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    String? path;
    if (_selectMode && _selected.isNotEmpty) {
      path = await ReportBuilder.buildSelected(
        app,
        app.i18n,
        _selected.toList(),
      );
    } else {
      path = await ReportBuilder.build(app, app.i18n);
    }
    if (!mounted) return;
    if (path == null) return;
    messenger.showSnackBar(SnackBar(content: Text(path)));
    await _refreshExportState();
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
    final app = AppScope.of(context);
    for (final id in _selected) {
      final r = app.routineLayer.findRoutine(id);
      if (r == null) continue;
      if (!r.completed && r.runningBlock == null) return true;
    }
    return false;
  }

  // ─── Групповое удаление ───
  // Все удаления — одною транзакциею: либо вся пачка, либо ничего.
  // Иначе при сбое посреди списка часть рутин осталась бы.
  Future<void> _deleteSelected() async {
    final app = AppScope.of(context);
    final ids = _selected.toList();
    if (ids.isEmpty) {
      _exitSelectMode();
      return;
    }
    await app.journal.transaction(() async {
      for (final id in ids) {
        await app.routineLayer.deleteRoutine(app.journal, id);
      }
    });
    _exitSelectMode();
  }

  // ─── Групповое завершение ───
  // Завершение рутины само гасит идущие блоки и пишет несколько
  // записей; вся пачка — внутри одной внешней транзакции.
  Future<void> _completeSelected() async {
    final app = AppScope.of(context);
    final ids = _selected.toList();
    if (ids.isEmpty) {
      _exitSelectMode();
      return;
    }
    await app.journal.transaction(() async {
      for (final id in ids) {
        final r = app.routineLayer.findRoutine(id);
        if (r == null) continue;
        if (r.completed) continue;
        await app.routineLayer.setCompleted(app.journal, id, true);
      }
    });
    _exitSelectMode();
  }

  ({List<Routine> active, List<Routine> done}) _sortedGroups(dynamic layer) {
    final all = List<Routine>.from(layer.routines);
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
    final app = AppScope.of(context);
    final bort = app.bort;
    final fg = bort.fg;
    final bg = bort.bg;
    final signal = bort.signal;
    final dim = bort.dim;
    final side = PultScope.of(context).smallSide;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final mosaic = width >= 800;
        const maxCols = 3;
        final cols = mosaic ? (width / 400).floor().clamp(1, maxCols) : 1;

        final groups = _sortedGroups(app.routineLayer);
        final i18n = app.i18n;

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
            Positioned(
              right: 12,
              bottom: 12,
              child: Pult(
                spec: PultSpec(
                  id: 'report',
                  icon: Icons.description_outlined,
                  selected: _hasNewEntries,
                  onTap: _hasNewEntries ? () => _export(context) : null,
                ),
                fg: _hasNewEntries ? fg : dim,
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
