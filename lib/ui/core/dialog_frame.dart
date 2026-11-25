import 'package:flutter/material.dart';

import '../pults/pult_core.dart';
import 'app_scope.dart';

class DialogFrame extends StatelessWidget {
  final VoidCallback onDismiss;
  final Widget child;
  final double? margin;
  final double? maxHeight;

  const DialogFrame({
    super.key,
    required this.onDismiss,
    required this.child,
    this.margin,
    this.maxHeight,
  });

  @override
  Widget build(BuildContext context) {
    final bort = BortScope.of(context);
    final side = PultScope.of(context).smallSide;

    final pad = side * bort.kFramePad;
    final strokeW = side * bort.kStroke;
    final radius = side * bort.kRadius * 1.15;
    final hMargin = margin ?? side * 1.2;
    final availableHeight =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom -
        32;

    // Unfocus any active field before the frame paints to prevent
    // the IME composing underline from leaking into the dialog.
    FocusManager.instance.primaryFocus?.unfocus();

    return DefaultTextStyle.merge(
      // Neutralise inherited decoration while allowing child styles.
      style: const TextStyle(decoration: TextDecoration.none),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onDismiss,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: hMargin),
              constraints: BoxConstraints(
                maxHeight:
                    maxHeight ??
                    (availableHeight * 0.9)
                        .clamp(0.0, double.infinity)
                        .toDouble(),
              ),
              decoration: BoxDecoration(
                color: bort.bg,
                border: Border.all(color: bort.fgsignal, width: strokeW),
                borderRadius: BorderRadius.circular(radius),
              ),
              clipBehavior: Clip.antiAlias,
              padding: EdgeInsets.all(pad),
              child: SingleChildScrollView(child: child),
            ),
          ),
        ),
      ),
    );
  }
}
