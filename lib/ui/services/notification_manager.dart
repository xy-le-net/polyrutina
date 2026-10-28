// ═══════════════════════════════════════════════════════════════════
// notification_manager.dart — orchestrates ongoing notifications.
//
// Listens to the ticker and the layer states to show, update, and
// cancel the ongoing notifications for the active field's shift and
// the active routine block.
//
// State signatures. Instead of calling the notification service on
// every tick (twice a second), this manager tracks the active field,
// block kind, and routine ID. The notification is pushed only when
// the signature changes (e.g., a new block starts, the shift stops).
// The system chronometer handles the visual ticking of the time,
// which saves resources and prevents notification spam.
//
// Texts come from I18n, keeping them short and localized.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import '../../data/field_layer.dart';
import '../../data/i18n.dart';
import '../../data/operational_layer.dart';
import '../../data/routine_layer.dart';
import '../../data/ticker.dart';
import 'notification_service.dart';

class NotificationManager {
  final OperationalLayer bort;
  final RoutineLayer routineLayer;
  final FieldLayer fieldLayer;
  final AppTicker ticker;
  final I18n i18n;

  // State caches to prevent spamming the OS notification service.
  int? _lastShiftFieldId;
  bool _lastShiftActive = false;
  int? _lastRoutineId;
  String? _lastBlockKind;

  NotificationManager({
    required this.bort,
    required this.routineLayer,
    required this.fieldLayer,
    required this.ticker,
    required this.i18n,
  }) {
    ticker.addListener(_onTick);
    _update(force: true);
  }

  void dispose() {
    ticker.removeListener(_onTick);
  }

  void _onTick() {
    _update();
  }

  void _update({bool force = false}) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final activeFieldId = fieldLayer.activeFieldId;

    // ─── Shift ───
    final shiftActive = activeFieldId != null && bort.onShift(activeFieldId);

    if (force ||
        activeFieldId != _lastShiftFieldId ||
        shiftActive != _lastShiftActive) {
      if (shiftActive) {
        final sessionSec = bort.shiftStartedAt(activeFieldId) != null
            ? now - bort.shiftStartedAt(activeFieldId)!
            : 0;
        final totalSec = bort.shiftSecondsNow(activeFieldId);

        final fieldName =
            fieldLayer.nodes[activeFieldId]?.name ?? i18n.t('field.root');
        final title = '${i18n.t('bort.shift')}: $fieldName';

        NotificationService.showShift(
          fieldId: activeFieldId,
          title: title,
          elapsedSec: sessionSec,
          totalSec: totalSec,
          t: i18n.t,
          labelTotal: i18n.t('notif.total'),
        );
      } else {
        NotificationService.cancelShift();
      }
      _lastShiftFieldId = activeFieldId;
      _lastShiftActive = shiftActive;
    }

    // ─── Routine ───
    final currentId = routineLayer.currentRoutineId;
    final currentRoutine = currentId != null
        ? routineLayer.findRoutine(currentId)
        : null;
    final runningBlock = currentRoutine?.runningBlock;
    final blockKind = runningBlock?.kind;

    if (force || currentId != _lastRoutineId || blockKind != _lastBlockKind) {
      if (currentRoutine != null && runningBlock != null) {
        final elapsedSec = runningBlock.secondsNowAt(now);
        final totalSec = currentRoutine.totalSeconds;

        // Determine field name for the routine
        String fieldName = i18n.t('field.root');
        if (currentRoutine.fieldParents.isNotEmpty) {
          final fId = currentRoutine.fieldParents.first;
          final node = fieldLayer.nodes[fId];
          if (node != null) fieldName = node.name;
        }

        final rTitle = currentRoutine.name.isEmpty
            ? i18n.t('routine.no_name')
            : currentRoutine.name;
        final title = '$fieldName · $rTitle';

        NotificationService.showRoutine(
          routineId: currentRoutine.id,
          title: title,
          blockTitle: i18n.t('routine.block.${runningBlock.kind}'),
          elapsedSec: elapsedSec,
          totalSec: totalSec,
          t: i18n.t,
          labelRunning: i18n.t('notif.running'),
          labelTotal: i18n.t('notif.total'),
        );
      } else {
        NotificationService.cancelRoutine();
      }
      _lastRoutineId = currentId;
      _lastBlockKind = blockKind;
    }
  }
}
