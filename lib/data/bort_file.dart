// ═══════════════════════════════════════════════════════════════════
// bort_file.dart — файл борта.
//
// Путь, чтение, отложенная запись operational_layer.json. Поля
// снимает и кладёт сам слой: сей модуль знает токмо Map.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

  // ─── Чтение ───
  Future<Map<String, dynamic>?> read() async {
    if (_file == null || !await _file!.exists()) return null;
    try {
      final raw = await _file!.readAsString();
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ─── Отложенная запись ───
  // builder зовётся при срабатывании таймера: карта собирается
  // из актуальных полей слоя.
  void schedule(Map<String, dynamic> Function() builder) {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 200), () {
      write(builder());
    });
  }

  // ─── Немедленная запись ───
  Future<void> writeNow(Map<String, dynamic> Function() builder) async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await write(builder());
  }

  Future<void> write(Map<String, dynamic> data) async {
    if (_file == null) return;
    try {
      await _file!.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  Future<void> delete() async {
    if (_file == null) return;
    if (await _file!.exists()) {
      await _file!.delete();
    }
  }
}
