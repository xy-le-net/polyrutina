// ═══════════════════════════════════════════════════════════════════
// pulse.dart — пульс: пульт с таймером.
//
// Пульс — ряд: слева таймер (TimerText), справа пульт (Pult).
// Единая сущность на всё, где нужен отсчёт с управляющим пультом:
//   — пульс блока в карточке рутины;
//   — пульс рутины в списке;
//   — смена в шапке списка.
//
// Цвета берутся из переданной пятёрки — обычной гаммы либо
// противоположной (для сигнальных объектов). Сие позволяет одному
// виджету работать и в обычном блоке, и в сигнальном, без
// условных проверок.
//
// colonVisible — фаза мелькания от единого тикера.
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
  // Идёт ли отсчёт.
  final bool running;
  // Пятёрка цветов: bg, bgdim, dim, fg, signal.
  final Color bg;
  final Color bgdim;
  final Color dim;
  final Color fg;
  final Color signal;
  // Базовая величина для размеров.
  final double side;
  // Фаза мелькания двоеточия.
  final bool colonVisible;
  // Размер пульта (по умолчанию — две трети от side).
  final double? pultSize;

  const Pulse({
    super.key,
    required this.spec,
    required this.seconds,
    required this.running,
    required this.bg,
    required this.bgdim,
    required this.dim,
    required this.fg,
    required this.signal,
    required this.side,
    this.colonVisible = true,
    this.pultSize,
  });

  @override
  Widget build(BuildContext context) {
    final numberSize = side * 0.4;
    final pultSide = pultSize ?? side * 0.6667;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Таймер: число — fg (при ходе контрастный, задан пятёркой),
        // подписи — dim.
        TimerText(
          seconds: seconds,
          running: running,
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
