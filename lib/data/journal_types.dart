// ═══════════════════════════════════════════════════════════════════
// journal_types.dart — роды записей, флаги, константа.
//
// Стабильный файл: к нему обращаются слои и вкладки. Логика чтения
// и записи — в journal_layer.dart. Здесь только перечисления
// и одна константа.
//
// Никаких классов, методов, полей — токмо статические сущности.
// ═══════════════════════════════════════════════════════════════════

// ─── Роды записей ───
// Числа фиксированы: смена рода ломает воспроизведение журнала.
class JournalType {
  static const int trace = 0; // след
  static const int routine = 1; // рутина и её блоки
  static const int timer = 2; // таймер (резерв)
  static const int actor = 3; // смена, сессия
  static const int bort = 4; // настройки борта

  static const List<int> all = [trace, routine, timer, actor, bort];
}

// ─── Биты поля flags ───
// Занято восемь, девять в запасе (8..15).
//   correction — правка: запись вытесняет прежнее состояние объекта.
class JournalFlag {
  static const int urgent = 1 << 0;
  static const int emergency = 1 << 1;
  static const int important = 1 << 2;
  static const int disputable = 1 << 3;
  static const int complexOp = 1 << 4;
  static const int local = 1 << 5;
  static const int synced = 1 << 6;
  static const int correction = 1 << 7;

  static const List<int> all = [
    urgent,
    emergency,
    important,
    disputable,
    complexOp,
    local,
    synced,
    correction,
  ];
}

// Приблизительный расход на одну запись помимо тела.
// Для оценки размера журнала в рубке.
const int kJournalOverhead = 24;
