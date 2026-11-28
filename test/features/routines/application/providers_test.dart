import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polyrutina/features/fields/application/providers.dart';
import 'package:polyrutina/features/routines/application/providers.dart';
import 'package:polyrutina/features/traces/application/providers.dart';

void main() {
  test('trace updates do not recreate routine state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final routines = container.read(routineLayerProvider);
    final traces = container.read(traceLayerProvider);

    traces.notifyListeners();

    expect(container.read(routineLayerProvider), same(routines));
  });

  test('field updates do not recreate routine state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final routines = container.read(routineLayerProvider);
    final fields = container.read(fieldLayerProvider);

    fields.notifyListeners();

    expect(container.read(routineLayerProvider), same(routines));
  });
}
