// ═══════════════════════════════════════════════════════════════════
// timer_text.dart — вид таймера по единому образцу.
//
// Назначение: единый вид отсчёта времени во всём приложении
// (в списке рутин, в карточке, во вкладке актора). Формат —
// две старшие единицы из четырёх: месяц, день, час, минута.
// Что именно показывать, решается по величине:
//   есть месяцы  → «ММ:ДД»  с подписями «мес» и «дн»;
//   есть дни     → «ДД:ЧЧ»  с подписями «дн» и «ч»;
//   иначе        → «ЧЧ:ММ»  с подписями «ч» и «мин».
//
// Вид: число крупно, подпись единицы уменьшена на треть
// (множитель 2/3) и окрашена приглушённым цветом. двоеточие
// меж числами мелькает: треть секунды видно, две трети нет.
//
// Цвет: при ходе число сигнальное, на паузе — основное. Подписи
// единиц — всегда приглушённые (dim), без прозрачности. Сие
// позволяет виду быть единым и в карточке, и в списке, и на
// пульте актора.
//
// Мелькание: только у идущего таймера. Покоящийся двоеточие
// держит постоянно — иначе, когда блоков много, мигали бы все
// разом, что раздражает и путает.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

class TimerText extends StatelessWidget {
  // seconds — сколько секунд показывать.
  final int seconds;
  // running — идёт ли таймер (влияет на цвет числа и на мелькание).
  final bool running;
  // Три цвета ролей: основной, приглушённый, сигнальный.
  final Color fg;
  final Color dim;
  final Color signal;
  // numberSize — кегль числа. Всё прочее (подписи единиц,
  // двоеточие) — производные от него.
  final double numberSize;
  // colonVisible — фаза мелькания, вычисляемая вызывающим по
  // системным часам (треть секунды видно, две трети нет).
  // Применяется токмо при running; на паузе двоеточие постоянное.
  final bool colonVisible;

  const TimerText({
    super.key,
    required this.seconds,
    required this.running,
    required this.fg,
    required this.dim,
    required this.signal,
    required this.numberSize,
    this.colonVisible = true,
  });

  // Две старшие единицы из четырёх.
  // Константы в секундах:
  //   monthSec — средний месяц (30.44 суток); так принято в быту,
  //              ибо точная длина месяца переменна;
  //   daySec   — сутки ровно;
  //   hourSec  — час ровно.
  // Возвращается четвёрка строк: число, подпись, число, подпись.
  static (String, String, String, String) parts(int sec) {
    if (sec < 0) sec = 0;
    const monthSec = 2629746;
    const daySec = 86400;
    const hourSec = 3600;

    String two(int n) => n.toString().padLeft(2, '0');

    final month = sec ~/ monthSec;
    final day = (sec % monthSec) ~/ daySec;
    final hour = (sec % daySec) ~/ hourSec;
    final minute = (sec % hourSec) ~/ 60;

    if (month > 0) return (two(month), 'мес', two(day), 'дн');
    if (day > 0) return (two(day), 'дн', two(hour), 'ч');
    return (two(hour), 'ч', two(minute), 'мин');
  }

  @override
  Widget build(BuildContext context) {
    // Число: при ходе — сигнальное, на паузе — основное.
    // Подписи единиц — приглушённые всегда, без прозрачности.
    final primary = running ? signal : fg;
    final secondary = dim;
    // Подпись единицы уменьшена на треть против числа.
    final unitSize = numberSize * 2 / 3;

    final (a, ua, b, ub) = parts(seconds);

    return Row(
      mainAxisSize: MainAxisSize.min,
      // Выравнивание по базовой линии: числа и подписи сидят
      // на одной строке ровно, несмотря на разный кегль.
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(a,
            style: TextStyle(
                color: primary, fontFamily: 'monospace', fontSize: numberSize)),
        Text(ua,
            style: TextStyle(
                color: secondary, fontFamily: 'monospace', fontSize: unitSize)),
        // Двоеточие: видно на треть секунды, скрыто на две трети.
        // На паузе — постоянное: мигает токмо идущий таймер,
        // иначе при нескольких блоках мигали бы все разом.
        Opacity(
          opacity: (!running || colonVisible) ? 1.0 : 0.0,
          child: Text(':',
              style: TextStyle(
                  color: primary,
                  fontFamily: 'monospace',
                  fontSize: numberSize)),
        ),
        Text(b,
            style: TextStyle(
                color: primary, fontFamily: 'monospace', fontSize: numberSize)),
        Text(ub,
            style: TextStyle(
                color: secondary, fontFamily: 'monospace', fontSize: unitSize)),
      ],
    );
  }
}
