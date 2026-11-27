import 'package:material_ui/material_ui.dart';

import '../core/bort_metrics.dart';
import 'dialog_frame.dart';

Future<bool> showConfirm(
  BuildContext context, {
  required String title,
  String? subtitle,
  required String confirmLabel,
  required String cancelLabel,
}) async {
  final metrics = BortMetrics.of(context, compact: true);

  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (ctx) {
      return DialogFrame(
        onDismiss: () => Navigator.of(ctx).pop(false),
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
                  color: metrics.bort.mid,
                  fontSize: metrics.smallFontSize,
                ),
              ),
            ],
            SizedBox(height: metrics.unit(metrics.bort.kFramePad * 0.8)),
            DialogActions(
              actions: [
                DialogAction(
                  label: cancelLabel,
                  onTap: () => Navigator.of(ctx).pop(false),
                ),
                DialogAction(
                  label: confirmLabel,
                  onTap: () => Navigator.of(ctx).pop(true),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  return result ?? false;
}
