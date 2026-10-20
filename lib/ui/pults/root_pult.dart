// ═══════════════════════════════════════════════════════════════════
// root_pult.dart — root pult (compass).
//
// Collapsed — a compass in the top-left corner. A tap requests
// opening the single left-side subpult sheet with tab kinds: the
// sheet itself is drawn via showPultSheet (pult_sheet.dart), while
// this widget merely sends the onOpen signal.
//
// The tab panel (RootTabsPanel) is abolished: subpults of all kinds
// slide out from the left in a unified manner. RootTabItem is
// preserved — it is used by main for the tab list.
//
// The unused `selected` parameter of _core has been removed: the
// root pult is never selected.
//
// Transparency is not applied.
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
      child: _core(Icons.explore, side),
    );
  }

  // Pult core: triple nested border.
  Widget _core(IconData icon, double s) {
    final coreColor = fg; // The root pult is never selected.
    final iconColor = bg;
    final borderW = s / 16;
    final rOuter = s * 0.18;
    final rInner = s * 0.14;
    final rCore = s * 0.10;

    Widget core = Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        color: coreColor,
        borderRadius: BorderRadius.circular(rCore),
      ),
      child: Center(
        child: Icon(icon, color: iconColor, size: s * 0.45),
      ),
    );

    core = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(rInner),
        border: Border.all(color: coreColor, width: borderW),
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
