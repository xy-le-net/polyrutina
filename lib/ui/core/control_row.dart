// ═══════════════════════════════════════════════════════════════════
// control_row.dart — строка управления экрана.
//
// Сквозной механизм для всех экранов. Корневой пульт (компас)
// висит в левом верхнем углу — он начало строки. Правое от него
// пространство отдаётся элементам, что не должны улистываться
// (название карточки, заголовок чек-листа, переключатели месяца).
//
// Содержимое строки сохраняет собственный размер (не растягивается,
// не сжимается), центрируется по горизонтали и вертикали в оставшейся
// от пульта области.
//
// Высота строки равна стороне корневого пульта. Элементы внутри
// выравниваются по центру по вертикали.
//
// Употребление: обернуть надобный ряд как ControlRow; сам корневой
// пульт остаётся в дереве главного экрана (main.dart) и здесь не
// рисуется — сие лишь резерв и раскладка.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

class ControlRow extends StatelessWidget {
  // Ширина корневого пульта. У резерва — та же.
  final double rootSide;
  // Отступ пульта от края экрана (в main.dart — 6).
  final double rootPad;
  // Содержимое правой части строки.
  final Widget? child;
  // Дополнительный зазор между пультом и содержимым.
  final double gap;

  const ControlRow({
    super.key,
    required this.rootSide,
    this.rootPad = 6.0,
    this.gap = 4.0,
    this.child,
  });

  // Полная ширина резервируемой зоны слева: отступ + пульт + зазор.
  static double reserve(
    double rootSide, {
    double rootPad = 6.0,
    double gap = 4.0,
  }) => rootPad + rootSide + gap;

  @override
  Widget build(BuildContext context) {
    final left = reserve(rootSide, rootPad: rootPad, gap: gap);
    return SizedBox(
      height: rootSide,
      child: Padding(
        padding: EdgeInsets.only(left: left),
        child: child == null ? const SizedBox.shrink() : Center(child: child),
      ),
    );
  }
}
