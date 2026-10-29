// ═══════════════════════════════════════════════════════════════════
// atomic_json.dart — atomic writing for JSON files.
//
// The target is never written in place: data goes to <name>.tmp
// first, which is then renamed onto the target. On POSIX, rename
// within a single filesystem is atomic, so a crash mid-write cannot
// leave a half-written target — either the old file survives or the
// new one appears whole. On failure, the stray .tmp is removed and
// the original target stays intact.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

Future<void> atomicWriteJson(File target, Map<String, dynamic> data) async {
  final tmp = File('${target.path}.tmp');
  try {
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(target.path);
  } catch (_) {
    try {
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {}
  }
}
