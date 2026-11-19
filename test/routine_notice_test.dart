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
}
