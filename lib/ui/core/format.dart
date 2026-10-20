// ═══════════════════════════════════════════════════════════════════
// format.dart — unified date and duration formatters.
//
// Everything language-dependent (unit labels, weekdays) is taken via
// the Translate function (String Function(String)).
//
// Unit labels: time.d, time.h, time.m, time.s.
// Weekdays: time.mon, time.tue, time.wed, time.thu, time.fri,
//           time.sat, time.sun.
//
// Leading zero — only on the second number in a pair («3h 07m»,
// «3d 05h»). A standalone number — without a zero («7m», «5s»).
//
// The repeated local two() closures have been extracted into the
// top-level _two() helper to eliminate duplication.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

typedef Translate = String Function(String key);

// ─── Pads a single-digit number with a leading zero ───
String _two(int n) => n.toString().padLeft(2, '0');

// ─── Date «Mon 06.10 10:31» ───
String fmtDate(int unixSec, Translate t) {
  final d = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000);
  final wd = _weekdayKey(d.weekday);
  return '${t(wd)} ${_two(d.day)}.${_two(d.month)} '
      '${_two(d.hour)}:${_two(d.minute)}';
}

// ─── Full date, with year — for the report ───
String fmtDateFull(int unixSec, Translate t) {
  final d = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000);
  final wd = _weekdayKey(d.weekday);
  return '${t(wd)} ${_two(d.day)}.${_two(d.month)}.${d.year} '
      '${_two(d.hour)}:${_two(d.minute)}';
}

// ─── Short time «9h 03m», «3d 5h», «7m» ───
String fmtTime(int sec, Translate t) {
  if (sec < 0) sec = 0;
  final days = sec ~/ 86400;
  final hours = (sec % 86400) ~/ 3600;
  final minutes = (sec % 3600) ~/ 60;
  if (days > 0) return '$days${t('time.d')} $hours${t('time.h')}';
  if (hours > 0) return '$hours${t('time.h')} ${_two(minutes)}${t('time.m')}';
  return '$minutes${t('time.m')}';
}

// ─── Editable time format: «dd:hh:mm:ss» ───
String fmtEditable(int sec) {
  if (sec < 0) sec = 0;
  final d = sec ~/ 86400;
  final h = (sec % 86400) ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  final s = sec % 60;
  if (d > 0) return '${_two(d)}:${_two(h)}:${_two(m)}:${_two(s)}';
  if (h > 0) return '${_two(h)}:${_two(m)}:${_two(s)}';
  return '${_two(m)}:${_two(s)}';
}

// ─── Parse editable time ───
int? parseEditable(String s) {
  final t = s.trim();
  if (t.isEmpty) return 0;
  final parts = t.split(':');
  int? n(int i) => int.tryParse(parts[i]);
  if (parts.length == 1) {
    final a = n(0);
    if (a == null) return null;
    return a;
  }
  if (parts.length == 2) {
    final a = n(0);
    final b = n(1);
    if (a == null || b == null) return null;
    return a * 60 + b;
  }
  if (parts.length == 3) {
    final a = n(0);
    final b = n(1);
    final c = n(2);
    if (a == null || b == null || c == null) return null;
    return a * 3600 + b * 60 + c;
  }
  if (parts.length == 4) {
    final a = n(0);
    final b = n(1);
    final c = n(2);
    final d = n(3);
    if (a == null || b == null || c == null || d == null) return null;
    return a * 86400 + b * 3600 + c * 60 + d;
  }
  return null;
}

// ─── Planned time: «days:hours:minutes» ───
// Days — up to three digits; hours and minutes — always two digits.
// Limit — 999 days less a fraction.
const int kPlannedMaxSec = 999 * 86400 + 23 * 3600 + 59 * 60;

String fmtPlannedTime(int sec) {
  if (sec < 0) sec = 0;
  if (sec > kPlannedMaxSec) sec = kPlannedMaxSec;
  final d = sec ~/ 86400;
  final h = (sec % 86400) ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  return '$d:${_two(h)}:${_two(m)}';
}

// ─── Parse planned time ───
// One number — minutes. Two through a colon — hours and minutes.
// Three — days, hours, minutes. Any part — a non-negative integer
// without a digit limit; canonization — in fmtPlannedTime.
// Returns seconds; null — if characters are non-numeric, negative,
// or the total exceeds the limit.
int? parsePlannedTime(String s) {
  final t = s.trim();
  if (t.isEmpty) return 0;
  final parts = t.split(':');
  int? n(String x) {
    final v = int.tryParse(x.trim());
    if (v == null || v < 0) return null;
    return v;
  }

  int total;
  if (parts.length == 1) {
    final m = n(parts[0]);
    if (m == null) return null;
    total = m * 60;
  } else if (parts.length == 2) {
    final h = n(parts[0]);
    final m = n(parts[1]);
    if (h == null || m == null) return null;
    total = h * 3600 + m * 60;
  } else if (parts.length == 3) {
    final d = n(parts[0]);
    final h = n(parts[1]);
    final m = n(parts[2]);
    if (d == null || h == null || m == null) return null;
    total = d * 86400 + h * 3600 + m * 60;
  } else {
    return null;
  }
  if (total > kPlannedMaxSec) return null;
  return total;
}

// ─── Weekday key ───
String _weekdayKey(int weekday) {
  switch (weekday) {
    case DateTime.monday:
      return 'time.mon';
    case DateTime.tuesday:
      return 'time.tue';
    case DateTime.wednesday:
      return 'time.wed';
    case DateTime.thursday:
      return 'time.thu';
    case DateTime.friday:
      return 'time.fri';
    case DateTime.saturday:
      return 'time.sat';
    case DateTime.sunday:
    default:
      return 'time.sun';
  }
}
