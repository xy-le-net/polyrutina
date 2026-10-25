// ═══════════════════════════════════════════════════════════════════
// lib/ui/core/dialog_frame.dart — common dialog frame.
//
// The unified frame for every in-app dialog: confirm, notice,
// progress, and the time-history viewers. Shape follows the
// blocks — bg fill, mid border, kRadius corners, kFramePad inset —
// so dialogs read as floating blocks over the page.
//
// Outside the frame — dismiss (tap on the barrier). Inside the
// frame — absorb (the inner GestureDetector swallows the tap), so
// touching text or empty space inside does not close the dialog by
// accident.
//
// Text-style isolation. The dialog is wrapped in
// DefaultTextStyle.merge with decoration: TextDecoration.none.
// Without it, the frame inherits the text style from the context
// that opened it — and when that context carries an active
// composing underline (observed when a single routine is exported
// from the card: the field's IME composing underline leaks into
// every Text in the dialog), every label and every word in the
// dialog is drawn with that underline. LinkText and any other
// element that sets its own decoration explicitly still wins,
// because TextStyle.decoration on the child overrides the merged
// default. The leak is therefore closed without altering the
// look of any dialog opened from a clean context.
//
// Geometry. Diameters, pad, stroke, and radius are derived from the
// small pult side (PultScope) and bort coefficients (kFramePad,
// kStroke, kRadius). Callers do not compute these; they supply only
// the content and (optionally) constraints.
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
