import 'dart:convert';
import 'dart:io';

final Map<String, Future<void>> _atomicWriteTails = {};

Future<void> atomicWriteJson(File target, Map<String, dynamic> data) async {
  final key = target.path;
  final previous = _atomicWriteTails[key] ?? Future<void>.value();
  final next = previous.then((_) async {
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
  });
  _atomicWriteTails[key] = next;
  await next;
  if (identical(_atomicWriteTails[key], next)) {
    _atomicWriteTails.remove(key);
  }
}
