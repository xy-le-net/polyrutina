// ═══════════════════════════════════════════════════════════════════
// routine.dart — модель рутины и её блоков.
//
// Рутина: идентификатор (номер записи о создании в журнале), имя,
// время создания, время последнего действия, пять блоков, флаги,
// признак завершённости.
//
// Время рутины — сумма её блоков.
//
// Блок: род, накопленные секунды, метка старта.
//
// lastActionAt. Время последнего действия. Служит для сортировки
// списка: покоящиеся по убыванию сего поля.
//
// flags. Биты JournalFlag. Правятся в карточке рутины.
//
// completed. Признак завершённости. Ставится чек-боксом в блоке
// «итог», снимается при пуске любого блока либо повторным касанием.
//
// Роды блоков: prep, transit, work, idle, closeout.
// ═══════════════════════════════════════════════════════════════════

class RoutineBlock {
  static const String prep = 'prep'; // подготовка
  static const String transit = 'transit'; // переход
  static const String work = 'work'; // работа
  static const String idle = 'idle'; // простой
  static const String closeout = 'closeout'; // завершение

  static const List<String> kinds = [prep, transit, work, idle, closeout];

  final String kind;
  int accumulatorSeconds;
  int? startedAt;

  RoutineBlock({
    required this.kind,
    this.accumulatorSeconds = 0,
    this.startedAt,
  });

  bool get isRunning => startedAt != null;

  int secondsNowAt(int now) {
    if (startedAt == null) return accumulatorSeconds;
    return accumulatorSeconds + (now - startedAt!);
  }

  int get secondsNow =>
      secondsNowAt(DateTime.now().millisecondsSinceEpoch ~/ 1000);

  void start({int? at}) {
    if (startedAt != null) return;
    startedAt = at ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  void pause({int? at}) {
    if (startedAt == null) return;
    final t = at ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    accumulatorSeconds += t - startedAt!;
    startedAt = null;
  }

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'accumulator': accumulatorSeconds,
        'started_at': startedAt,
      };

  factory RoutineBlock.fromJson(Map<String, dynamic> j) => RoutineBlock(
        kind: j['kind'] as String,
        accumulatorSeconds: (j['accumulator'] as num?)?.toInt() ?? 0,
        startedAt: (j['started_at'] as num?)?.toInt(),
      );
}

class Routine {
  final int id;
  String name;
  final int createdAt;
  final List<RoutineBlock> blocks;

  // Время последнего действия. Служит для сортировки списка.
  int lastActionAt;

  // Флаги (биты JournalFlag). Правятся в карточке.
  int flags;

  // Признак завершённости. Ставится в блоке «итог».
  bool completed;

  Routine({
    required this.id,
    this.name = '',
    required this.createdAt,
    required this.blocks,
    int? lastActionAt,
    this.flags = 0,
    this.completed = false,
  }) : lastActionAt = lastActionAt ?? createdAt;

  factory Routine.create(int id, {int? at}) {
    final t = at ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return Routine(
      id: id,
      name: '',
      createdAt: t,
      lastActionAt: t,
      blocks: RoutineBlock.kinds.map((k) => RoutineBlock(kind: k)).toList(),
    );
  }

  int get totalSeconds {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return blocks.fold(0, (s, b) => s + b.secondsNowAt(now));
  }

  RoutineBlock? blockOf(String kind) {
    for (final b in blocks) {
      if (b.kind == kind) return b;
    }
    return null;
  }

  RoutineBlock? get runningBlock {
    for (final b in blocks) {
      if (b.isRunning) return b;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'created_at': createdAt,
        'last_action_at': lastActionAt,
        'flags': flags,
        'completed': completed,
        'blocks': blocks.map((b) => b.toJson()).toList(),
      };

  factory Routine.fromJson(Map<String, dynamic> j) => Routine(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? '',
        createdAt: (j['created_at'] as num).toInt(),
        lastActionAt: (j['last_action_at'] as num?)?.toInt(),
        flags: (j['flags'] as num?)?.toInt() ?? 0,
        completed: j['completed'] as bool? ?? false,
        blocks: (j['blocks'] as List)
            .map((b) => RoutineBlock.fromJson(b as Map<String, dynamic>))
            .toList(),
      );
}
