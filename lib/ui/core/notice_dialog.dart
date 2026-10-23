// ═══════════════════════════════════════════════════════════════════
// lib/ui/core/notice_dialog.dart — floating notice.
//
// Frame geometry lives in DialogFrame: bg fill, dim border,
// kRadius corners, kFramePad inset. Inside — title, optional
// subtitle, and a confirm word (signal-colored), as in «reset»
// elsewhere. Dismissed by the button or by a tap outside the frame.
// No other buttons.
//
// Usage:
//   await showNotice(context, title: 'сирот не нашлось');
//   await showNotice(context, title: 'удалено: 3',
//                    subtitle: 'освобождено: 12 МБ');
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../pults/pult_core.dart';
import 'app_scope.dart';
import 'dialog_frame.dart';
import 'link_text.dart';

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

  await showDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (ctx) {
      return DialogFrame(
        onDismiss: () => Navigator.of(ctx).pop(),
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
                  color: bort.dim,
                  fontSize: side * bort.kNumberSmall,
                ),
              ),
            ],
            SizedBox(height: pad * 0.8),
            Align(
              alignment: Alignment.centerRight,
              child: LinkText(
                text: i18n.t('common.ok'),
                color: bort.signal,
                fontSize: side * bort.kName,
                padding: EdgeInsets.symmetric(
                  horizontal: side * 0.2,
                  vertical: side * 0.1,
                ),
                onTap: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      );
    },
  );
}
