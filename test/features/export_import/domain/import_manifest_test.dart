import 'package:flutter_test/flutter_test.dart';
import 'package:polyrutina/features/export_import/domain/import_manifest.dart';

void main() {
  test(
    'parses routine metadata, checklist items, and explicit notice state',
    () {
      final routine = ImportManifest.parseRoutine({
        'schema': 1,
        'source_device': 'device',
        'source_first_run': 12,
        'source_routine_id': 34,
        'notice_before_sec': 0,
        'notice_set': true,
        'field_parents': [5],
        'traces': [
          {
            'kind': 'checklist',
            'slot': 'prep',
            'items': [
              {'text': 'Inspect', 'done': true},
            ],
            'files': [
              {'kind': 'geo', 'name': '', 'lat': 10.5, 'lon': -20.25},
            ],
          },
        ],
      });

      expect(routine?.key, 'device/12/34');
      expect(routine?.noticeBeforeSec, 0);
      expect(routine?.noticeSet, isTrue);
      expect(routine?.fieldParents, [5]);
      expect(routine?.traces.single.items.single.done, isTrue);
      expect(routine?.traces.single.files.single.lat, 10.5);
    },
  );

  test('supports legacy notice data and rejects unsupported schemas', () {
    final legacy = ImportManifest.parseRoutine({
      'schema': 1,
      'source_routine_id': 1,
      'planned_seconds': 300,
    });

    expect(legacy?.noticeBeforeSec, 300);
    expect(legacy?.noticeSet, isTrue);
    expect(
      ImportManifest.parseRoutine({
        'schema': ImportManifest.schemaVersion + 1,
        'source_routine_id': 1,
      }),
      isNull,
    );
  });

  test('parses valid month records and ignores empty or malformed months', () {
    final months = ImportManifest.parseSeries({
      'series': {
        'shift': [
          {
            'field_id': 7,
            'year': 2026,
            'month': 11,
            'days': {'28': 120, '29': 0, 'not-a-day': 60},
          },
          {
            'field_id': 7,
            'year': 2026,
            'month': 12,
            'days': {'1': 0},
          },
          {'year': 2026, 'month': 12, 'days': <dynamic>[]},
        ],
      },
    });

    expect(months, hasLength(1));
    expect(months.single.kind, 'shift');
    expect(months.single.fieldId, 7);
    expect(months.single.days, {28: 120});
  });
}
