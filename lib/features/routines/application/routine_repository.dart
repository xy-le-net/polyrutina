import 'package:polyrutina/features/routines/domain/routine.dart';

class RoutineCache {
  final List<Routine> routines;
  final String? lastActiveBlockKind;
  final bool needsJournalReplay;
  // The cache snapshot only covers journal entries through this ID.
  final int lastJournalId;

  const RoutineCache({
    required this.routines,
    required this.lastActiveBlockKind,
    required this.needsJournalReplay,
    this.lastJournalId = 0,
  });

  const RoutineCache.empty({
    this.needsJournalReplay = false,
    this.lastJournalId = 0,
  }) : routines = const [],
       lastActiveBlockKind = null;
}

abstract interface class RoutineRepository {
  Future<RoutineCache> load();
  Future<void> save({
    required List<Routine> routines,
    required String? lastActiveBlockKind,
    required int lastJournalId,
  });
}
