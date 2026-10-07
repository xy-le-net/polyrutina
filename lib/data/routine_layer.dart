// ═══════════════════════════════════════════════════════════════════
// routine_layer.dart — слой рутин.
//
// Держит список рутин и их блоки. Номер рутины — номер записи
// о её создании в журнале.
//
// Журнал. Регистрируется в JournalLayer на род routine.
//
// Кэш. Пишется отложенно (200 мс). При сворачивании — saveNow.
//
// currentRoutineId. Номер рутины, чей блок идёт. В памяти.
//
// lastActiveBlockKind. Род последнего пущенного блока. НЕ сбрасывается
// при остановке. Хранится в кэше (не токмо в памяти), дабы после
// перезапуска прокрутка карточки шла к прежнему блоку.
//
// Завершённость. Признак completed. Установка гасит идущий блок.
// Снятие пуском блока — косвенно, без отдельной записи.
//
// Флаги. Биты JournalFlag.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
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

  int? currentRoutineId;
  String? lastActiveBlockKind;

  // ─── Служебное ───
  File? _file;
  Timer? _saveTimer;

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

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
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
      lastActiveBlockKind = data['last_active_block_kind'] as String?;
    } catch (_) {}
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 200), () {
      _saveToFile();
    });
  }

  Future<void> _saveToFile() async {
    if (_file == null) return;
    final data = <String, dynamic>{
      'routines': routines.map((r) => r.toJson()).toList(),
      'last_active_block_kind': lastActiveBlockKind,
    };
    await _file!.writeAsString(jsonEncode(data));
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _saveToFile();
  }

  // ─── Применение одной записи журнала ───
  void _applyEntry(JournalData e) {
    try {
      final data = jsonDecode(e.body) as Map<String, dynamic>;
      final action = data['action'] as String?;
      switch (action) {
        case 'reset':
          routines = [];
          currentRoutineId = null;
          lastActiveBlockKind = null;
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
          if (currentRoutineId == id) currentRoutineId = null;
          break;
        case 'flags':
          final id = (data['routine'] as num).toInt();
          final r = findRoutine(id);
          if (r != null) {
            r.flags = (data['value'] as num?)?.toInt() ?? r.flags;
          }
          break;
        case 'complete':
          final id = (data['routine'] as num).toInt();
          final v = data['value'] as bool? ?? true;
          final r = findRoutine(id);
          if (r != null) r.completed = v;
          break;
        case 'start_block':
          final id = (data['routine'] as num).toInt();
          final kind = data['block'] as String?;
          final at = (data['at'] as num?)?.toInt() ?? e.time;
          final r = findRoutine(id);
          if (r != null && kind != null) {
            r.blockOf(kind)?.start(at: at);
            r.lastActionAt = at;
            r.completed = false;
            currentRoutineId = id;
            lastActiveBlockKind = kind;
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
            if (r.runningBlock == null && currentRoutineId == id) {
              currentRoutineId = null;
            }
          }
          break;
        case 'set_block_time':
          final id = (data['routine'] as num).toInt();
          final kind = data['block'] as String?;
          final secs = (data['seconds'] as num?)?.toInt();
          final r = findRoutine(id);
          if (r != null && kind != null && secs != null) {
            final b = r.blockOf(kind);
            if (b != null) {
              b.accumulatorSeconds = secs;
              b.startedAt = null;
            }
            r.lastActionAt = e.time;
          }
          break;
      }
    } catch (_) {}
  }

  void _resetMemory() {
    routines = [];
    currentRoutineId = null;
    lastActiveBlockKind = null;
    notifyListeners();
  }

  // ─── Дублирование ───
  Future<Routine?> duplicateRoutine(JournalLayer journal, int sourceId) async {
    final src = findRoutine(sourceId);
    if (src == null) return null;
    final r = await createRoutine(journal);
    if (src.name.isNotEmpty) {
      await renameRoutine(journal, r.id, src.name);
    }
    if (src.flags != 0) {
      await setFlags(journal, r.id, src.flags);
    }
    return findRoutine(r.id);
  }

  // ─── Мутации ───
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
    _scheduleSave();
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
    _scheduleSave();
    notifyListeners();
  }

  Future<void> deleteRoutine(JournalLayer journal, int id) async {
    routines.removeWhere((r) => r.id == id);
    if (currentRoutineId == id) currentRoutineId = null;
    await journal.log(
      type: JournalType.routine,
      body: '{"action":"delete","routine":$id}',
    );
    _scheduleSave();
    notifyListeners();
  }

  Future<void> setFlags(JournalLayer journal, int id, int flags) async {
    final r = findRoutine(id);
    if (r == null) return;
    r.flags = flags;
    r.lastActionAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await journal.log(
      type: JournalType.routine,
      body: '{"action":"flags","routine":$id,"value":$flags}',
    );
    _scheduleSave();
    notifyListeners();
  }

  // ─── Завершённость ───
  // Ставится чек-боксом в блоке «итог». Снятие — повторным касанием
  // либо пуском блока (косвенно).
  Future<void> setCompleted(JournalLayer journal, int id, bool value) async {
    final r = findRoutine(id);
    if (r == null) return;
    if (r.completed == value) return;

    // Установка гасит идущий блок.
    if (value) {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      for (final b in r.blocks) {
        if (b.isRunning) {
          b.pause(at: now);
          await journal.log(
            type: JournalType.routine,
            body: '{"action":"pause_block","routine":$id,'
                '"block":"${b.kind}","at":$now}',
          );
        }
      }
      if (currentRoutineId == id) currentRoutineId = null;
    }

    r.completed = value;
    r.lastActionAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await journal.log(
      type: JournalType.routine,
      body: '{"action":"complete","routine":$id,"value":$value}',
    );
    _scheduleSave();
    notifyListeners();
  }

  // ─── Правка времени блока ───
  Future<void> setBlockTime(
      JournalLayer journal, int routineId, String kind, int seconds) async {
    final r = findRoutine(routineId);
    if (r == null) return;
    final b = r.blockOf(kind);
    if (b == null || b.isRunning) return;
    b.accumulatorSeconds = seconds;
    r.lastActionAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await journal.log(
      type: JournalType.routine,
      body: '{"action":"set_block_time","routine":$routineId,'
          '"block":"$kind","seconds":$seconds}',
    );
    _scheduleSave();
    notifyListeners();
  }

  // ─── Блоки ───
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

    // Гасим текущую рутину, ежели иная.
    if (currentRoutineId != null && currentRoutineId != routineId) {
      final other = findRoutine(currentRoutineId!);
      if (other != null) {
        for (final b in other.blocks) {
          if (b.isRunning) {
            b.pause(at: now);
            await journal.log(
              type: JournalType.routine,
              body: '{"action":"pause_block","routine":${other.id},'
                  '"block":"${b.kind}","at":$now}',
            );
          }
        }
      }
    }

    // Гасим прочие блоки сей рутины.
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
    r.completed = false;
    currentRoutineId = routineId;
    lastActiveBlockKind = kind;
    _scheduleSave();
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
    if (r.runningBlock == null && currentRoutineId == routineId) {
      currentRoutineId = null;
    }
    await journal.log(
      type: JournalType.routine,
      body: '{"action":"pause_block","routine":$routineId,'
          '"block":"$kind","at":$now}',
    );
    _scheduleSave();
    notifyListeners();
  }

  // ─── Поиск и вспомогательное ───
  Routine? findRoutine(int id) {
    for (final r in routines) {
      if (r.id == id) return r;
    }
    return null;
  }

  Future<void> resetAll() async {
    if (_file != null && await _file!.exists()) {
      await _file!.delete();
    }
    routines = [];
    currentRoutineId = null;
    lastActiveBlockKind = null;
    await _saveToFile();
    notifyListeners();
  }
}
