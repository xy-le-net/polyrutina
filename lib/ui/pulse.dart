// ═══════════════════════════════════════════════════════════════════
// pulse.dart — пульс: пульт с таймером.
//
// Пульс — это ряд: слева таймер (TimerText), справа пульт (Pult).
// Единая сущность на всё, где нужен отсчёт с управляющим пультом:
//   — пульс блока в карточке рутины;
//   — пульс рутины в списке;
//   — смена в шапке списка.
//
// Цвета берутся у пульта: таймер наследует их. Ежели пульт
// сигнальный (selected), таймер тоже сигнальный; ежели приглушённый
// (fg: dim), таймер приглушён.
//
// Нулевой таймер скрыт — места не занимает (правило TimerText).
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import 'pult.dart';
import 'timer_text.dart';

class Pulse extends StatelessWidget {
  // Пульт: икона, действия, выделенность.
  final PultSpec spec;
  // Секунды таймера (0 — скрыт).
  final int seconds;
  // Идёт ли отсчёт (влияет на цвет и мелькание).
  final bool running;
  // Четыре цвета ролей.
  final Color fg;
  final Color dim;
  final Color bg;
  final Color signal;
  // Баговая величина: размер пульта. Таймер считается от неё.
  final double side;
  // Фаза мелькания двоеточия (вычисляется вызывающим).
  final bool colonVisible;
  // Размер пульта (обычно smallSide либо доля).
  final double? pultSize;

  const Pulse({
    super.key,
    required this.spec,
    required this.seconds,
    required this.running,
    required this.fg,
    required this.dim,
    required this.bg,
    required this.signal,
    required this.side,
    this.colonVisible = true,
    this.pultSize,
  });

  @override
  Widget build(BuildContext context) {
    // Кегль таймера — половина от размера пульта (то, что прежде
    // звалось kNumber * side либо kNumberSmall * side).
    final numberSize = side * 0.4;
    final pultSide = pultSize ?? side * 0.6667;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Таймер: цвет берётся от пульта. Ежели пульт сигнальный
        // (running), таймер сигнальный; иначе приглушённый по числу
        // и подписям.
        TimerText(
          seconds: seconds,
          running: running,
          // Число — сигнальное при ходе, основное в покое.
          // Подписи единиц — приглушённые (сам TimerText решает).
          fg: fg,
          dim: dim,
          signal: signal,
          numberSize: numberSize,
          colonVisible: colonVisible,
        ),
        if (seconds > 0) SizedBox(width: side * 0.15),
        Pult(
          spec: spec,
          fg: fg,
          bg: bg,
          signal: signal,
          overrideSize: pultSide,
        ),
      ],
    );
  }
}
