// ═══════════════════════════════════════════════════════════════════
// format.dart — shared formatters for dates, durations, and names.
//
// Everything language-dependent (time-unit labels, weekdays) goes
// through the translator Translate (a String Function(String)).
//
// Unit labels: time.d, time.h, time.m, time.s.
// Weekdays: time.mon, time.tue, time.wed, time.thu, time.fri,
//           time.sat, time.sun.
//
// Leading zero — only on the second number of a pair («3ч 07м»,
// «3д 05ч»). A single number carries no zero («7м», «5с»).
//
// File names. safeFileName strips characters forbidden by the
// filesystem (backslash, slash, colon, asterisk, question mark,
// quote, angle brackets, pipe) and replaces each with an uppercase
// «X». safeFileNameOr additionally falls back to «noname» when the
// result is empty — the convention used by the export report.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

typedef Translate = String Function(String key);

// ─── Date «пн 06.10 10:31» ───
String fmtDate(int unixSec, Translate t) {
  final d = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000);
  final wd = weekdayKey(d.weekday);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t(wd)} ${two(d.day)}.${two(d.month)} '
      '${two(d.hour)}:${two(d.minute)}';
}

// ─── Full date with the year — for the report ───
String fmtDateFull(int unixSec, Translate t) {
  final d = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000);
  final wd = weekdayKey(d.weekday);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t(wd)} ${two(d.day)}.${two(d.month)}.${d.year} '
      '${two(d.hour)}:${two(d.minute)}';
}

// ─── Short time «9ч 03м», «3д 5ч», «7м» ───
String fmtTime(int sec, Translate t) {
  if (sec < 0) sec = 0;
  final days = sec ~/ 86400;
  final hours = (sec % 86400) ~/ 3600;
  final minutes = (sec % 3600) ~/ 60;
  String two(int n) => n.toString().padLeft(2, '0');
  if (days > 0) return '$days${t('time.d')} $hours${t('time.h')}';
  if (hours > 0) return '$hours${t('time.h')} ${two(minutes)}${t('time.m')}';
  return '$minutes${t('time.m')}';
}

// ─── Editable time format: «дд:чч:мм:сс» ───
String fmtEditable(int sec) {
  if (sec < 0) sec = 0;
  final d = sec ~/ 86400;
  final h = (sec % 86400) ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  final s = sec % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  if (d > 0) return '${two(d)}:${two(h)}:${two(m)}:${two(s)}';
  if (h > 0) return '${two(h)}:${two(m)}:${two(s)}';
  return '${two(m)}:${two(s)}';
}

// ─── Editable time parsing ───
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
// Days — up to three digits; hours and minutes — always two.
// The ceiling is 999 days short of a full year.
const int kPlannedMaxSec = 999 * 86400 + 23 * 3600 + 59 * 60;

String fmtPlannedTime(int sec) {
  if (sec < 0) sec = 0;
  if (sec > kPlannedMaxSec) sec = kPlannedMaxSec;
  final d = sec ~/ 86400;
  final h = (sec % 86400) ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return '$d:${two(h)}:${two(m)}';
}

// ─── Planned time parsing ───
// One number — minutes. Two, colon-separated — hours and minutes.
// Three — days, hours, minutes. Any part must be a non-negative
// integer without a digit limit; the canonical reduction happens
// in fmtPlannedTime. Returns seconds; null when the input contains
// non-numeric or negative parts, or the total exceeds the ceiling.
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
// Public: both the formatters above and action_dialog use it.
String weekdayKey(int weekday) {
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

// ─── Forbidden-character replacement ───
// Every occurrence of a filesystem-reserved character is replaced
// with an uppercase «X». No trimming, no fallback: the caller
// decides what to do with an empty result.
String safeFileName(String s) {
  final bad = RegExp(r'[\\/:*?"<>|]');
  return s.replaceAllMapped(bad, (_) => 'X');
}

// ─── Forbidden-character replacement with fallback ───
// Same as safeFileName, but an empty (or whitespace-only) result
// becomes «noname» — the export report's convention.
String safeFileNameOr(String s) {
  final out = safeFileName(s).trim();
  return out.isEmpty ? 'noname' : out;
}
