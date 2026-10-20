// ═══════════════════════════════════════════════════════════════════
// app_scope.dart — application context for tabs.
//
// Layers: bort, routineLayer, traceLayer, journal, ticker, i18n.
// Callbacks: refresh, reloadI18n, openRoutine.
//
// toggleShift — the single point of connection between the shift
// and routines. Writes entries of the «actor» kind (shift start/end)
// to the journal for chronology, and moves the local bort layer.
//
// toggleBlockWithShift — starts a block with auto-start of the shift.
//
// pulseBort — notifies the bort about user action.
//
// The logic for pausing all running blocks of a routine has been
// extracted into the private method _pauseAllBlocks to eliminate
// code duplication between toggleShift and toggleBlockWithShift.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/journal_layer.dart';
import '../../data/journal_types.dart';
import '../../data/operational_layer.dart';
import '../../data/routine_layer.dart';
import '../../data/trace_layer.dart';
import '../../data/ticker.dart';
import '../../data/i18n.dart';

class AppContext {
  final OperationalLayer bort;
  final RoutineLayer routineLayer;
  final TraceLayer traceLayer;
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
    required this.journal,
    required this.ticker,
    required this.i18n,
    required this.refresh,
    required this.reloadI18n,
    required this.openRoutine,
  });

  // ─── Pause all running blocks of a routine ───
  // Helper method to stop the current activity in a routine.
  Future<void> _pauseAllBlocks(int routineId) async {
    final r = routineLayer.findRoutine(routineId);
    if (r == null) return;
    for (final b in r.blocks) {
      if (b.isRunning) {
        await routineLayer.pauseBlock(journal, r.id, b.kind);
      }
    }
  }

  // ─── Routine block start with shift connection ───
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

    await routineLayer.toggleBlock(journal, routineId, kind);
  }

  // ─── Shift toggle ───
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
    final cur = routineLayer.currentRoutineId;
    if (cur == null) return;
    await _pauseAllBlocks(cur);
  }

  // ─── User action ───
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
  bool updateShouldNotify(covariant AppScope oldWidget) {
    return true;
  }
}
