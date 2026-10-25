// ═══════════════════════════════════════════════════════════════════
// lib/ui/core/block.dart — unified block for routine cards and the
// rubka.
//
// Structure:
//   — frame with rounded corners;
//   — title at the top left;
//   — collapse mark at the top left corner, signal-colored,
//     slightly overhanging the outline — as a label;
//   — content under the title (hidden when collapsed);
//   — optional widgets in the corners: top right (timer)
//     and bottom right (pulse).
//
// Frame rule. The frame is computed by borderFor (core/frame.dart):
// active — fgsignal, doubled stroke; inactive, parity 0 — fg;
// inactive, parity 1 — mid. The background is bg for every item;
// the former dim / normal alternation through the background is
// abolished. The active frame wins over parity.
//
// The `dim` parameter (the secondary color used for the title and
// the collapse mark's label) is kept, but no longer drives the
// border.
//
// Touching the title or the mark toggles collapse when canCollapse
// is true. The summary of a card cannot be collapsed — the mark is
// not drawn.
//
// Serves the rubka blocks too: same frames, title, collapse; the
// corners are unused there.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import 'frame.dart';

class Block extends StatelessWidget {
  final String title;
  final Widget? child;
  final bool collapsed;
  final bool canCollapse;
  final VoidCallback? onToggleCollapsed;

  // Right corners: optional widgets.
  final Widget? cornerRightTop;
  final Widget? cornerRightBottom;

  // Colors.
  final Color bg;
  final Color dim;
  final Color fg;
  final Color signal;

  // Sizes.
  final double titleSize;
  final double pad;
  final double gap;
  final double strokeW;
  final double radiusW;

  // Frame state.
  // active — the item is running (frame turns fgsignal, doubled).
  // parity — 0 for an even position in the visible order, 1 for an
  // odd one; decides between fg and mid for the non-active frame.
  // Ignored when active is true.
  final bool active;
  final int parity;

  // Reserve at the bottom under the corner pult.
  final double reserveBottom;

  const Block({
    super.key,
    required this.title,
    this.child,
    this.collapsed = false,
    this.canCollapse = true,
    this.onToggleCollapsed,
    this.cornerRightTop,
    this.cornerRightBottom,
    required this.bg,
    required this.dim,
    required this.fg,
    required this.signal,
    required this.titleSize,
    required this.pad,
    required this.gap,
    required this.strokeW,
    required this.radiusW,
    this.active = false,
    this.parity = 0,
    this.reserveBottom = 0,
  });

  @override
  Widget build(BuildContext context) {
    final isCollapsed = canCollapse && collapsed;
    // Collapse mark: signal-colored, slightly overhanging the
    // outline.
    final markSize = titleSize * 1.2;

    // Frame rule: one call to borderFor decides color and stroke.
    // The active state wins over parity; parity distinguishes even
    // and odd positions only among non-active items.
    final frame = borderFor(
      parity: parity,
      active: active,
      strokeW: strokeW,
      fg: fg,
      mid: dim,
      fgsignal: signal,
    );

    return Container(
      margin: EdgeInsets.only(bottom: gap),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: frame.color, width: frame.width),
        borderRadius: BorderRadius.circular(radiusW),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              pad + markSize * 0.75,
              pad,
              pad,
              pad + reserveBottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title — tappable to toggle collapse.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: canCollapse ? onToggleCollapsed : null,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The title is capped at a single line and
                      // ellipsized: pults on the right can squeeze
                      // the available width, and a two-line wrap
                      // would break the uniform height of the block
                      // header.
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(color: dim, fontSize: titleSize),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (cornerRightTop != null) ...[
                        const SizedBox(width: 8),
                        cornerRightTop!,
                      ],
                    ],
                  ),
                ),
                if (!isCollapsed && child != null) ...[
                  SizedBox(height: pad * 0.5),
                  child!,
                ],
              ],
            ),
          ),
          // Collapse mark — top left corner.
          if (canCollapse)
            Positioned(
              left: -markSize * 0.25,
              top: -markSize * 0.25,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onToggleCollapsed,
                child: Container(
                  width: markSize,
                  height: markSize,
                  decoration: BoxDecoration(
                    color: signal,
                    borderRadius: BorderRadius.circular(markSize * 0.2),
                  ),
                  child: Icon(
                    collapsed ? Icons.unfold_more : Icons.unfold_less,
                    color: bg,
                    size: markSize * 0.7,
                  ),
                ),
              ),
            ),
          // Pulse — bottom right corner.
          if (cornerRightBottom != null)
            Positioned(right: pad, bottom: pad, child: cornerRightBottom!),
        ],
      ),
    );
  }
}
