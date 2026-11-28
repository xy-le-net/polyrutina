class ShiftDailyTotal {
  const ShiftDailyTotal({required this.dayStart, required this.seconds});

  final int dayStart;
  final int seconds;
}

class ShiftAccounting {
  const ShiftAccounting._();

  static int secondsAt({
    required int accumulatedSeconds,
    required int? startedAt,
    required int now,
    required int dayStart,
  }) {
    if (startedAt == null) return accumulatedSeconds;
    final start = startedAt > dayStart ? startedAt : dayStart;
    if (start >= now) return accumulatedSeconds;
    return accumulatedSeconds + now - start;
  }

  static List<ShiftDailyTotal> closeDay({
    required int currentMidnight,
    required int previousMidnight,
    required bool onShift,
    required int? startedAt,
    required int accumulatedSeconds,
  }) {
    final previousDayStart = currentMidnight - Duration.secondsPerDay;
    var runningSeconds = 0;
    if (onShift && startedAt != null) {
      final start = startedAt > previousDayStart ? startedAt : previousDayStart;
      if (start < currentMidnight) {
        runningSeconds = currentMidnight - start;
      }
    }

    final skippedDays =
        previousMidnight > 0 &&
        currentMidnight - previousMidnight > Duration.secondsPerDay;
    if (!skippedDays) {
      final total = _capDay(accumulatedSeconds + runningSeconds);
      return total > 0
          ? [ShiftDailyTotal(dayStart: previousDayStart, seconds: total)]
          : const [];
    }

    final totals = <ShiftDailyTotal>[];
    final previousTotal = _capDay(accumulatedSeconds);
    if (previousMidnight > 0 && previousTotal > 0) {
      totals.add(
        ShiftDailyTotal(dayStart: previousMidnight, seconds: previousTotal),
      );
    }
    final currentTotal = _capDay(runningSeconds);
    if (currentTotal > 0) {
      totals.add(
        ShiftDailyTotal(dayStart: previousDayStart, seconds: currentTotal),
      );
    }
    return totals;
  }

  static int _capDay(int seconds) {
    if (seconds <= 0) return 0;
    return seconds > Duration.secondsPerDay ? Duration.secondsPerDay : seconds;
  }
}
