import 'package:flutter_test/flutter_test.dart';
import 'package:polyrutina/features/settings/domain/time_series.dart';
import 'package:polyrutina/features/settings/domain/time_series_repository.dart';

void main() {
  test('loads and saves monthly totals through its repository port', () async {
    final repository = _MemoryTimeSeriesRepository({
      '0': {
        '2026': {
          '11': {'28': 1800},
        },
      },
    });
    final series = TimeSeries(repository);

    await series.init();
    expect(series.daysFor(0, 2026, 11), {28: 1800});

    series.addDay(0, 2026, 11, 29, 600);
    await series.saveNow();

    expect(repository.data, {
      '0': {
        '2026': {
          '11': {'28': 1800, '29': 600},
        },
      },
    });
  });
}

class _MemoryTimeSeriesRepository implements TimeSeriesRepository {
  _MemoryTimeSeriesRepository(this.data);

  Map<String, dynamic>? data;

  @override
  Future<Map<String, dynamic>?> load() async => data;

  @override
  Future<void> save(Map<String, dynamic> data) async {
    this.data = data;
  }
}
