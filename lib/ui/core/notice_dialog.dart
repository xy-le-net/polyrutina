// ═══════════════════════════════════════════════════════════════════
// notice_dialog.dart — pop-up notification in the style of blocks.
//
// Structure. A frame of the same shape as the blocks: background bg,
// border dim, corner radius kRadius, padding kFramePad. Inside — text
// and a confirmation button by word (signal-colored), as «reset»
// elsewhere. Dismissed by tapping the button or tapping outside the
// frame. No other buttons exist.
//
// Usage.
//   await showNotice(context, title: 'no orphans found');
//   await showNotice(context, title: 'removed: 3',
//                    subtitle: 'freed: 12 MB');
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../pults/pult_core.dart';
import 'app_scope.dart';

Future<void> showNotice(
  BuildContext context, {
  required String title,
  String? subtitle,
}) async {
  final app = AppScope.of(context);
  final bort = app.bort;
  final i18n = app.i18n;
  final side = PultScope.of(context).smallSide;

  final pad = side * bort.kFramePad;
  final strokeW = side * bort.kStroke;
  final radius = side * bort.kRadius;

  await showDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (ctx) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Tapping outside the frame — dismiss.
        onTap: () => Navigator.of(ctx).pop(),
        child: Center(
          child: GestureDetector(
            // Tapping inside the frame — absorb, do not dismiss.
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
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: side * 0.2,
                          vertical: side * 0.1,
                        ),
                        child: Text(
                          i18n.t('common.ok'),
                          style: TextStyle(
                            color: bort.signal,
                            fontSize: side * bort.kName,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
