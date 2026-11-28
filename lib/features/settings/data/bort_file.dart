import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:polyrutina/core/data/atomic_json.dart';

class BortFile {
  File? _file;
  Timer? _saveTimer;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _file = File(p.join(dir.path, 'operational_layer.json'));
  }

  void dispose() {
    _saveTimer?.cancel();
  }

  Future<Map<String, dynamic>?> read() async {
    if (_file == null || !await _file!.exists()) return null;
    try {
      final raw = await _file!.readAsString();
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // builder is called when the timer fires: the map is assembled
  // from the layer's current fields.
  void schedule(Map<String, dynamic> Function() builder) {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 200), () {
      write(builder());
    });
  }

  Future<void> writeNow(Map<String, dynamic> Function() builder) async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await write(builder());
  }

  Future<void> write(Map<String, dynamic> data) async {
    final target = _file;
    if (target == null) return;
    await atomicWriteJson(target, data);
  }

  Future<void> delete() async {
    final target = _file;
    if (target == null) return;
    if (await target.exists()) {
      await target.delete();
    }
  }
}
