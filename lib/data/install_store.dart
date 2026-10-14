// ═══════════════════════════════════════════════════════════════════
// install_store.dart — установочные данные борта.
//
// Первый запуск (секунды Unix) и идентификатор устройства. Хранятся
// в install.json рядом с прочими файлами борта.
//
// Идентификатор берётся у системы; коли недоступен — случайный,
// заводится при первом пуске.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class InstallStore {
  int firstRunUnixSec = 0;
  String deviceId = '';

  File? _file;

  // ─── Пуск: прочитать либо завести ───
  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _file = File(p.join(dir.path, 'install.json'));

    Map<String, dynamic>? data;
    try {
      if (await _file!.exists()) {
        final raw = await _file!.readAsString();
        data = jsonDecode(raw) as Map<String, dynamic>;
        firstRunUnixSec = (data['first_run_unix_sec'] as num?)?.toInt() ?? 0;
        deviceId = data['device_id'] as String? ?? '';
      }
    } catch (_) {}

    if (firstRunUnixSec == 0) {
      firstRunUnixSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    }
    if (deviceId.isEmpty) {
      final sys = await _readSystemDeviceId();
      deviceId = sys.isNotEmpty ? sys : _randomId();
    }
    await _save();
  }

  Future<void> _save() async {
    if (_file == null) return;
    try {
      await _file!.writeAsString(
        jsonEncode({
          'first_run_unix_sec': firstRunUnixSec,
          'device_id': deviceId,
        }),
      );
    } catch (_) {}
  }

  static Future<String> _readSystemDeviceId() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        return a.id;
      } else if (Platform.isIOS) {
        final i = await info.iosInfo;
        return i.identifierForVendor ?? '';
      } else if (Platform.isWindows) {
        final w = await info.windowsInfo;
        return w.deviceId;
      } else if (Platform.isMacOS) {
        final m = await info.macOsInfo;
        return m.systemGUID ?? '';
      } else if (Platform.isLinux) {
        final l = await info.linuxInfo;
        return l.machineId ?? '';
      }
    } catch (_) {}
    return '';
  }

  static String _randomId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    final b = StringBuffer();
    for (var i = 0; i < 16; i++) {
      b.write(chars[r.nextInt(chars.length)]);
    }
    return b.toString();
  }
}
