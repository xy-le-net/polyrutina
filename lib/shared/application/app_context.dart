import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

final appContextProvider = StateProvider<AppContext?>((ref) => null);

AppContext appContextOf(BuildContext context) {
  final appContext = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(appContextProvider);
  assert(appContext != null, 'Application context is not initialized');
  return appContext!;
}
