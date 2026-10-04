// ═══════════════════════════════════════════════════════════════════
// routine.dart — модель рутины и её блоков.
//
// Рутина: идентификатор, имя (может быть пусто), время создания,
// пять блоков. Время рутины = сумма её блоков.
//
// Блок: род (подготовка, переход, выполнение, переход, завершение),
// накопленные секунды, метка старта (если идёт).
//
// Блоки взаимоисключающие — сие поведение обеспечивает UI,
// модель лишь хранит состояния.
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
  int? startedAt; // unix-секунды, null — стоит

  RoutineBlock({
    required this.kind,
    this.accumulatorSeconds = 0,
    this.startedAt,
  });

  bool get isRunning => startedAt != null;

  int get secondsNow {
    if (startedAt == null) return accumulatorSeconds;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return accumulatorSeconds + (now - startedAt!);
  }

  void start() {
    if (startedAt != null) return;
    startedAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  void pause() {
    if (startedAt == null) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    accumulatorSeconds += now - startedAt!;
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

  factory Routine.create(int id) => Routine(
        id: id,
        name: '',
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        blocks: RoutineBlock.kinds.map((k) => RoutineBlock(kind: k)).toList(),
      );

  int get totalSeconds => blocks.fold(0, (s, b) => s + b.secondsNow);

  RoutineBlock? blockOf(String kind) {
    for (final b in blocks) {
      if (b.kind == kind) return b;
    }
    return null;
  }

  // Ежели идёт один блок — вернуть его.
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
