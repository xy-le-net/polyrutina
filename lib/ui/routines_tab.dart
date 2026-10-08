// ═══════════════════════════════════════════════════════════════════
// routines_tab.dart — вкладка рутин.
//
// Сверху — строка смены. Под ней — список рутин.
//
// Пульс создания — левый нижний угол. Пульс отчёта — правый нижний.
//
// Пульс рутины:
//   в ходе — пауза (короткое);
//   в покое — пуск блока «выполнение»;
//   завершена — короткое открывает карточку;
//   долгое — веер: дублировать, удалить, отметить завершённой
//     (для незапущенной незавершённой).
//
// Смена: долгое нажатие на пульс — правка времени.
//
// Формат дат и длительностей — из format.dart; подписи единиц
// времени — из словаря чрез Translate.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../data/journal_types.dart';
import '../data/routine.dart';
import '../data/ticker.dart';
import 'app_scope.dart';
import 'format.dart';
import 'pulse.dart';
import 'pult_core.dart';
import 'report.dart';
import 'timer_text.dart';

class RoutinesTab extends StatefulWidget {
  const RoutinesTab({super.key});

  @override
  State<RoutinesTab> createState() => _RoutinesTabState();
}

class _RoutinesTabState extends State<RoutinesTab> {
  AppTicker? _ticker;

  bool _hasNewEntries = false;

