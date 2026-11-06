// ═══════════════════════════════════════════════════════════════════
// notice_picker.dart — notice-interval input dialog.
//
// Replaces planned_picker.dart. The pult used to set a planned
// duration; it now sets a lead time — how long before the due date
// the user should be reminded. The input and output format is the
// same («days:hours:minutes»), parsed by parseNoticeTime and
// rendered by fmtNoticeTime (core/format.dart). The old names
// (showPlannedPicker, routine.planned_title, hint.planned) are
// gone; the caller (routine_card) was updated accordingly.
//
// Returns the notice interval in seconds, or null when the user
// cancels or the input cannot be parsed. Zero is a legitimate
// return value («remind right at the due moment»); whether the
// notice was actually assigned is decided by the caller, which
// always treats a successful return as assignment (see
// RoutineLayer.setNotice).
//
// Shown only when a date is assigned. The caller enforces that; the
// picker itself is not date-aware.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/bort_field.dart';
import '../core/dialog_frame.dart';
import '../core/format.dart';
import '../pults/pult_core.dart';

Future<int?> showNoticePicker(
  BuildContext context, {
  required int initialSeconds,
}) async {
  final i18n = I18nScope.of(context);
  final bort = BortScope.of(context);
  final side = PultScope.of(context).smallSide;

  final initial = fmtNoticeTime(initialSeconds);

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
