class JournalType {
  static const int trace = 0;
  static const int routine = 1;
  static const int timer = 2;
  static const int actor = 3;
  static const int bort = 4;
  static const int fieldNode = 5;
  static const int template = 6;

  static const List<int> active = [trace, routine, actor, fieldNode, template];

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

class JournalFlag {
  static const int urgent = 1 << 0;
  static const int emergency = 1 << 1;
  static const int important = 1 << 2;
  static const int disputable = 1 << 3;
  static const int complexOp = 1 << 4;
  static const int local = 1 << 5;
  static const int synced = 1 << 6;
  static const int correction = 1 << 7;

  static const int fromServer = 1 << 8;

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

  static const int serviceMask = fromServer;
}

const int kJournalOverhead = 24;
