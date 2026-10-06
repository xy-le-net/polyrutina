// ═══════════════════════════════════════════════════════════════════
// routines_tab.dart — вкладка рутин.
//
// Сверху — строка смены (пульс и таймер), прижата вправо.
// Под ней — список рутин: лента на узком экране, мозаика на широком.
// Слева внизу — пульт создания.
//
// Сортировка. Идущие сверху, между собой — по времени пуска идущего
// блока (позже пущен — выше). Покоящиеся ниже, между собой — по
// последнему действию (позже тронут — выше).
//
// Плашка: имя (ежели есть), дата создания, сумма таймеров (ежели
// не нуль), пульс. Идущая плашка сигнальная — цвета её обращаются
// правилом invertOnSignal, тексты и таймер читаются.
//
// Пульс рутины: в ходе — «пауза» сигнальная (касание — пауза);
// в покое — корзинка приглушённая (касание молчит); долгое нажатие
// в любом состоянии — подпульт удаления с подтверждением.
//
// Вход в карточку — касание по телу плашки.
//
// Связь смены и рутин: остановка смены гасит идущую рутину.
// Автозапуск смены при пуске блока — в AppContext.toggleBlockWithShift.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/journal_types.dart';
import '../data/operational_layer.dart';
import 'app_scope.dart';
import 'pulse.dart';
import 'pult.dart';
import 'routine_card.dart';
import 'timer_text.dart';

class RoutinesTab extends StatefulWidget {
  const RoutinesTab({super.key});

  @override
  State<RoutinesTab> createState() => _RoutinesTabState();
}

