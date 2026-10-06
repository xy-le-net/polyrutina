// ═══════════════════════════════════════════════════════════════════
// routine.dart — модель рутины и её блоков.
//
// Рутина: идентификатор (номер записи о создании в журнале), имя,
// время создания, время последнего действия, пять блоков.
//
// Время рутины — сумма её блоков.
//
// Блок: род, накопленные секунды, метка старта. Методы start и pause
// принимают необязательный час — для исторического пробега журнала.
//
// lastActionAt. Время последнего действия (пуск либо остановка блока).
// Используется для сортировки списка рутин: покоящиеся сортируются
// по убыванию сего поля. Обновляется слоем при всякой мутации.
//
// Роды блоков: prep, transit, work, idle, closeout. Сии — пять
// рабочих блоков. Шестой и седьмой — note (описание) и summary
// (итог) — не блоки в смысле времени, они части того же блока
// карточки, но без счёта.
// ═══════════════════════════════════════════════════════════════════

class RoutineBlock {
  // Пять рабочих родов.
  static const String prep = 'prep'; // подготовка
  static const String transit = 'transit'; // переход (идёт работа)
  static const String work = 'work'; // работа
  static const String idle = 'idle'; // простой (ожидание)
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

  // Пуск. Ежели at задан — час берётся из него (импорт журнала).
  void start({int? at}) {
    if (startedAt != null) return;
    startedAt = at ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  // Остановка. Ежели at задан — час из него.
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

  // Время последнего действия (пуск либо остановка блока, а также
  // создание и переименование). Обновляется слоем. Служит для
  // сортировки списка: свежайшие сверху.
  int lastActionAt;

  Routine({
    required this.id,
    this.name = '',
    required this.createdAt,
    required this.blocks,
    int? lastActionAt,
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
        'blocks': blocks.map((b) => b.toJson()).toList(),
      };

  factory Routine.fromJson(Map<String, dynamic> j) => Routine(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? '',
        createdAt: (j['created_at'] as num).toInt(),
        lastActionAt: (j['last_action_at'] as num?)?.toInt(),
        blocks: (j['blocks'] as List)
            .map((b) => RoutineBlock.fromJson(b as Map<String, dynamic>))
            .toList(),
      );
}
