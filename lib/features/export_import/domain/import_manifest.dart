class ImportManifest {
  const ImportManifest._();

  static const int schemaVersion = 1;

  static ParsedRoutine? parseRoutine(Map<String, dynamic> json) {
    final schema = (json['schema'] as num?)?.toInt();
    if (schema == null || schema > schemaVersion) return null;
    final device = json['source_device'] as String? ?? '';
    final firstRun = (json['source_first_run'] as num?)?.toInt() ?? 0;
    final sourceId = (json['source_routine_id'] as num?)?.toInt();
    if (sourceId == null) return null;

    final fieldParents =
        (json['field_parents'] as List?)
            ?.map((value) => (value as num).toInt())
            .toList() ??
        [];

    final blocks = <ParsedBlock>[];
    final rawBlocks = json['blocks'];
    if (rawBlocks is List) {
      for (final block in rawBlocks) {
        if (block is! Map) continue;
        blocks.add(
          ParsedBlock(
            kind: block['kind'] as String? ?? '',
            accumulator: (block['accumulator'] as num?)?.toInt() ?? 0,
            timeEdited: block['time_edited'] as bool? ?? false,
          ),
        );
      }
    }

    final traces = <ParsedTrace>[];
    final rawTraces = json['traces'];
    if (rawTraces is List) {
      for (final trace in rawTraces) {
        if (trace is! Map) continue;
        final files = <ParsedFile>[];
        final rawFiles = trace['files'];
        if (rawFiles is List) {
          for (final file in rawFiles) {
            if (file is! Map) continue;
            files.add(
              ParsedFile(
                kind: file['kind'] as String? ?? 'file',
                name: file['name'] as String? ?? '',
                lat: (file['lat'] as num?)?.toDouble(),
                lon: (file['lon'] as num?)?.toDouble(),
                acc: (file['acc'] as num?)?.toDouble(),
              ),
            );
          }
        }
        final items = <ParsedItem>[];
        final rawItems = trace['items'];
        if (rawItems is List) {
          for (final item in rawItems) {
            if (item is! Map) continue;
            items.add(
              ParsedItem(
                text: item['text'] as String? ?? '',
                done: item['done'] as bool? ?? false,
              ),
            );
          }
        }
        traces.add(
          ParsedTrace(
            slot: trace['slot'] as String? ?? '',
            kind: trace['kind'] as String? ?? 'text',
            text: trace['text'] as String? ?? '',
            items: items,
            files: files,
          ),
        );
      }
    }

    final hasNewNotice =
        json.containsKey('notice_before_sec') || json.containsKey('notice_set');
    final int noticeBeforeSec;
    final bool noticeSet;
    if (hasNewNotice) {
      noticeBeforeSec = (json['notice_before_sec'] as num?)?.toInt() ?? 0;
      noticeSet = json['notice_set'] as bool? ?? false;
    } else {
      final old = (json['planned_seconds'] as num?)?.toInt() ?? 0;
      noticeBeforeSec = old;
      noticeSet = old > 0;
    }

    return ParsedRoutine(
      sourceDevice: device,
      sourceFirstRun: firstRun,
      sourceRoutineId: sourceId,
      name: json['name'] as String? ?? '',
      flags: (json['flags'] as num?)?.toInt() ?? 0,
      completed: json['completed'] as bool? ?? false,
      createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      lastActionAt: (json['last_action_at'] as num?)?.toInt() ?? 0,
      lastPulseAt: (json['last_pulse_at'] as num?)?.toInt(),
      completedAt: (json['completed_at'] as num?)?.toInt(),
      scheduledAt: (json['scheduled_at'] as num?)?.toInt(),
      noticeBeforeSec: noticeBeforeSec,
      noticeSet: noticeSet,
      fieldParents: fieldParents,
      blocks: blocks,
      traces: traces,
    );
  }

  static List<ParsedMonth> parseSeries(Map<String, dynamic> json) {
    final out = <ParsedMonth>[];
    final raw = json['series'];
    if (raw is! Map) return out;
    for (final kindKey in raw.keys) {
      final kind = kindKey.toString();
      final months = raw[kindKey];
      if (months is! List) continue;
      for (final monthData in months) {
        if (monthData is! Map) continue;
        final fieldId = (monthData['field_id'] as num?)?.toInt() ?? 0;
        final year = (monthData['year'] as num?)?.toInt();
        final month = (monthData['month'] as num?)?.toInt();
        final days = monthData['days'];
        if (year == null || month == null || days is! Map) continue;
        final dayMap = <int, int>{};
        for (final dayKey in days.keys) {
          final day = int.tryParse(dayKey.toString());
          if (day == null) continue;
          final seconds = (days[dayKey] as num?)?.toInt() ?? 0;
          if (seconds > 0) dayMap[day] = seconds;
        }
        if (dayMap.isEmpty) continue;
        out.add(
          ParsedMonth(
            kind: kind,
            fieldId: fieldId,
            year: year,
            month: month,
            days: dayMap,
          ),
        );
      }
    }
    return out;
  }
}

class ParsedMonth {
  const ParsedMonth({
    required this.kind,
    required this.fieldId,
    required this.year,
    required this.month,
    required this.days,
  });

  final String kind;
  final int fieldId;
  final int year;
  final int month;
  final Map<int, int> days;
}

class ParsedRoutine {
  const ParsedRoutine({
    required this.sourceDevice,
    required this.sourceFirstRun,
    required this.sourceRoutineId,
    required this.name,
    required this.flags,
    required this.completed,
    required this.createdAt,
    required this.lastActionAt,
    required this.blocks,
    required this.traces,
    this.lastPulseAt,
    this.completedAt,
    this.scheduledAt,
    this.noticeBeforeSec = 0,
    this.noticeSet = false,
    this.fieldParents = const [],
  });

  final String sourceDevice;
  final int sourceFirstRun;
  final int sourceRoutineId;
  final String name;
  final int flags;
  final bool completed;
  final int createdAt;
  final int lastActionAt;
  final int? lastPulseAt;
  final int? completedAt;
  final int? scheduledAt;
  final int noticeBeforeSec;
  final bool noticeSet;
  final List<int> fieldParents;
  final List<ParsedBlock> blocks;
  final List<ParsedTrace> traces;

  String get key => '$sourceDevice/$sourceFirstRun/$sourceRoutineId';
}

class ParsedBlock {
  const ParsedBlock({
    required this.kind,
    required this.accumulator,
    required this.timeEdited,
  });

  final String kind;
  final int accumulator;
  final bool timeEdited;
}

class ParsedTrace {
  const ParsedTrace({
    required this.slot,
    required this.kind,
    required this.text,
    required this.items,
    required this.files,
  });

  final String slot;
  final String kind;
  final String text;
  final List<ParsedItem> items;
  final List<ParsedFile> files;
}

class ParsedItem {
  const ParsedItem({required this.text, required this.done});

  final String text;
  final bool done;
}

class ParsedFile {
  const ParsedFile({
    required this.kind,
    required this.name,
    this.lat,
    this.lon,
    this.acc,
  });

  final String kind;
  final String name;
  final double? lat;
  final double? lon;
  final double? acc;
}
