// ═══════════════════════════════════════════════════════════════════
// lib/ui/core/dialog_frame.dart — common dialog frame.
//
// The unified frame for every in-app dialog: confirm, notice,
// progress, and the time-history viewers.
//
// Text-style isolation. The dialog is wrapped in
// DefaultTextStyle.merge with decoration: TextDecoration.none.
// Additionally, FocusManager.instance.primaryFocus?.unfocus() is
// called in the build method to forcefully remove the IME composing
// underline before the dialog paints.
//
// Geometry. Diameters, pad, stroke, and radius are derived from the
// small pult side (PultScope) and bort coefficients.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

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
    final radius = side * bort.kRadius;
    final hMargin = margin ?? side * 1.2;

    // Unfocus any active field before the frame paints to prevent
    // the IME composing underline from leaking into the dialog.
    FocusManager.instance.primaryFocus?.unfocus();

    return DefaultTextStyle.merge(
      // Neutralise inherited decoration. Explicit decoration on a
      // child (LinkText's underline, for example) still wins.
      style: const TextStyle(decoration: TextDecoration.none),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onDismiss,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: hMargin),
              constraints: maxHeight == null
                  ? null
                  : BoxConstraints(maxHeight: maxHeight!),
              decoration: BoxDecoration(
                color: bort.bg,
                border: Border.all(color: bort.mid, width: strokeW),
                borderRadius: BorderRadius.circular(radius),
              ),
              padding: EdgeInsets.all(pad),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
