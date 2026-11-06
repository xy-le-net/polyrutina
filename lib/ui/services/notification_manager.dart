// ═══════════════════════════════════════════════════════════════════
// notification_manager.dart — orchestrates ongoing notifications.
//
// Listens to the ticker and the layer states to show, update, and
// cancel the ongoing notifications for the unified shift and the
// active routine block.
//
// Unified shift. The shift is no longer bound to a field: one timer
// for the entire application, stored under the zero-field key.
//
// Bodies. The manager formats the content; the service only shows
// and cancels. Shift: title «смена» (no field name), body two lines
// — «текущее» (live time since start, ticking) and «сегодня»
// (today's total, refreshed once per minute via the same change
// detector used for routines). Routine: title is the field name (or
// «общее» if unattached), body four lines — routine name, current
// slot with its time, and «всего: X». No field name is prepended to
// the routine title itself; the field lives on the first body line.
//
// Throttling. The system's chronometer handles the ticking display.
// The notification is only updated when its body string actually
// changes (e.g., once a minute, or when a block changes). No
// redundant platform-channel calls.
//
// Stop buttons. The «stop» actions reach the app through
// pending_action.json; they are applied by main.dart with the same
// semantics as an in-app press (mutexes honoured). The manager only
// makes sure that when the shift or the routine stops, the
// corresponding notification is cancelled promptly.
//
// Shift gating. When bort.shiftEnabled is false, no shift
// notification is shown or refreshed; a stale one is cancelled if
// present.
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

  // The shift is unified: its identity is the zero-field key.
  static const int _shiftFieldId = 0;

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
    _updateShift(now, force: force);
    _updateRoutine(now, force: force);
  }

  // ─── Shift notification ───
  // Title: «смена» — the field is deliberately not mentioned.
  // Body: «текущее: X» and «сегодня: Y» on separate lines. «текущее»
  // is the elapsed time since the current shift started; «сегодня»
  // is today's total, recalculated at each tick, but pushed to the
  // platform only when the visible string changes (the chronometer
  // in the notification handles the seconds).
  void _updateShift(int now, {bool force = false}) {
    final shiftActive = bort.shiftEnabled && bort.onShift(_shiftFieldId);

    if (!shiftActive) {
      if (_wasShiftActive || force) {
        NotificationService.cancelShift();
      }
      _wasShiftActive = false;
      _lastShiftBody = '';
      return;
    }

    final startedAt = bort.shiftStartedAt(_shiftFieldId);
    final sessionSec = startedAt != null ? now - startedAt : 0;
    final totalSec = bort.shiftSecondsNow(_shiftFieldId);

    final title = i18n.t('bort.shift');
    final body =
        '${i18n.t('notif.current')}: ${fmtTime(sessionSec, i18n.t)}\n'
        '${i18n.t('notif.today')}: ${fmtTime(totalSec, i18n.t)}';

    if (force || !_wasShiftActive || body != _lastShiftBody) {
      NotificationService.showShift(
        fieldId: _shiftFieldId,
        title: title,
        body: body,
        elapsedSec: sessionSec,
        stopLabel: _stopLabel(),
      );
      _lastShiftBody = body;
    }
    _wasShiftActive = true;
  }

  // ─── Routine notification ───
  // Title: the field name, or «общее» if the routine is unattached.
  // Body (four lines):
  //   <routine name>
  //   <current slot>: <its time>
  //   всего: <total>
  // The current slot's time restarts on every slot change, but the
  // total never resets. On slot change the body string differs, so
  // the push is refreshed immediately.
  void _updateRoutine(int now, {bool force = false}) {
    final currentId = routineLayer.currentRoutineId;
    final currentRoutine = currentId != null
        ? routineLayer.findRoutine(currentId)
        : null;
    final runningBlock = currentRoutine?.runningBlock;

    if (currentRoutine == null || runningBlock == null) {
      if (_lastRoutineId != null || force) {
        NotificationService.cancelRoutine();
      }
      _lastRoutineId = null;
      _lastBlockKind = null;
      _lastRoutineBody = '';
      return;
    }

    // Field label: first bound field's name, or «общее» when the
    // routine has no field parents.
    String fieldName;
    if (currentRoutine.fieldParents.isNotEmpty) {
      final fId = currentRoutine.fieldParents.first;
      final node = fieldLayer.nodes[fId];
      fieldName = (node != null && node.name.isNotEmpty)
          ? node.name
          : i18n.t('field.root');
    } else {
      fieldName = i18n.t('field.shared');
    }

    final rTitle = currentRoutine.name.isEmpty
        ? i18n.t('routine.no_name')
        : currentRoutine.name;
    final blockTitle = i18n.t('routine.block.${runningBlock.kind}');
    final blockSec = runningBlock.secondsNowAt(now);
    final totalSec = currentRoutine.totalSeconds;

    // The title carries the field label; the routine name opens
    // the body, so the field name is not repeated inside.
    final title = fieldName;
    final body =
        '$rTitle\n'
        '$blockTitle: ${fmtTime(blockSec, i18n.t)}\n'
        '${i18n.t('notif.total')}: ${fmtTime(totalSec, i18n.t)}';

    if (force ||
        _lastRoutineId != currentId ||
        _lastBlockKind != runningBlock.kind ||
        body != _lastRoutineBody) {
      NotificationService.showRoutine(
        routineId: currentRoutine.id,
        title: title,
        body: body,
        elapsedSec: blockSec,
        stopLabel: _stopLabel(),
      );
      _lastRoutineBody = body;
      _lastBlockKind = runningBlock.kind;
    }
    _lastRoutineId = currentId;
  }

  String _stopLabel() => bort.lang == 'ru' ? 'Остановить' : 'Stop';
}
