// ═══════════════════════════════════════════════════════════════════
// control_row.dart — screen control row.
//
// A cross-cutting mechanism for all screens. The root pult (compass)
// hangs in the top-left corner — it is the start of the row. The space
// to its right is given to the immovable part of the page: title,
// month switcher, card name, etc.
//
// Pure layout reservation. The row draws nothing of its own: the pult
// is painted in main.dart's Stack above the navigator, so any
// decoration here would clip against the pult's rounded contour and
// break the unified silhouette. The former filled, bordered block has
// been removed; only the horizontal and vertical reservation remains.
//
// Pult footprint. RootPult wraps its core in two border decorations;
// each contributes 2 × (side / 16) to the child's size, so the total
// visual footprint is 1.25 × the declared side. The reservation
// accounts for that factor (pultVisualScale) so that the content
// cannot slide under the pult — previously the row reserved only the
// declared side, leaving a 25% overlap.
//
// The row's content preserves its own size, is aligned horizontally
// and vertically in the area remaining from the pult. The alignment
// defaults to center (appropriate for the month switcher) and can be
// set to centerLeft for titles that should sit flush with the
// reserved zone.
//
// The row's height matches the pult's visual footprint (minHeight
// instead of a fixed height; the content may exceed it). The former
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

class ControlRow extends StatelessWidget {
  // Width of the root pult as declared by its caller.
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

  // The pult's visual footprint exceeds its declared side: RootPult
  // wraps its core in two border decorations, and each contributes
  // 2 × (side / 16) to the total. Hence the factor 1.25.
  static const double pultVisualScale = 1.25;

  // Full width of the reserved zone on the left: offset + visual
  // pult size + gap.
  static double reserve(
    double rootSide, {
    double rootPad = 6.0,
    double gap = 4.0,
  }) => rootPad + rootSide * pultVisualScale + gap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(left: rootPad),
      constraints: BoxConstraints(minHeight: rootSide * pultVisualScale),
      child: Row(
        children: [
          // Reserve space for the pult's visual footprint plus the gap.
          SizedBox(width: rootSide * pultVisualScale + gap),
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
