import 'package:material_ui/material_ui.dart';

class ControlRow extends StatelessWidget {
  // Declared root-pult width.
  final double rootSide;
  // Match the root pult's screen offset.
  final double rootPad;
  // Content beside the root pult.
  final Widget? child;
  // Gap between the pult and content.
  final double gap;
  // Alignment within the remaining width.
  final Alignment alignment;

  const ControlRow({
    super.key,
    required this.rootSide,
    this.rootPad = 6.0,
    this.gap = 4.0,
    this.child,
    this.alignment = Alignment.center,
  });

  // Include both border decorations in the visible pult width.
  static const double pultVisualScale = 1.25;
  static const double enlargementScale = 1.2;

  // Width reserved for the root pult and its gap.
  static double reserve(
    double rootSide, {
    double rootPad = 6.0,
    double gap = 4.0,
  }) => rootPad + rootSide * enlargementScale * pultVisualScale + gap;

  @override
  Widget build(BuildContext context) {
    final controlSide = rootSide * enlargementScale;
    return Container(
      // Align with the root pult; callers should not add top padding.
      margin: EdgeInsets.only(left: rootPad, top: rootPad),
      constraints: BoxConstraints.tightFor(
        height: controlSide * pultVisualScale,
      ),
      child: Row(
        // Center content within the root pult's vertical zone.
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: controlSide * pultVisualScale + gap),
          // Constrain the child to prevent overlap with the pult.
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
