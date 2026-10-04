// ═══════════════════════════════════════════════════════════════════
// routines_tab.dart — вкладка рутин.
//
// Плашка: имя слева вверху; коли имени нет — время создания вместо
// него; под этим — время пульса (суммарное время рутины). Пульс
// удаления — в правом-нижнем углу, уменьшен на треть, с подтверждением.
// При ходе рутины имя и время пульса — сигнальным цветом, двоеточие
// мелькает. Касание по телу плашки открывает карточку.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';

import 'app_scope.dart';
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
          app.routineLayer.routines.any((r) => r.runningBlock != null);
      if (anyRunning) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _fmtDate(int unixSec) {
    final d = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000);
    return '${d.day.toString().padLeft(2, '0')}.'
        '${d.month.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _create(BuildContext context) async {
    final app = AppScope.of(context);
    final r = await app.routineLayer.createRoutine();
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RoutineCard(routineId: r.id),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final routines = app.routineLayer.routinesNewestFirst;
    final brightness = Theme.of(context).brightness;
    final fg = bort.currentFg(brightness);
    final bg = bort.currentBg(brightness);
    final signal = bort.currentSignal(brightness);
    final dim = bort.currentDim(brightness);
    final side = PultScope.of(context).smallSide;

    final ms = DateTime.now().millisecond;
    final colonVisible = ms < 333;

    final pultSide = side * 2 / 3;
    final numberSize = side * 0.3;

    return Stack(
      children: [
        if (routines.isEmpty)
          Center(
            child: Text(
              app.i18n.t('routine.none'),
              style: TextStyle(color: dim),
            ),
          )
        else
          ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 80, 8, 80),
            itemCount: routines.length,
            itemBuilder: (context, i) {
              final r = routines[i];
              final running = r.runningBlock != null;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => RoutineCard(routineId: r.id),
                      ),
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: fg.withValues(alpha: 0.05),
                      border: Border.all(color: dim, width: 0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.all(10),
                    child: Stack(
                      children: [
                        Padding(
                          padding: EdgeInsets.only(
                            right: pultSide + 8,
                            top: 2,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Имя; коли пусто — время создания вместо него.
                              Text(
                                r.name.isEmpty ? _fmtDate(r.createdAt) : r.name,
                                style: TextStyle(
                                  color: running ? signal : fg,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              // Время пульса — суммарное время рутины.
                              TimerText(
                                seconds: r.totalSeconds,
                                running: running,
                                fg: fg,
                                dim: dim,
                                signal: signal,
                                numberSize: numberSize,
                                colonVisible: colonVisible,
                              ),
                            ],
                          ),
                        ),
                        // Пульт удаления — в правом-нижнем углу.
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Pult(
                            spec: PultSpec(
                              id: 'delete_${r.id}',
                              icon: Icons.delete_outline,
                              selected: running,
                              confirm: true,
                              onTap: () {
                                app.routineLayer.deleteRoutine(r.id);
                              },
                            ),
                            fg: dim,
                            bg: bg,
                            signal: signal,
                            overrideSize: pultSide,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
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
  }
}
