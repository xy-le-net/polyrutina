// ═══════════════════════════════════════════════════════════════════
// lib/data/routine.dart — routine and its blocks.
//
// Routine: id, name, creation time, last action time, last
// effective pulse time, completion-install time, scheduled date,
// planned man-hours, five blocks, flags, completion flag, and
// sourceKey.
//
// Block: kind, accumulated seconds, start mark, time-edited flag.
//
// lastActionAt. Time of the last action — for sorting.
//
// lastPulseAt. Time of the last effective pulse — on block start
// or stop. Used to pick the day in the «days» calendar, where
// other actions (rename, flag change) must not shift the mark.
//
// completedAt. The moment completion was set; cleared when it is
// unset. The senior measure of the day when the mark is chosen in
// the calendar.
//
// scheduledAt. Planned end date (Unix seconds). Zero means absent.
//
// plannedSeconds. Planned man-hours in seconds; input and output
// in «dd:hh:mm» format (years and months beyond — do not fit,
// but going past 99 days is not prohibited).
//
// flags. JournalFlag bits. Edited in the card.
//
// completed. Completion flag. Set in the «summary» block.
//
// sourceKey. Identifier of the source routine this one was
// imported from: «deviceId/firstRun/routineId» of the exporting
// device. Empty for routines created natively or via duplication.
// Used by import to skip already-present routines, so re-importing
// the same archive is idempotent.
//
// timeEdited (per block). True when time was edited manually.
// Shown underlined. Reset on block start.
//
// Block kinds: prep, transit, work, idle, closeout.
// ═══════════════════════════════════════════════════════════════════

class RoutineBlock {
  static const String prep = 'prep'; // preparation
  static const String transit = 'transit'; // transit
  static const String work = 'work'; // execution
  static const String idle = 'idle'; // idle
  static const String closeout = 'closeout'; // closeout

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

  // Manual time edit. Zero — erasure, the mark is cleared.
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

  factory RoutineBlock.fromJson(Map<String, dynamic> j) {
    final kind = j['kind'];
    if (kind is! String || kind.isEmpty) {
      throw const FormatException('routine block: missing kind');
    }
    return RoutineBlock(
      kind: kind,
      accumulatorSeconds: (j['accumulator'] as num?)?.toInt() ?? 0,
      startedAt: (j['started_at'] as num?)?.toInt(),
      timeEdited: j['time_edited'] as bool? ?? false,
    );
  }
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

  // Identifier of the source routine this one was imported from:
  // «deviceId/firstRun/routineId» of the exporting device. Empty
  // for routines created natively or via duplication. Used by
  // import to skip already-present routines, so re-importing the
  // same archive is idempotent.
  String sourceKey;

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
    this.sourceKey = '',
  }) : lastActionAt = lastActionAt ?? createdAt;

  factory Routine.create(int id, {int? at, String sourceKey = ''}) {
    final t = at ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return Routine(
      id: id,
      name: '',
      createdAt: t,
      lastActionAt: t,
      blocks: RoutineBlock.kinds.map((k) => RoutineBlock(kind: k)).toList(),
      sourceKey: sourceKey,
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
    'source_key': sourceKey,
    'blocks': blocks.map((b) => b.toJson()).toList(),
  };

  // Lenient parsing: a damaged record must not take down the whole
  // cache. Only `id` and `created_at` are mandatory — without them
  // the record cannot be identified or placed on the timeline, so a
  // FormatException is thrown and the caller is expected to skip
  // that single record. Every other field falls back to a sane
  // default, and a malformed block is dropped without discarding
  // its siblings.
  factory Routine.fromJson(Map<String, dynamic> j) {
    final id = (j['id'] as num?)?.toInt();
    final createdAt = (j['created_at'] as num?)?.toInt();
    if (id == null || createdAt == null) {
      throw const FormatException('routine: missing id or created_at');
    }
    final blocks = <RoutineBlock>[];
    final rawBlocks = j['blocks'];
    if (rawBlocks is List) {
      for (final b in rawBlocks) {
        if (b is! Map) continue;
        try {
          blocks.add(RoutineBlock.fromJson(Map<String, dynamic>.from(b)));
        } catch (_) {
          // Skip a single malformed block; keep the rest.
        }
      }
    }
    return Routine(
      id: id,
      name: j['name'] as String? ?? '',
      createdAt: createdAt,
      lastActionAt: (j['last_action_at'] as num?)?.toInt(),
      lastPulseAt: (j['last_pulse_at'] as num?)?.toInt(),
      completedAt: (j['completed_at'] as num?)?.toInt(),
      scheduledAt: (j['scheduled_at'] as num?)?.toInt(),
      plannedSeconds: (j['planned_seconds'] as num?)?.toInt() ?? 0,
      flags: (j['flags'] as num?)?.toInt() ?? 0,
      completed: j['completed'] as bool? ?? false,
      sourceKey: j['source_key'] as String? ?? '',
      blocks: blocks,
    );
  }
}
