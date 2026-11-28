import 'package:polyrutina/features/routines/domain/routine.dart';

class RoutineCache {
  final List<Routine> routines;
  final String? lastActiveBlockKind;
  final bool needsJournalReplay;

  const RoutineCache({
    required this.routines,
    required this.lastActiveBlockKind,
    required this.needsJournalReplay,
  });

  const RoutineCache.empty({this.needsJournalReplay = false})
    : routines = const [],
      lastActiveBlockKind = null;
}

abstract interface class RoutineRepository {
  Future<RoutineCache> load();
  Future<void> save({
    required List<Routine> routines,
    required String? lastActiveBlockKind,
  });
}
