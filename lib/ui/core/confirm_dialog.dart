// ═══════════════════════════════════════════════════════════════════
// confirm_dialog.dart — modal confirmation in the block style.
//
// Shape follows the blocks: bg fill, dim border, kRadius corners,
// kFramePad inset. Inside — title text, optional subtitle, and two
// words: cancel (dim) and confirm (signal). Tap on cancel, on
// confirm, or outside the frame dismisses the dialog; the result
// is a bool: true for confirm, false otherwise.
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
  final strokeW = side * bort.kStroke;
  final radius = side * bort.kRadius;
  // 1.6× reduction for the action labels.
  final actionSize = side * bort.kName / 1.6;

  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (ctx) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(ctx).pop(false),
        child: Center(
          child: GestureDetector(
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
                  if (subtitle != null) ...[
                    SizedBox(height: pad * 0.5),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: bort.dim,
                        fontSize: side * bort.kNumberSmall,
                      ),
                    ),
                  ],
                  SizedBox(height: pad * 0.8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(ctx).pop(false),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: side * 0.3,
                            vertical: side * 0.1,
                          ),
                          child: Text(
                            cancelLabel,
                            style: TextStyle(
                              color: bort.dim,
                              fontSize: actionSize,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: side * 0.4),
                      GestureDetector(
                        onTap: () => Navigator.of(ctx).pop(true),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: side * 0.3,
                            vertical: side * 0.1,
                          ),
                          child: Text(
                            confirmLabel,
                            style: TextStyle(
                              color: bort.signal,
                              fontSize: actionSize,
                              height: 1.0,
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
