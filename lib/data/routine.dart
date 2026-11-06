// ═══════════════════════════════════════════════════════════════════
// lib/data/routine.dart — routine and its blocks.
//
// Routine: id, name, creation time, last action time, last
// effective pulse time, completion-install time, scheduled date,
// notice interval, five blocks, flags, completion flag, sourceKey,
// fieldParents (nodes of the field graph this routine is attached to),
// and lastBlockKind.
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
// scheduledAt. Planned end date (Unix seconds). Zero or null means
// absent.
//
// noticeBeforeSec. Notice interval: how long before the due date
// the user should be reminded. This replaces the former
// «plannedSeconds» (planned duration) — the pult now sets a lead
// time, not a target effort. Zero is a valid value («remind right
// at the due moment»); whether a notice was actually set is told
// apart by noticeSet.
//
// noticeSet. True when a notice interval was explicitly assigned.
// This is what makes «overdue» distinguishable from «never had a
// notice»: zero seconds is a legitimate interval, so the flag,
// not the number, carries the fact of assignment. Cleared when
// the date is cleared, per the spec.
//
// flags. JournalFlag bits. Edited in the card.
//
// completed. Completion flag. Set in the «summary» block.
//
// sourceKey. Identifier of the source routine this one was
// imported from: «deviceId/firstRun/routineId» of the exporting
// device. Empty for routines created natively or via duplication.
//
// fieldParents. Identifiers of the field nodes (graph vertices)
// to which this routine is attached. An empty list means the
// routine is unattached; the UI treats such a routine as belonging
// to no field (and the notification body labels it «shared»).
//
// lastBlockKind. The kind of the most recently active block.
//
// timeEdited (per block). True when time was edited manually.
//
// isOverdue. A derived predicate: the due date has passed, the
// routine is not completed, and a notice was set. This drives the
// first-place, doubled-frame rendering in the routines list and
// the overdue push at startup.
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

  // Notice interval, in seconds before the due date. Zero is a
  // legitimate value; noticeSet, not the number, carries the fact
  // that a notice was assigned.
  int noticeBeforeSec;
  bool noticeSet;

  int flags;
  bool completed;

  String sourceKey;
  List<int> fieldParents;
  String? lastBlockKind;

  Routine({
    required this.id,
    this.name = '',
    required this.createdAt,
    required this.blocks,
    int? lastActionAt,
    this.lastPulseAt,
    this.completedAt,
    this.scheduledAt,
    this.noticeBeforeSec = 0,
    this.noticeSet = false,
    this.flags = 0,
    this.completed = false,
    this.sourceKey = '',
    List<int>? fieldParents,
    this.lastBlockKind,
  }) : lastActionAt = lastActionAt ?? createdAt,
       fieldParents = fieldParents ?? [];

  factory Routine.create(
    int id, {
    int? at,
    String sourceKey = '',
    int? createdAt,
    List<int>? fieldParents,
  }) {
    final t = at ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return Routine(
      id: id,
      name: '',
      createdAt: createdAt ?? t,
      lastActionAt: t,
      blocks: RoutineBlock.kinds.map((k) => RoutineBlock(kind: k)).toList(),
      sourceKey: sourceKey,
      fieldParents: fieldParents,
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

  // ─── Derived status ───

  // Whether this routine is presently overdue. See the header for
  // the rule: due date passed, not completed, notice was set.
  bool isOverdueAt(int now) {
    if (completed) return false;
    if (!noticeSet) return false;
    final due = scheduledAt;
    if (due == null || due <= 0) return false;
    return due < now;
  }

  bool get isOverdue =>
      isOverdueAt(DateTime.now().millisecondsSinceEpoch ~/ 1000);

  // The moment a notice should fire (unix seconds), or null when
  // the notice is not applicable. Used by the scheduler.
  int? noticeMoment() {
    if (!noticeSet) return null;
    final due = scheduledAt;
    if (due == null || due <= 0) return null;
    return due - noticeBeforeSec;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'created_at': createdAt,
    'last_action_at': lastActionAt,
    'last_pulse_at': lastPulseAt,
    'completed_at': completedAt,
    'scheduled_at': scheduledAt,
    'notice_before_sec': noticeBeforeSec,
    'notice_set': noticeSet,
    'flags': flags,
    'completed': completed,
    'source_key': sourceKey,
    'field_parents': fieldParents,
    'last_block_kind': lastBlockKind,
    'blocks': blocks.map((b) => b.toJson()).toList(),
  };

  // Lenient parsing: a damaged record must not take down the whole
  // cache. Only `id` and `created_at` are mandatory. Both the old
  // planned_seconds and the new notice_before_sec are accepted so
  // that archives built before the rename still load.
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

    // Notice field: prefer the new name, fall back to the old one.
    final rawNotice =
        (j['notice_before_sec'] as num?)?.toInt() ??
        (j['planned_seconds'] as num?)?.toInt() ??
        0;
    final hasNewNoticeFlag = j.containsKey('notice_set');
    final bool noticeSet;
    if (hasNewNoticeFlag) {
      noticeSet = j['notice_set'] as bool? ?? false;
    } else {
      // Old archives carried no explicit flag; a non-zero interval
      // is the historical signal of assignment. Zero seconds was
      // never a real value under the old semantics.
      noticeSet = rawNotice > 0;
    }

    return Routine(
      id: id,
      name: j['name'] as String? ?? '',
      createdAt: createdAt,
      lastActionAt: (j['last_action_at'] as num?)?.toInt(),
      lastPulseAt: (j['last_pulse_at'] as num?)?.toInt(),
      completedAt: (j['completed_at'] as num?)?.toInt(),
      scheduledAt: (j['scheduled_at'] as num?)?.toInt(),
      noticeBeforeSec: rawNotice,
      noticeSet: noticeSet,
      flags: (j['flags'] as num?)?.toInt() ?? 0,
      completed: j['completed'] as bool? ?? false,
      sourceKey: j['source_key'] as String? ?? '',
      fieldParents:
          (j['field_parents'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          [],
      lastBlockKind: j['last_block_kind'] as String?,
      blocks: blocks,
    );
  }
}
