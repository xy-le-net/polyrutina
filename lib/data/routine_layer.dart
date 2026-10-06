// ═══════════════════════════════════════════════════════════════════
// routine_layer.dart — слой рутин.
//
// Держит список рутин и их блоки. Номер рутины — это номер записи
// о её создании в журнале.
//
// Журнал. Слой не ходит в базу сам: при пуске он регистрируется
// в JournalLayer на род routine. Записи приходят готовыми, применяются
// тотчас.
//
// Кэш. Список рутин пишется в routine_layer.json для ускорения
// старта. При пуске кэш читается, затем накатываются дельты из
// журнала после отметки, что помнит JournalLayer.
//
// lastActionAt. Обновляется при всякой мутации рутины: создание,
// переименование, пуск и остановка блока. Служит для сортировки
// списка рутин: свежайшие сверху.
//
// Блоки взаимоисключающие: пуск одного гасит прочие.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database.dart';
import 'journal_layer.dart';
import 'journal_types.dart';
import 'routine.dart';

class RoutineLayer extends ChangeNotifier {
  // ─── Текущее состояние ───
  List<Routine> routines = [];

  // Номер рутины, в коей идёт блок (для глобального взаимоисключения:
  // идти может токмо одна рутина разом). null — ничего не идёт.
  // Хранится в памяти; восстанавливается из журнала.
  int? currentRoutineId;

  // ─── Служебное ───
  File? _file;

  // Свежайшие сверху по внутреннему порядку id.
  List<Routine> get routinesNewestFirst {
    final copy = List<Routine>.from(routines);
    copy.sort((a, b) => b.id.compareTo(a.id));
    return copy;
  }

  // ─── Пуск ───
  Future<void> init(JournalLayer journal) async {
    final dir = await getApplicationDocumentsDirectory();
    _file = File(p.join(dir.path, 'routine_layer.json'));
    await _loadFromFile();

    journal.register(
      name: 'routine',
      types: [JournalType.routine],
      apply: _applyEntry,
      reset: _resetMemory,
    );

    notifyListeners();
  }

