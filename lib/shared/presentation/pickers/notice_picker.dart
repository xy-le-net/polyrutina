import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:polyrutina/core/application/providers.dart';
import 'package:polyrutina/shared/presentation/bort_metrics.dart';
import 'package:polyrutina/shared/presentation/widgets/dialog_frame.dart';
import 'package:polyrutina/shared/presentation/widgets/wheel_picker.dart';

Future<int?> showNoticePicker(
  BuildContext context, {
  required int initialSeconds,
  bool noticeSet = false,
}) async {
  final i18n = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(i18nProvider)!;
  final metrics = BortMetrics.of(context, compact: true);
  final side = metrics.side;

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
                DialogTitle(text: i18n.t('routine.notice_title')),
                SizedBox(height: metrics.unit(0.4)),
                SizedBox(
                  height: metrics.wheelPickerHeight,
                  child: WheelValuePicker(
                    columns: [
                      WheelColumn(
                        label: i18n.t('notice.days'),
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
                SizedBox(height: metrics.unit(0.5)),
                DialogActions(
                  actions: [
                    DialogAction(
                      label: i18n.t('common.cancel'),
                      onTap: () => Navigator.of(ctx).pop(),
                    ),
                    DialogAction(
                      label: i18n.t('common.ok'),
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
