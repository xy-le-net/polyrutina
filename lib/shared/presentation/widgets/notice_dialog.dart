import 'package:polyrutina/core/localization/providers.dart';
import 'package:polyrutina/shared/application/provider_read.dart';
import 'package:material_ui/material_ui.dart';

import 'package:polyrutina/shared/presentation/bort_metrics.dart';
import 'package:polyrutina/shared/presentation/widgets/dialog_frame.dart';

Future<void> showNotice(
  BuildContext context, {
  required String title,
  String? subtitle,
}) async {
  final i18n = readProvider(context, i18nProvider)!;
  final metrics = BortMetrics.of(context, compact: true);
  final bort = metrics.bort;

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
            DialogTitle(text: title),
            if (subtitle != null) ...[
              SizedBox(height: metrics.unit(metrics.bort.kFramePad * 0.5)),
              Text(
                subtitle,
                style: TextStyle(
                  color: bort.mid,
                  fontSize: metrics.smallFontSize,
                ),
              ),
            ],
            SizedBox(height: metrics.unit(metrics.bort.kFramePad * 0.8)),
            DialogActions(
              actions: [
                DialogAction(
                  label: i18n.t('common.ok'),
                  onTap: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
