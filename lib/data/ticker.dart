// ═══════════════════════════════════════════════════════════════════
// ticker.dart — unified application ticker.
//
// Purpose: one Timer for the entire application instead of separate
// timers in each widget. Widgets that need to update by the clock
// listen to this ticker and call setState on its signal.
//
// Period — five hundred milliseconds. Half a second visible, half a
// second not — this is how the colon of a running timer blinks. Two
// ticks per second are negligible for a modern device.
//
// Wall-second. The timer runs in half-seconds, but the time on the
// wall clock changes once a second. The wallSecond method returns
// the current epoch second — based on it, widgets decide whether
// the visible unit (minute, hour) has changed, and whether they
// need to redraw.
//
// Lifecycle. The pause and resume methods allow the main application
// to stop the ticker when going to background and restart it when
// returning to the foreground, saving battery.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

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
