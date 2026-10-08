// ═══════════════════════════════════════════════════════════════════
// bort_time.dart — время активной работы в приложении.
//
// Время борта — накопительное за ТЕКУЩИЕ сутки. С полуночи (той,
// что настроена в рубке) до следующей. Живёт в файле борта.
//
// Идёт при действиях с таймаутом в 20 секунд. Бездействие дольше —
// стоп. Сворачивание, закрытие — стоп.
//
// При первом открытии после полуночи:
//   — итог за прошедшие сутки пишется в журнал рода bort с ключом
//     bort_time;
//   — счётчик обнуляется, отсчёт начинается заново.
//
// Метод tickBort вызывается тикером (500 мс). PulseBort — при всяком
// касании. Проверка полуночи — при пуске.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'journal_layer.dart';
import 'journal_types.dart';

// Таймаут бездействия — 20 секунд.
const int kBortTimeoutSec = 20;

class BortTime {
  // ─── Состояние ───
  // Накопительное за текущие сутки.
  int bortTime = 0;
  // Миг последнего действия (секунды Unix). 0 — нет действия.
  int lastActionAt = 0;
  // Миг последней прошедшей полуночи (секунды Unix).
  int prevMidnight = 0;

  // Настроенная строка «чч:мм» — начало суток.
  String midnight = '00:00';

  // ─── Действие пользователя ───
  // Зовётся при касании либо ином действии. Ежели прошло немного
  // с прошлого раза — прибавляет прошедшее к накопленному. Иначе —
  // просто ставит метку (пропуск — не засчитывается).
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
  // Зовётся тикером. Ежели бездействие дольше таймаута — метка
  // сбрасывается: отсчёт стоп.
  void tick() {
    if (lastActionAt == 0) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (now - lastActionAt > kBortTimeoutSec) {
      lastActionAt = 0;
    }
  }

  // ─── Свернуть/закрыть ───
  // При уходе приложения в фон — метка сбрасывается.
  void stopNow() {
    lastActionAt = 0;
  }

  // ─── Проверка полуночи ───
  // Зовётся при пуске. Ежели с прошлой отмеченной полуночи прошло
  // более одной суточной границы — итог прошедших суток пишется
  // в журнал рода bort с ключом bort_time, счётчик обнуляется.
  //
  // Бортовая полночь задаётся строкою midnight (чч:мм). Сие позволяет
  // вести сутки не с 00:00, а с другого часа — для смен, идущих
  // чрез ночь.
  Future<void> checkMidnight(JournalLayer journal) async {
    final now = DateTime.now();
    // Ближайшая прошедшая «полночь» с учётом настроенного часа.
    final curMidnight = _lastMidnightBefore(now);
    if (prevMidnight == 0) {
      // Первый запуск — запоминаем, в журнал не пишем.
      prevMidnight = curMidnight;
      return;
    }
    if (curMidnight <= prevMidnight) return;
    // Прошла хотя бы одна полночь. Итог в журнал.
    await journal.log(
      type: JournalType.bort,
      body:
          '{"key":"bort_time","value":"$bortTime",'
          '"midnight":$curMidnight}',
    );
    bortTime = 0;
    prevMidnight = curMidnight;
  }

  // ─── Ближайшая полночь перед моментом ───
  // Возвращает секунды Unix последней прошедшей «полночи» —
  // настроенной как чч:мм, а не 00:00.
  int _lastMidnightBefore(DateTime now) {
    final parts = midnight.split(':');
    int hh = 0, mm = 0;
    if (parts.length == 2) {
      hh = int.tryParse(parts[0]) ?? 0;
      mm = int.tryParse(parts[1]) ?? 0;
    }
    var candidate = DateTime(now.year, now.month, now.day, hh, mm);
    if (candidate.isAfter(now)) {
      // Ежели настроенная полночь ещё не наступила сегодня —
      // берём вчерашнюю.
      candidate = candidate.subtract(const Duration(days: 1));
    }
    return candidate.millisecondsSinceEpoch ~/ 1000;
  }

  // ─── Сериализация ───
  Map<String, dynamic> toJson() => {
    'bort_time': bortTime,
    'bort_last_action_at': lastActionAt,
    'bort_prev_midnight': prevMidnight,
  };

  void loadJson(Map<String, dynamic> data) {
    bortTime = (data['bort_time'] as num?)?.toInt() ?? 0;
    lastActionAt = (data['bort_last_action_at'] as num?)?.toInt() ?? 0;
    prevMidnight = (data['bort_prev_midnight'] as num?)?.toInt() ?? 0;
  }

  // ─── Сброс ───
  void reset() {
    bortTime = 0;
    lastActionAt = 0;
    prevMidnight = 0;
  }
}
