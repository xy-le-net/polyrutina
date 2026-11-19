import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/dialog_frame.dart';
import '../core/link_text.dart';
import '../core/wheel_picker.dart';
import '../pults/pult_core.dart';

Future<int?> showNoticePicker(
  BuildContext context, {
  required int initialSeconds,
  bool noticeSet = false,
}) async {
  final i18n = I18nScope.of(context);
  final bort = BortScope.of(context);
  final side = PultScope.of(context).smallSide;

  final safeInitial = (noticeSet ? initialSeconds : 0)
      .clamp(0, 999 * 86400 + 23 * 3600 + 59 * 60)
      .toInt();
  var days = safeInitial ~/ 86400;
  var hours = (safeInitial % 86400) ~/ 3600;
  var minutes = (safeInitial % 3600) ~/ 60;

  final result = await showDialog<int>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setState) {
          return DialogFrame(
            onDismiss: () => Navigator.of(ctx).pop(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  i18n.t('routine.notice_title'),
                  style: TextStyle(
                    color: bort.fg,
                    fontSize: side * bort.kTitle,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: side * 2.8,
                  child: WheelValuePicker(
                    columns: [
                      WheelColumn(
                        label: i18n.t('notice.days'),
                        separator: ':',
                        value: days,
                        itemCount: 1000,
                        onChanged: (v) => setState(() => days = v),
                      ),
                      WheelColumn(
                        label: i18n.t('notice.hours'),
                        separator: ':',
                        value: hours,
                        itemCount: 24,
                        onChanged: (v) => setState(() => hours = v),
                        formatter: (v) => v.toString().padLeft(2, '0'),
                      ),
                      WheelColumn(
                        label: i18n.t('notice.minutes'),
                        value: minutes,
                        itemCount: 60,
                        onChanged: (v) => setState(() => minutes = v),
                        formatter: (v) => v.toString().padLeft(2, '0'),
                      ),
                    ],
                    side: side,
                  ),
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
                      onTap: () => Navigator.of(
                        ctx,
                      ).pop(days * 86400 + hours * 3600 + minutes * 60),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    },
  );
  return result;
}
