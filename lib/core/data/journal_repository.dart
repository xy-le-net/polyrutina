import 'package:drift/drift.dart';
import 'package:polyrutina/core/data/database.dart';
import 'package:polyrutina/core/domain/journal_entry.dart';
import 'package:polyrutina/core/domain/journal_types.dart';

abstract interface class JournalRepository {
  Future<T> transaction<T>(Future<T> Function() action);
  Future<int> insert({required int type, required String body, int flags = 0});
  Stream<List<JournalEntry>> watchAll();
  Future<List<JournalEntry>> entriesAfter(int fromId, {int? type});
  Future<List<JournalEntry>> all();
  Future<void> clearEntries();
  Future<int> deleteSynced();
  Future<int> countSynced();
  Future<void> markSynced(int id);
  Future<int> countEntries();
  Future<int> lastEntryId();
  Future<void> reclaimSpace();
}

class DriftJournalRepository implements JournalRepository {
  final AppDb _db;

  DriftJournalRepository(this._db);

  @override
  Future<T> transaction<T>(Future<T> Function() action) =>
      _db.transaction(action);

  @override
  Future<int> insert({required int type, required String body, int flags = 0}) {
    return _db
        .into(_db.journal)
        .insert(
          JournalCompanion.insert(
            time: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            flags: Value(flags),
            type: type,
            body: body,
          ),
        );
  }

  @override
  Stream<List<JournalEntry>> watchAll() {
    return (_db.select(_db.journal)
          ..orderBy([(table) => OrderingTerm.asc(table.id)]))
        .watch()
        .map((rows) => rows.map(_toEntry).toList());
  }

  @override
  Future<List<JournalEntry>> entriesAfter(int fromId, {int? type}) async {
    final rows =
        await (_db.select(_db.journal)
              ..where((table) {
                if (type == null) return table.id.isBiggerThanValue(fromId);
                return table.id.isBiggerThanValue(fromId) &
                    table.type.equals(type);
              })
              ..orderBy([(table) => OrderingTerm.asc(table.id)]))
            .get();
    return rows.map(_toEntry).toList();
  }

  @override
  Future<List<JournalEntry>> all() async {
    final rows = await (_db.select(
      _db.journal,
    )..orderBy([(table) => OrderingTerm.asc(table.id)])).get();
    return rows.map(_toEntry).toList();
  }

  JournalEntry _toEntry(JournalData row) => JournalEntry(
    id: row.id,
    time: row.time,
    flags: row.flags,
    type: row.type,
    body: row.body,
  );

  @override
  Future<void> clearEntries() async {
    await _db.delete(_db.journal).go();
  }

  @override
  Future<int> deleteSynced() {
    return _db.customUpdate(
      'DELETE FROM journal WHERE (flags & ?1) != 0',
      variables: [const Variable<int>(JournalFlag.synced)],
      updates: {_db.journal},
    );
  }

  @override
  Future<int> countSynced() async {
    final count = _db.journal.id.count();
    final query = _db.selectOnly(_db.journal)
      ..addColumns([count])
      ..where(
        _db.journal.flags
            .bitwiseAnd(const Constant(JournalFlag.synced))
            .equals(JournalFlag.synced),
      );
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  @override
  Future<void> markSynced(int id) async {
    await _db.customUpdate(
      'UPDATE journal SET flags = flags | ?1 '
      'WHERE id = ?2 AND (flags & ?1) = 0',
      variables: [const Variable<int>(JournalFlag.synced), Variable<int>(id)],
      updates: {_db.journal},
    );
  }

  @override
  Future<int> countEntries() async {
    final count = _db.journal.id.count();
    final query = _db.selectOnly(_db.journal)..addColumns([count]);
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  @override
  Future<int> lastEntryId() async {
    final rows =
        await (_db.select(_db.journal)
              ..orderBy([(table) => OrderingTerm.desc(table.id)])
              ..limit(1))
            .get();
    return rows.isEmpty ? 0 : rows.first.id;
  }

  @override
  Future<void> reclaimSpace() async {
    await _db.customSelect('PRAGMA wal_checkpoint(TRUNCATE)').get();
    await _db.customStatement('VACUUM');
    await _db.customStatement('PRAGMA optimize');
  }
}
