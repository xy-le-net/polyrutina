// ═══════════════════════════════════════════════════════════════════
// link_text.dart — clickable word with a uniform look.
//
// Two roles: primary (signal color, advances the flow) and
// secondary (dim, backs out). Both share one underline thickness
// and one text style, so a row of links reads as one family.
//
// Decoration. The underline is forced to a single, thin stroke
// (decorationThickness: 1.0) to prevent double lines on high-DPI
// screens or when inherited styles add their own.
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
            decorationThickness: 1.0,
          ),
        ),
      ),
    );
  }
}
