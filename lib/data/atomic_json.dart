import 'dart:convert';
import 'dart:io';

Future<void> atomicWriteJson(File target, Map<String, dynamic> data) async {
  // A unique temporary name prevents overlapping saves of the same
  // logical file from deleting or replacing each other's snapshot.
  final tmp = File(
    '${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  try {
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(target.path);
  } catch (_) {
    try {
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {}
  }
}
