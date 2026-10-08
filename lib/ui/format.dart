// ═══════════════════════════════════════════════════════════════════
// format.dart — единые форматтеры дат и длительностей.
//
// Собирает в одном месте то, что прежде дублировалось по вкладкам
// и карточкам: даты с днём недели, короткое время («9ч 03м»),
// формат правки («дд:чч:мм:сс») и его разбор.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

// ─── Дата «пн 06.10 10:31» ───
String fmtDate(int unixSec) {
  final d = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000);
  const weekdays = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
  final wd = weekdays[d.weekday - 1];
  String two(int n) => n.toString().padLeft(2, '0');
  return '$wd ${two(d.day)}.${two(d.month)} '
      '${two(d.hour)}:${two(d.minute)}';
}

// ─── Дата полная, с годом — для отчёта ───
String fmtDateFull(int unixSec) {
  final d = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000);
  const weekdays = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
  final wd = weekdays[d.weekday - 1];
  String two(int n) => n.toString().padLeft(2, '0');
  return '$wd ${two(d.day)}.${two(d.month)}.${d.year} '
      '${two(d.hour)}:${two(d.minute)}';
}

// ─── Короткое время «9ч 03м», «3д 5ч», «03м» ───
// Две старшие единицы. Минуты — двузначны, дни и часы — без нуля.
String fmtTime(int sec) {
  if (sec < 0) sec = 0;
  final days = sec ~/ 86400;
  final hours = (sec % 86400) ~/ 3600;
  final minutes = (sec % 3600) ~/ 60;
  String two(int n) => n.toString().padLeft(2, '0');
  if (days > 0) return '${days}д ${hours}ч';
  if (hours > 0) return '${hours}ч ${two(minutes)}м';
  return '${two(minutes)}м';
}

// ─── Формат правки времени: «дд:чч:мм:сс» ───
// Для малых значений — сокращённо.
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
// Принимает «дд:чч:мм:сс», «чч:мм:сс», «мм:сс» и одиночное число
// (секунды). Пусто — ноль (стирание). Ошибка разбора — null.
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
