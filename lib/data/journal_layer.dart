// ═══════════════════════════════════════════════════════════════════
// journal_layer.dart — слой журнала.
//
// Единственный, кто знает про базу и формат тела записей.
//
// Регистрация. Слой зовёт register с именем, списком родов, функцией
// применения записи. JournalLayer помнит по каждому слою номер
// последней отданной ему записи.
//
// Раздача. pump читает всё после наименьшей отметки, раздаёт каждому
// слою его роды, движет отметки вперёд.
//
// Счёт и объём. entryCount и entryBytes обновляются инкрементально
// при pump — без чтения всей таблицы. Рубка читает их напрямую,
// когда блок «данные» открыт.
//
// Состояние отметок пишется в файл ОТЛОЖЕННО и только когда отметки
// действительно изменились.
//
// Прозрачность не применяется.
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

  // ─── Счёт и объём ───
  // Обновляются инкрементально при pump. Рубка читает напрямую.
  int entryCount = 0;
  int entryBytes = 0;

  File? _stateFile;
  Timer? _saveTimer;

  bool _stateDirty = false;
  bool _pumping = false;
  StreamSubscription<List<JournalData>>? _sub;

  // ─── Пуск ───
  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _stateFile = File(p.join(dir.path, 'journal_layer.json'));
    await _loadState();
    // Начальный пересчёт счёта и объёма.
    await _recomputeStats();
    _sub = watchAll().listen((_) => pump());
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  // ─── Регистрация ───
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

  // ─── Раздача ───
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
          // Обновление счёта и объёма — инкрементально.
          entryCount += 1;
          entryBytes += e.body.length + kJournalOverhead;
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

  // ─── Полное перечитывание ───
  Future<void> reread() async {
    for (final l in _layers.values) {
      l.reset?.call();
      l.lastId = 0;
    }
    _savedIds.clear();
    _stateDirty = true;
    await _saveStateNow();
    await _recomputeStats();
    await pump();
  }

  // ─── Пересчёт счёта и объёма ───
  // Зовётся при пуске и полном перечитывании. При обычной работе
  // счёт движется инкрементально в pump.
  Future<void> _recomputeStats() async {
    final all = await db.select(db.journal).get();
    entryCount = all.length;
    entryBytes =
        all.fold<int>(0, (s, e) => s + e.body.length) +
        entryCount * kJournalOverhead;
  }

  // ─── Запись ───
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
    await pump();
    return id;
  }

  // ─── Чтение ───
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

  // ─── Управление ───
  Future<({int count, int bytes})> size() async {
    return (count: entryCount, bytes: entryBytes);
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
    entryCount = 0;
    entryBytes = 0;
    notifyListeners();
  }

  Future<void> deleteSynced() async {
    final rows = await db.select(db.journal).get();
    final ids = rows
        .where((r) => (r.flags & JournalFlag.synced) != 0)
        .map((r) => r.id)
        .toList();
    if (ids.isEmpty) return;
    await (db.delete(db.journal)..where((t) => t.id.isIn(ids))).go();
    await _recomputeStats();
    notifyListeners();
  }

  Future<int> countSynced() async {
    final rows = await db.select(db.journal).get();
    return rows.where((r) => (r.flags & JournalFlag.synced) != 0).length;
  }

  Future<void> markSynced(int id) async {
    final row = await (db.select(
      db.journal,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    final newFlags = row.flags | JournalFlag.synced;
    await (db.update(db.journal)..where((t) => t.id.equals(id))).write(
      JournalCompanion(flags: Value(newFlags)),
    );
  }

  // Номер последней записи в журнале.
  Future<int> lastEntryId() async {
    final rows =
        await (db.select(db.journal)
              ..orderBy([(t) => OrderingTerm.desc(t.id)])
              ..limit(1))
            .get();
    return rows.isEmpty ? 0 : rows.first.id;
  }

  // ─── Сохранение отметок ───
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
