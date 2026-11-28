import 'package:flutter_test/flutter_test.dart';
import 'package:polyrutina/features/routines/domain/routine.dart';

void main() {
  test('shows ticker history only after a slot ran', () {
    final routine = Routine.create(1, at: 100);

    expect(routine.hasTicker, isFalse);

    routine.blockOf(RoutineBlock.work)!.setEditedTime(30);
    expect(routine.hasTicker, isFalse);

    routine.startBlockAt(RoutineBlock.prep, 120);
    expect(routine.hasTicker, isTrue);

    routine.pauseBlockAt(RoutineBlock.prep, 150);
    routine.blockOf(RoutineBlock.prep)!.setEditedTime(0);
    expect(routine.hasTicker, isTrue);
  });

  test('starts and pauses a block using supplied time', () {
    final routine = Routine.create(1, at: 100);

    expect(routine.startBlockAt(RoutineBlock.work, 120), isTrue);
    expect(routine.startBlockAt('unknown', 125), isFalse);
    expect(routine.lastActionAt, 120);
    expect(routine.lastPulseAt, 120);
    expect(routine.lastBlockKind, RoutineBlock.work);

    expect(routine.pauseBlockAt(RoutineBlock.work, 155), isTrue);
    expect(routine.pauseBlockAt(RoutineBlock.work, 160), isFalse);
    expect(routine.blockOf(RoutineBlock.work)!.accumulatorSeconds, 35);
  });

  test('completion pauses running blocks and reopening clears completion', () {
    final routine = Routine.create(1, at: 100);
    routine.startBlockAt(RoutineBlock.prep, 110);
    routine.startBlockAt(RoutineBlock.work, 130);

    expect(routine.completeAt(150), [RoutineBlock.prep, RoutineBlock.work]);
    expect(routine.completed, isTrue);
    expect(routine.completedAt, 150);
    expect(routine.blockOf(RoutineBlock.prep)!.accumulatorSeconds, 40);
    expect(routine.blockOf(RoutineBlock.work)!.accumulatorSeconds, 20);
    expect(routine.runningBlock, isNull);

    routine.reopenAt();

    expect(routine.completed, isFalse);
    expect(routine.completedAt, isNull);
    expect(routine.lastActionAt, 150);
  });

  test(
    'editing a running slot preserves its ticker without changing activity',
    () {
      final routine = Routine.create(1, at: 100);
      routine.startBlockAt(RoutineBlock.work, 120);

      routine.blockOf(RoutineBlock.work)!.setEditedTime(70, at: 150);

      final block = routine.blockOf(RoutineBlock.work)!;
      expect(block.isRunning, isTrue);
      expect(block.accumulatorSeconds, 70);
      expect(block.startedAt, 150);
      expect(block.secondsNowAt(160), 80);
      expect(block.timeEdited, isFalse);
      expect(routine.lastActionAt, 120);
    },
  );

  test(
    'legacy last action timestamps normalize to creation or last ticker',
    () {
      final created = Routine.fromJson({
        'id': 1,
        'created_at': 100,
        'last_action_at': 900,
      });
      final ticked = Routine.fromJson({
        'id': 2,
        'created_at': 100,
        'last_action_at': 900,
        'last_pulse_at': 150,
      });

      expect(created.lastActionAt, 100);
      expect(ticked.lastActionAt, 150);
    },
  );
}