class _RoutinesTabState extends State<RoutinesTab> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      final app = AppScope.of(context);
      final anyRunning =
          app.routineLayer.routines.any((r) => r.runningBlock != null) ||
              app.bort.onShift;
      if (anyRunning) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  // Дата «дд.мм чч:мм».
  String _fmtDate(int unixSec) {
    final d = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000);
    return '${d.day.toString().padLeft(2, '0')}.'
        '${d.month.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _create(BuildContext context) async {
    final app = AppScope.of(context);
    final r = await app.routineLayer.createRoutine(app.journal);
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RoutineCard(routineId: r.id),
        ),
      );
    }
  }

  // Сортировка: идущие по времени пуска (позже выше), покоящиеся
  // по последнему действию (позже выше).
  List<dynamic> _sorted(dynamic layer) {
    final all = List<dynamic>.from(layer.routines);
    all.sort((a, b) {
      final aRun = a.runningBlock != null;
      final bRun = b.runningBlock != null;
      if (aRun && !bRun) return -1;
      if (!aRun && bRun) return 1;
      if (aRun && bRun) {
        final at = a.runningBlock?.startedAt ?? 0;
        final bt = b.runningBlock?.startedAt ?? 0;
        return bt.compareTo(at);
      }
      return (b.lastActionAt as int).compareTo(a.lastActionAt as int);
    });
    return all;
  }

  // ─── Пульс смены ───
  // Смена идёт — останавливаем; при сем идущая рутина встаёт.
  // Смена стоит — запускаем.
  Future<void> _toggleShift(BuildContext context) async {
    final app = AppScope.of(context);
    final bort = app.bort;
    final going = !bort.onShift;

    await app.journal.log(
      type: JournalType.actor,
      body: '{"action":"${going ? 'shift_start' : 'shift_stop'}"}',
    );

    if (going) {
      bort.startShift();
    } else {
      bort.stopShift();
      // Остановка смены влечёт остановку идущей рутины.
      for (final r in app.routineLayer.routines) {
        for (final b in r.blocks) {
          if (b.isRunning) {
            await app.routineLayer.pauseBlock(app.journal, r.id, b.kind);
          }
        }
      }
    }
    if (mounted) setState(() {});
  }

  // ─── Плашка рутины ───
  Widget _plate(
    BuildContext context,
    dynamic r,
    GlobalKey plateKey, {
    required dynamic bort,
    required double side,
  }) {
    final app = AppScope.of(context);
    final running = r.runningBlock != null;

    // ─── Цвета плашки ───
    // Пять ролей; идущая плашка берёт обращённые.
    final Color bg = bort.bg;
    final Color bgdim = bort.bgdim;
    final Color dim = bort.dim;
    final Color fg = bort.fg;
    final Color signal = bort.signal;

    final Color frameBg;
    final Color nameColor;
    final Color dateColor;
    final Color timerFg;
    final Color timerDim;
    final Color timerSignal;
    final Color pultFg;
    final Color pultBg;
    final Color pultSignal;

    if (running) {
      final inv = OperationalLayer.invertOnSignal(
        bg: bg,
        bgdim: bgdim,
        dim: dim,
        fg: fg,
        signal: signal,
      );
      frameBg = signal;
      nameColor = inv['fg']!;
      dateColor = inv['dim']!;
      timerFg = inv['fg']!;
      timerDim = inv['dim']!;
      timerSignal = inv['signal']!;
      pultFg = inv['fg']!;
      pultBg = signal;
      pultSignal = inv['signal']!;
    } else {
      frameBg = bg;
      nameColor = fg;
      dateColor = dim;
      timerFg = fg;
      timerDim = dim;
      timerSignal = signal;
      pultFg = dim;
      pultBg = bg;
      pultSignal = signal;
    }

    final nameSize = side * bort.kName;
    final dateSize = side * bort.kTitle * 0.7;
    final numberSize = side * bort.kNumberSmall;
    final pultSide = side * bort.kPultSmall;
    final strokeW = side * bort.kStroke;
    final radiusW = side * bort.kRadius;
    final framePad = side * bort.kFramePad * 0.6;

    final ms = DateTime.now().millisecond;
    final colonVisible = ms < 333;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RoutineCard(routineId: r.id),
          ),
        );
      },
      child: Container(
        key: plateKey,
        decoration: BoxDecoration(
          color: frameBg,
          border: Border.all(color: running ? dateColor : dim, width: strokeW),
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
                      style: TextStyle(color: nameColor, fontSize: nameSize),
                      overflow: TextOverflow.ellipsis,
                    ),
                  Text(
                    _fmtDate(r.createdAt),
                    style: TextStyle(color: dateColor, fontSize: dateSize),
                  ),
                  if (r.totalSeconds > 0) ...[
                    SizedBox(height: dateSize * 0.4),
                    TimerText(
                      seconds: r.totalSeconds,
                      running: running,
                      fg: timerFg,
                      dim: timerDim,
                      signal: timerSignal,
                      numberSize: numberSize,
                      colonVisible: colonVisible,
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: side * 0.15),
            // ─── Пульс рутины ───
            // В ходе — «пауза», короткое гасит блок.
            // В покое — корзинка приглушённая, короткое молчит.
            // Долгое в любом состоянии — подпульт удаления.
            Pult(
              spec: PultSpec(
                id: 'routine_${r.id}',
                icon: running ? Icons.pause : Icons.delete_outline,
                selected: running,
                onTap: running
                    ? () {
                        for (final b in r.blocks) {
                          if (b.isRunning) {
                            app.routineLayer
                                .pauseBlock(app.journal, r.id, b.kind);
                          }
                        }
                        setState(() {});
                      }
                    : null,
                onLongPress: () {
                  PultScope.of(context).open(
                    plateKey,
                    () => [
                      PultSpec(
                        id: 'delete_${r.id}',
                        icon: Icons.delete_outline,
                        label: app.i18n.t('bort.delete'),
                        confirm: true,
                        onTap: () {
                          app.routineLayer.deleteRoutine(app.journal, r.id);
                        },
                      ),
                    ],
                  );
                },
              ),
              fg: pultFg,
              bg: pultBg,
              signal: pultSignal,
              overrideSize: pultSide,
            ),
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
    final signal = bort.signal;
    final dim = bort.dim;
    final side = PultScope.of(context).smallSide;

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final mosaic = width >= 800;
      const maxCols = 3;
      final cols = mosaic ? (width / 400).floor().clamp(1, maxCols) : 1;

      final sorted = _sorted(app.routineLayer);

      // Строка смены: всегда видна, прижата вправо.
      final shiftPulse = Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
        child: Align(
          alignment: Alignment.centerRight,
          child: Pulse(
            spec: PultSpec(
              id: 'shift',
              icon: bort.onShift ? Icons.pause : Icons.play_arrow,
              selected: bort.onShift,
              onTap: () => _toggleShift(context),
            ),
            seconds: bort.shiftSecondsNow,
            running: bort.onShift,
            fg: fg,
            dim: dim,
            bg: bg,
            signal: signal,
            side: side,
            pultSize: side * bort.kPultSmall,
          ),
        ),
      );

      final plates = <Widget>[];
      for (final r in sorted) {
        plates.add(
          Padding(
            padding: const EdgeInsets.all(4),
            child: _plate(
              context,
              r,
              GlobalKey(),
              bort: bort,
              side: side,
            ),
          ),
        );
      }

      return Stack(
        children: [
          Column(
            children: [
              shiftPulse,
              Expanded(
                child: sorted.isEmpty
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
                            children: plates,
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(8, 4, 8, 80),
                            children: plates,
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
