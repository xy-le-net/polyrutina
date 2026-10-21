// ═══════════════════════════════════════════════════════════════════
// database.dart — journal table and database class.
//
// Structure only: which fields, which types, where the file lives.
// Reading and writing live in journal_repository.dart.
//
// WAL. The connection is opened in Write-Ahead Logging mode, so
// that readers do not block on writers, and a crash mid-transaction
// cannot corrupt the main file. journal_compactor already relies on
// PRAGMA wal_checkpoint(TRUNCATE); this is the piece that makes
// that checkpoint meaningful. synchronous = NORMAL is a safe
// companion: it preserves database integrity across power loss
// (the last transaction may be lost, but the file stays valid),
// while avoiding the cost of FULL on every commit.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

// ─── Imports ───

// dart:io gives File — disk operations.
import 'dart:io';

// The main drift package: column types (IntColumn, TextColumn),
// the @DriftDatabase annotation, Value, Constant.
import 'package:drift/drift.dart';

// The native SQLite implementation for mobile and desktop.
// Drift uses it to open the database file.
import 'package:drift/native.dart';

// path as p — path utilities: p.join('a', 'b').
import 'package:path/path.dart' as p;

// path_provider — resolve the application's documents folder.
import 'package:path_provider/path_provider.dart';

// ─── Generated part ───
//
// The part directive links this file with database.g.dart,
// which Drift generates after:
//     dart run build_runner build
//
// Without this line, the generated code is not connected, and the
// error "part 'database.g.dart' is missing" appears.
part 'database.g.dart';

// ═══════════════════════════════════════════════════════════════════
// Journal table — the project's single table.
//
// Dogma: the journal is one; all data flows through it. No separate
// tables for routines, traces, timers, or settings.
//
// The entry number (id) serves as the object identifier in links:
// when a trace is attached to a routine block or to another trace,
// the body stores the journal entry number where that object was
// created. This avoids storing "kind + name" pairs.
// ═══════════════════════════════════════════════════════════════════
class Journal extends Table {
  // ─── id field ───
  // Primary key, autoincrement.
  // This is the "detached" (local) entry number.
  // Filled by SQLite itself; no manual assignment.
  // Monotone: used as the object identifier in links.
  IntColumn get id => integer().autoIncrement()();

  // ─── time field ───
  // Timestamp in seconds since the Unix epoch (1 Jan 1970 UTC).
  //
  // Why seconds, not milliseconds:
  //   — sufficient for the journal;
  //   — the number is more compact;
  //   — if higher precision is needed later (two events in one
  //     second), a separate field can be added without breaking the
  //     schema.
  IntColumn get time => integer()();

  // ─── flags field ───
  // Bit field of marks.
  //
  // Eight bits are used:
  //   bit 0 — urgent;
  //   bit 1 — emergency;
  //   bit 2 — important;
  //   bit 3 — disputable;
  //   bit 4 — complex;
  //   bit 5 — local;
  //   bit 6 — synced;
  //   bit 7 — correction (the entry supersedes the object's prior
  //           state rather than creating a new object).
  // The remaining eight bits (8..15) are spare; bit 8 is used by the
  // service (fromServer).
  //
  // withDefault(Constant(0)) means: if flags are not given on insert,
  // store zero.
  IntColumn get flags => integer().withDefault(const Constant(0))();

  // ─── type field ───
  // Entry kind as a number. Decoding lives in journal_types.dart:
  //   0 — trace
  //   1 — routine
  //   2 — reserved (formerly timer)
  //   3 — actor (shift, session)
  //   4 — reserved (formerly bort)
  //
  // Stored as a number, not a string: cheaper and faster.
  IntColumn get type => integer()();

  // ─── body field ───
  // Entry body — a JSON string.
  // Everything related to a given entry lives inside:
  //   — trace:    {"kind":"text","text":"...","parents":[..],"children":[..]}
  //   — routine:  {"action":"create"} and similar
  //   — shift:    {"action":"shift_start"}
  //
  // JSON gives flexibility: fields can be added without database
  // migrations.
  TextColumn get body => text()();
}

// ═══════════════════════════════════════════════════════════════════
// Database class — AppDb.
//
// Drift itself supplies the methods from database.g.dart:
// the journal getter (the table as a query),
// insert, select, update, delete.
//
// All we declare is: which tables the database has and the schema
// version.
// ═══════════════════════════════════════════════════════════════════
@DriftDatabase(tables: [Journal])
class AppDb extends _$AppDb {
  // Constructor: pass the connection method — _openConnection.
  AppDb() : super(_openConnection());

  // Schema version.
  // When the table structure changes, the version must be bumped;
  // otherwise SQLite will not know the structure changed and will
  // not migrate. Currently version one.
  @override
  int get schemaVersion => 1;
}

// ═══════════════════════════════════════════════════════════════════
// _openConnection — where the database file physically lives.
//
// Placed in the application's documents folder:
//   Android: /data/data/<package>/app_flutter/polyrutina.sqlite
//   Windows: C:\Users\<user>\Documents\polyrutina.sqlite
//   iOS:     <app sandbox>/Documents/polyrutina.sqlite
//
// LazyDatabase means: the connection opens on the first access to
// the database, not immediately on app start.
//
// WAL mode is enabled here — on the first connection — via a setup
// callback. See the file header for the rationale.
// ═══════════════════════════════════════════════════════════════════
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    // resolve the documents folder
    final dir = await getApplicationDocumentsDirectory();

    // assemble the full path to the database file
    final file = File(p.join(dir.path, 'polyrutina.sqlite'));

    // createInBackground opens the database in a separate isolate,
    // so that heavy queries do not freeze the UI.
    return NativeDatabase.createInBackground(
      file,
      setup: (rawDb) {
        rawDb.execute('PRAGMA journal_mode = WAL');
        rawDb.execute('PRAGMA synchronous = NORMAL');
      },
    );
  });
}
