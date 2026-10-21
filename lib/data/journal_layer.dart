// ═══════════════════════════════════════════════════════════════════
// journal_layer.dart — журнальный слой.
//
// The single keeper of the database and the entry body format.
//
// Registration. The layer calls register with a name, a list of
// kinds, and an apply function. JournalLayer remembers, per layer,
// the id of the last entry handed to it.
//
// Distribution. pump reads everything after the smallest mark,
// distributes to each layer its kinds, advances the marks.
//
// Subscription. Set up in start, not init — after all layers have
// registered. This avoids dropping early entries.
//
// Transactions. Actions that produce several entries at once are
// wrapped in a transaction. Inside it, log does not run pump;
// pump runs once on leaving the outer transaction.
//
// Sync flags. deleteSynced, countSynced, and markSynced operate via
// SQL conditions (bitwise AND against JournalFlag.synced) rather
// than by loading every row and filtering in Dart. The former
// approach was O(n) in the journal size; this one is O(k) in the
// matched rows.
//
// The journal's size is not measured here: the rubka reads the bort
// files directly. The service "local" flag for bort-side records is
// not set here: the bit JournalFlag.fromServer serves that purpose.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database.dart';
import 'journal_types.dart';

typedef ApplyFn = void Function(JournalData entry);
typedef ResetFn = void Function();

class _LayerReg {
  final List<int> types;
  final ApplyFn apply;
  final ResetFn? reset;
  int lastId;

  _LayerReg({
    required this.types,
    required this.apply,
    this.reset,
    this.lastId = 0,
  });
}

class JournalLayer extends ChangeNotifier {
  final AppDb db;
  JournalLayer(this.db);

  final Map<String, _LayerReg> _layers = {};
  final Map<String, int> _savedIds = {};

  File? _stateFile;
  Timer? _saveTimer;

  bool _stateDirty = false;
  bool _pumping = false;
  int _txDepth = 0;

  StreamSubscription<List<JournalData>>? _sub;

