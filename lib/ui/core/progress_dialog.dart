// ═══════════════════════════════════════════════════════════════════
// progress_dialog.dart — pop-up frame with a circular progress.
//
// Structure. A frame of the same shape as blocks and notices:
// background bg, border dim, corner radius kRadius, padding
// kFramePad. Inside — a caption, a circular fill indicator, and
// the link-word «cancel» in signal color.
//
// Progress. Value from 0.0 to 1.0. Inside the circle — percentages
// as whole numbers (no decimals). The circle is drawn by the
// standard CircularProgressIndicator with value; color — signal,
// background — dim.
//
// Cancel. Tapping the word «cancel» — cancel signal; the dialog
// closes, and the calling code must dispose of the unfinished work.
//
// Usage:
//   final token = ProgressToken();
//   showDialog(..., builder: (_) => ProgressDialog(token: token));
//   // during work, periodically: token.report(0.3);
//   // upon completion: Navigator.pop(context);
//   // if token.cancelled — abort the work.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../pults/pult_core.dart';
import 'app_scope.dart';

class ProgressToken extends ChangeNotifier {
  double _value = 0;
  bool _cancelled = false;

  double get value => _value;
  bool get cancelled => _cancelled;

  // Reports a new progress value, clamped to [0.0, 1.0].
  // Notifies only when the value actually changes.
  void report(double v) {
    if (_cancelled) return;
    if (v < 0) v = 0;
    if (v > 1) v = 1;
    if (v == _value) return;
    _value = v;
    notifyListeners();
  }

  // Marks the work as cancelled.
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
    final radius = side * bort.kRadius;
    final circleSize = side * 2.4;

    return Center(
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: side * 1.2),
        decoration: BoxDecoration(
          color: bort.bg,
          border: Border.all(color: bort.dim, width: strokeW),
          borderRadius: BorderRadius.circular(radius),
        ),
        padding: EdgeInsets.all(pad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(color: bort.fg, fontSize: side * bort.kTitle),
            ),
            SizedBox(height: pad),
            // Circular progress with percentages inside.
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
                          color: bort.signal,
                          backgroundColor: bort.dim,
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
            // The link-word «cancel» in signal color.
            GestureDetector(
              onTap: () {
                token.cancel();
                Navigator.of(context).pop();
              },
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: side * 0.2,
                  vertical: side * 0.1,
                ),
                child: Text(
                  i18n.t('export.cancel'),
                  style: TextStyle(
                    color: bort.signal,
                    fontSize: side * bort.kName,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
