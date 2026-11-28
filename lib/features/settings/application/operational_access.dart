import 'package:polyrutina/features/settings/domain/time_series.dart';

abstract interface class OperationalAccess {
  String get deviceId;
  int get firstRunUnixSec;
  Map<String, TimeSeries> get series;

  int nextMediaIndex();
  int nextExportIndex(String objectKey);

  void applySeriesMonth(
    String kind,
    int fieldId,
    int year,
    int month,
    Map<int, int> days,
  );

  void setLastExportId(int id);
  void setLastRereadId(int id);
}
