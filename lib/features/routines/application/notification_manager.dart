import 'package:polyrutina/features/fields/application/field_layer.dart';
import 'package:polyrutina/core/localization/i18n.dart';
import 'package:polyrutina/features/settings/application/operational_layer.dart';
import 'package:polyrutina/features/routines/application/routine_access.dart';
import 'package:polyrutina/core/application/ticker.dart';
import 'package:polyrutina/shared/application/format.dart';
import 'package:polyrutina/core/application/notification_service.dart';

class NotificationManager {
  final OperationalLayer bort;
  final RoutineAccess routineLayer;
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

  // Body (four lines):
  //   <routine name>
  //   <current slot>: <its time>
  // The current slot's time restarts on every slot change, but the
  // total never resets. On slot change the body string differs, so
  // the push is refreshed immediately.
  void _updateRoutine(int now, {bool force = false}) {
    final currentId = routineLayer.currentRoutineId;
    var currentRoutine = currentId != null
        ? routineLayer.findRoutine(currentId)
        : null;
    if (currentRoutine?.runningBlock == null) {
      currentRoutine = null;
      for (final routine in routineLayer.routines) {
        if (routine.runningBlock == null) continue;
        if (currentRoutine == null ||
            routine.lastActionAt > currentRoutine.lastActionAt) {
          currentRoutine = routine;
        }
      }
    }
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
        _lastRoutineId != currentRoutine.id ||
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
    _lastRoutineId = currentRoutine.id;
  }

  String _stopLabel() => bort.lang == 'ru' ? 'Остановить' : 'Stop';
}
