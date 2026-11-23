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
      constraints: BoxConstraints.tightFor(height: rootSide * pultVisualScale),
      child: Row(
        // Keep the content centered within the root pult's fixed
        // vertical zone, regardless of its intrinsic height.
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
