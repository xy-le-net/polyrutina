// ═══════════════════════════════════════════════════════════════════
// journal_repository.dart — коды типов, флагов и обёртка над базой.
// ═══════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart';
import 'database.dart';

// ─── Роды записей ───
class JournalType {
  static const int trace = 0;
  static const int routine = 1;
  static const int timer = 2;
  static const int actor = 3;
  static const int bort = 4;

  static const List<int> all = [trace, routine, timer, actor, bort];
}

// ─── Биты поля flags ───
class JournalFlag {
  static const int urgent = 1 << 0;
  static const int emergency = 1 << 1;
  static const int important = 1 << 2;
  static const int disputable = 1 << 3;
  static const int complexOp = 1 << 4;
  static const int local = 1 << 5;
  static const int synced = 1 << 6;

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

  // Поток последних записей: обновляется при всяком изменении базы.
  Stream<List<JournalData>> watchRecent({int limit = 50}) {
    return (db.select(db.journal)
          ..orderBy([(t) => OrderingTerm.desc(t.id)])
          ..limit(limit))
        .watch();
  }

  Future<List<JournalData>> entriesAfter(int fromId, {int? type}) {
    return (db.select(db.journal)
          ..where((t) {
            if (type == null) return t.id.isBiggerThanValue(fromId);
            return t.id.isBiggerThanValue(fromId) & t.type.equals(type);
          })
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
  }

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

  Future<int> countSynced() async {
    final rows = await db.select(db.journal).get();
    return rows.where((r) => (r.flags & JournalFlag.synced) != 0).length;
  }

  Future<void> clearAll() async {
    await db.delete(db.journal).go();
  }

  Future<void> deleteSynced() async {
    final rows = await db.select(db.journal).get();
    final ids = rows
        .where((r) => (r.flags & JournalFlag.synced) != 0)
        .map((r) => r.id)
        .toList();
    if (ids.isEmpty) return;
    await (db.delete(db.journal)..where((t) => t.id.isIn(ids))).go();
  }

  Future<void> markSynced(int id) async {
    final row = await (db.select(db.journal)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return;
    final newFlags = row.flags | JournalFlag.synced;
    await (db.update(db.journal)..where((t) => t.id.equals(id)))
        .write(JournalCompanion(flags: Value(newFlags)));
  }
}
