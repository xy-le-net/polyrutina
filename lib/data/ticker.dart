import 'dart:async';

import 'package:flutter/foundation.dart';

class AppTicker extends ChangeNotifier {
  // The single timer. One for the whole application.
  Timer? _timer;

  // Tick period — five hundred milliseconds.
  static const Duration period = Duration(milliseconds: 500);

  // Colon blink phase: true — visible, false — not.
  bool _colonVisible = true;
  bool get colonVisible => _colonVisible;

  bool _paused = false;

  AppTicker() {
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(period, (_) {
      _colonVisible = !_colonVisible;
      notifyListeners();
    });
  }

  // Pauses the ticker. Used when the app goes to background.
  void pause() {
    if (_paused) return;
    _paused = true;
    _timer?.cancel();
    _timer = null;
  }

  // Resumes the ticker. Used when the app returns to foreground.
  void resume() {
    if (!_paused) return;
    _paused = false;
    _startTimer();
  }

  // Current epoch second. Widgets compare it with a saved one
  // to decide whether the visible unit has changed.
  int get wallSecond => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  // Current epoch minute — for coarse comparison.
  int get wallMinute => wallSecond ~/ 60;

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
