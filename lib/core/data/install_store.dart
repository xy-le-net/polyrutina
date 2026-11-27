import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:polyrutina/core/data/atomic_json.dart';

class InstallStore {
  int firstRunUnixSec = 0;
  String deviceId = '';
  int mediaCounter = 0;

  File? _file;
  Future<void> _saveQueue = Future.value();

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
        mediaCounter = (data['media_counter'] as num?)?.toInt() ?? 0;
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

  // Monotone: every call returns a new value greater than the
  // cause the same index to be reused after a restart. The actual
  // write is queued to prevent race conditions.
  int nextMediaIndex() {
    mediaCounter++;
    _queueSave();
    return mediaCounter;
  }

  void _queueSave() {
    final snapshot = _buildData();
    _saveQueue = _saveQueue.then((_) => _writeData(snapshot));
  }

  Future<void> _save() async {
    final snapshot = _buildData();
    await _writeData(snapshot);
    _saveQueue = _saveQueue.then((_) {});
  }

  Map<String, dynamic> _buildData() => {
    'first_run_unix_sec': firstRunUnixSec,
    'device_id': deviceId,
    'media_counter': mediaCounter,
  };

  Future<void> _writeData(Map<String, dynamic> data) async {
    final target = _file;
    if (target == null) return;
    await atomicWriteJson(target, data);
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
