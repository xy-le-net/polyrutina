// ═══════════════════════════════════════════════════════════════════
// routine.dart — модель рутины и её блоков.
//
// Рутина: идентификатор, имя, время создания, время последнего
// действия, время последнего отработавшего пульса, время установки
// завершённости, намеченная дата, планируемые человекочасы, пять
// блоков, флаги, признак завершённости.
//
// Блок: род, накопленные секунды, метка старта, признак правки
// времени (timeEdited).
//
// lastActionAt. Время последнего действия — для сортировки.
//
// lastPulseAt. Время последнего отработавшего пульса — при пуске
// либо остановке блока. Служит для выбора дня в календаре «дни»,
// где прочие действия (переименование, смена флагов) не должны
// сдвигать метку.
//
// completedAt. Миг установки завершённости; снимается при снятии
// оной. Старшая мера дня при выборе пометы в календаре.
//
// scheduledAt. Намеченная конечная дата (секунды Unix). Нульозначие
// отсутствия.
//
// plannedSeconds. Планируемые человекочасы в секундах; ввод и вывод
// в формате «дд:чч:мм» (годы и месяцы сверх — не укладываются,
// но за пределы 99 дней выходить не возбраняется).
//
// flags. Биты JournalFlag. Правятся в карточке.
//
// completed. Признак завершённости. Ставится в блоке «итог».
//
// timeEdited (у блока). Истина, ежели время правилось вручную.
// Показывается подчёркнутым. При пуске блока сбрасывается.
//
// Роды блоков: prep, transit, work, idle, closeout.
// ═══════════════════════════════════════════════════════════════════

class RoutineBlock {
  static const String prep = 'prep'; // подготовка
  static const String transit = 'transit'; // переход
  static const String work = 'work'; // выполнение
  static const String idle = 'idle'; // простой
  static const String closeout = 'closeout'; // завершение

  static const List<String> kinds = [prep, transit, work, idle, closeout];

  final String kind;
  int accumulatorSeconds;
  int? startedAt;
  bool timeEdited;

  RoutineBlock({
    required this.kind,
    this.accumulatorSeconds = 0,
    this.startedAt,
    this.timeEdited = false,
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
    timeEdited = false;
  }

  void pause({int? at}) {
    if (startedAt == null) return;
    final t = at ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    accumulatorSeconds += t - startedAt!;
    startedAt = null;
  }

  // Правка времени вручную. Ноль — стирание, пометка снимается.
  void setEditedTime(int seconds) {
    accumulatorSeconds = seconds;
    startedAt = null;
    timeEdited = seconds > 0;
  }

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'accumulator': accumulatorSeconds,
    'started_at': startedAt,
    'time_edited': timeEdited,
  };

  factory RoutineBlock.fromJson(Map<String, dynamic> j) => RoutineBlock(
    kind: j['kind'] as String,
    accumulatorSeconds: (j['accumulator'] as num?)?.toInt() ?? 0,
    startedAt: (j['started_at'] as num?)?.toInt(),
    timeEdited: j['time_edited'] as bool? ?? false,
  );
}

class Routine {
  final int id;
  String name;
  final int createdAt;
  final List<RoutineBlock> blocks;

  int lastActionAt;
  int? lastPulseAt;
  int? completedAt;
  int? scheduledAt;
  int plannedSeconds;

  int flags;
  bool completed;

  Routine({
    required this.id,
    this.name = '',
    required this.createdAt,
    required this.blocks,
    int? lastActionAt,
    this.lastPulseAt,
    this.completedAt,
    this.scheduledAt,
    this.plannedSeconds = 0,
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
    'last_pulse_at': lastPulseAt,
    'completed_at': completedAt,
    'scheduled_at': scheduledAt,
    'planned_seconds': plannedSeconds,
    'flags': flags,
    'completed': completed,
    'blocks': blocks.map((b) => b.toJson()).toList(),
  };

  factory Routine.fromJson(Map<String, dynamic> j) => Routine(
    id: (j['id'] as num).toInt(),
    name: j['name'] as String? ?? '',
    createdAt: (j['created_at'] as num).toInt(),
    lastActionAt: (j['last_action_at'] as num?)?.toInt(),
    lastPulseAt: (j['last_pulse_at'] as num?)?.toInt(),
    completedAt: (j['completed_at'] as num?)?.toInt(),
    scheduledAt: (j['scheduled_at'] as num?)?.toInt(),
    plannedSeconds: (j['planned_seconds'] as num?)?.toInt() ?? 0,
    flags: (j['flags'] as num?)?.toInt() ?? 0,
    completed: j['completed'] as bool? ?? false,
    blocks: (j['blocks'] as List)
        .map((b) => RoutineBlock.fromJson(b as Map<String, dynamic>))
        .toList(),
  );
}
