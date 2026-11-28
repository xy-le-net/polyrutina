import 'package:polyrutina/core/localization/providers.dart';
import 'package:polyrutina/shared/application/provider_read.dart';
import 'package:polyrutina/features/settings/application/providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:polyrutina/shared/presentation/bort_metrics.dart';
import 'package:polyrutina/shared/presentation/widgets/dialog_frame.dart';

class ProgressToken extends ChangeNotifier {
  double _value = 0;
  bool _cancelled = false;

  double get value => _value;
  bool get cancelled => _cancelled;

  void report(double v) {
    if (_cancelled) return;
    if (v < 0) v = 0;
    if (v > 1) v = 1;
    if (v == _value) return;
    _value = v;
    notifyListeners();
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    notifyListeners();
  }
}

class ProgressDialog extends ConsumerWidget {
  final ProgressToken token;
  final String title;

  const ProgressDialog({super.key, required this.token, required this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bort = ref.watch(operationalLayerProvider);
    final i18n = readProvider(context, i18nProvider)!;
    final metrics = BortMetrics.of(context, compact: true);

    final pad = metrics.framePadding;
    final strokeW = metrics.stroke;
    final circleSize = metrics.unit(2.4);

    return DialogFrame(
      // The frame does not dismiss on an outside tap.
      onDismiss: () {},
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DialogTitle(text: title),
          SizedBox(height: pad),
          // Circular progress with percentages at the center.
          AnimatedBuilder(
            animation: token,
            builder: (_, __) {
              final percent = (token.value * 100).round();
              return SizedBox(
                width: circleSize,
                height: circleSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: circleSize,
                      height: circleSize,
                      child: CircularProgressIndicator(
                        value: token.value,
                        strokeWidth: strokeW * 6,
                        color: bort.fgsignal,
                        backgroundColor: bort.mid,
                      ),
                    ),
                    Text(
                      '$percent%',
                      style: TextStyle(
                        color: bort.fg,
                        fontSize: metrics.numberFontSize,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          SizedBox(height: pad),
          // Polite waiting message instead of a deceptive cancel button.
          Text(
            i18n.t('common.wait'),
            textAlign: TextAlign.center,
            style: TextStyle(color: bort.mid, fontSize: metrics.smallFontSize),
          ),
        ],
      ),
    );
  }
}
