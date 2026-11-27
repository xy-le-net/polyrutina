import 'package:material_ui/material_ui.dart';

import '../core/app_scope.dart';
import '../core/bort_metrics.dart';

class StubTab extends StatelessWidget {
  const StubTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final i18n = app.i18n;
    final bort = app.bort;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            i18n.t('stub.title'),
            style: TextStyle(
              color: bort.fg,
              fontSize: BortMetrics.of(context).titleFontSize,
            ),
          ),
          const SizedBox(height: 8),
          Text(i18n.t('stub.text'), style: TextStyle(color: bort.mid)),
        ],
      ),
    );
  }
}
