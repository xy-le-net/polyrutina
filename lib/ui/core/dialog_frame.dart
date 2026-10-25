// ═══════════════════════════════════════════════════════════════════
// lib/ui/core/dialog_frame.dart — common dialog frame.
//
// The unified frame for every in-app dialog: confirm, notice,
// progress, and shift history. Shape follows the blocks — bg fill,
// dim border, kRadius corners, kFramePad inset — so dialogs read as
// floating blocks over the page.
//
// Outside the frame — dismiss (tap on the barrier). Inside the
// frame — absorb (the inner GestureDetector swallows the tap), so
// touching text or empty space inside does not close the dialog by
// accident.
//
// Geometry. Diameters, pad, stroke, and radius are derived from the
// small pult side (PultScope) and bort coefficients (kFramePad,
// kStroke, kRadius). Callers do not compute these; they supply only
// the content and (optionally) constraints.
//
// Usage:
//   showDialog<bool>(
//     context: context,
//     barrierColor: Colors.transparent,
//     builder: (ctx) => DialogFrame(
//       onDismiss: () => Navigator.of(ctx).pop(false),
//       child: Column(...),
//     ),
//   );
//
// A caller that wants extra padding around the frame (horizontal
// margin) passes it via margin. The default matches the former
// dialogs (side * 1.2 on each side).
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../pults/pult_core.dart';
import 'app_scope.dart';

class DialogFrame extends StatelessWidget {
  // Dismissal callback — runs on a tap outside the frame.
  final VoidCallback onDismiss;

  // Dialog body — the caller's column.
  final Widget child;

  // Optional horizontal margin around the frame.
  final double? margin;

  // Optional height cap; when null, the frame is as tall as its
  // content (bounded by the screen).
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

    return GestureDetector(
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
    );
  }
}
