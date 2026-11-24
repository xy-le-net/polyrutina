import 'package:flutter_test/flutter_test.dart';
import 'package:polyrutina/data/routine.dart';

void main() {
  test('scheduled routine notifies at its due moment by default', () {
    final routine = Routine.create(1)..scheduledAt = 1_800_000_000;

    expect(routine.noticeMoment(), 1_800_000_000);
  });

  test('configured lead time moves the notification before the due moment', () {
    final routine = Routine.create(1)
      ..scheduledAt = 1_800_000_000
      ..noticeSet = true
      ..noticeBeforeSec = 3600;

    expect(routine.noticeMoment(), 1_799_996_400);
  });

  test('missing routine blocks are restored from the cache parser', () {
    final routine = Routine.fromJson({
      'id': 7,
      'created_at': 100,
      'blocks': [
        {'kind': 'work', 'accumulator': 12},
      ],
    });

    expect(
      routine.blocks.map((b) => b.kind).toSet(),
      RoutineBlock.kinds.toSet(),
    );
  });

  test(
    'negative and clock-backward block times do not create negative totals',
    () {
      final block = RoutineBlock(kind: 'work', accumulatorSeconds: 5);
      block.start(at: 100);

      expect(block.secondsNowAt(90), 5);
      block.pause(at: 90);
      expect(block.accumulatorSeconds, 5);

      block.setEditedTime(-10);
      expect(block.accumulatorSeconds, 0);
      expect(block.timeEdited, isFalse);
    },
  );
}
