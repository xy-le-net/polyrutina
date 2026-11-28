import 'package:path/path.dart' as p;

import 'package:polyrutina/features/export_import/application/export_context.dart';
import 'package:polyrutina/features/export_import/domain/import_manifest.dart';
import 'package:polyrutina/features/routines/domain/routine.dart';

class ReportJson {
  static const int schemaVersion = ImportManifest.schemaVersion;

  static List<Map<String, dynamic>> buildFields(ExportContext app) {
    final out = <Map<String, dynamic>>[];
    for (final node in app.fieldLayer.nodes.values) {
      out.add({
        'id': node.id,
        'name': node.name,
        'parents': node.parents,
        'is_root': node.isRoot,
        'default_root': node.id == app.fieldLayer.rootId,
      });
    }
    return out;
  }

  static Map<String, dynamic> buildSeries(ExportContext app) {
    final out = <String, dynamic>{};
    for (final entry in app.settings.series.entries) {
      final months = <Map<String, dynamic>>[];
      for (final month in entry.value.allMonths(0)) {
        final days = <String, int>{
          for (final day in month.days.entries) day.key.toString(): day.value,
        };
        months.add({
          'field_id': 0,
          'year': month.year,
          'month': month.month,
          'days': days,
        });
      }
      if (months.isNotEmpty) out[entry.key] = months;
    }
    return out;
  }

  static Map<String, dynamic> buildRoutine(
    ExportContext app,
    Routine routine, {
    Map<String, String> mediaNamesByPath = const {},
  }) {
    final settings = app.settings;
    final traces = <Map<String, dynamic>>[];
    for (final trace in app.traceLayer.traces.values) {
      if (trace.deleted || !trace.parents.contains(routine.id)) continue;
      traces.add({
        'slot': trace.slot,
        'kind': trace.kind,
        'text': trace.text,
        'items': trace.items.map((item) => item.toJson()).toList(),
        'files': trace.files
            .map(
              (file) => {
                'kind': file.kind,
                'name':
                    mediaNamesByPath[file.path] ??
                    (file.name.isEmpty ? p.basename(file.path) : file.name),
                if (file.lat != null) 'lat': file.lat,
                if (file.lon != null) 'lon': file.lon,
                if (file.acc != null) 'acc': file.acc,
              },
            )
            .toList(),
      });
    }

    return {
      'schema': schemaVersion,
      'source_device': settings.deviceId,
      'source_first_run': settings.firstRunUnixSec,
      'source_routine_id': routine.id,
      'name': routine.name,
      'flags': routine.flags,
      'completed': routine.completed,
      'created_at': routine.createdAt,
      'last_action_at': routine.lastActionAt,
      'last_pulse_at': routine.lastPulseAt,
      'completed_at': routine.completedAt,
      'scheduled_at': routine.scheduledAt,
      'notice_before_sec': routine.noticeBeforeSec,
      'notice_set': routine.noticeSet,
      'field_parents': routine.fieldParents,
      'blocks': [
        for (final block in routine.blocks)
          {
            'kind': block.kind,
            'accumulator': block.accumulatorSeconds,
            'time_edited': block.timeEdited,
          },
      ],
      'traces': traces,
    };
  }
}
