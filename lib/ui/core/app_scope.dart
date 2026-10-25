// ═══════════════════════════════════════════════════════════════════
// app_scope.dart — application context and point scopes.
//
// AppContext — an immutable set of dependencies and delegates. Lives
// as long as the app; recreated on language change (and even then,
// within a single frame).
//
// AppScope (InheritedWidget) provides AppContext. Notifies only when
// the context itself changes, not when layers change: UI updates go
// through point scopes (see below).
//
// Point scopes:
//   BortScope    — OperationalLayer: theme, shift, bort time.
//   RoutineScope — RoutineLayer: cards, lists, days.
//   TraceScope   — TraceLayer: trace fields, checklists, media.
//   FieldScope   — FieldLayer: tree of field nodes.
//   TickerScope  — AppTicker: timers and colon blink.
//   I18nScope    — dictionary: interface strings.
//
// Each scope is an InheritedNotifier (I18n is InheritedWidget).
// A widget reading a layer depends on the corresponding scope and
// rebuilds only when it changes.
//
// toggleBlockWithShift and toggleShift — delegates of AppContext:
// connection of shift and routines through the journal (actor kind).
//
// pulseBort — notify the bort of a user action.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

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
  final Future<void> Function(int routineId) openRoutine;

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
  });

  // ─── Start a routine block with shift logic ───
  Future<void> toggleBlockWithShift(int routineId, String kind) async {
    final r = routineLayer.findRoutine(routineId);
    if (r == null) return;
    final b = r.blockOf(kind);
    if (b == null) return;

    final going = !b.isRunning;

    if (going && !bort.onShift) {
      await journal.log(
        type: JournalType.actor,
        body: '{"action":"shift_start"}',
      );
      bort.startShift();
    }

    // The mutex flag lives in the operational layer; the routine
    // layer merely obeys. When mutex is off, other blocks keep
    // running.
    await routineLayer.toggleBlock(
      journal,
      routineId,
      kind,
      mutex: bort.mutexRoutines,
      mutexSlots: bort.mutexSlots,
    );
  }

  // ─── Shift ───
  Future<void> toggleShift() async {
    final going = !bort.onShift;
    await journal.log(
      type: JournalType.actor,
      body: '{"action":"${going ? 'shift_start' : 'shift_stop'}"}',
    );
    if (going) {
      bort.startShift();
      return;
    }
    bort.stopShift();
    // Walk every routine, not only the current one: with routine
    // mutex off, several blocks may be running at once, and all of
    // them must stop when the shift stops. The routine layer is the
    // single source of truth for which blocks are running; the bort
    // keeps no parallel list.
    for (final r in routineLayer.routines) {
      for (final b in r.blocks) {
        if (b.isRunning) {
          await routineLayer.pauseBlock(journal, r.id, b.kind);
        }
      }
    }
  }

  // ─── User action ───
  void pulseBort() {
    bort.pulseBort();
  }
}

// ─── AppScope: permanent context ───
// Notifies only when AppContext itself changes (by fields). Layer
// changes do not reach here: UI updates go through point scopes.
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
    // Method tear-offs in Dart are stable: reference comparison is
    // correct even for delegates (refresh, reloadI18n, openRoutine).
    return old.appContext.bort != appContext.bort ||
        old.appContext.routineLayer != appContext.routineLayer ||
        old.appContext.traceLayer != appContext.traceLayer ||
        old.appContext.fieldLayer != appContext.fieldLayer ||
        old.appContext.journal != appContext.journal ||
        old.appContext.ticker != appContext.ticker ||
        old.appContext.i18n != appContext.i18n ||
        old.appContext.refresh != appContext.refresh ||
        old.appContext.reloadI18n != appContext.reloadI18n ||
        old.appContext.openRoutine != appContext.openRoutine;
  }
}

// ─── BortScope ───
// Subscribers: theme, shift, bort time, block collapses.
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

// ─── RoutineScope ───
// Subscribers: RoutineCard, RoutinePlate, RoutinesTab, DaysTab.
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

// ─── TraceScope ───
// Subscribers: TraceField, ChecklistScreen, RoutineCard (via _hasTrace),
// MediaViewer (on deletion).
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

// ─── FieldScope ───
// Subscribers: FieldTab, RoutineCard (on field attach/detach).
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

// ─── TickerScope ───
// Subscribers: Pulse, TimerText, RoutineCard, RoutinesTab, ShiftRow.
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

// ─── I18nScope ───
// Subscribers: everything that prints strings. I18n changes rarely —
// on language switch; this rare event rebuilds subscribers.
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
