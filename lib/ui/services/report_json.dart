// ═══════════════════════════════════════════════════════════════════
// lib/ui/services/report_json.dart — build and parse of the
// portable routine format.
//
// data.json (schema = 1):
//   {
//     "schema": 1,
//     "fields": [ { "id": 1, "name": "...", "parents": [], "is_root": true } ],
//     "series": {
//       "shift": [ { "field_id": 0, "year": 2026, "month": 11,
//                    "days": { "1": 3600, "2": 7200 } } ],
//       "bort":  [ { "field_id": 0, ... } ]
//     },
//     "routines": [ ... ]
//   }
//
// The `series` block carries every month of every registered time
// series. Shift is unified under field 0; the exporter therefore
// walks only field 0 (the per-field loop is gone), keeping the
// archive compact and the import side unambiguous. Archives produced
// by older builds that contained per-field shift entries are still
// read: the importer collapses them under field 0 (see
// import_service.dart). No schema bump: the routine field rename
// (planned_seconds → notice_before_sec + notice_set) is handled
// leniently at parse time, and old archives carry the old name,
// which the parser accepts.
//
// Notice interval. The former planned duration is now a lead time;
// the JSON carries `notice_before_sec` (integer) and `notice_set`
// (bool). Old archives carry `planned_seconds`; a non-zero value is
// treated as «notice was set», with notice_before_sec taken as-is.
// Because the two concepts are semantically different (duration vs
// lead time), the numeric value is preserved verbatim — archives
// round-trip byte-for-byte, even though the meaning is re-interpreted.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import '../../data/routine.dart';
import '../core/app_scope.dart';

class ReportJson {
  static const int schemaVersion = 1;

  // ─── Build fields array ───
  static List<Map<String, dynamic>> buildFields(AppContext app) {
    final out = <Map<String, dynamic>>[];
    for (final n in app.fieldLayer.nodes.values) {
      out.add({
        'id': n.id,
        'name': n.name,
        'parents': n.parents,
        'is_root': n.isRoot,
      });
    }
    return out;
  }

  // ─── Build series block ───
  // Shift is unified: only field 0 is walked. Bort is always under 0.
  static Map<String, dynamic> buildSeries(AppContext app) {
    final out = <String, dynamic>{};
    for (final entry in app.bort.series.entries) {
      final kind = entry.key;
      final series = entry.value;
      final months = <Map<String, dynamic>>[];
      for (final m in series.allMonths(0)) {
        final days = <String, int>{};
        for (final e in m.days.entries) {
          days[e.key.toString()] = e.value;
        }
        months.add({
          'field_id': 0,
          'year': m.year,
          'month': m.month,
          'days': days,
        });
      }
      if (months.isNotEmpty) out[kind] = months;
    }
    return out;
  }

  // ─── Build a single routine object ───
  static Map<String, dynamic> buildRoutine(AppContext app, Routine r) {
    final bort = app.bort;
    final traces = <Map<String, dynamic>>[];
    for (final t in app.traceLayer.traces.values) {
      if (t.deleted) continue;
      if (!t.parents.contains(r.id)) continue;
      traces.add({
        'slot': t.slot,
        'kind': t.kind,
        'text': t.text,
        'items': t.items.map((e) => e.toJson()).toList(),
        'files': t.files
            .map(
              (f) => {
                'kind': f.kind,
                'name': f.name.isEmpty ? f.path : f.name,
                if (f.lat != null) 'lat': f.lat,
                if (f.lon != null) 'lon': f.lon,
                if (f.acc != null) 'acc': f.acc,
              },
            )
            .toList(),
      });
    }

    return {
      'schema': schemaVersion,
      'source_device': bort.deviceId,
      'source_first_run': bort.firstRunUnixSec,
      'source_routine_id': r.id,
      'name': r.name,
      'flags': r.flags,
      'completed': r.completed,
      'created_at': r.createdAt,
      'last_action_at': r.lastActionAt,
      'last_pulse_at': r.lastPulseAt,
      'completed_at': r.completedAt,
      'scheduled_at': r.scheduledAt,
      'notice_before_sec': r.noticeBeforeSec,
      'notice_set': r.noticeSet,
      'field_parents': r.fieldParents,
      'blocks': [
        for (final b in r.blocks)
          {
            'kind': b.kind,
            'accumulator': b.accumulatorSeconds,
            'time_edited': b.timeEdited,
          },
      ],
      'traces': traces,
    };
  }

