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
