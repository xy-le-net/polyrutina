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
