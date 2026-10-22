// ═══════════════════════════════════════════════════════════════════
// control_row.dart — screen control row.
//
// A cross-cutting mechanism for all screens. The root pult (compass)
// hangs in the top-left corner — it is the start of the row. The space
// to its right is given to the immovable part of the page: title,
// month switcher, card name, etc.
//
// The row's content preserves its own size, is aligned horizontally
// and vertically in the area remaining from the pult. The alignment
// defaults to center (appropriate for the month switcher) and can be
// set to centerLeft for titles that should sit flush with the
// reserved zone.
//
// The row's height equals the root pult's side, but can grow if the
// content is taller (minHeight instead of a fixed height). The former
// FittedBox wrapper has been removed: it broke layouts that rely on
// Expanded inside the child. The child is wrapped in a SizedBox with
// infinite width so that intrinsically-sized widgets (notably a
// TextField) take the full remaining width instead of shrinking to
// their content and rendering long titles outside the reserved zone.
//
// Usage. Wrap the desired row as a ControlRow. The root pult itself
// remains in the main screen's tree (main.dart) and is not drawn here
// — this is merely a reservation and layout. For AppBars, where a
// separate widget is inappropriate, the static method reserve() gives
// the same left padding value.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import 'app_scope.dart';

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
    final bort = BortScope.of(context);
    final strokeW = rootSide * bort.kStroke;
    final radiusW = rootSide * bort.kRadius;

    // The row is drawn as a single block: a filled container with
    // a border and rounded corners. The root pult sits on top of
    // the left reserve, so the row and the pult read as one unit.
    // The left margin shifts the block to align with the root pult
    // (which is placed at rootPad from the screen edge).
    return Container(
      margin: EdgeInsets.only(left: rootPad),
      constraints: BoxConstraints(minHeight: rootSide),
      decoration: BoxDecoration(
        color: bort.bg,
        border: Border.all(color: bort.dim, width: strokeW),
        borderRadius: BorderRadius.circular(radiusW),
      ),
      child: Row(
        children: [
          // Reserve space for the root pult plus the gap.
          SizedBox(width: rootSide + gap),
          // Allocate the remaining space and prevent overlap. The
          // SizedBox(width: double.infinity) forces the child to take
          // the full remaining width; without it, a widget such as a
          // TextField would shrink to its intrinsic width under the
          // Align's loose constraints, and long titles would render
          // outside the reserved zone.
          Expanded(
            child: Align(
              alignment: alignment,
              child: child == null
                  ? const SizedBox.shrink()
                  : SizedBox(width: double.infinity, child: child),
            ),
          ),
        ],
      ),
    );
  }
}
