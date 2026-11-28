import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polyrutina/core/application/providers.dart';
import 'package:polyrutina/core/domain/journal_types.dart';
import 'package:polyrutina/features/routines/application/providers.dart';
import 'package:polyrutina/features/settings/application/providers.dart';

final routineCommandsProvider = Provider<RoutineCommands>(
  RoutineCommands.new,
);

class RoutineCommands {
  final Ref _ref;

  const RoutineCommands(this._ref);

  Future<void> toggleBlockWithShift(int routineId, String kind) async {
    final journal = _ref.read(journalLayerProvider);
    final settings = _ref.read(operationalLayerProvider);
    final routines = _ref.read(routineLayerProvider);
    final routine = routines.findRoutine(routineId);
    final block = routine?.blockOf(kind);
    if (routine == null || block == null) return;

    final going = !block.isRunning;
    if (settings.shiftEnabled &&
        going &&
        settings.mutexShift &&
        !settings.onShift(0)) {
      await journal.log(
        type: JournalType.actor,
        body: jsonEncode({'action': 'shift_start', 'field_id': 0}),
      );
      settings.startShift(0);
    }

    await routines.toggleBlock(
      journal,
      routineId,
      kind,
      mutex: settings.mutexRoutines,
      mutexSlots: settings.mutexSlots,
    );
  }

  Future<void> toggleShift() async {
    final settings = _ref.read(operationalLayerProvider);
    if (!settings.shiftEnabled) return;

    final journal = _ref.read(journalLayerProvider);
    final routines = _ref.read(routineLayerProvider);
    final going = !settings.onShift(0);
    await journal.log(
      type: JournalType.actor,
      body: jsonEncode({
        'action': going ? 'shift_start' : 'shift_stop',
        'field_id': 0,
      }),
    );

    if (going) {
      settings.startShift(0);
      return;
    }

    settings.stopShift(0);
    if (!settings.mutexShift) return;

    for (final routine in routines.routines) {
      for (final block in routine.blocks) {
        if (block.isRunning) {
          await routines.pauseBlock(journal, routine.id, block.kind);
        }
      }
    }
  }
}