  // ─── Parse ───
  static ParsedRoutine? parseRoutine(Map<String, dynamic> j) {
    final schema = (j['schema'] as num?)?.toInt();
    if (schema == null || schema > schemaVersion) return null;
    final device = j['source_device'] as String? ?? '';
    final firstRun = (j['source_first_run'] as num?)?.toInt() ?? 0;
    final srcId = (j['source_routine_id'] as num?)?.toInt();
    if (srcId == null) return null;

    final fieldParents =
        (j['field_parents'] as List?)
            ?.map((e) => (e as num).toInt())
            .toList() ??
        [];

    final blocks = <ParsedBlock>[];
    final rawBlocks = j['blocks'];
    if (rawBlocks is List) {
      for (final b in rawBlocks) {
        if (b is! Map) continue;
        blocks.add(
          ParsedBlock(
            kind: b['kind'] as String? ?? '',
            accumulator: (b['accumulator'] as num?)?.toInt() ?? 0,
            timeEdited: b['time_edited'] as bool? ?? false,
          ),
        );
      }
    }

    final traces = <ParsedTrace>[];
    final rawTraces = j['traces'];
    if (rawTraces is List) {
      for (final t in rawTraces) {
        if (t is! Map) continue;
        final files = <ParsedFile>[];
        final rawFiles = t['files'];
        if (rawFiles is List) {
          for (final f in rawFiles) {
            if (f is! Map) continue;
            files.add(
              ParsedFile(
                kind: f['kind'] as String? ?? 'file',
                name: f['name'] as String? ?? '',
                lat: (f['lat'] as num?)?.toDouble(),
                lon: (f['lon'] as num?)?.toDouble(),
                acc: (f['acc'] as num?)?.toDouble(),
              ),
            );
          }
        }
        final items = <ParsedItem>[];
        final rawItems = t['items'];
        if (rawItems is List) {
          for (final it in rawItems) {
            if (it is! Map) continue;
            items.add(
              ParsedItem(
                text: it['text'] as String? ?? '',
                done: it['done'] as bool? ?? false,
              ),
            );
          }
        }
        traces.add(
          ParsedTrace(
            slot: t['slot'] as String? ?? '',
            kind: t['kind'] as String? ?? 'text',
            text: t['text'] as String? ?? '',
            items: items,
            files: files,
          ),
        );
      }
    }

    // Notice: prefer the new pair; fall back to the old name.
    final hasNewNotice =
        j.containsKey('notice_before_sec') || j.containsKey('notice_set');
    final int noticeBeforeSec;
    final bool noticeSet;
    if (hasNewNotice) {
      noticeBeforeSec = (j['notice_before_sec'] as num?)?.toInt() ?? 0;
      noticeSet = j['notice_set'] as bool? ?? false;
    } else {
      final old = (j['planned_seconds'] as num?)?.toInt() ?? 0;
      noticeBeforeSec = old;
      noticeSet = old > 0;
    }

    return ParsedRoutine(
      sourceDevice: device,
      sourceFirstRun: firstRun,
      sourceRoutineId: srcId,
      name: j['name'] as String? ?? '',
      flags: (j['flags'] as num?)?.toInt() ?? 0,
      completed: j['completed'] as bool? ?? false,
      createdAt: (j['created_at'] as num?)?.toInt() ?? 0,
      lastActionAt: (j['last_action_at'] as num?)?.toInt() ?? 0,
      lastPulseAt: (j['last_pulse_at'] as num?)?.toInt(),
      completedAt: (j['completed_at'] as num?)?.toInt(),
      scheduledAt: (j['scheduled_at'] as num?)?.toInt(),
      noticeBeforeSec: noticeBeforeSec,
      noticeSet: noticeSet,
      fieldParents: fieldParents,
      blocks: blocks,
      traces: traces,
    );
  }

  // ─── Parse the series block ───
  // Returns a flat list of month records; an absent or malformed
  // block yields an empty list. Shift entries under non-zero fields
  // are collapsed under 0 at import time (see import_service.dart);
  // the parser returns them verbatim, preserving the field_id.
  static List<ParsedMonth> parseSeries(Map<String, dynamic> data) {
    final out = <ParsedMonth>[];
    final raw = data['series'];
    if (raw is! Map) return out;
    for (final kindKey in raw.keys) {
      final kind = kindKey.toString();
      final months = raw[kindKey];
      if (months is! List) continue;
      for (final m in months) {
        if (m is! Map) continue;
        final fieldId = (m['field_id'] as num?)?.toInt() ?? 0;
        final year = (m['year'] as num?)?.toInt();
        final month = (m['month'] as num?)?.toInt();
        final days = m['days'];
        if (year == null || month == null || days is! Map) continue;
        final dayMap = <int, int>{};
        for (final dk in days.keys) {
          final d = int.tryParse(dk.toString());
          if (d == null) continue;
          final v = (days[dk] as num?)?.toInt() ?? 0;
          if (v > 0) dayMap[d] = v;
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
  final String kind;
  final int fieldId;
  final int year;
  final int month;
  final Map<int, int> days;
  ParsedMonth({
    required this.kind,
    required this.fieldId,
    required this.year,
    required this.month,
    required this.days,
  });
}

class ParsedRoutine {
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

  ParsedRoutine({
    required this.sourceDevice,
    required this.sourceFirstRun,
    required this.sourceRoutineId,
    required this.name,
    required this.flags,
    required this.completed,
    required this.createdAt,
    required this.lastActionAt,
    this.lastPulseAt,
    this.completedAt,
    this.scheduledAt,
    this.noticeBeforeSec = 0,
    this.noticeSet = false,
    this.fieldParents = const [],
    required this.blocks,
    required this.traces,
  });

  String get key => '$sourceDevice/$sourceFirstRun/$sourceRoutineId';
}

class ParsedBlock {
  final String kind;
  final int accumulator;
  final bool timeEdited;
  ParsedBlock({
    required this.kind,
    required this.accumulator,
    required this.timeEdited,
  });
}

class ParsedTrace {
  final String slot;
  final String kind;
  final String text;
  final List<ParsedItem> items;
  final List<ParsedFile> files;
  ParsedTrace({
    required this.slot,
    required this.kind,
    required this.text,
    required this.items,
    required this.files,
  });
}

class ParsedItem {
  final String text;
  final bool done;
  ParsedItem({required this.text, required this.done});
}

class ParsedFile {
  final String kind;
  final String name;
  final double? lat;
  final double? lon;
  final double? acc;
  ParsedFile({
    required this.kind,
    required this.name,
    this.lat,
    this.lon,
    this.acc,
  });
}
