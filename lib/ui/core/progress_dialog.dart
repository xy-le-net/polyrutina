// ═══════════════════════════════════════════════════════════════════
// lib/ui/core/progress_dialog.dart — circular progress dialog.
//
// Frame geometry lives in DialogFrame: bg fill, dim border,
// kRadius corners, kFramePad inset. Inside — title, circular
// progress with a percentage at the center, and a text prompt.
//
// No cancel button. The app might freeze during heavy synchronous
// operations (though we try to avoid it), so a cancel button that
// doesn't actually abort the work is deceptive. Instead, the user
// is shown a polite message: 'common.wait' (e.g. "please wait").
//
// Progress. The value runs from 0.0 to 1.0. Percentages are shown
// as integers (no decimals). The ring is drawn with the standard
// CircularProgressIndicator at `value`; the arc is signal-colored,
// the track is dim.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../pults/pult_core.dart';
import 'app_scope.dart';
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
    final side = PultScope.of(context).smallSide;

    final pad = side * bort.kFramePad;
    final strokeW = side * bort.kStroke;
    final circleSize = side * 2.4;

    return DialogFrame(
      // The frame does not dismiss on an outside tap.
      onDismiss: () {},
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(color: bort.fg, fontSize: side * bort.kTitle),
          ),
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
                        fontSize: side * bort.kName,
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
            style: TextStyle(
              color: bort.mid,
              fontSize: side * bort.kName * 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
