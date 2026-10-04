// ═══════════════════════════════════════════════════════════════════
// routine_layer.dart — слой рутин.
//
// Держит список рутин и их блоки. Номер рутины — это номер записи
// о её создании в локальном журнале (поле id таблицы journal).
// Отдельного счётчика нет: AUTOINCREMENT первичного ключа SQLite
// сам даёт монотонные неповторяемые номера, в том числе после
// удалений. Воспроизведение журнала даёт те же номера, что были
// при создании,— оттого кэш и журнал согласованы всегда.
//
// Собственные мутации пишутся в журнал и применяются локально.
// Журнальный поток нужен для приёма записей, введённых извне,—
// например, из консоли вкладки журнала.
//
// Все операции идемпотентны: повторное применение одной записи
// не меняет состояние.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database.dart';
import 'journal_repository.dart';
import 'routine.dart';

class RoutineLayer extends ChangeNotifier {
  // ─── Текущее состояние ───
  List<Routine> routines = [];

  // ─── Служебное ───
  JournalRepository? _journal;
  File? _file;
  int _lastAppliedId = 0;
  bool _applying = false;
  StreamSubscription<List<JournalData>>? _sub;

  // Список для показа: свежайшие сверху. Внутренний порядок
  // (по возрастанию id) сохраняется — он нужен для воспроизведения.
  List<Routine> get routinesNewestFirst {
    final copy = List<Routine>.from(routines);
    copy.sort((a, b) => b.id.compareTo(a.id));
    return copy;
  }

  // ─── Пуск ───
  Future<void> init(JournalRepository journal) async {
    _journal = journal;
    final dir = await getApplicationDocumentsDirectory();
    _file = File(p.join(dir.path, 'routine_layer.json'));
    await _loadFromFile();
    await applyJournalDeltas();
    _sub = journal.watchAll().listen((_) => _onJournalChanged());
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _onJournalChanged() async {
    await applyJournalDeltas();
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
      _lastAppliedId = (data['last_id'] as num?)?.toInt() ?? 0;
    } catch (_) {}
  }

  Future<void> _saveToFile() async {
    if (_file == null) return;
    final data = <String, dynamic>{
      'routines': routines.map((r) => r.toJson()).toList(),
      'last_id': _lastAppliedId,
    };
    await _file!.writeAsString(jsonEncode(data));
  }

  // ─── Применение записей журнала ───
  // Цикл повторяется, покуда не перестанут появляться новые записи:
  // ежели во время разбора в журнал легла ещё запись, она будет
  // подхвачена следующей итерацией. Флаг _applying гасит параллельные
  // заходы.
  Future<void> applyJournalDeltas() async {
    if (_journal == null) return;
    if (_applying) return;
    _applying = true;
    try {
      while (true) {
        final entries = await _journal!
            .entriesAfter(_lastAppliedId, type: JournalType.routine);
        if (entries.isEmpty) break;
        for (final e in entries) {
          _applyEntry(e);
          _lastAppliedId = e.id;
        }
      }
      await _saveToFile();
      notifyListeners();
    } finally {
      _applying = false;
    }
  }

  // ─── Разбор одной записи ───
  // Принимает всю запись, а не токмо тело: для действия create
  // номер берётся из e.id, а час создания — из e.time.
  void _applyEntry(JournalData e) {
    try {
      final data = jsonDecode(e.body) as Map<String, dynamic>;
      final action = data['action'] as String?;
      switch (action) {
        case 'reset':
          routines = [];
          break;
        case 'create':
          // Ручной ввод из консоли может задать номер явно чрез поле
          // routine; при обычном создании поле отсутствует, и номер
          // берётся из записи журнала.
          final bodyId = (data['routine'] as num?)?.toInt();
          final id = bodyId ?? e.id;
          if (findRoutine(id) == null) {
            routines.add(Routine.create(id, at: e.time));
          }
          break;
        case 'rename':
          final id = (data['routine'] as num).toInt();
          final r = findRoutine(id);
          if (r != null) r.name = data['name'] as String? ?? '';
          break;
        case 'delete':
          final id = (data['routine'] as num).toInt();
          routines.removeWhere((r) => r.id == id);
          break;
        case 'start_block':
          final id = (data['routine'] as num).toInt();
          final kind = data['block'] as String?;
          final at = (data['at'] as num?)?.toInt();
          final r = findRoutine(id);
          if (r != null && kind != null) r.blockOf(kind)?.start(at: at);
          break;
        case 'pause_block':
          final id = (data['routine'] as num).toInt();
          final kind = data['block'] as String?;
          final at = (data['at'] as num?)?.toInt();
          final r = findRoutine(id);
          if (r != null && kind != null) r.blockOf(kind)?.pause(at: at);
          break;
      }
    } catch (_) {}
  }

