// ═══════════════════════════════════════════════════════════════════
// journal_repository.dart — коды типов, флагов и обёртка над базой.
//
// Единая точка для записи и чтения журнала.
// ═══════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart';
import 'database.dart';

// ─── Роды записей ───
class JournalType {
  static const int trace = 0; // след: текст, фото, аудио, гео
  static const int routine = 1; // рутина: задача и её ход
  static const int timer = 2; // таймер: пуск, пауза, стоп
  static const int actor = 3; // актор: рождение, смена роли, уход
  static const int bort = 4; // настройка чрез консоль журнала

  static const List<int> all = [trace, routine, timer, actor, bort];
}

// ─── Биты поля flags ───
// Ноль означает «флагов нет»; биты начинаются с единицы.
class JournalFlag {
  static const int urgent = 1 << 0; // 1  срочно
  static const int emergency = 1 << 1; // 2  аварийно
  static const int important = 1 << 2; // 4  важно
  static const int disputable = 1 << 3; // 8  спорно
  static const int complexOp = 1 << 4; // 16 сложно
  static const int local = 1 << 5; // 32 локальное
  static const int synced = 1 << 6; // 64 синхронизировано

  static const List<int> all = [
    urgent,
    emergency,
    important,
    disputable,
    complexOp,
    local,
    synced,
  ];
}

// Надбавка на служебные поля записи.
const int kJournalOverhead = 24;

class JournalRepository {
  final AppDb db;
  JournalRepository(this.db);

  Future<int> log({
    required int type,
    String body = '{}',
    int flags = 0,
  }) {
    return db.into(db.journal).insert(JournalCompanion.insert(
          time: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          flags: Value(flags),
          type: type,
          body: body,
        ));
  }

  Future<List<JournalData>> recent({int limit = 50}) {
    return (db.select(db.journal)
          ..orderBy([(t) => OrderingTerm.desc(t.id)])
          ..limit(limit))
        .get();
  }

  // Записи после указанного id. Ежели type задан — только сего рода.
  Future<List<JournalData>> entriesAfter(int fromId, {int? type}) {
    return (db.select(db.journal)
          ..where((t) {
            if (type == null) return t.id.isBiggerThanValue(fromId);
            return t.id.isBiggerThanValue(fromId) & t.type.equals(type);
          })
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
  }

  // Полный список записей — по возрастанию id.
  // Нужен для пересборки борта с нуля.
  Future<List<JournalData>> all() {
    return (db.select(db.journal)..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
  }

  Future<({int count, int bytes})> size() async {
    final all = await db.select(db.journal).get();
    final c = all.length;
    final b =
        all.fold<int>(0, (s, e) => s + e.body.length) + c * kJournalOverhead;
    return (count: c, bytes: b);
  }

  // Число записей с флагом synced.
  Future<int> countSynced() async {
    final rows = await db.select(db.journal).get();
    return rows.where((r) => (r.flags & JournalFlag.synced) != 0).length;
  }

  // Удалить все записи.
  Future<void> clearAll() async {
    await db.delete(db.journal).go();
  }

  // Удалить только синхронизированные.
  Future<void> deleteSynced() async {
    final rows = await db.select(db.journal).get();
    final ids = rows
        .where((r) => (r.flags & JournalFlag.synced) != 0)
        .map((r) => r.id)
        .toList();
    if (ids.isEmpty) return;
    await (db.delete(db.journal)..where((t) => t.id.isIn(ids))).go();
  }

  // Пометить запись как синхронизированную.
  Future<void> markSynced(int id) async {
    final row = await (db.select(db.journal)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return;
    final newFlags = row.flags | JournalFlag.synced;
    await (db.update(db.journal)..where((t) => t.id.equals(id)))
        .write(JournalCompanion(flags: Value(newFlags)));
  }
}
