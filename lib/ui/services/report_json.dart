// ═══════════════════════════════════════════════════════════════════
// lib/ui/services/report_json.dart — build and parse of the
// portable routine format.
//
// data.json (schema = 1):
//   {
//     "schema": 1,
//     "source_device": "...",
//     "source_first_run": 1234567890,
//     "source_routine_id": 42,
//     "name": "...",
//     "flags": 0,
//     "completed": false,
//     "created_at": 1234567890,
//     "last_action_at": 1234567890,
//     "last_pulse_at": 1234567890,
//     "completed_at": 1234567890,
//     "scheduled_at": 1234567890,
//     "planned_seconds": 0,
//     "blocks": [
//       {"kind":"prep","accumulator":0,"time_edited":false},
//       ...
//     ],
//     "traces": [
//       {"slot":"work","kind":"text","text":"...","items":[],"files":[]},
//       ...
//     ]
//   }
//
// Optional fields (last_pulse_at, completed_at, scheduled_at) are
// null when unset; planned_seconds is always written, zero when
// unset. On the receiving side, null means «absent», and the
// importer uses that to leave the corresponding value untouched.
//
// Files inside traces[].files: {kind, name, lat?, lon?, acc?}. The
// `name` is the file's basename in the archive (media/). `path`
// is not written to JSON: on import the path is assembled locally.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import '../../data/routine.dart';
import '../core/app_scope.dart';

class ReportJson {
  static const int schemaVersion = 1;

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
      'planned_seconds': r.plannedSeconds,
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
      plannedSeconds: (j['planned_seconds'] as num?)?.toInt() ?? 0,
      blocks: blocks,
      traces: traces,
    );
  }
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
  final int plannedSeconds;
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
    this.plannedSeconds = 0,
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
