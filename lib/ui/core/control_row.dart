// ═══════════════════════════════════════════════════════════════════
// control_row.dart — screen control row.
//
// A cross-cutting mechanism for all screens. The root pult (compass)
// hangs in the top-left corner — it is the start of the row. The space
// to its right is given to elements that must not slip under it
// (card title, checklist title, month switchers).
//
// The row's content preserves its own size, is aligned horizontally
// and vertically in the area remaining from the pult, and is scaled
// down if it exceeds the available width. The alignment defaults to
// center (appropriate for the month switcher) and can be set to
// centerLeft for titles that should sit flush with the reserved zone.
//
// The row's height equals the root pult's side. Elements inside are
// vertically centered.
//
// Usage. Wrap the desired row as a ControlRow. The root pult itself
// remains in the main screen's tree (main.dart) and is not drawn here
// — this is merely a reservation and layout. For AppBars, where a
// separate widget is inappropriate, the static method reserve() gives
// the same left padding value.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

class ControlRow extends StatelessWidget {
  // Width of the root pult. Same for the reserve.
  final double rootSide;
  // Pult's offset from the screen edge (in main.dart — 6).
  final double rootPad;
  // Content of the row's right part.
  final Widget? child;
  // Additional gap between the pult and the content.
  final double gap;
  // Alignment of the content in the remaining space.
  final Alignment alignment;

  const ControlRow({
    super.key,
    required this.rootSide,
    this.rootPad = 6.0,
    this.gap = 4.0,
    this.child,
    this.alignment = Alignment.center,
  });

  // Full width of the reserved zone on the left: offset + pult + gap.
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
      child: Row(
        children: [
          // Reserve space for the root pult.
          SizedBox(width: left),
          // Allocate the remaining space and prevent overlap.
          Expanded(
            child: child == null
                ? const SizedBox.shrink()
                : Align(
                    alignment: alignment,
                    child: FittedBox(fit: BoxFit.scaleDown, child: child),
                  ),
          ),
        ],
      ),
    );
  }
}