  bool _editingShift = false;
  TextEditingController? _shiftEditCtrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    _ticker?.removeListener(_onTick);
    _ticker = app.ticker;
    _ticker?.addListener(_onTick);
    _refreshExportState();
  }

  void _onTick() {
    if (!mounted) return;
    final app = AppScope.of(context);
    final anyRunning =
        app.routineLayer.routines.any((r) => r.runningBlock != null) ||
        app.bort.onShift;
    if (anyRunning) setState(() {});
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
    _shiftEditCtrl?.dispose();
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
    final path = await ReportBuilder.build(app, app.i18n);
    if (!mounted) return;
    if (path == null) return;
    messenger.showSnackBar(SnackBar(content: Text(path)));
    await _refreshExportState();
  }

  // ─── Смена: правка времени ───
  void _startShiftEdit(int seconds) {
    _shiftEditCtrl?.dispose();
    _shiftEditCtrl = TextEditingController(text: fmtEditable(seconds));
    setState(() => _editingShift = true);
  }

  Future<void> _confirmShiftEdit() async {
    final app = AppScope.of(context);
    final sec = parseEditable(_shiftEditCtrl?.text ?? '');
    if (sec == null) {
      setState(() => _editingShift = false);
      _shiftEditCtrl?.dispose();
      _shiftEditCtrl = null;
      return;
    }
    await app.journal.log(
      type: JournalType.actor,
      body: '{"action":"shift_edit","seconds":$sec}',
    );
    app.bort.setShiftTime(sec);
    if (mounted) {
      setState(() => _editingShift = false);
      _shiftEditCtrl?.dispose();
      _shiftEditCtrl = null;
    }
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

  Widget _plate(
    BuildContext context,
    Routine r, {
    required Color fg,
    required Color bg,
    required Color bgdim,
    required Color dim,
    required Color signal,
    required double side,
  }) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    final running = r.runningBlock != null;

    final Color plateBg;
    final Color textMain;
    final Color textSoft;
    final Color accent;
    if (running) {
      final opposite = bort.colorsForOpposite();
      if (opposite != null) {
        plateBg = opposite['bg']!;
        textMain = opposite['fg']!;
        textSoft = opposite['dim']!;
        accent = opposite['signal']!;
      } else {
        plateBg = signal;
        textMain = bg;
        textSoft = bgdim;
        accent = bg;
      }
    } else {
      plateBg = bg;
      textMain = fg;
      textSoft = dim;
      accent = signal;
    }

    final nameSize = side * bort.kName;
    final dateSize = side * bort.kTitle * 0.7;
    final numberSize = side * bort.kNumberSmall;
    final pultSide = side * bort.kPultSmall;
    final strokeW = side * bort.kStroke;
    final radiusW = side * bort.kRadius;
    final framePad = side * bort.kFramePad * 0.6;

    final IconData pulseIcon;
    final VoidCallback? pulseTap;
    if (r.completed) {
      pulseIcon = Icons.check_box_outlined;
      pulseTap = () => app.openRoutine(r.id);
    } else if (running) {
      pulseIcon = Icons.pause;
      pulseTap = () async {
        for (final b in r.blocks) {
          if (b.isRunning) {
            await app.routineLayer.pauseBlock(app.journal, r.id, b.kind);
          }
        }
        if (mounted) setState(() {});
      };
    } else {
      pulseIcon = Icons.play_arrow;
      pulseTap = () async {
        await app.toggleBlockWithShift(r.id, RoutineBlock.work);
        if (mounted) setState(() {});
      };
    }

    final subs = <PultSpec>[
      PultSpec(
        id: 'dup_${r.id}',
        icon: Icons.copy,
        label: i18n.t('bort.duplicate'),
        onTap: () async {
          await app.routineLayer.duplicateRoutine(app.journal, r.id);
          if (mounted) setState(() {});
        },
      ),
      PultSpec(
        id: 'del_${r.id}',
        icon: Icons.delete_outline,
        label: i18n.t('bort.delete'),
        confirm: true,
        onTap: () {
          app.routineLayer.deleteRoutine(app.journal, r.id);
        },
      ),
    ];
    if (!r.completed && !running) {
      subs.add(
        PultSpec(
          id: 'complete_${r.id}',
          icon: Icons.check_circle_outline,
          label: i18n.t('routine.mark_completed'),
          confirm: true,
          onTap: () {
            app.routineLayer.setCompleted(app.journal, r.id, true);
          },
        ),
      );
    }

    final rightControl = Pult(
      spec: PultSpec(
        id: 'routine_${r.id}',
        icon: pulseIcon,
        selected: running,
        onTap: pulseTap,
        longSubs: () => subs,
      ),
      fg: running ? textMain : textSoft,
      bg: plateBg,
      signal: accent,
      overrideSize: pultSide,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => app.openRoutine(r.id),
      child: Container(
        decoration: BoxDecoration(
          color: plateBg,
          border: Border.all(color: textSoft, width: strokeW),
          borderRadius: BorderRadius.circular(radiusW),
        ),
        padding: EdgeInsets.all(framePad),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (r.name.isNotEmpty)
                    Text(
                      r.name,
                      style: TextStyle(color: textMain, fontSize: nameSize),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 10),
                  Text(
                    fmtDate(r.createdAt, i18n.t),
                    style: TextStyle(color: textSoft, fontSize: dateSize),
                  ),
                  if (r.totalSeconds > 0) ...[
                    SizedBox(height: dateSize * 0.4),
                    TimerText(
                      seconds: r.totalSeconds,
                      running: running,
                      fg: textMain,
                      dim: textSoft,
                      numberSize: numberSize,
                      colonVisible: app.ticker.colonVisible,
                      t: i18n.t,
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: side * 0.15),
            rightControl,
          ],
        ),
      ),
    );
  }

  // ─── Строка смены ───
  Widget _shiftRow(
    BuildContext context,
    Color fg,
    Color dim,
    Color bg,
    Color bgdim,
    Color signal,
    double side,
  ) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;

    if (_editingShift) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SizedBox(
              width: side * 3.0,
              child: TextField(
                controller: _shiftEditCtrl,
                autofocus: true,
                style: TextStyle(color: fg, fontSize: side * 0.4),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'дд:чч:мм:сс',
                  hintStyle: TextStyle(color: dim),
                  border: const OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(side * 0.1),
                ),
                onSubmitted: (_) => _confirmShiftEdit(),
              ),
            ),
            SizedBox(width: side * 0.1),
            Pult(
              spec: PultSpec(
                id: 'shift_confirm',
                icon: Icons.check,
                onTap: _confirmShiftEdit,
              ),
              fg: fg,
              bg: bg,
              signal: signal,
              overrideSize: side * bort.kPultSmall,
            ),
          ],
        ),
      );
    }

    Widget pulse = Pulse(
      spec: PultSpec(
        id: 'shift',
        icon: bort.onShift ? Icons.pause : Icons.play_arrow,
        selected: bort.onShift,
        onTap: () async {
          await app.toggleShift();
          if (mounted) setState(() {});
        },
        onLongPress: () => _startShiftEdit(bort.shiftSecondsNow),
      ),
      seconds: bort.shiftSecondsNow,
      running: bort.onShift,
      fg: fg,
      dim: dim,
      bg: bg,
      signal: signal,
      side: side,
      colonVisible: app.ticker.colonVisible,
      pultSize: side * bort.kPultSmall,
      t: i18n.t,
    );
    if (bort.shiftEdited) {
      pulse = Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: dim, width: side * bort.kStroke * 2),
          ),
        ),
        child: pulse,
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
      child: Align(alignment: Alignment.centerRight, child: pulse),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final fg = bort.fg;
    final bg = bort.bg;
    final bgdim = bort.bgdim;
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

        final shiftPulse = _shiftRow(context, fg, dim, bg, bgdim, signal, side);

        final items = <Widget>[];

        for (final r in groups.active) {
          items.add(
            Padding(
              padding: const EdgeInsets.all(4),
              child: _plate(
                context,
                r,
                fg: fg,
                bg: bg,
                bgdim: bgdim,
                dim: dim,
                signal: signal,
                side: side,
              ),
            ),
          );
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
            items.add(
              Padding(
                padding: const EdgeInsets.all(4),
                child: _plate(
                  context,
                  r,
                  fg: fg,
                  bg: bg,
                  bgdim: bgdim,
                  dim: dim,
                  signal: signal,
                  side: side,
                ),
              ),
            );
          }
        }

        return Stack(
          children: [
            Column(
              children: [
                shiftPulse,
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Text(
                            i18n.t('routine.none'),
                            style: TextStyle(color: dim),
                          ),
                        )
                      : (mosaic
                            ? GridView.count(
                                padding: const EdgeInsets.fromLTRB(8, 4, 8, 80),
                                crossAxisCount: cols,
                                childAspectRatio: 2.5,
                                children: items,
                              )
                            : ListView(
                                padding: const EdgeInsets.fromLTRB(8, 4, 8, 80),
                                children: items,
                              )),
                ),
              ],
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: Pult(
                spec: PultSpec(
                  id: 'create_routine',
                  icon: Icons.add,
                  onTap: () => _create(context),
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
          ],
        );
      },
    );
  }
}
