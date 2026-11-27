import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:polyrutina/core/data/atomic_json.dart';
import 'package:polyrutina/core/data/database.dart';
import 'package:polyrutina/core/domain/journal_types.dart';

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

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _stateFile = File(p.join(dir.path, 'journal_layer.json'));
    await _loadState();
  }

  void start() {
    _sub ??= watchAll().listen((_) => pump());
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

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

  // Drops the persisted mark for one layer and zeroes its in-memory
  // lastId, so that the next pump replays the journal from the
  // beginning for that layer only. Called by a layer whose cache was
  // discarded (schema bump): otherwise the caught-up mark would
  // short-circuit pump and leave the layer empty.
  void clearMark(String name) {
    _savedIds.remove(name);
    final l = _layers[name];
    if (l != null) l.lastId = 0;
    _stateDirty = true;
    _scheduleSave();
  }

  Future<T> transaction<T>(Future<T> Function() action) async {
    _txDepth++;
    try {
      return await db.transaction(action);
    } finally {
      _txDepth--;
      if (_txDepth == 0) await pump();
    }
  }

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

  Future<void> deleteSynced() async {
    final n = await db.customUpdate(
      'DELETE FROM journal WHERE (flags & ?1) != 0',
      variables: [const Variable<int>(JournalFlag.synced)],
      updates: {db.journal},
    );
    if (n > 0) notifyListeners();
  }

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

  Future<void> markSynced(int id) async {
    await db.customUpdate(
      'UPDATE journal SET flags = flags | ?1 '
      'WHERE id = ?2 AND (flags & ?1) = 0',
      variables: [const Variable<int>(JournalFlag.synced), Variable<int>(id)],
      updates: {db.journal},
    );
  }

  Future<int> countEntries() async {
    final count = db.journal.id.count();
    final q = db.selectOnly(db.journal)..addColumns([count]);
    final row = await q.getSingle();
    return row.read(count) ?? 0;
  }

  Future<int> lastEntryId() async {
    final rows =
        await (db.select(db.journal)
              ..orderBy([(t) => OrderingTerm.desc(t.id)])
              ..limit(1))
            .get();
    return rows.isEmpty ? 0 : rows.first.id;
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 200), _saveStateNow);
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _saveStateNow();
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
    await atomicWriteJson(_stateFile!, data);
    _stateDirty = false;
  }
}
