// ═══════════════════════════════════════════════════════════════════
// format.dart — единые форматтеры дат и длительностей.
//
// Всё, что зависит от языка (подписи единиц времени, дни недели),
// берётся чрез переводчик Translate (сие String Function(String)).
//
// Подписи единиц: time.d, time.h, time.m, time.s.
// Дни недели: time.mon, time.tue, time.wed, time.thu, time.fri,
//             time.sat, time.sun.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

typedef Translate = String Function(String key);

// ─── Дата «пн 06.10 10:31» ───
String fmtDate(int unixSec, Translate t) {
  final d = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000);
  final wd = _weekdayKey(d.weekday);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t(wd)} ${two(d.day)}.${two(d.month)} '
      '${two(d.hour)}:${two(d.minute)}';
}

// ─── Дата полная, с годом — для отчёта ───
String fmtDateFull(int unixSec, Translate t) {
  final d = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000);
  final wd = _weekdayKey(d.weekday);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t(wd)} ${two(d.day)}.${two(d.month)}.${d.year} '
      '${two(d.hour)}:${two(d.minute)}';
}

// ─── Короткое время «9ч 03м», «3д 5ч», «03м» ───
String fmtTime(int sec, Translate t) {
  if (sec < 0) sec = 0;
  final days = sec ~/ 86400;
  final hours = (sec % 86400) ~/ 3600;
  final minutes = (sec % 3600) ~/ 60;
  String two(int n) => n.toString().padLeft(2, '0');
  if (days > 0) return '$days${t('time.d')} $hours${t('time.h')}';
  if (hours > 0) return '$hours${t('time.h')} ${two(minutes)}${t('time.m')}';
  return '${two(minutes)}${t('time.m')}';
}

// ─── Формат правки времени: «дд:чч:мм:сс» ───
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

// ─── Разбор правки времени ───
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

// ─── Ключ дня недели ───
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
