const int kBortTimeoutSec = 20;

// Technical noon: the time of day assumed when a scheduled routine
// is given a date without a chosen time. Sits alongside midnight
// as a named moment of the day: midnight opens it, noon bisects it.
const int kBortTechNoonHour = 12;
const int kBortTechNoonMinute = 0;

// Parsed form of the midnight string.
class _ParsedMidnight {
  final int hh;
  final int mm;
  const _ParsedMidnight(this.hh, this.mm);
}

class BortTime {
  // Cumulative for the current day.
  int bortTime = 0;
  // Yesterday's total — for display in the rubka.
  int yesterday = 0;
  // Moment of the last action (Unix seconds). 0 — no action.
  int lastActionAt = 0;
  // Moment of the last passed midnight (Unix seconds).
  int prevMidnight = 0;

  // Configured midnight string (HH:MM) — the start of the day.
  // Backed by a setter that invalidates the parse cache.
  String _midnight = '00:00';
  String get midnight => _midnight;
  set midnight(String v) {
    if (_midnight == v) return;
    _midnight = v;
    _parsedMidnight = null;
  }

  // Parsed cache; null when not yet computed or invalidated.
  _ParsedMidnight? _parsedMidnight;

  _ParsedMidnight _parse() {
    final cached = _parsedMidnight;
    if (cached != null) return cached;
    final parts = _midnight.split(':');
    int hh = 0;
    int mm = 0;
    if (parts.length == 2) {
      hh = int.tryParse(parts[0]) ?? 0;
      mm = int.tryParse(parts[1]) ?? 0;
    }
    final p = _ParsedMidnight(hh, mm);
    _parsedMidnight = p;
    return p;
  }

  void pulse() {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (lastActionAt != 0) {
      final dt = now - lastActionAt;
      if (dt > 0 && dt <= kBortTimeoutSec) {
        bortTime += dt;
      }
    }
    lastActionAt = now;
  }

  void tick() {
    if (lastActionAt == 0) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (now - lastActionAt > kBortTimeoutSec) {
      lastActionAt = 0;
    }
  }

  void stopNow() {
    lastActionAt = 0;
  }

  // Returns the passed midnight moment if it has passed, else 0.
  // On transition: yesterday = bortTime, bortTime = 0.
  int checkMidnight() {
    final now = DateTime.now();
    final curMidnight = lastMidnightBefore(now);
    if (prevMidnight == 0) {
      prevMidnight = curMidnight;
      return 0;
    }
    if (curMidnight <= prevMidnight) return 0;
    yesterday = bortTime;
    bortTime = 0;
    prevMidnight = curMidnight;
    return curMidnight;
  }

  // Public — the shift needs it.
  int lastMidnightBefore(DateTime now) {
    final p = _parse();
    var candidate = DateTime(now.year, now.month, now.day, p.hh, p.mm);
    if (candidate.isAfter(now)) {
      candidate = candidate.subtract(const Duration(days: 1));
    }
    return candidate.millisecondsSinceEpoch ~/ 1000;
  }

  Map<String, dynamic> toJson() => {
    'bort_time': bortTime,
    'bort_yesterday': yesterday,
    'bort_last_action_at': lastActionAt,
    'bort_prev_midnight': prevMidnight,
  };

  void loadJson(Map<String, dynamic> data) {
    bortTime = (data['bort_time'] as num?)?.toInt() ?? 0;
    yesterday = (data['bort_yesterday'] as num?)?.toInt() ?? 0;
    lastActionAt = (data['bort_last_action_at'] as num?)?.toInt() ?? 0;
    prevMidnight = (data['bort_prev_midnight'] as num?)?.toInt() ?? 0;
  }

  void reset() {
    bortTime = 0;
    yesterday = 0;
    lastActionAt = 0;
    prevMidnight = 0;
  }
}
