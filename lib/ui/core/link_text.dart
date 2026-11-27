import 'package:material_ui/material_ui.dart';

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
    final linkSize = fontSize;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: padding,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bort.fgsignal,
            borderRadius: BorderRadius.circular(linkSize * 0.22),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: linkSize * 0.3,
              vertical: linkSize * 0.15,
            ),
            child: Text(
              text,
              style: TextStyle(
                color: bort.bgsignal,
                fontSize: linkSize,
                fontWeight: FontWeight.normal,
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
