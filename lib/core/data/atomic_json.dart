import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

final Map<String, Future<void>> _atomicWriteTails = {};

Future<void> atomicWriteJson(File target, Map<String, dynamic> data) async {
  final key = target.path;
  final previous = _atomicWriteTails[key] ?? Future<void>.value();
  final next = previous.catchError((Object _) {}).then((_) async {
    final tmp = File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await tmp.writeAsString(jsonEncode(data), flush: true);
      await tmp.rename(target.path);
    } catch (error, stackTrace) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (cleanupError, cleanupStackTrace) {
        debugPrint('Failed to remove temporary JSON file: $cleanupError');
        debugPrintStack(stackTrace: cleanupStackTrace);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  });
  _atomicWriteTails[key] = next;
  try {
    await next;
  } finally {
    if (identical(_atomicWriteTails[key], next)) {
      _atomicWriteTails.remove(key);
    }
  }
}
