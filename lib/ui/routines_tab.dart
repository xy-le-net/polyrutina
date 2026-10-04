// ═══════════════════════════════════════════════════════════════════
// routines_tab.dart — вкладка рутин.
//
// Список рутин плашками. Каждая плашка: имя (либо место под него),
// время создания, суммарное время; пульт входа справа.
// В левом нижнем углу — пульт создания рутины.
//
// При создании рутина заводится в борте, ложится запись в журнал,
// и тотчас открывается карточка.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'pult.dart';
import 'routine_card.dart';

class RoutinesTab extends StatelessWidget {
  const RoutinesTab({super.key});

  String _fmtDate(int unixSec) {
    final d = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000);
    return '${d.day.toString().padLeft(2, '0')}.'
        '${d.month.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  String _fmtTime(int sec) {
    if (sec < 0) sec = 0;
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _create(BuildContext context) async {
    final app = AppScope.of(context);
    final r = await app.bort.createRoutine();
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
    final brightness = Theme.of(context).brightness;
    final fg = bort.currentFg(brightness);
    final bg = bort.currentBg(brightness);
    final signal = bort.currentSignal(brightness);
    final dim = bort.currentDim(brightness);
    final side = PultScope.of(context).smallSide;

    return Stack(
      children: [
        // Список рутин.
        if (bort.routines.isEmpty)
          Center(
            child: Text(
              app.i18n.t('routine.none'),
              style: TextStyle(color: dim),
            ),
          )
        else
          ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 80, 8, 80),
            itemCount: bort.routines.length,
            itemBuilder: (context, i) {
              final r = bort.routines[i];
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
                      border: Border.all(color: dim),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.name.isEmpty
                                    ? app.i18n.t('routine.no_name')
                                    : r.name,
                                style: TextStyle(color: fg, fontSize: 16),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _fmtDate(r.createdAt),
                                style: TextStyle(color: dim, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _fmtTime(r.totalSeconds),
                          style: TextStyle(color: fg, fontFamily: 'monospace'),
                        ),
                        const SizedBox(width: 8),
                        // Пульт входа.
                        Pult(
                          spec: PultSpec(
                            id: 'open_${r.id}',
                            icon: Icons.chevron_right,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => RoutineCard(routineId: r.id),
                                ),
                              );
                            },
                          ),
                          fg: fg,
                          bg: bg,
                          signal: signal,
                          overrideSize: side,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

        // Пульт создания — левый нижний угол.
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
