import 'package:polyrutina/core/localization/providers.dart';
import 'package:polyrutina/features/settings/application/providers.dart';
import 'package:polyrutina/shared/application/provider_read.dart';
import 'package:material_ui/material_ui.dart';

import 'package:polyrutina/shared/presentation/bort_metrics.dart';

class StubTab extends StatelessWidget {
  const StubTab({super.key});

  @override
  Widget build(BuildContext context) {
    final i18n = readProvider(context, i18nProvider)!;
    final bort = readProvider(context, operationalLayerProvider);

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
