import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'domain and data modules respect feature ownership and domain boundaries',
    () async {
      final featureRoot = Directory('lib/features');
      final files = featureRoot
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
      final violations = <String>[];
      final importPattern = RegExp(
        r'''(?:import|export)\s+['"]package:polyrutina/features/([^/]+)/([^/'"]+)/''',
      );

      for (final file in files) {
        final normalized = file.path.replaceAll('\\', '/');
        final match = RegExp(
          r'/features/([^/]+)/(domain|data)/',
        ).firstMatch(normalized);
        if (match == null) continue;

        final owner = match.group(1)!;
        final source = await file.readAsString();
        for (final dependency in importPattern.allMatches(source)) {
          final target = dependency.group(1)!;
          if (target != owner) {
            violations.add('${file.path} imports feature "$target"');
          } else if (match.group(2) == 'domain' &&
              dependency.group(2) != 'domain') {
            violations.add(
              '${file.path} domain imports an outer feature layer',
            );
          }
        }

        if (match.group(2) == 'domain') {
          final forbidden = RegExp(
            r'''(?:import|export)\s+['"]package:flutter(?:_[^/'"]+)?(?:/|['"])''',
          );
          if (forbidden.hasMatch(source)) {
            violations.add('${file.path} imports Flutter from domain');
          }
        }
      }

      expect(violations, isEmpty, reason: violations.join('\n'));
    },
  );
}
