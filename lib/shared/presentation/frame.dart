import 'package:material_ui/material_ui.dart';

/// Frame geometry for one item: color and stroke width. The parity
/// is 0 for even positions, 1 for odd, and is ignored when the item
/// is active.
class FrameStyle {
  final Color color;
  final double width;

  const FrameStyle({required this.color, required this.width});
}

/// Compute the frame style for one item.
///
/// [parity] — 0 for an even position in the visible order, 1 for an
/// odd one. Ignored when [active] is true.
/// [active] — the item is running.
/// [strokeW] — the normal stroke width; the active frame doubles it.
/// [fg] — base content color; used for the even non-active frame.
/// [mid] — secondary color; used for the odd non-active frame.
/// [fgsignal] — signal color; used for the active frame.
FrameStyle borderFor({
  required int parity,
  required bool active,
  required double strokeW,
  required Color fg,
  required Color mid,
  required Color fgsignal,
}) {
  if (active) {
    return FrameStyle(color: fgsignal, width: strokeW * 2);
  }
  if (parity.isEven) {
    return FrameStyle(color: fg, width: strokeW);
  }
  return FrameStyle(color: mid, width: strokeW);
}
