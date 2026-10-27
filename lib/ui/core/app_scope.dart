// ═══════════════════════════════════════════════════════════════════
// app_scope.dart — application context and point scopes.
//
// AppContext — an immutable set of dependencies and delegates. Lives
// as long as the app; recreated on language change.
//
// AppScope (InheritedWidget) provides AppContext. Notifies only when
// the context itself changes.
//
// Point scopes:
//   BortScope    — OperationalLayer: theme, shift, bort time.
//   RoutineScope — RoutineLayer: cards, lists, days.
//   TraceScope   — TraceLayer: trace fields, checklists, media.
//   FieldScope   — FieldLayer: tree of field nodes, active field.
//   TickerScope  — AppTicker: timers and colon blink.
//   I18nScope    — dictionary: interface strings.
//
// Field awareness. Shift and block toggles now require a fieldId
// (the root node of the field they belong to). The AppContext
// methods accept this ID to correctly route the shift start/stop
// and log it to the journal.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'dart:convert';
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

    // Auto-start shift only if enabled and not already running for
    // this specific field.
    if (going && bort.autoStartShift && !bort.onShift(fieldId)) {
      await journal.log(
        type: JournalType.actor,
        body: jsonEncode({'action': 'shift_start', 'field_id': fieldId}),
      );
      bort.startShift(fieldId);
    }

    await routineLayer.toggleBlock(
      journal,
      routineId,
      kind,
      mutex: bort.mutexRoutines,
      mutexSlots: bort.mutexSlots,
    );
  }

  // ─── Shift ───
  Future<void> toggleShift(int fieldId) async {
    final going = !bort.onShift(fieldId);
    await journal.log(
      type: JournalType.actor,
      body: jsonEncode({
        'action': going ? 'shift_start' : 'shift_stop',
        'field_id': fieldId,
      }),
    );
    if (going) {
      bort.startShift(fieldId);
      return;
    }
    bort.stopShift(fieldId);

    // Walk every routine, but only pause those attached to the
    // field whose shift is stopping.
    for (final r in routineLayer.routines) {
      if (!r.fieldParents.contains(fieldId)) continue;
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
        old.appContext.openRoutine != appContext.openRoutine;
  }
}

// ─── BortScope ───
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

// ─── TickerScope ───
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
