import 'package:material_ui/material_ui.dart';

import '../core/app_scope.dart';
import '../core/bort_metrics.dart';
import 'dialog_frame.dart';

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

class ProgressDialog extends StatelessWidget {
  final ProgressToken token;
  final String title;

  const ProgressDialog({super.key, required this.token, required this.title});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
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
