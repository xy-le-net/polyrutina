// ═══════════════════════════════════════════════════════════════════
// lib/ui/core/control_row.dart — screen control row.
//
// A cross-cutting mechanism for all screens. The root pult (compass)
// hangs in the top-left corner — it is the start of the row. The space
// to its right is given to the immovable part of the page: title,
// month switcher, card name, etc.
//
// Pure layout reservation. The row draws nothing of its own: the pult
// is painted in main.dart's Stack above the navigator, so any
// decoration here would clip against the pult's rounded contour and
// break the unified silhouette.
//
// Alignment. The row reserves the pult's visual footprint (see
// pultVisualScale) and centers its content both horizontally and
// vertically inside that zone. Both offsets — the left margin and
// the top margin — equal rootPad, so the row starts exactly where
// the root pult starts (main.dart positions the pult at the same
// offset). The vertical centering is achieved by giving the inner
// Row a minHeight equal to the pult's visual footprint and letting
// its crossAxis default (center) place the child in the middle.
// Callers must NOT add a top Padding: that responsibility now
// belongs here, and any top padding on the caller side would shift
// the row by that amount and reintroduce the misalignment this
// widget exists to prevent.
//
// Pult footprint. RootPult wraps its core in two border decorations;
// each contributes 2 × (side / 16) to the child's size, so the total
// visual footprint is 1.25 × the declared side. The reservation
// accounts for that factor (pultVisualScale) so that the content
// cannot slide under the pult.
//
// The row's content preserves its own size, is aligned horizontally
// and vertically in the area remaining from the pult. The alignment
// defaults to center (appropriate for the month switcher) and can be
// set to centerLeft for titles that should sit flush with the
// reserved zone.
//
// The child is wrapped in a SizedBox with infinite width so that
// intrinsically-sized widgets (notably a TextField) take the full
// remaining width instead of shrinking to their content and
// rendering long titles outside the reserved zone.
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
  // Pult's offset from the screen edge (in main.dart — 6). Applied
  // both as the row's left margin and as its top margin, so the row
  // starts exactly where the root pult starts.
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
      // Left and top margins equal rootPad, mirroring main.dart's
      // Positioned(left: _rootPad, top: _rootPad) for the root pult.
      // Callers must not add a top Padding.
      margin: EdgeInsets.only(left: rootPad, top: rootPad),
      constraints: BoxConstraints(minHeight: rootSide * pultVisualScale),
      child: Row(
        // Center on the cross axis, so the child sits in the middle
        // of the pult's vertical zone. The Row's height is the larger
        // of the pult footprint and the child's intrinsic height,
        // which makes this the single vertical-centering rule for
        // every control row.
        crossAxisAlignment: CrossAxisAlignment.center,
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
