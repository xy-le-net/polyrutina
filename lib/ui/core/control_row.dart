// ═══════════════════════════════════════════════════════════════════
// control_row.dart — screen control row.
//
// A cross-cutting mechanism for all screens. The root pult (compass)
// hangs in the top-left corner — it is the start of the row. The space
// to its right is given to elements that must not slip under it
// (card title, checklist title, month switchers).
//
// The row's content preserves its own size, is centered horizontally
// and vertically in the area remaining from the pult. To prevent
// overflow and overlap with the root pult, the content is wrapped in
// an Expanded widget, and FittedBox scales it down if the width
// exceeds the available space.
//
// The row's height equals the root pult's side. Elements inside are
// vertically centered.
//
// Usage. Wrap the desired row as a ControlRow. The root pult itself
// remains in the main screen's tree (main.dart) and is not drawn here
// — this is merely a reservation and layout. For AppBars, where a
// separate widget is inappropriate, the static method reserve() gives
// the same left padding value.
//
// Transparency is not applied.
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

  const ControlRow({
    super.key,
    required this.rootSide,
    this.rootPad = 6.0,
    this.gap = 4.0,
    this.child,
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
                : Center(
                    // Scale down content if it exceeds the width.
                    child: FittedBox(fit: BoxFit.scaleDown, child: child),
                  ),
          ),
        ],
      ),
    );
  }
}
