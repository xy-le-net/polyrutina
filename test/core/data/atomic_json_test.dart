import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:polyrutina/core/data/atomic_json.dart';

void main() {
  test(
    'surfaces write failures and accepts a later write to the same path',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'atomic-json-test-',
      );
      addTearDown(() => directory.delete(recursive: true));

      final target = File(p.join(directory.path, 'cache.json'));
      await Directory(target.path).create();

      await expectLater(
        atomicWriteJson(target, {'value': 1}),
        throwsA(isA<FileSystemException>()),
      );

      await Directory(target.path).delete();
      await atomicWriteJson(target, {'value': 2});

      expect(jsonDecode(await target.readAsString()), {'value': 2});
    },
  );
}
