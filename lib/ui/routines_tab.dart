// ═══════════════════════════════════════════════════════════════════
// routines_tab.dart — вкладка рутин.
//
// Сверху — строка смены (пульс и таймер), прижата вправо.
// Под ней — список рутин: лента на узком экране, мозаика на широком.
//
// Сортировка: идущие (по времени пуска), покоящиеся (по lastActionAt),
// завершённые внизу отделены строкою «завершено».
//
// Пульс рутины: в ходе — пауза; в покое — пуск блока (последний
// пущенный либо «работа»); завершена — галочка (короткое снимает,
// долгое даёт веер). Долгое в любом состоянии — дублировать/удалить.
//
// Связь смены и рутин — в AppContext.toggleShift.
//
// Тикер — единый AppTicker. Открытие карточки — app.openRoutine.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../data/routine.dart';
import '../data/ticker.dart';
import 'app_scope.dart';
import 'pulse.dart';
import 'pult.dart';
import 'timer_text.dart';

class RoutinesTab extends StatefulWidget {
  const RoutinesTab({super.key});

  @override
  State<RoutinesTab> createState() => _RoutinesTabState();
}

class _RoutinesTabState extends State<RoutinesTab> {
  AppTicker? _ticker;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    _ticker?.removeListener(_onTick);
    _ticker = app.ticker;
    _ticker?.addListener(_onTick);
  }

  void _onTick() {
    if (!mounted) return;
    final app = AppScope.of(context);
    final anyRunning =
        app.routineLayer.routines.any((r) => r.runningBlock != null) ||
            app.bort.onShift;
    if (anyRunning) setState(() {});
  }

  @override
  void dispose() {
    _ticker?.removeListener(_onTick);
    super.dispose();
  }

  String _fmtDate(int unixSec) {
    final d = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000);
    const weekdays = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
    final wd = weekdays[d.weekday - 1];
    return '$wd ${d.day.toString().padLeft(2, '0')}.'
        '${d.month.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _create(BuildContext context) async {
    final app = AppScope.of(context);
    final r = await app.routineLayer.createRoutine(app.journal);
    if (context.mounted) {
      await app.openRoutine(r.id);
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
      pulseTap = () {
        app.routineLayer.setCompleted(app.journal, r.id, false);
      };
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
        final kind = app.routineLayer.lastActiveBlockKind ?? RoutineBlock.work;
        await app.toggleBlockWithShift(r.id, kind);
        if (mounted) setState(() {});
      };
    }

    final rightControl = Pult(
      spec: PultSpec(
        id: 'routine_${r.id}',
        icon: pulseIcon,
        selected: running,
        onTap: pulseTap,
        longSubs: () => [
          PultSpec(
            id: 'dup_${r.id}',
            icon: Icons.copy,
            label: app.i18n.t('bort.duplicate'),
            onTap: () async {
              await app.routineLayer.duplicateRoutine(app.journal, r.id);
              if (mounted) setState(() {});
            },
          ),
          PultSpec(
            id: 'del_${r.id}',
            icon: Icons.delete_outline,
            label: app.i18n.t('bort.delete'),
            confirm: true,
            onTap: () {
              app.routineLayer.deleteRoutine(app.journal, r.id);
            },
          ),
        ],
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
                      style: TextStyle(
                        color: textMain,
                        fontSize: nameSize,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  Text(
                    _fmtDate(r.createdAt),
                    style: TextStyle(
                      color: textSoft,
                      fontSize: dateSize,
                    ),
                  ),
                  if (r.totalSeconds > 0) ...[
                    SizedBox(height: dateSize * 0.4),
                    TimerText(
                      seconds: r.totalSeconds,
                      running: running,
                      fg: textMain,
                      dim: textSoft,
                      signal: accent,
                      numberSize: numberSize,
                      colonVisible: app.ticker.colonVisible,
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

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final mosaic = width >= 800;
      const maxCols = 3;
      final cols = mosaic ? (width / 400).floor().clamp(1, maxCols) : 1;

      final groups = _sortedGroups(app.routineLayer);
      final i18n = app.i18n;

      final shiftPulse = Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
        child: Align(
          alignment: Alignment.centerRight,
          child: Pulse(
            spec: PultSpec(
              id: 'shift',
              icon: bort.onShift ? Icons.pause : Icons.play_arrow,
              selected: bort.onShift,
              onTap: () async {
                await app.toggleShift();
                if (mounted) setState(() {});
              },
            ),
            seconds: bort.shiftSecondsNow,
            running: bort.onShift,
            fg: fg,
            dim: dim,
            bg: bg,
            bgdim: bgdim,
            signal: signal,
            side: side,
            colonVisible: app.ticker.colonVisible,
            pultSize: side * bort.kPultSmall,
          ),
        ),
      );

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
                          app.i18n.t('routine.none'),
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
        ],
      );
    });
  }
}
