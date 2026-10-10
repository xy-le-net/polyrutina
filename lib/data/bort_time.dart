// ═══════════════════════════════════════════════════════════════════
// bort_time.dart — время активной работы в приложении.
//
// Время борта — накопительное за ТЕКУЩИЕ сутки. С полуночи (той,
// что настроена в рубке) до следующей. Живёт в файле борта, в журнал
// не пишется (род «борт» упразднён).
//
// Идёт при действиях с таймаутом в 20 секунд. Бездействие дольше —
// стоп. Сворачивание, закрытие — стоп.
//
// При переходе чрез полуночь: накопленное кладётся в yesterday
// (для показа в рубке), счётчик обнуляется. Проверка — при пуске
// и тикером.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

const int kBortTimeoutSec = 20;

class BortTime {
  // ─── Состояние ───
  // Накопительное за текущие сутки.
  int bortTime = 0;
  // Вчерашний итог — для показа в рубке.
  int yesterday = 0;
  // Миг последнего действия (секунды Unix). 0 — нет действия.
  int lastActionAt = 0;
  // Миг последней прошедшей полуночи (секунды Unix).
  int prevMidnight = 0;

  // Настроенная строка «чч:мм» — начало суток.
  String midnight = '00:00';

  // ─── Действие пользователя ───
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

  // ─── Тик ───
  void tick() {
    if (lastActionAt == 0) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (now - lastActionAt > kBortTimeoutSec) {
      lastActionAt = 0;
    }
  }

  // ─── Свернуть/закрыть ───
  void stopNow() {
    lastActionAt = 0;
  }

  // ─── Проверка полуночи ───
  // Возвращает миг прошедшей полуночи, коли она прошла, иначе 0.
  // При переходе: yesterday = bortTime, bortTime = 0.
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

  // ─── Ближайшая полночь перед моментом ───
  // Публичная — нужна смене.
  int lastMidnightBefore(DateTime now) {
    final parts = midnight.split(':');
    int hh = 0, mm = 0;
    if (parts.length == 2) {
      hh = int.tryParse(parts[0]) ?? 0;
      mm = int.tryParse(parts[1]) ?? 0;
    }
    var candidate = DateTime(now.year, now.month, now.day, hh, mm);
    if (candidate.isAfter(now)) {
      candidate = candidate.subtract(const Duration(days: 1));
    }
    return candidate.millisecondsSinceEpoch ~/ 1000;
  }

  // ─── Сериализация ───
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

  // ─── Сброс ───
  void reset() {
    bortTime = 0;
    yesterday = 0;
    lastActionAt = 0;
    prevMidnight = 0;
  }
}
