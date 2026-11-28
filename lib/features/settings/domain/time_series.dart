import 'dart:async';

import 'package:polyrutina/features/settings/application/time_series_repository.dart';

class TimeSeries {
  TimeSeries(this._repository);

  final TimeSeriesRepository _repository;
  // {fieldId: {year: {month: {day: seconds}}}}
  final Map<int, Map<int, Map<int, Map<int, int>>>> _data = {};
  Timer? _saveTimer;

  Future<void> init() async {
    await _load();
  }

  Future<void> _load() async {
    final data = await _repository.load();
    if (data == null) return;
    for (final fKey in data.keys) {
      final fId = int.tryParse(fKey) ?? 0;
      final years = data[fKey];
      if (years is! Map) continue;
      for (final yKey in years.keys) {
        final y = int.tryParse(yKey.toString());
        if (y == null) continue;
        final months = years[yKey];
        if (months is! Map) continue;
        for (final mKey in months.keys) {
          final m = int.tryParse(mKey.toString());
          if (m == null) continue;
          final days = months[mKey];
          if (days is! Map) continue;
          final dayMap = <int, int>{};
          for (final dKey in days.keys) {
            final d = int.tryParse(dKey.toString());
            if (d == null) continue;
            final v = (days[dKey] as num?)?.toInt() ?? 0;
            if (v > 0) dayMap[d] = v;
          }
          if (dayMap.isEmpty) continue;
          _data.putIfAbsent(fId, () => {}).putIfAbsent(y, () => {})[m] = dayMap;
        }
      }
    }
  }

  Future<void> _save() async {
    final out = <String, dynamic>{};
    for (final fe in _data.entries) {
      final fOut = <String, dynamic>{};
      for (final ye in fe.value.entries) {
        final months = <String, dynamic>{};
        for (final me in ye.value.entries) {
          final days = <String, int>{};
          for (final de in me.value.entries) {
            if (de.value > 0) days[de.key.toString()] = de.value;
          }
          if (days.isNotEmpty) months[me.key.toString()] = days;
        }
        if (months.isNotEmpty) fOut[ye.key.toString()] = months;
      }
      if (fOut.isNotEmpty) out[fe.key.toString()] = fOut;
    }
    await _repository.save(out);
  }

  void addDay(
    int fieldId,
    int year,
    int month,
    int day,
    int seconds, {
    bool persist = true,
  }) {
    if (seconds <= 0) return;
    _data
            .putIfAbsent(fieldId, () => {})
            .putIfAbsent(year, () => {})
            .putIfAbsent(month, () => {})[day] =
        seconds;
    if (persist) _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 200), () {
      unawaited(_save());
    });
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _save();
  }

  void dispose() {
    _saveTimer?.cancel();
    _saveTimer = null;
  }

  MonthTotals? lastMonth(int fieldId) {
    final fData = _data[fieldId];
    if (fData == null) return null;
    int? bestY;
    int? bestM;
    for (final ye in fData.entries) {
      for (final me in ye.value.entries) {
        if (me.value.isEmpty) continue;
        if (bestY == null ||
            ye.key > bestY ||
            (ye.key == bestY && me.key > bestM!)) {
          bestY = ye.key;
          bestM = me.key;
        }
      }
    }
    if (bestY == null || bestM == null) return null;
    final dayMap = fData[bestY]![bestM]!;
    return MonthTotals(
      year: bestY,
      month: bestM,
      days: dayMap.map((k, v) => MapEntry(k.toString(), v)),
    );
  }

  // All months present for a field, in chronological order. Used by
  // the compactor to write every month into the journal, so that the
  // full history is preserved rather than only the latest month.
  List<({int year, int month, Map<int, int> days})> allMonths(int fieldId) {
    final out = <({int year, int month, Map<int, int> days})>[];
    final fData = _data[fieldId];
    if (fData == null) return out;
    final years = fData.keys.toList()..sort();
    for (final y in years) {
      final months = fData[y]!;
      final ms = months.keys.toList()..sort();
      for (final m in ms) {
        final days = months[m]!;
        if (days.isEmpty) continue;
        out.add((year: y, month: m, days: Map<int, int>.from(days)));
      }
    }
    return out;
  }

  Map<int, int> daysFor(int fieldId, int year, int month) {
    final out = <int, int>{};
    final fData = _data[fieldId];
    if (fData == null) return out;
    final months = fData[year];
    if (months == null) return out;
    final days = months[month];
    if (days == null) return out;
    for (final e in days.entries) {
      if (e.value > 0) out[e.key] = e.value;
    }
    return out;
  }

  void pruneBefore(int fieldId, MonthTotals keep) {
    final fData = _data[fieldId];
    if (fData == null) return;
    fData.removeWhere((y, months) {
      if (y < keep.year) return true;
      if (y > keep.year) return false;
      months.removeWhere((m, _) => m < keep.month);
      return months.isEmpty;
    });
    _scheduleSave();
  }

  void reset() {
    _data.clear();
    _scheduleSave();
  }
}

class MonthTotals {
  final int year;
  final int month;
  final Map<String, int> days;
  MonthTotals({required this.year, required this.month, required this.days});
}
