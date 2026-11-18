import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/bort_field.dart';
import '../core/dialog_frame.dart';
import '../core/format.dart';
import '../pults/pult_core.dart';

Future<int?> showNoticePicker(
  BuildContext context, {
  required int initialSeconds,
  bool noticeSet = false,
}) async {
  final i18n = I18nScope.of(context);
  final bort = BortScope.of(context);
  final side = PultScope.of(context).smallSide;

  // Pre-fill only when a notice was actually assigned. An unset
  // notice leaves the field empty so the hint is visible.
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
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(i18n.t('common.cancel')),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(currentText),
                  child: Text(i18n.t('common.ok')),
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