  // ─── Полный пересбор ───
  // Сбрасывает память и воспроизводит весь рутинный журнал с нуля.
  Future<void> reloadFromJournal() async {
    if (_journal == null) return;
    routines = [];
    _lastAppliedId = 0;
    await applyJournalDeltas();
  }

  // ─── Создание ───
  // Запись в журнал кладётся первою, её номер становится номером
  // рутины. Тело пустое по части номера: при воспроизведении номер
  // берётся из поля id самой записи.
  Future<Routine> createRoutine() async {
    if (_journal == null) {
      // Без журнала рутина не может получить положительный номер.
      final id = -DateTime.now().millisecondsSinceEpoch;
      final r = Routine.create(id);
      routines.add(r);
      await _saveToFile();
      notifyListeners();
      return r;
    }
    final id = await _journal!.log(
      type: JournalType.routine,
      body: '{"action":"create"}',
    );
    if (findRoutine(id) == null) {
      routines.add(Routine.create(id));
    }
    await _saveToFile();
    notifyListeners();
    return findRoutine(id)!;
  }

  Future<void> renameRoutine(int id, String name) async {
    final r = findRoutine(id);
    if (r == null) return;
    r.name = name;
    if (_journal != null) {
      await _journal!.log(
        type: JournalType.routine,
        body: '{"action":"rename","routine":$id,"name":${jsonEncode(name)}}',
      );
    }
    await _saveToFile();
    notifyListeners();
  }

  Future<void> deleteRoutine(int id) async {
    routines.removeWhere((r) => r.id == id);
    if (_journal != null) {
      await _journal!.log(
        type: JournalType.routine,
        body: '{"action":"delete","routine":$id}',
      );
    }
    await _saveToFile();
    notifyListeners();
  }

  // ─── Блоки ───
  // Блоки одной рутины взаимоисключающие: пуск одного гасит прочие.
  // Сие гарантирует, что сумма времени блоков равна времени рутины,
  // а не удваивает счёт при параллельном ходе.
  Future<void> toggleBlock(int routineId, String kind) async {
    final r = findRoutine(routineId);
    if (r == null) return;
    final b = r.blockOf(kind);
    if (b == null) return;
    if (b.isRunning) {
      await pauseBlock(routineId, kind);
    } else {
      await startBlock(routineId, kind);
    }
  }

  Future<void> startBlock(int routineId, String kind) async {
    final r = findRoutine(routineId);
    if (r == null) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    for (final b in r.blocks) {
      if (b.isRunning && b.kind != kind) {
        b.pause(at: now);
        if (_journal != null) {
          await _journal!.log(
            type: JournalType.routine,
            body: '{"action":"pause_block","routine":$routineId,'
                '"block":"${b.kind}","at":$now}',
          );
        }
      }
    }
    final target = r.blockOf(kind);
    if (target != null && !target.isRunning) {
      target.start(at: now);
      if (_journal != null) {
        await _journal!.log(
          type: JournalType.routine,
          body: '{"action":"start_block","routine":$routineId,'
              '"block":"$kind","at":$now}',
        );
      }
    }
    await _saveToFile();
    notifyListeners();
  }

  Future<void> pauseBlock(int routineId, String kind) async {
    final r = findRoutine(routineId);
    if (r == null) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final b = r.blockOf(kind);
    if (b == null || !b.isRunning) return;
    b.pause(at: now);
    if (_journal != null) {
      await _journal!.log(
        type: JournalType.routine,
        body: '{"action":"pause_block","routine":$routineId,'
            '"block":"$kind","at":$now}',
      );
    }
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
    _lastAppliedId = 0;
    await _saveToFile();
    notifyListeners();
  }
}
