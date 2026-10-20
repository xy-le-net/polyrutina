// ═══════════════════════════════════════════════════════════════════
// block.dart — unified block for the routine card and the rubka.
//
// Structure:
//   — frame with smoothed corners;
//   — title at the top left;
//   — collapse icon in the top-left corner, signal-colored, slightly
//     protruding beyond the contour (by a quarter) — like a tag;
//   — content under the title (hidden when collapsed);
//   — optional widgets in the corners: top-right (timer)
//     and bottom-right (pulse).
//
// Tapping the title or the icon — collapses/expands, if canCollapse.
// The summary of the card cannot be collapsed — the icon is not
// rendered.
//
// Serves rubka blocks: the same frames, title, collapsing;
// corners are not used.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

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
  // Active block (running) — signal-colored frame.
  final bool active;
  // Bottom reserve for the corner pulse.
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
    this.reserveBottom = 0,
  });

  @override
  Widget build(BuildContext context) {
    final isCollapsed = canCollapse && collapsed;
    // Collapse icon: signal-colored, slightly protruding beyond
    // the contour.
    final markSize = titleSize * 1.2;

    return Container(
      margin: EdgeInsets.only(bottom: gap),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: active ? fg : dim, width: strokeW),
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
                // Title — clickable for collapsing.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: canCollapse ? onToggleCollapsed : null,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(color: dim, fontSize: titleSize),
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
          // Collapse icon — top-left corner.
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
          // Pulse — bottom-right corner. Along the same edge as the
          // top one: right = pad (coinciding with the end of the
          // padding where cornerRightTop is laid out), bottom = pad.
          if (cornerRightBottom != null)
            Positioned(right: pad, bottom: pad, child: cornerRightBottom!),
        ],
      ),
    );
  }
}
