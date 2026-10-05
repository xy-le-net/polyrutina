// ═══════════════════════════════════════════════════════════════════
// routines_tab.dart — вкладка рутин.
//
// Назначение: список рутин свежайшими сверху. Каждая плашка:
//   имя рутины (при пустом — время создания) слева вверху;
//   под ним — время пульса (суммарное время рутины) таймером;
//   пульт удаления — в правом-нижнем углу, с подтверждением;
//   касание по телу плашки открывает карточку рутины.
//
// При ходе рутины имя и таймер показываются сигнальным цветом,
// двоеточие таймера мелькает. Сие требует перерисовки списка
// десять раз в секунду — но токмо покуда хоть одна рутина
// в работе; в покое тиканий нет.
//
// Размеры берутся из коэффициентов борта (kName, kNumberSmall,
// kPultSmall, kStroke, kRadius, kFramePad). Правка любого
// коэффициента в рубке меняет вид списка согласованно.
//
// Прозрачность не применяется.
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
  // Тик для мелькания двоеточия у идущих таймеров. Перерисовка
  // зовётся токмо при наличии идущей рутины; иначе тик молчит.
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

  // Дата вида «дд.мм чч:мм». Годится и для времени создания
  // при пустом имени, и для прочих мелких меток.
  String _fmtDate(int unixSec) {
    final d = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000);
    return '${d.day.toString().padLeft(2, '0')}.'
        '${d.month.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  // Создание рутины: слой заводит её в памяти и кладёт запись
  // в журнал; номер берётся из записи. Тотчас открываем карточку,
  // дабы можно было начать работу без лишнего касания.
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
    final selBg = bort.currentBgSel(brightness);
    final side = PultScope.of(context).smallSide;

    // Мелькание двоеточия: треть секунды видно, две трети нет.
    final ms = DateTime.now().millisecond;
    final colonVisible = ms < 333;

    // Все размеры — производные от коэффициентов борта.
    // pultSide — уменьшенный пульт удаления в углу.
    // numberSize — кегль таймера (в списке он мельче, чем в карточке).
    // nameSize — кегль имени рутины.
    // strokeW и radiusW — толщина обводки и радиус скругления плашки.
    // framePad — отбивка внутри плашки; взята долею от kFramePad,
    //   ибо в списке плашка плотнее, чем рамка блока в карточке.
    final pultSide = side * bort.kPultSmall;
    final numberSize = side * bort.kNumberSmall;
    final nameSize = side * bort.kName;
    final strokeW = side * bort.kStroke;
    final radiusW = side * bort.kRadius;
    final framePad = side * bort.kFramePad * 0.6;

    return Stack(
      children: [
        // ─── Пустой список ───
        // Простая надпись по центру: подсказка, что рутин ещё нет.
        if (routines.isEmpty)
          Center(
            child: Text(
              app.i18n.t('routine.none'),
              style: TextStyle(color: dim),
            ),
          )
        else
          // ─── Список плашек ───
          // Свежайшие сверху. Прокрутка с отступами сверху и снизу —
          // дабы корневой пульт и пульт создания не перекрывали
          // содержимое.
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
                    // Подсветка плашки — цветом bgsel. Рамка
                    // приглушённая и тонкая. Скругление — от
                    // коэффициента радиуса рамок.
                    decoration: BoxDecoration(
                      color: selBg,
                      border: Border.all(color: dim, width: strokeW),
                      borderRadius: BorderRadius.circular(radiusW),
                    ),
                    padding: EdgeInsets.all(framePad),
                    child: Stack(
                      children: [
                        // Тело плашки: имя (либо время создания)
                        // и под ним таймер пульса. Справа оставлен
                        // запас под пульт в углу.
                        Padding(
                          padding: EdgeInsets.only(
                            right: pultSide + 8,
                            top: 2,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Имя рутины; при пустом имени —
                              // время её создания. При ходе —
                              // сигнальный цвет.
                              Text(
                                r.name.isEmpty ? _fmtDate(r.createdAt) : r.name,
                                style: TextStyle(
                                  color: running ? signal : fg,
                                  fontSize: nameSize,
                                ),
                              ),
                              const SizedBox(height: 4),
                              // Таймер пульса: две старшие единицы
                              // из четырёх (месяц, день, час, минута).
                              // При ходе — сигнальным цветом, при
                              // паузе — приглушённым. Двоеточие
                              // мелькает по уставу.
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

                        // ─── Пульт удаления ───
                        // В правом-нижнем углу. Подтверждение —
                        // увеличенным пультом поверх (confirm: true;
                        // механизм в PultLayer). На паузе приглушён,
                        // при ходе — сигнальный (selected).
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

        // ─── Пульт создания ───
        // В левом-нижнем углу, обычного размера. Заводит рутину
        // и тотчас открывает её карточку.
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