  // ─── Startup ───
  // Subscription is not set up here; it is deferred to start().
  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _stateFile = File(p.join(dir.path, 'journal_layer.json'));
    await _loadState();
  }

  // ─── Subscription ───
  // Called after all layers have registered.
  void start() {
    _sub ??= watchAll().listen((_) => pump());
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  // ─── Registration ───
  void register({
    required String name,
    required List<int> types,
    required ApplyFn apply,
    ResetFn? reset,
  }) {
    _layers[name] = _LayerReg(
      types: types,
      apply: apply,
      reset: reset,
      lastId: _savedIds[name] ?? 0,
    );
  }

  // ─── Transaction ───
  Future<T> transaction<T>(Future<T> Function() action) async {
    _txDepth++;
    try {
      return await db.transaction(action);
    } finally {
      _txDepth--;
      if (_txDepth == 0) await pump();
    }
  }

  // ─── Distribution ───
  Future<void> pump() async {
    if (_pumping) return;
    if (_layers.isEmpty) return;
    _pumping = true;
    try {
      while (true) {
        final minLast = _layers.values
            .map((l) => l.lastId)
            .reduce((a, b) => a < b ? a : b);
        final entries = await entriesAfter(minLast);
        if (entries.isEmpty) break;
        for (final e in entries) {
          for (final l in _layers.values) {
            if (e.id <= l.lastId) continue;
            if (l.types.contains(e.type)) {
              try {
                l.apply(e);
              } catch (_) {}
            }
            l.lastId = e.id;
            _stateDirty = true;
          }
        }
      }
    } finally {
      _pumping = false;
    }
    if (_stateDirty) _scheduleSave();
    notifyListeners();
  }

  // ─── Full reread ───
  Future<void> reread() async {
    for (final l in _layers.values) {
      l.reset?.call();
      l.lastId = 0;
    }
    _savedIds.clear();
    _stateDirty = true;
    await _saveStateNow();
    await pump();
  }

  // ─── Write ───
  Future<int> log({
    required int type,
    String body = '{}',
    int flags = 0,
  }) async {
    final id = await db
        .into(db.journal)
        .insert(
          JournalCompanion.insert(
            time: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            flags: Value(flags),
            type: type,
            body: body,
          ),
        );
    if (_txDepth == 0) await pump();
    return id;
  }

  // ─── Read ───
  Future<List<JournalData>> recent({int limit = 50}) {
    return (db.select(db.journal)
          ..orderBy([(t) => OrderingTerm.desc(t.id)])
          ..limit(limit))
        .get();
  }

  Stream<List<JournalData>> watchRecent({int limit = 50}) {
    return (db.select(db.journal)
          ..orderBy([(t) => OrderingTerm.desc(t.id)])
          ..limit(limit))
        .watch();
  }

  Stream<List<JournalData>> watchAll() {
    return (db.select(
      db.journal,
    )..orderBy([(t) => OrderingTerm.asc(t.id)])).watch();
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
    return (db.select(
      db.journal,
    )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
  }

  // ─── Management ───
  Future<void> clearAll() async {
    await db.delete(db.journal).go();
    for (final l in _layers.values) {
      l.reset?.call();
      l.lastId = 0;
    }
    _savedIds.clear();
    _stateDirty = true;
    await _saveStateNow();
    try {
      await db.customStatement('VACUUM');
    } catch (_) {}
    notifyListeners();
  }

  // Deletes every entry carrying the synced flag. Runs as a single
  // DELETE with a bitwise condition — no full scan in Dart.
  Future<void> deleteSynced() async {
    final n = await db.customUpdate(
      'DELETE FROM journal WHERE (flags & ?1) != 0',
      variables: [const Variable<int>(JournalFlag.synced)],
      updates: {db.journal},
    );
    if (n > 0) notifyListeners();
  }

  // Counts entries carrying the synced flag. COUNT(*) with a bitwise
  // condition — no row transfer into Dart.
  //
  // Type note: bitwiseAnd takes Expression<int> (wrap the mask in
  // Constant), while equals takes a plain int for Expression<int>.
  Future<int> countSynced() async {
    final count = db.journal.id.count();
    final q = db.selectOnly(db.journal)
      ..addColumns([count])
      ..where(
        db.journal.flags
            .bitwiseAnd(const Constant(JournalFlag.synced))
            .equals(JournalFlag.synced),
      );
    final row = await q.getSingle();
    return row.read(count) ?? 0;
  }

  // Sets the synced flag on one entry. A single UPDATE with a bitwise
  // OR; the WHERE clause makes it idempotent — no spurious
  // notification when the flag is already set.
  Future<void> markSynced(int id) async {
    await db.customUpdate(
      'UPDATE journal SET flags = flags | ?1 '
      'WHERE id = ?2 AND (flags & ?1) = 0',
      variables: [const Variable<int>(JournalFlag.synced), Variable<int>(id)],
      updates: {db.journal},
    );
  }

  Future<int> lastEntryId() async {
    final rows =
        await (db.select(db.journal)
              ..orderBy([(t) => OrderingTerm.desc(t.id)])
              ..limit(1))
            .get();
    return rows.isEmpty ? 0 : rows.first.id;
  }

  // ─── Mark saving ───
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 200), () {
      _saveStateNow();
    });
  }

  Future<void> _loadState() async {
    if (_stateFile == null || !await _stateFile!.exists()) return;
    try {
      final raw = await _stateFile!.readAsString();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final layers = data['layers'];
      if (layers is Map) {
        for (final k in layers.keys) {
          final v = layers[k];
          if (v is num) _savedIds[k.toString()] = v.toInt();
        }
      }
    } catch (_) {}
  }

  Future<void> _saveStateNow() async {
    if (_stateFile == null) return;
    final data = {'layers': _layers.map((k, v) => MapEntry(k, v.lastId))};
    await _stateFile!.writeAsString(jsonEncode(data));
    _stateDirty = false;
  }
}
