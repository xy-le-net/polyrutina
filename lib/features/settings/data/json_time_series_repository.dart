import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:polyrutina/core/data/atomic_json.dart';
import 'package:polyrutina/features/settings/domain/time_series_repository.dart';

class JsonTimeSeriesRepository implements TimeSeriesRepository {
  JsonTimeSeriesRepository(this.fileName);

  final String fileName;

  Future<File?> _target() async {
    final directory = await getApplicationDocumentsDirectory();
    return File(p.join(directory.path, fileName));
  }

  @override
  Future<Map<String, dynamic>?> load() async {
    final target = await _target();
    if (!await target!.exists()) return null;
    try {
      final raw = await target.readAsString();
      final data = jsonDecode(raw);
      return data is Map ? Map<String, dynamic>.from(data) : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(Map<String, dynamic> data) async {
    final target = await _target();
    if (target == null) return;
    await atomicWriteJson(target, data);
  }
}
