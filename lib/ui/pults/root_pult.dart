// ═══════════════════════════════════════════════════════════════════
// root_pult.dart — корневой пульт (компас).
//
// Свёрнутый — компас в левом верхнем углу. Касание просит открыть
// единый левосторонний лист подпультов с родами вкладок.
//
// Икона компаса увеличена на треть (до 0.60 от стороны), дабы
// соответствовать новым размерам икон в pult_core.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

class RootTabItem {
  final IconData icon;
  final String labelKey;
  const RootTabItem({required this.icon, required this.labelKey});
}

class RootPult extends StatelessWidget {
  final double side;
  final Color fg;
  final Color bg;
  final Color signal;
  final VoidCallback onOpen;

  const RootPult({
    super.key,
    required this.side,
    required this.fg,
    required this.bg,
    required this.signal,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (_) => onOpen(),
      child: _core(Icons.explore, false, side),
    );
  }

  // Ядро пульта: тройная вложенная обводка.
  Widget _core(IconData icon, bool selected, double s) {
    final coreColor = selected ? signal : fg;
    final iconColor = bg;
    final borderW = s / 16;
    final rOuter = s * 0.18;
    final rInner = s * 0.14;
    final rCore = s * 0.10;

    // Увеличение иконы на треть (было 0.45, стало 0.60)
    final iconSize = selected ? s * 0.80 : s * 0.60;

    Widget core = Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        color: coreColor,
        borderRadius: BorderRadius.circular(rCore),
      ),
      child: Center(
        child: Icon(icon, color: iconColor, size: iconSize),
      ),
    );

    core = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(rInner),
        border: Border.all(
          color: selected ? iconColor : coreColor,
          width: borderW,
        ),
      ),
      child: core,
    );

    core = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(rOuter),
        border: Border.all(color: coreColor, width: borderW),
      ),
      child: core,
    );

    return core;
  }
}
