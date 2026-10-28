// ═══════════════════════════════════════════════════════════════════
// json_io.dart — shared atomic JSON writer.
//
// A single implementation of the «write to .tmp, rename onto target»
// pattern used across all caches (bort file, install store, routine,
// trace, field layers). On POSIX, rename within a single filesystem
// is atomic, so a crash mid-write cannot leave a half-written target:
// either the old file survives or the new one appears whole.
//
// Extracted to eliminate duplication. On failure, the stray .tmp
// file is removed so that a subsequent write is not blocked by it.
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
