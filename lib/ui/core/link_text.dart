import 'package:flutter/material.dart';

import 'app_scope.dart';

class LinkText extends StatelessWidget {
  final String text;
  final double fontSize;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final String? fontFamily;

  const LinkText({
    super.key,
    required this.text,
    // Keep accepting existing call-site colors; palette roles own link colors.
    Color? color,
    required this.fontSize,
    required this.onTap,
    this.padding = EdgeInsets.zero,
    this.fontFamily,
  });

  @override
  Widget build(BuildContext context) {
    final bort = BortScope.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: padding,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bort.fgsignal,
            borderRadius: BorderRadius.circular(fontSize * 0.15),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: fontSize * 0.3,
              vertical: fontSize * 0.15,
            ),
            child: Text(
              text,
              style: TextStyle(
                color: bort.bgsignal,
                fontSize: fontSize,
                fontFamily: fontFamily,
                height: 1.0,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
