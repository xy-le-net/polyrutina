import 'package:flutter_test/flutter_test.dart';
import 'package:polyrutina/features/settings/domain/shift_accounting.dart';

void main() {
  test('counts only elapsed time within the current day', () {
    expect(
      ShiftAccounting.secondsAt(
        accumulatedSeconds: 120,
        startedAt: 50,
        now: 300,
        dayStart: 100,
      ),
      320,
    );
    expect(
      ShiftAccounting.secondsAt(
        accumulatedSeconds: 120,
        startedAt: 400,
        now: 300,
        dayStart: 100,
      ),
      120,
    );
  });

  test('records an ordinary day with its running portion', () {
    expect(
      ShiftAccounting.closeDay(
        currentMidnight: 200000,
        previousMidnight: 113600,
        onShift: true,
        startedAt: 198800,
        accumulatedSeconds: 600,
      ).map((total) => (total.dayStart, total.seconds)).toList(),
      [(113600, 1800)],
    );
  });

  test('caps and separates totals when multiple days were skipped', () {
    expect(
      ShiftAccounting.closeDay(
        currentMidnight: 286400,
        previousMidnight: 100000,
        onShift: true,
        startedAt: 282800,
        accumulatedSeconds: 90000,
      ).map((total) => (total.dayStart, total.seconds)).toList(),
      [(100000, 86400), (200000, 3600)],
    );
  });
}
