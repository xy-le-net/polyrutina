// ═══════════════════════════════════════════════════════════════════
// install_store.dart — installation data of the bort.
//
// First run (Unix seconds) and device id. Stored in install.json
// alongside the other bort files.
//
// Device id is taken from the system; if unavailable — a random
// one, generated on first launch.
//
// media_counter — a monotone counter for media file names. Every
// media file written by the application takes the next value:
//   <kind>_<index>_<deviceId>_<firstRun>.<ext>
// The counter is per device+first-run, monotone and never reused.
// Old install.json files lack the field; they load with zero, and
// the first call to nextMediaIndex() writes one.
//
// Atomic write. The target file is never written in place: data
// goes to <name>.tmp first, which is then renamed onto the target.
// A crash mid-write cannot leave a half-written install.json.
//
// Transparency is not applied.
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
  int mediaCounter = 0;

  File? _file;

  // ─── Startup: read or create ───
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

  // ─── Next media index ───
  // Monotone: every call returns a new value greater than the
  // previous one. The value is persisted at once, so that a crash
  // does not cause the same index to be reused after a restart.
  int nextMediaIndex() {
    mediaCounter++;
    _save();
    return mediaCounter;
  }

  Future<void> _save() async {
    final target = _file;
    if (target == null) return;
    final tmp = File('${target.path}.tmp');
    try {
      await tmp.writeAsString(
        jsonEncode({
          'first_run_unix_sec': firstRunUnixSec,
          'device_id': deviceId,
          'media_counter': mediaCounter,
        }),
        flush: true,
      );
      await tmp.rename(target.path);
    } catch (_) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
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
