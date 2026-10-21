// ═══════════════════════════════════════════════════════════════════
// confirm_dialog.dart — warning dialog for irreversible actions.
//
// Similar in shape to notice_dialog, but provides two explicit
// choices: «cancel» (dim color) and «confirm» (signal color).
// Tapping outside the frame acts as cancel.
//
// Returns true if confirmed, false if cancelled.
//
// Usage:
//   final ok = await showConfirmDialog(context, title: 'Delete all?');
//   if (ok) { ... }
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../pults/pult_core.dart';
import 'app_scope.dart';

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? confirmLabel,
}) async {
  final app = AppScope.of(context);
  final bort = app.bort;
  final i18n = app.i18n;
  final side = PultScope.of(context).smallSide;

  final pad = side * bort.kFramePad;
  final strokeW = side * bort.kStroke;
  final radius = side * bort.kRadius;

  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (ctx) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Tapping outside the frame — cancel.
        onTap: () => Navigator.of(ctx).pop(false),
        child: Center(
          child: GestureDetector(
            // Tapping inside the frame — absorb.
            onTap: () {},
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: side * 1.2),
              decoration: BoxDecoration(
                color: bort.bg,
                border: Border.all(color: bort.dim, width: strokeW),
                borderRadius: BorderRadius.circular(radius),
              ),
              padding: EdgeInsets.all(pad),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: bort.fg,
                      fontSize: side * bort.kTitle,
                    ),
                  ),
                  SizedBox(height: pad * 0.8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Cancel action (dim color).
                      GestureDetector(
                        onTap: () => Navigator.of(ctx).pop(false),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: side * 0.2,
                            vertical: side * 0.1,
                          ),
                          child: Text(
                            i18n.t('common.cancel'),
                            style: TextStyle(
                              color: bort.dim,
                              fontSize: side * bort.kName,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: side * 0.4),
                      // Confirm action (signal color).
                      GestureDetector(
                        onTap: () => Navigator.of(ctx).pop(true),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: side * 0.2,
                            vertical: side * 0.1,
                          ),
                          child: Text(
                            confirmLabel ?? i18n.t('bort.delete'),
                            style: TextStyle(
                              color: bort.signal,
                              fontSize: side * bort.kName,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  return result ?? false;
}
