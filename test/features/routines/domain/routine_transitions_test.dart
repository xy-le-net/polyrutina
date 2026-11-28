import 'package:flutter_test/flutter_test.dart';
import 'package:polyrutina/features/routines/domain/routine.dart';

void main() {
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

    routine.reopenAt(170);

    expect(routine.completed, isFalse);
    expect(routine.completedAt, isNull);
    expect(routine.lastActionAt, 170);
  });
}
