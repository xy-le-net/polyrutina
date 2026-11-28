import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:polyrutina/core/data/atomic_json.dart';
import 'package:polyrutina/core/data/journal_repository.dart';
import 'package:polyrutina/core/domain/journal_entry.dart';

typedef ApplyFn = void Function(JournalEntry entry);
typedef ResetFn = void Function();
typedef ProgressFn = void Function(int lastId);

class _LayerReg {
  final List<int> types;
  final ApplyFn apply;
  final ResetFn? reset;
  final ProgressFn? onProgress;
  int lastId;

  _LayerReg({
    required this.types,
    required this.apply,
    this.reset,
    this.onProgress,
    this.lastId = 0,
  });
}

class JournalLayer extends ChangeNotifier {
  final JournalRepository repository;
  JournalLayer(this.repository);

  final Map<String, _LayerReg> _layers = {};
  final Map<String, int> _savedIds = {};

  File? _stateFile;
  Timer? _saveTimer;

  bool _stateDirty = false;
  bool _pumping = false;
  int _txDepth = 0;

  StreamSubscription<List<JournalEntry>>? _sub;

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
    ProgressFn? onProgress,
    int? initialLastId,
  }) {
    _layers[name] = _LayerReg(
      types: types,
      apply: apply,
      reset: reset,
      onProgress: onProgress,
      lastId: initialLastId ?? _savedIds[name] ?? 0,
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
    if (l != null) {
      l.lastId = 0;
      l.onProgress?.call(0);
    }
    _stateDirty = true;
    _scheduleSave();
  }

  Future<T> transaction<T>(Future<T> Function() action) async {
    _txDepth++;
    try {
      return await repository.transaction(action);
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
            l.onProgress?.call(e.id);
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
      l.onProgress?.call(0);
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
    final id = await repository.insert(type: type, body: body, flags: flags);
    if (_txDepth == 0) await pump();
    return id;
  }

  Stream<List<JournalEntry>> watchAll() {
    return repository.watchAll();
  }

  Future<List<JournalEntry>> entriesAfter(int fromId, {int? type}) {
    return repository.entriesAfter(fromId, type: type);
  }

  Future<List<JournalEntry>> all() => repository.all();

  Future<void> clearAll() async {
    await repository.clearEntries();
    for (final l in _layers.values) {
      l.reset?.call();
      l.lastId = 0;
      l.onProgress?.call(0);
    }
    _savedIds.clear();
    _stateDirty = true;
    await _saveStateNow();
    try {
      await repository.reclaimSpace();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> deleteSynced() async {
    final n = await repository.deleteSynced();
    if (n > 0) notifyListeners();
  }

  Future<int> countSynced() => repository.countSynced();

  Future<void> markSynced(int id) => repository.markSynced(id);

  Future<int> countEntries() => repository.countEntries();

  Future<int> lastEntryId() => repository.lastEntryId();

  Future<void> reclaimSpace() => repository.reclaimSpace();

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
