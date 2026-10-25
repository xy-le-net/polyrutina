// ═══════════════════════════════════════════════════════════════════
// lib/ui/core/frame.dart — unified frame rule.
//
// One rule for every framed surface in the app: routine blocks,
// routine plates in the list, and the four rubka blocks. The rule
// is: the frame carries state; the background does not.
//
// States:
//   active   — the item is running (a block with startedAt, a plate
//              with a running block). The frame takes fgsignal and
//              its stroke is doubled. Signal reads as «this is what
//              is happening now»; doubling the stroke strengthens
//              that at a glance and keeps the reading intact on a
//              monochrome screen or under any color-vision shift
//              (the difference is weight, not only hue).
//   parity 0 — even position in the visible order, not running.
//              The frame takes fg: a firm but neutral line.
//   parity 1 — odd position, not running. The frame takes mid: a
//              softer line. Alternation through the frame alone
//              replaces the former alternation through the
//              background (dimmed / normal), which is abolished.
//
// The background of a non-running item is always bg — the same for
// every position. Dimming the background is no longer a signal of
// position; the frame carries that information.
//
// Active wins over parity: a running item gets the signal frame
// regardless of its position. When several items run at once, all
// of them are active, all signal-framed, all with the doubled
// stroke; their neighbours alternate through the frame only. The
// running background is still the inverted palette (runningColors),
// so running items stand out by both hue and weight — and, on a
// monochrome screen, by weight alone.
//
// Transparency is not applied: no alpha, no opacity, no animated
// transitions. The frame is one of the three states listed above,
// computed per build.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

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
