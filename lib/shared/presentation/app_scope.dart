import 'dart:convert';
import 'package:material_ui/material_ui.dart';

import 'package:polyrutina/core/data/field_layer.dart';
import 'package:polyrutina/core/localization/i18n.dart';
import 'package:polyrutina/core/data/journal_layer.dart';
import 'package:polyrutina/core/domain/journal_types.dart';
import 'package:polyrutina/core/application/operational_layer.dart';
import 'package:polyrutina/shared/application/routine_access.dart';
import 'package:polyrutina/core/application/ticker.dart';
import 'package:polyrutina/core/data/trace_layer.dart';

class AppContext {
  final OperationalLayer bort;
  final RoutineAccess routineLayer;
  final TraceLayer traceLayer;
  final FieldLayer fieldLayer;
  final JournalLayer journal;
  final AppTicker ticker;
  final I18n i18n;
  final Future<void> Function() refresh;
  final Future<void> Function() reloadI18n;
  final Future<void> Function(int routineId, {bool autofocusName}) openRoutine;
  final Future<void> Function(int routineId, BuildContext context)
  exportRoutine;
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
    required this.exportRoutine,
    required this.afterJournalReset,
  });

  // Keep fieldId for API compatibility; shift state is global.
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

    // Start the linked shift with the block, but do not restart an active shift.
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

  // Keep fieldId for API compatibility; the rubka toggle owns disabled state.
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

    // Pause all running blocks when the shift is linked to routines.
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
        old.appContext.exportRoutine != appContext.exportRoutine ||
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

class RoutineScope extends InheritedNotifier<RoutineAccess> {
  const RoutineScope({
    super.key,
    required RoutineAccess routineLayer,
    required super.child,
  }) : super(notifier: routineLayer);

  static RoutineAccess of(BuildContext c) {
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

// Notifies field views when the active field changes.
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
