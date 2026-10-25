// ═══════════════════════════════════════════════════════════════════
// lib/ui/core/confirm_dialog.dart — modal confirmation.
//
// Frame geometry lives in DialogFrame: bg fill, dim border,
// kRadius corners, kFramePad inset. Inside — title, optional
// subtitle, and two words: cancel (dim, underlined) and confirm
// (signal, underlined). Both words go through LinkText, so the
// underline and the hit area are uniform across the app.
//
// Tap on cancel, on confirm, or outside the frame dismisses the
// dialog; the result is a bool — true for confirm, false otherwise.
//
// Usage:
//   final ok = await showConfirm(context,
//       title: 'Delete all entries?',
//       confirmLabel: 'Delete',
//       cancelLabel: 'Cancel');
//   if (ok) { ... }
//
// Button labels are set at kName / 1.6: at the full kName size the
// words overflow the frame on narrow screens (notably with long
// Russian labels such as «удалить» and «отмена»). The height is
// normalized to 1.0 so that the tightened line does not drift
// vertically against the right-aligned row.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../pults/pult_core.dart';
import 'app_scope.dart';
import 'dialog_frame.dart';
import 'link_text.dart';

Future<bool> showConfirm(
  BuildContext context, {
  required String title,
  String? subtitle,
  required String confirmLabel,
  required String cancelLabel,
}) async {
  final bort = BortScope.of(context);
  final side = PultScope.of(context).smallSide;

  final pad = side * bort.kFramePad;
  // 1.6× reduction for the action labels.
  final actionSize = side * bort.kName / 1.6;
  final actionPad = EdgeInsets.symmetric(
    horizontal: side * 0.3,
    vertical: side * 0.1,
  );

  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (ctx) {
      return DialogFrame(
        onDismiss: () => Navigator.of(ctx).pop(false),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(color: bort.fg, fontSize: side * bort.kTitle),
            ),
            if (subtitle != null) ...[
              SizedBox(height: pad * 0.5),
              Text(
                subtitle,
                style: TextStyle(
                  color: bort.mid,
                  fontSize: side * bort.kNumberSmall,
                ),
              ),
            ],
            SizedBox(height: pad * 0.8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                LinkText(
                  text: cancelLabel,
                  color: bort.mid,
                  fontSize: actionSize,
                  padding: actionPad,
                  onTap: () => Navigator.of(ctx).pop(false),
                ),
                SizedBox(width: side * 0.4),
                LinkText(
                  text: confirmLabel,
                  color: bort.fgsignal,
                  fontSize: actionSize,
                  padding: actionPad,
                  onTap: () => Navigator.of(ctx).pop(true),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  return result ?? false;
}
