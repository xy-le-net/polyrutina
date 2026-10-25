// ═══════════════════════════════════════════════════════════════════
// notification_manager.dart — orchestrates ongoing notifications.
//
// Listens to the ticker and the layer states to show, update, and
// cancel the ongoing notifications for the shift and the active
// routine block.
//
// The update is throttled to once per second (the ticker fires twice
// a second). Notifications are rebuilt only when the state changes,
// but the elapsed time is refreshed every second while active.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import '../../data/operational_layer.dart';
import '../../data/routine_layer.dart';
import '../../data/ticker.dart';
import 'notification_service.dart';

class NotificationManager {
  final OperationalLayer bort;
  final RoutineLayer routineLayer;
  final AppTicker ticker;

  int _lastSec = 0;
  bool _wasShiftActive = false;
  int? _lastRoutineId;

  NotificationManager({
    required this.bort,
    required this.routineLayer,
    required this.ticker,
  }) {
    ticker.addListener(_onTick);
    _update(force: true);
  }

  void dispose() {
    ticker.removeListener(_onTick);
  }

  void _onTick() {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (now == _lastSec) return;
    _lastSec = now;
    _update();
  }

  void _update({bool force = false}) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // ─── Shift ───
    final shiftActive = bort.onShift;
    if (shiftActive) {
      final sessionSec = bort.shiftStartedAt != null
          ? now - bort.shiftStartedAt!
          : 0;
      final totalSec = bort.shiftSecondsNow;
      NotificationService.showShift(
        sinceLastSec: sessionSec,
        totalSec: totalSec,
        lang: bort.lang,
      );
      _wasShiftActive = true;
    } else {
      if (_wasShiftActive || force) {
        NotificationService.cancelShift();
      }
      _wasShiftActive = false;
    }

    // ─── Routine ───
    final currentId = routineLayer.currentRoutineId;
    final currentRoutine = currentId != null
        ? routineLayer.findRoutine(currentId)
        : null;
    final runningBlock = currentRoutine?.runningBlock;

    if (currentRoutine != null && runningBlock != null) {
      final elapsedSec = runningBlock.secondsNowAt(now);
      final totalSec = currentRoutine.totalSeconds;
      NotificationService.showRoutine(
        routineName: currentRoutine.name,
        blockTitle: runningBlock.kind,
        elapsedSec: elapsedSec,
        totalSec: totalSec,
        lang: bort.lang,
      );
      _lastRoutineId = currentId;
    } else {
      if (_lastRoutineId != null || force) {
        NotificationService.cancelRoutine();
      }
      _lastRoutineId = null;
    }
  }
}
