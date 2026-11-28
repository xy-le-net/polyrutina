import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polyrutina/features/fields/application/providers.dart';
import 'package:polyrutina/features/routines/application/routine_repository.dart';
import 'package:polyrutina/features/routines/application/routine_layer.dart';
import 'package:polyrutina/features/routines/data/json_routine_repository.dart';
import 'package:polyrutina/features/traces/application/providers.dart';

final routineRepositoryProvider = Provider<RoutineRepository>(
  (ref) => JsonRoutineRepository(),
);

final routineLayerProvider = ChangeNotifierProvider<RoutineLayer>((ref) {
  final fields = ref.watch(fieldLayerProvider);
  final traces = ref.watch(traceLayerProvider);
  return RoutineLayer(
    repository: ref.watch(routineRepositoryProvider),
    fieldContext: () =>
        (activeFieldId: fields.activeFieldId, rootId: fields.rootId),
    copyTraces: (journal, sourceId, targetId, slots) => traces.copyForParent(
      journal,
      sourceId: sourceId,
      targetId: targetId,
      slots: slots,
    ),
  );
});
