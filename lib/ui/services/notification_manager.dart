// ═══════════════════════════════════════════════════════════════════
// notification_manager.dart — orchestrates ongoing notifications.
//
// Listens to the ticker and the layer states to show, update, and
// cancel the ongoing notifications for the active field's shift and
// the active routine block.
//
// Throttling. The system's chronometer handles the ticking display.
// To save battery and avoid spamming the platform channel, the
// notification is only updated when its text actually changes (e.g.,
// once a minute, or when the block state changes).
//
// Timer synchronization. The chronometer (when) is set to the
// current block's elapsed time. The total time (body) is calculated
// separately and formatted via the unified dictionary and format
// helpers, ensuring both display consistent information without
// desynchronization.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import '../../data/field_layer.dart';
import '../../data/i18n.dart';
import '../../data/operational_layer.dart';
import '../../data/routine_layer.dart';
import '../../data/ticker.dart';
import '../core/format.dart';
import 'notification_service.dart';

class NotificationManager {
  final OperationalLayer bort;
  final RoutineLayer routineLayer;
  final FieldLayer fieldLayer;
  final AppTicker ticker;
  final I18n i18n;

  String _lastShiftBody = '';
  String _lastRoutineBody = '';

  bool _wasShiftActive = false;
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

    if (shiftActive) {
      final sessionSec = bort.shiftStartedAt(activeFieldId) != null
          ? now - bort.shiftStartedAt(activeFieldId)!
          : 0;
      final totalSec = bort.shiftSecondsNow(activeFieldId);

      final fieldName =
          fieldLayer.nodes[activeFieldId]?.name ?? i18n.t('field.root');
      final title = '${i18n.t('bort.shift')}: $fieldName';
      final body = '${i18n.t('notif.total')}: ${fmtTime(totalSec, i18n.t)}';

      if (force || !_wasShiftActive || body != _lastShiftBody) {
        NotificationService.showShift(
          fieldId: activeFieldId,
          title: title,
          body: body,
          elapsedSec: sessionSec,
          lang: bort.lang,
        );
        _lastShiftBody = body;
      }
      _wasShiftActive = true;
    } else {
      if (_wasShiftActive || force) {
        NotificationService.cancelShift();
      }
      _wasShiftActive = false;
      _lastShiftBody = '';
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

      final blockTitle = i18n.t('routine.block.${runningBlock.kind}');
      final body =
          '$blockTitle ${i18n.t('notif.running')}\n'
          '${i18n.t('notif.total')}: ${fmtTime(totalSec, i18n.t)}';

      if (force ||
          _lastRoutineId != currentId ||
          _lastBlockKind != runningBlock.kind ||
          body != _lastRoutineBody) {
        NotificationService.showRoutine(
          routineId: currentRoutine.id,
          title: title,
          body: body,
          elapsedSec: elapsedSec,
          lang: bort.lang,
        );
        _lastRoutineBody = body;
        _lastBlockKind = runningBlock.kind;
      }
      _lastRoutineId = currentId;
    } else {
      if (_lastRoutineId != null || force) {
        NotificationService.cancelRoutine();
      }
      _lastRoutineId = null;
      _lastBlockKind = null;
      _lastRoutineBody = '';
    }
  }
}