  // ─── Кэш ───
  Future<void> _loadFromFile() async {
    if (_file == null || !await _file!.exists()) return;
    try {
      final raw = await _file!.readAsString();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final r = data['routines'];
      if (r is List) {
        routines =
            r.map((e) => Routine.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
  }

  Future<void> _saveToFile() async {
    if (_file == null) return;
    final data = <String, dynamic>{
      'routines': routines.map((r) => r.toJson()).toList(),
    };
    await _file!.writeAsString(jsonEncode(data));
  }

  // ─── Применение одной записи журнала ───
  // Принимает всю запись: для create номер берётся из e.id, час
  // создания — из e.time. Всякая мутация обновляет lastActionAt
  // (для сортировки списка).
  void _applyEntry(JournalData e) {
    try {
      final data = jsonDecode(e.body) as Map<String, dynamic>;
      final action = data['action'] as String?;
      switch (action) {
        case 'reset':
          routines = [];
          break;
        case 'create':
          final bodyId = (data['routine'] as num?)?.toInt();
          final id = bodyId ?? e.id;
          if (findRoutine(id) == null) {
            routines.add(Routine.create(id, at: e.time));
          }
          break;
        case 'rename':
          final id = (data['routine'] as num).toInt();
          final r = findRoutine(id);
          if (r != null) {
            r.name = data['name'] as String? ?? '';
            r.lastActionAt = e.time;
          }
          break;
        case 'delete':
          final id = (data['routine'] as num).toInt();
          routines.removeWhere((r) => r.id == id);
          break;
        case 'start_block':
          final id = (data['routine'] as num).toInt();
          final kind = data['block'] as String?;
          final at = (data['at'] as num?)?.toInt() ?? e.time;
          final r = findRoutine(id);
          if (r != null && kind != null) {
            r.blockOf(kind)?.start(at: at);
            r.lastActionAt = at;
            currentRoutineId = id;
          }
          break;
        case 'pause_block':
          final id = (data['routine'] as num).toInt();
          final kind = data['block'] as String?;
          final at = (data['at'] as num?)?.toInt() ?? e.time;
          final r = findRoutine(id);
          if (r != null && kind != null) {
            r.blockOf(kind)?.pause(at: at);
            r.lastActionAt = at;
            // Ежели в сей рутине ничего не осталось бегущего — индекс
            // обнуляется: текущая рутина более не идёт.
            if (r.runningBlock == null) currentRoutineId = null;
          }
          break;
      }
    } catch (_) {}
  }

  // Полный сброс памяти (зовётся из JournalLayer.reread).
  void _resetMemory() {
    routines = [];
    currentRoutineId = null;
    notifyListeners();
  }

  // ─── Мутации ───
  // Локально применяем тотчас, запись в журнал шлём чрез JournalLayer.
  // lastActionAt обновляется тотчас для сортировки.

  Future<Routine> createRoutine(JournalLayer journal) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final id = await journal.log(
      type: JournalType.routine,
      body: '{"action":"create"}',
    );
    if (findRoutine(id) == null) {
      final r = Routine.create(id);
      r.lastActionAt = now;
      routines.add(r);
    }
    await _saveToFile();
    notifyListeners();
    return findRoutine(id)!;
  }

  Future<void> renameRoutine(JournalLayer journal, int id, String name) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final r = findRoutine(id);
    if (r == null) return;
    r.name = name;
    r.lastActionAt = now;
    await journal.log(
      type: JournalType.routine,
      body: '{"action":"rename","routine":$id,"name":${jsonEncode(name)}}',
    );
    await _saveToFile();
    notifyListeners();
  }

  Future<void> deleteRoutine(JournalLayer journal, int id) async {
    routines.removeWhere((r) => r.id == id);
    await journal.log(
      type: JournalType.routine,
      body: '{"action":"delete","routine":$id}',
    );
    await _saveToFile();
    notifyListeners();
  }

  // ─── Блоки ───
  // Взаимоисключение: пуск одного гасит прочие.
  Future<void> toggleBlock(
      JournalLayer journal, int routineId, String kind) async {
    final r = findRoutine(routineId);
    if (r == null) return;
    final b = r.blockOf(kind);
    if (b == null) return;
    if (b.isRunning) {
      await pauseBlock(journal, routineId, kind);
    } else {
      await startBlock(journal, routineId, kind);
    }
  }

  Future<void> startBlock(
      JournalLayer journal, int routineId, String kind) async {
    final r = findRoutine(routineId);
    if (r == null) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Глобальное взаимоисключение: идти может токмо одна рутина
    // разом. Ежели есть текущая, но сие не та же рутина — гасим её
    // блок. Внутри же самой рутины блоки гасят друг друга ниже.
    final curId = currentRoutineId;
    if (curId != null && curId != routineId) {
      final cur = findRoutine(curId);
      if (cur != null) {
        for (final b in cur.blocks) {
          if (b.isRunning) {
            b.pause(at: now);
            await journal.log(
              type: JournalType.routine,
              body: '{"action":"pause_block","routine":$curId,'
                  '"block":"${b.kind}","at":$now}',
            );
          }
        }
      }
    }

    // Внутри той же рутины: пуск одного блока гасит прочие её блоки.
    for (final b in r.blocks) {
      if (b.isRunning && b.kind != kind) {
        b.pause(at: now);
        await journal.log(
          type: JournalType.routine,
          body: '{"action":"pause_block","routine":$routineId,'
              '"block":"${b.kind}","at":$now}',
        );
      }
    }

    final target = r.blockOf(kind);
    if (target != null && !target.isRunning) {
      target.start(at: now);
      await journal.log(
        type: JournalType.routine,
        body: '{"action":"start_block","routine":$routineId,'
            '"block":"$kind","at":$now}',
      );
    }
    r.lastActionAt = now;
    currentRoutineId = routineId;
    await _saveToFile();
    notifyListeners();
  }

  Future<void> pauseBlock(
      JournalLayer journal, int routineId, String kind) async {
    final r = findRoutine(routineId);
    if (r == null) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final b = r.blockOf(kind);
    if (b == null || !b.isRunning) return;
    b.pause(at: now);
    r.lastActionAt = now;
    // Ежели в сей рутине ничего не осталось бегущего — индекс обнуляется.
    if (r.runningBlock == null) currentRoutineId = null;
    await journal.log(
      type: JournalType.routine,
      body: '{"action":"pause_block","routine":$routineId,'
          '"block":"$kind","at":$now}',
    );
    await _saveToFile();
    notifyListeners();
  }

  // ─── Поиск и вспомогательное ───
  Routine? findRoutine(int id) {
    for (final r in routines) {
      if (r.id == id) return r;
    }
    return null;
  }

  Future<void> saveNow() async {
    await _saveToFile();
  }

  Future<void> resetAll() async {
    if (_file != null && await _file!.exists()) {
      await _file!.delete();
    }
    routines = [];
    await _saveToFile();
    notifyListeners();
  }
}
