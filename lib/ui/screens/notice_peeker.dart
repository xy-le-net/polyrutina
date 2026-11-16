// ═══════════════════════════════════════════════════════════════════
// notice_picker.dart — notice-interval input dialog.
//
// Replaces planned_picker.dart. The pult used to set a planned
// duration; it now sets a lead time — how long before the due date
// the user should be reminded. The input and output format is
// «days:hours:minutes», parsed by parseNoticeTime and rendered by
// fmtNoticeTime (core/format.dart). Seconds are not accepted.
//
// Initial value. When a notice was already assigned (noticeSet), the
// field is pre-filled with the canonical form of the current
// interval; otherwise it starts empty and the hint is visible until
// the first character is typed. The hint reads «дни:часы:минуты»
// (hint.notice in the dictionary).
//
// Returns the notice interval in seconds, or null when the user
// cancels or the input cannot be parsed. Zero is a legitimate
// return value («remind right at the due moment»); confirming an
// empty field yields zero, since parseNoticeTime('') == 0 and
// zero means «at the due moment». Whether the notice was actually
// assigned is decided by the caller, which always treats a
// successful return as assignment (see RoutineLayer.setNotice).
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
