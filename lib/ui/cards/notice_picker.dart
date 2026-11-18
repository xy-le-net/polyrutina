import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/bort_field.dart';
import '../core/dialog_frame.dart';
import '../core/format.dart';
import '../core/link_text.dart';
import '../pults/pult_core.dart';

Future<int?> showNoticePicker(
  BuildContext context, {
  required int initialSeconds,
  bool noticeSet = false,
}) async {
  final i18n = I18nScope.of(context);
  final bort = BortScope.of(context);
  final side = PultScope.of(context).smallSide;

  final initial = noticeSet ? fmtNoticeTime(initialSeconds) : '';

  final result = await showDialog<String>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (ctx) {
      String currentText = initial;
      return DialogFrame(
        onDismiss: () => Navigator.of(ctx).pop(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              i18n.t('routine.notice_title'),
              style: TextStyle(color: bort.fg, fontSize: side * bort.kTitle),
            ),
            const SizedBox(height: 12),
            BortField(
              initial: initial,
              fg: bort.fg,
              readOnly: false,
              hint: i18n.t('hint.notice'),
              onChanged: (v) => currentText = v,
              onCommit: (v) async {
                Navigator.of(ctx).pop(v);
              },
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                LinkText(
                  text: i18n.t('common.cancel'),
                  color: bort.bgsignal,
                  fontSize: side * bort.kName / 1.6,
                  padding: EdgeInsets.symmetric(
                    horizontal: side * 0.3,
                    vertical: side * 0.1,
                  ),
                  onTap: () => Navigator.of(ctx).pop(),
                ),
                SizedBox(width: side * 0.3),
                LinkText(
                  text: i18n.t('common.ok'),
                  color: bort.bgsignal,
                  fontSize: side * bort.kName / 1.6,
                  padding: EdgeInsets.symmetric(
                    horizontal: side * 0.3,
                    vertical: side * 0.1,
                  ),
                  onTap: () => Navigator.of(ctx).pop(currentText),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );

  if (result == null) return null;
  return parseNoticeTime(result);
}
