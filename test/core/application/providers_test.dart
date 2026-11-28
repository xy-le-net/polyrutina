import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polyrutina/core/application/providers.dart';

void main() {
  test('selected tab starts at routines and can be changed', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(selectedTabProvider), 0);

    container.read(selectedTabProvider.notifier).select(2);

    expect(container.read(selectedTabProvider), 2);
  });
}
