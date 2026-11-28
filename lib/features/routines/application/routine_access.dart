import 'package:flutter/foundation.dart';
import 'package:polyrutina/core/data/journal_layer.dart';
import 'package:polyrutina/features/routines/domain/routine.dart';

abstract interface class RoutineAccess implements Listenable {
  List<Routine> get routines;
  bool get anyRunning;
  int? get currentRoutineId;
  String? get lastActiveBlockKind;

  Routine? findRoutine(int id);
  Routine? findRoutineBySourceKey(String key);

  Future<Routine?> duplicateRoutine(JournalLayer journal, int sourceId);
  Future<Routine> createRoutine(
    JournalLayer journal, {
    String sourceKey,
    int? createdAt,
    List<int>? fieldParents,
  });
  Future<void> writeSnapshot(JournalLayer journal, Routine routine);
  Future<void> renameRoutine(JournalLayer journal, int id, String name);
  Future<void> deleteRoutine(JournalLayer journal, int id);
  Future<void> setFlags(JournalLayer journal, int id, int flags);
  Future<void> setSchedule(JournalLayer journal, int id, int? at);
  Future<void> setNotice(JournalLayer journal, int id, int seconds);
  Future<void> clearNotice(JournalLayer journal, int id);
  Future<void> attachToField(JournalLayer journal, int routineId, int nodeId);
  Future<void> detachFromField(JournalLayer journal, int routineId, int nodeId);
  Future<void> setCompleted(JournalLayer journal, int id, bool value);
  Future<void> setBlockTime(
    JournalLayer journal,
    int routineId,
    String kind,
    int seconds,
  );
  Future<void> toggleBlock(
    JournalLayer journal,
    int routineId,
    String kind, {
    bool mutex,
    bool mutexSlots,
  });
  Future<void> pauseBlock(JournalLayer journal, int routineId, String kind);
}
