// ═══════════════════════════════════════════════════════════════════
// bort_file.dart — bort file.
//
// Path, reading, deferred writing of operational_layer.json. Fields
// are taken and put by the layer itself: this module knows only Map.
//
// Atomic write. The target file is never written in place: data
// goes to <name>.tmp first, which is then renamed onto the target.
// The shared helper atomicWriteJson is used for this purpose.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'atomic_json.dart';

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

  // ─── Read ───
  Future<Map<String, dynamic>?> read() async {
    if (_file == null || !await _file!.exists()) return null;
    try {
      final raw = await _file!.readAsString();
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ─── Deferred write ───
  // builder is called when the timer fires: the map is assembled
  // from the layer's current fields.
  void schedule(Map<String, dynamic> Function() builder) {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 200), () {
      write(builder());
    });
  }

  // ─── Immediate write ───
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
