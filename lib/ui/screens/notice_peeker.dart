import 'package:material_ui/material_ui.dart';

import '../core/app_scope.dart';
import '../core/bort_field.dart';
import '../core/bort_metrics.dart';
import '../core/dialog_frame.dart';
import '../core/format.dart';

Future<int?> showNoticePicker(
  BuildContext context, {
  required int initialSeconds,
  bool noticeSet = false,
}) async {
  final i18n = I18nScope.of(context);
  final metrics = BortMetrics.of(context, compact: true);

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
            DialogTitle(text: i18n.t('routine.notice_title')),
            SizedBox(height: metrics.unit(0.4)),
            BortField(
              initial: initial,
              fg: metrics.bort.fg,
              readOnly: false,
              hint: i18n.t('hint.notice'),
              onChanged: (v) => currentText = v,
              onCommit: (v) async {
                Navigator.of(ctx).pop(v);
              },
            ),
            SizedBox(height: metrics.unit(0.5)),
            DialogActions(
              actions: [
                DialogAction(
                  label: i18n.t('common.cancel'),
                  onTap: () => Navigator.of(ctx).pop(),
                ),
                DialogAction(
                  label: i18n.t('common.ok'),
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
