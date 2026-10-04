// ═══════════════════════════════════════════════════════════════════
// routine.dart — модель рутины и её блоков.
//
// Рутина: идентификатор, имя, время создания, пять блоков.
// Время рутины = сумма её блоков.
//
// Блок: род, накопленные секунды, метка старта. Методы start и pause
// принимают необязательный час — для исторического пробега журнала.
// ═══════════════════════════════════════════════════════════════════

class RoutineBlock {
  static const String prep = 'prep';
  static const String trans1 = 'trans1';
  static const String work = 'work';
  static const String trans2 = 'trans2';
  static const String closeout = 'closeout';

  static const List<String> kinds = [prep, trans1, work, trans2, closeout];

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

  Routine({
    required this.id,
    this.name = '',
    required this.createdAt,
    required this.blocks,
  });

  factory Routine.create(int id, {int? at}) => Routine(
        id: id,
        name: '',
        createdAt: at ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
        blocks: RoutineBlock.kinds.map((k) => RoutineBlock(kind: k)).toList(),
      );

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
        'blocks': blocks.map((b) => b.toJson()).toList(),
      };

  factory Routine.fromJson(Map<String, dynamic> j) => Routine(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? '',
        createdAt: (j['created_at'] as num).toInt(),
        blocks: (j['blocks'] as List)
            .map((b) => RoutineBlock.fromJson(b as Map<String, dynamic>))
            .toList(),
      );
}
