import 'dart:convert';
import 'package:material_ui/material_ui.dart';

import '../../data/field_layer.dart';
import '../../data/i18n.dart';
import '../../data/journal_layer.dart';
import '../../data/journal_types.dart';
import '../../data/operational_layer.dart';
import '../../data/routine_layer.dart';
import '../../data/ticker.dart';
import '../../data/trace_layer.dart';

class AppContext {
  final OperationalLayer bort;
  final RoutineLayer routineLayer;
  final TraceLayer traceLayer;
  final FieldLayer fieldLayer;
  final JournalLayer journal;
  final AppTicker ticker;
  final I18n i18n;
  final Future<void> Function() refresh;
  final Future<void> Function() reloadI18n;
  final Future<void> Function(int routineId, {bool autofocusName}) openRoutine;
  final Future<void> Function() afterJournalReset;

  const AppContext({
    required this.bort,
    required this.routineLayer,
    required this.traceLayer,
    required this.fieldLayer,
    required this.journal,
    required this.ticker,
    required this.i18n,
    required this.refresh,
    required this.reloadI18n,
    required this.openRoutine,
    required this.afterJournalReset,
  });

  // The field argument is kept for source compatibility; the shift
  // is global, so its identity is ignored here.
  Future<void> toggleBlockWithShift(
    int fieldId,
    int routineId,
    String kind,
  ) async {
    final r = routineLayer.findRoutine(routineId);
    if (r == null) return;
    final b = r.blockOf(kind);
    if (b == null) return;

    final going = !b.isRunning;

    // Auto-start the shift when the block is started, the shift
    // exists (toggle on), the shift is linked to routines, and it
    // is not already running. If it is already running, it is
    // deliberately left as is (per the spec: no restart).
    if (bort.shiftEnabled && going && bort.mutexShift && !bort.onShift(0)) {
      await journal.log(
        type: JournalType.actor,
        body: jsonEncode({'action': 'shift_start', 'field_id': 0}),
      );
      bort.startShift(0);
    }

    await routineLayer.toggleBlock(
      journal,
      routineId,
      kind,
      mutex: bort.mutexRoutines,
      mutexSlots: bort.mutexSlots,
    );
  }

  // The field argument is kept for source compatibility; the shift
  // is unified, so the identity is ignored. When shiftEnabled is
  // false, this is a no-op: no shift, no state change, no journal
  // entry — the toggle switch in the rubka owns that transition
  // (see operational_layer).
  Future<void> toggleShift(int fieldId) async {
    if (!bort.shiftEnabled) return;
    final going = !bort.onShift(0);
    await journal.log(
      type: JournalType.actor,
      body: jsonEncode({
        'action': going ? 'shift_start' : 'shift_stop',
        'field_id': 0,
      }),
    );

    if (going) {
      bort.startShift(0);
      return;
    }

    bort.stopShift(0);

    // Pause every running block across every field when the shift
    // is linked to routines. No descent check: the shift is global,
    // so its scope covers all fields equally.
    if (bort.mutexShift) {
      for (final r in routineLayer.routines) {
        for (final b in r.blocks) {
          if (b.isRunning) {
            await routineLayer.pauseBlock(journal, r.id, b.kind);
          }
        }
      }
    }
  }

  void pulseBort() {
    bort.pulseBort();
  }
}

class AppScope extends InheritedWidget {
  final AppContext appContext;

  const AppScope({super.key, required this.appContext, required super.child});

  static AppContext of(BuildContext c) {
    final scope = c.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found');
    return scope!.appContext;
  }

  @override
  bool updateShouldNotify(covariant AppScope old) {
    return old.appContext.bort != appContext.bort ||
        old.appContext.routineLayer != appContext.routineLayer ||
        old.appContext.traceLayer != appContext.traceLayer ||
        old.appContext.fieldLayer != appContext.fieldLayer ||
        old.appContext.journal != appContext.journal ||
        old.appContext.ticker != appContext.ticker ||
        old.appContext.i18n != appContext.i18n ||
        old.appContext.refresh != appContext.refresh ||
        old.appContext.reloadI18n != appContext.reloadI18n ||
        old.appContext.openRoutine != appContext.openRoutine ||
        old.appContext.afterJournalReset != appContext.afterJournalReset;
  }
}

class BortScope extends InheritedNotifier<OperationalLayer> {
  const BortScope({
    super.key,
    required OperationalLayer bort,
    required super.child,
  }) : super(notifier: bort);

  static OperationalLayer of(BuildContext c) {
    final s = c.dependOnInheritedWidgetOfExactType<BortScope>();
    assert(s != null, 'BortScope not found');
    return s!.notifier!;
  }
}

class RoutineScope extends InheritedNotifier<RoutineLayer> {
  const RoutineScope({
    super.key,
    required RoutineLayer routineLayer,
    required super.child,
  }) : super(notifier: routineLayer);

  static RoutineLayer of(BuildContext c) {
    final s = c.dependOnInheritedWidgetOfExactType<RoutineScope>();
    assert(s != null, 'RoutineScope not found');
    return s!.notifier!;
  }
}

class TraceScope extends InheritedNotifier<TraceLayer> {
  const TraceScope({
    super.key,
    required TraceLayer traceLayer,
    required super.child,
  }) : super(notifier: traceLayer);

  static TraceLayer of(BuildContext c) {
    final s = c.dependOnInheritedWidgetOfExactType<TraceScope>();
    assert(s != null, 'TraceScope not found');
    return s!.notifier!;
  }
}

// Subscribers: FieldTab, RoutineCard (on field attach/detach),
// and anything tracking the active field.
class FieldScope extends InheritedNotifier<FieldLayer> {
  const FieldScope({
    super.key,
    required FieldLayer fieldLayer,
    required super.child,
  }) : super(notifier: fieldLayer);

  static FieldLayer of(BuildContext c) {
    final s = c.dependOnInheritedWidgetOfExactType<FieldScope>();
    assert(s != null, 'FieldScope not found');
    return s!.notifier!;
  }
}

class TickerScope extends InheritedNotifier<AppTicker> {
  const TickerScope({
    super.key,
    required AppTicker ticker,
    required super.child,
  }) : super(notifier: ticker);

  static AppTicker of(BuildContext c) {
    final s = c.dependOnInheritedWidgetOfExactType<TickerScope>();
    assert(s != null, 'TickerScope not found');
    return s!.notifier!;
  }
}

class I18nScope extends InheritedWidget {
  final I18n i18n;

  const I18nScope({super.key, required this.i18n, required super.child});

  static I18n of(BuildContext c) {
    final s = c.dependOnInheritedWidgetOfExactType<I18nScope>();
    assert(s != null, 'I18nScope not found');
    return s!.i18n;
  }

  @override
  bool updateShouldNotify(I18nScope old) => old.i18n != i18n;
}
