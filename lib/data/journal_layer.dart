// ═══════════════════════════════════════════════════════════════════
// journal_layer.dart — слой журнала.
//
// Единственный, кто знает про базу и про формат тела записей.
// Читает журнал после отметки последнего прочитанного, разбирает
// по родам, отдаёт готовое зарегистрированным слоям.
//
// Регистрация. Слой при пуске зовёт register с именем, списком
// родов, что ему интересны, и функцией применения одной записи.
// JournalLayer помнит по каждому слою номер последней отданной
// ему записи — свой у каждого, дабы слой мог отстать и догнать.
//
// Записи. Журнал неизменяем. Правка — новая запись с флагом
// correction, вытесняющая прежнее состояние объекта при воспроизведении.
//
// Поток. JournalLayer подписан на watchAll базы: всякая вставка
// (своя либо чужая, из консоли журнала) тотчас раздаётся слоям.
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

// Функция применения одной записи, коий слой зарегистрировался.
typedef ApplyFn = void Function(JournalData entry);

// Функция сброса памяти слоя — зовётся при полном перечитывании.
typedef ResetFn = void Function();

// ─── Регистрация одного слоя ───
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
  // База. Единственное место в приложении, работающее с нею напрямую.
  final AppDb db;
  JournalLayer(this.db);

  // Зарегистрированные слои по имени.
  final Map<String, _LayerReg> _layers = {};

  // Сохранённые отметки, прочитанные из файла при init.
  // Регистрация слоёв происходит после init, потому отметки держим
  // отдельно, дабы в register восстановить нужную.
  final Map<String, int> _savedIds = {};

  // Файл отметок.
  File? _stateFile;

  // Флаг, гасящий параллельные заходы pump.
  bool _pumping = false;

  // Подписка на поток журнала.
  StreamSubscription<List<JournalData>>? _sub;

  // ─── Пуск ───
  // Читает сохранённые отметки, подписывается на поток.
  // Регистрация слоёв — после сего, в main.
  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _stateFile = File(p.join(dir.path, 'journal_layer.json'));
    await _loadState();
    _sub = watchAll().listen((_) => pump());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ─── Регистрация ───
  // Зовётся слоем при пуске. Восстанавливает прежнюю отметку,
  // коли она сохранена.
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
  // Читает всё после наименьшей отметки среди слоёв, проходит
  // по записям и раздаёт каждому слою его роды. Отметка слоя
  // движется по всем прочитанным записям, даже ежели род не его:
  // слой «видел» запись и пропустил по роду.
  //
  // Цикл повторяется, покуда не перестанут появляться новые записи
  // (могли лечь в журнал во время разбора).
  Future<void> pump() async {
    if (_pumping) return;
    if (_layers.isEmpty) return;
    _pumping = true;
    try {
      while (true) {
        final minLast =
            _layers.values.map((l) => l.lastId).reduce((a, b) => a < b ? a : b);
        final entries = await entriesAfter(minLast);
        if (entries.isEmpty) break;
        for (final e in entries) {
          for (final l in _layers.values) {
            if (e.id <= l.lastId) continue;
            if (l.types.contains(e.type)) {
              try {
                l.apply(e);
              } catch (_) {
                // Битые записи не роняют разбор: пропускаем.
              }
            }
            l.lastId = e.id;
          }
        }
      }
    } finally {
      _pumping = false;
    }
    await _saveState();
    notifyListeners();
  }

  // ─── Полное перечитывание ───
  // Зовётся по кнопке «перечитать» в рубке либо по запросу слоя.
  // Сбрасывает память слоёв, обнуляет отметки, воспроизводит заново.
  Future<void> reread() async {
    for (final l in _layers.values) {
      l.reset?.call();
      l.lastId = 0;
    }
    await _saveState();
    await pump();
  }

  // ─── Запись ───
  // Единственный способ что-либо занести в журнал.
  // Возвращает номер записи — он же идентификатор создаваемого
  // объекта (рутины, следа и подобного).
  Future<int> log({
    required int type,
    String body = '{}',
    int flags = 0,
  }) async {
    final id = await db.into(db.journal).insert(JournalCompanion.insert(
          time: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          flags: Value(flags),
          type: type,
          body: body,
        ));
    await pump();
    return id;
  }

  // ─── Чтение (для вкладок и рубки) ───
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
    return (db.select(db.journal)..orderBy([(t) => OrderingTerm.asc(t.id)]))
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

  // ─── Управление (из рубки) ───
  Future<({int count, int bytes})> size() async {
    final all = await db.select(db.journal).get();
    final c = all.length;
    final b =
        all.fold<int>(0, (s, e) => s + e.body.length) + c * kJournalOverhead;
    return (count: c, bytes: b);
  }

  Future<void> clearAll() async {
    await db.delete(db.journal).go();
    for (final l in _layers.values) {
      l.reset?.call();
      l.lastId = 0;
    }
    await _saveState();
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
    notifyListeners();
  }

  Future<int> countSynced() async {
    final rows = await db.select(db.journal).get();
    return rows.where((r) => (r.flags & JournalFlag.synced) != 0).length;
  }

  Future<void> markSynced(int id) async {
    final row = await (db.select(db.journal)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return;
    final newFlags = row.flags | JournalFlag.synced;
    await (db.update(db.journal)..where((t) => t.id.equals(id)))
        .write(JournalCompanion(flags: Value(newFlags)));
  }

  // ─── Сохранение отметок ───
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

  Future<void> _saveState() async {
    if (_stateFile == null) return;
    final data = {
      'layers': _layers.map((k, v) => MapEntry(k, v.lastId)),
    };
    await _stateFile!.writeAsString(jsonEncode(data));
  }
}
