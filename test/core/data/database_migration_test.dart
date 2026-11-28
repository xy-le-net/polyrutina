import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polyrutina/core/data/database.dart';

void main() {
  test('creates the journal type index for a new database', () async {
    final db = AppDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final indexes = await db
        .customSelect(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'index' AND name = 'journal_type_id_idx'",
        )
        .get();

    expect(indexes, hasLength(1));
  });

  test('upgrades version one and preserves existing journal entries', () async {
    final db = AppDb.forTesting(
      NativeDatabase.memory(
        setup: (database) {
          database.execute(
            'CREATE TABLE journal ('
            'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
            'time INTEGER NOT NULL, '
            'flags INTEGER NOT NULL DEFAULT 0, '
            'type INTEGER NOT NULL, '
            'body TEXT NOT NULL)',
          );
          database.execute(
            "INSERT INTO journal (time, flags, type, body) "
            "VALUES (123, 0, 4, '{}')",
          );
          database.execute('PRAGMA user_version = 1');
        },
      ),
    );
    addTearDown(db.close);

    final entries = await db.select(db.journal).get();
    final indexes = await db
        .customSelect(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'index' AND name = 'journal_type_id_idx'",
        )
        .get();

    expect(entries, hasLength(1));
    expect(entries.single.body, '{}');
    expect(indexes, hasLength(1));
  });
}
