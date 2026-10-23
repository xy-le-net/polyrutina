// ═══════════════════════════════════════════════════════════════════
// lib/ui/core/link_text.dart — clickable word with a uniform look.
//
// Two roles:
//   — primary: the action that advances the flow («ok», «delete»,
//     «reset», the shift row) — drawn signal-colored and underlined;
//   — secondary: the action that backs out («cancel», «clear date»)
//     — drawn dim and underlined.
//
// Both share one underline thickness and one text style, so a row
// of links reads as one family. The underline color follows the
// text color; no separate stroke is painted.
//
// Used by confirm/notice/progress dialogs and the shift row in the
// rubka. Callers supply the color and size; the widget only owns
// the underline and the hit area.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

class LinkText extends StatelessWidget {
  final String text;
  final Color color;
  final double fontSize;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  const LinkText({
    super.key,
    required this.text,
    required this.color,
    required this.fontSize,
    required this.onTap,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: padding,
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            height: 1.0,
            decoration: TextDecoration.underline,
            decorationColor: color,
          ),
        ),
      ),
    );
  }
}
