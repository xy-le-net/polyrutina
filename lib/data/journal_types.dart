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
// Роды «таймер» и «борт» упразднены, но числа их сохранены
// зарезервированными: записи прежних версий всё ещё прочтутся.
// Новые записи сих родов не пишутся.
class JournalType {
  static const int trace = 0; // след
  static const int routine = 1; // рутина и её блоки
  static const int timer = 2; // зарезервировано (не пишется)
  static const int actor = 3; // смена, сессия
  static const int bort = 4; // зарезервировано (не пишется)
  static const int fieldNode = 5; // узел поля (дерево)
  static const int template = 6; // шаблон / репертуар

  // Роды, что ныне пишутся.
  static const List<int> active = [trace, routine, actor, fieldNode, template];

  // Все числа подряд — для восстановления по журналу.
  static const List<int> all = [
    trace,
    routine,
    timer,
    actor,
    bort,
    fieldNode,
    template,
  ];
}

// ─── Биты поля flags ───
// Пользовательских восемь (0..7):
//   correction — правка: запись вытесняет прежнее состояние объекта.
// Служебные старшие (8..15):
//   fromServer — запись пришла с «нулевого борта», а не рождена здесь.
//   synced     — запись отправлена на сервер и принята им.
class JournalFlag {
  // пользовательские
  static const int urgent = 1 << 0;
  static const int emergency = 1 << 1;
  static const int important = 1 << 2;
  static const int disputable = 1 << 3;
  static const int complexOp = 1 << 4;
  static const int local = 1 << 5;
  static const int synced = 1 << 6;
  static const int correction = 1 << 7;

  // служебные
  static const int fromServer = 1 << 8;

  // Пользовательские биты — для карточек и подпультов.
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

  // Маска служебных битов: их не трогают из интерфейса.
  static const int serviceMask = fromServer;
}

// Приблизительный расход на одну запись помимо тела.
// Для оценки размера журнала в рубке.
const int kJournalOverhead = 24;
