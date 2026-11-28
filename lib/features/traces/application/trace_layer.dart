import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:polyrutina/core/data/journal_layer.dart';
import 'package:polyrutina/core/domain/journal_entry.dart';
import 'package:polyrutina/core/domain/journal_types.dart';
import 'package:polyrutina/features/traces/application/trace_repository.dart';
import 'package:polyrutina/features/traces/domain/trace.dart';

export 'package:polyrutina/features/traces/domain/trace.dart';

class TraceLayer extends ChangeNotifier {
  TraceLayer(this._repository);

  final TraceRepository _repository;
  final Map<int, Trace> traces = {};

  // Index: parentId -> "kind:slot" -> minimum trace ID
  final Map<int, Map<String, int>> _traceIndex = {};

  Timer? _saveTimer;

  Future<void> init(JournalLayer journal) async {
    final cache = await _repository.load();
    for (final trace in cache.traces) {
      traces[trace.id] = trace;
    }
    _rebuildIndices();

    journal.register(
      name: 'trace',
      types: [JournalType.trace],
      apply: _applyEntry,
      reset: _resetMemory,
    );
    if (cache.needsJournalReplay) {
      journal.clearMark('trace');
      await journal.pump();
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  void _rebuildIndices() {
    _traceIndex.clear();
    for (final t in traces.values) {
      if (t.deleted) continue;
      for (final pId in t.parents) {
        final key = '${t.kind}:${t.slot}';
        final existingId = _traceIndex[pId]?[key];
        if (existingId == null || t.id < existingId) {
          _traceIndex.putIfAbsent(pId, () => {})[key] = t.id;
        }
      }
    }
  }

  void _updateIndexForTrace(Trace t) {
    if (t.deleted) return;
    for (final pId in t.parents) {
      final key = '${t.kind}:${t.slot}';
      final existingId = _traceIndex[pId]?[key];
      if (existingId == null || t.id < existingId) {
        _traceIndex.putIfAbsent(pId, () => {})[key] = t.id;
      }
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 200), _saveToFile);
  }

  Future<void> _saveToFile() async {
    await _repository.save(traces: traces.values.toList());
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _saveToFile();
  }

  void _applyEntry(JournalEntry e) {
    try {
      final data = jsonDecode(e.body) as Map<String, dynamic>;
      final isCorrection = (e.flags & JournalFlag.correction) != 0;
      final target = (data['target'] as num?)?.toInt();
      final id = target ?? e.id;

      if (isCorrection) {
        final existing = traces[id];
        if (existing == null) return;
        existing.kind = data['kind'] as String? ?? existing.kind;
        existing.slot = data['slot'] as String? ?? existing.slot;
        existing.text = data['text'] as String? ?? existing.text;
        if (data['items'] is List) {
          existing.items = (data['items'] as List)
              .map((x) => TraceItem.fromJson(x as Map<String, dynamic>))
              .toList();
        }
        if (data['files'] is List) {
          existing.files = (data['files'] as List)
              .map((x) => TraceFile.fromJson(x as Map<String, dynamic>))
              .toList();
        }
        if (data['parents'] is List) {
          existing.parents = (data['parents'] as List)
              .map((x) => (x as num).toInt())
              .toList();
        }
        if (data['children'] is List) {
          existing.children = (data['children'] as List)
              .map((x) => (x as num).toInt())
              .toList();
        }
        if (data['field_parents'] is List) {
          existing.fieldParents = (data['field_parents'] as List)
              .map((x) => (x as num).toInt())
              .toList();
        }
        existing.deleted = data['deleted'] as bool? ?? existing.deleted;
        _rebuildIndices();
        return;
      }

      if (traces.containsKey(e.id)) return;
      final t = Trace.fromJson(e.id, data);
      traces[e.id] = t;
      _updateIndexForTrace(t);
    } catch (_) {}
  }

  void _resetMemory() {
    traces.clear();
    _traceIndex.clear();
    notifyListeners();
  }

  Trace? find(int id) => traces[id];

  List<Trace> attachedTo(int objectId) {
    final out = <Trace>[];
    for (final t in traces.values) {
      if (t.deleted) continue;
      if (t.parents.contains(objectId)) out.add(t);
    }
    out.sort((a, b) => a.id.compareTo(b.id));
    return out;
  }

  List<Trace> attachedToField(int nodeId) {
    final out = <Trace>[];
    for (final t in traces.values) {
      if (t.deleted) continue;
      if (t.fieldParents.contains(nodeId)) out.add(t);
    }
    out.sort((a, b) => a.id.compareTo(b.id));
    return out;
  }

  Set<String> attachedMediaNames({
    required Set<int> parentIds,
    required Set<int> fieldIds,
  }) {
    final names = <String>{};
    for (final t in traces.values) {
      if (t.deleted) continue;
      final attached =
          t.parents.any(parentIds.contains) ||
          t.fieldParents.any(fieldIds.contains);
      if (!attached) continue;
      for (final f in t.files) {
        if (f.path.isNotEmpty) names.add(p.basename(f.path));
        if (f.name.isNotEmpty) names.add(p.basename(f.name));
      }
    }
    return names;
  }

  Trace? findFirstBySlot(int objectId, String slot) {
    return findFirstByKindSlot(objectId, TraceKind.text, slot) ??
        findFirstByKindSlot(objectId, TraceKind.checklist, slot);
  }

  Trace? findFirstByKindSlot(int objectId, String kind, String slot) {
    final key = '$kind:$slot';
    final id = _traceIndex[objectId]?[key];

    if (id != null) {
      final t = traces[id];
      if (t != null && !t.deleted && t.parents.contains(objectId)) {
        return t;
      }
    }

    // Fallback if index is stale or missing
    Trace? found;
    for (final t in traces.values) {
      if (t.deleted) continue;
      if (t.kind != kind) continue;
      if (t.slot != slot) continue;
      if (!t.parents.contains(objectId)) continue;
      if (found == null || t.id < found.id) found = t;
    }
    if (found != null) {
      _traceIndex.putIfAbsent(objectId, () => {})[key] = found.id;
    }
    return found;
  }

  Future<int> createText(
    JournalLayer journal, {
    String slot = '',
    String text = '',
    List<int> parents = const [],
    List<int> fieldParents = const [],
  }) async {
    final body = jsonEncode({
      'kind': TraceKind.text,
      'slot': slot,
      'text': text,
      'items': <dynamic>[],
      'parents': parents,
      'children': <dynamic>[],
      'files': <dynamic>[],
      'field_parents': fieldParents,
    });
    final id = await journal.log(type: JournalType.trace, body: body);

    final t = Trace(
      id: id,
      slot: slot,
      text: text,
      parents: List<int>.from(parents),
      fieldParents: List<int>.from(fieldParents),
    );
    traces.putIfAbsent(id, () => t);
    _updateIndexForTrace(t);

    _scheduleSave();
    return id;
  }

  Future<int> createChecklist(
    JournalLayer journal, {
    String slot = '',
    List<String> items = const [],
    List<int> parents = const [],
    List<int> fieldParents = const [],
  }) async {
    final body = jsonEncode({
      'kind': TraceKind.checklist,
      'slot': slot,
      'text': '',
      'items': items.map((s) => {'text': s, 'done': false}).toList(),
      'parents': parents,
      'children': <dynamic>[],
      'files': <dynamic>[],
      'field_parents': fieldParents,
    });
    final id = await journal.log(type: JournalType.trace, body: body);

    final t = Trace(
      id: id,
      kind: TraceKind.checklist,
      slot: slot,
      items: [for (final s in items) TraceItem(text: s, done: false)],
      parents: List<int>.from(parents),
      fieldParents: List<int>.from(fieldParents),
    );
    traces.putIfAbsent(id, () => t);
    _updateIndexForTrace(t);

    _scheduleSave();
    return id;
  }

  Future<void> _updateBody(JournalLayer journal, int traceId, Trace t) async {
    final body = <String, dynamic>{
      'target': traceId,
      'kind': t.kind,
      'slot': t.slot,
      'text': t.text,
      'items': t.items.map((e) => e.toJson()).toList(),
      'parents': t.parents,
      'children': t.children,
      'files': t.files.map((e) => e.toJson()).toList(),
      'field_parents': t.fieldParents,
      'deleted': t.deleted,
    };
    await journal.log(
      type: JournalType.trace,
      body: jsonEncode(body),
      flags: JournalFlag.correction,
    );
    _updateIndexForTrace(t);
    _scheduleSave();
  }

  Future<void> updateText(
    JournalLayer journal,
    int traceId,
    String text,
  ) async {
    final t = traces[traceId];
    if (t == null) return;
    t.text = text;
    await _updateBody(journal, traceId, t);
  }

  Future<void> updateItems(
    JournalLayer journal,
    int traceId,
    List<TraceItem> items,
  ) async {
    final t = traces[traceId];
    if (t == null) return;
    t.items = items;
    await _updateBody(journal, traceId, t);
  }

  Future<void> attachFile(
    JournalLayer journal, {
    required int objectId,
    required String slot,
    required TraceFile file,
  }) async {
    var t = findFirstByKindSlot(objectId, TraceKind.text, slot);
    if (t == null) {
      final id = await createText(
        journal,
        slot: slot,
        text: '',
        parents: [objectId],
      );
      t = traces[id];
    }
    if (t == null) return;
    t.files = [...t.files, file];
    await _updateBody(journal, t.id, t);
    notifyListeners();
  }

  Future<void> copyForParent(
    JournalLayer journal, {
    required int sourceId,
    required int targetId,
    required List<String> slots,
  }) async {
    for (final slot in slots) {
      final trace = findFirstBySlot(sourceId, slot);
      if (trace == null) continue;

      if (trace.kind == TraceKind.text && trace.text.isNotEmpty) {
        await createText(
          journal,
          slot: slot,
          text: trace.text,
          parents: [targetId],
        );
      }

      if (trace.kind == TraceKind.checklist) {
        final items = trace.items
            .where((item) => item.text.trim().isNotEmpty)
            .map((item) => item.text)
            .toList();
        if (items.isNotEmpty) {
          await createChecklist(
            journal,
            slot: slot,
            items: items,
            parents: [targetId],
          );
        }
      }
    }
  }

  Future<void> removeFile(JournalLayer journal, int traceId, int index) async {
    final t = traces[traceId];
    if (t == null) return;
    if (index < 0 || index >= t.files.length) return;
    t.files = [...t.files]..removeAt(index);
    await _updateBody(journal, traceId, t);
    notifyListeners();
  }

  Future<void> remove(JournalLayer journal, int traceId) async {
    final t = traces[traceId];
    if (t == null) return;
    t.deleted = true;
    await _updateBody(journal, traceId, t);
    _rebuildIndices();
    // Index will fallback and find the next available trace or none.
  }

  Future<void> attach(JournalLayer journal, int traceId, int objectId) async {
    final t = traces[traceId];
    if (t == null) return;
    if (t.parents.contains(objectId)) return;
    t.parents = [...t.parents, objectId];
    await _updateBody(journal, traceId, t);
  }

  Future<void> detach(JournalLayer journal, int traceId, int objectId) async {
    final t = traces[traceId];
    if (t == null) return;
    t.parents = t.parents.where((x) => x != objectId).toList();
    await _updateBody(journal, traceId, t);
  }

  Future<void> attachToField(
    JournalLayer journal,
    int traceId,
    int nodeId,
  ) async {
    final t = traces[traceId];
    if (t == null) return;
    if (t.fieldParents.contains(nodeId)) return;
    t.fieldParents = [...t.fieldParents, nodeId];
    await _updateBody(journal, traceId, t);
    notifyListeners();
  }

  Future<void> detachFromField(
    JournalLayer journal,
    int traceId,
    int nodeId,
  ) async {
    final t = traces[traceId];
    if (t == null) return;
    t.fieldParents = t.fieldParents.where((x) => x != nodeId).toList();
    await _updateBody(journal, traceId, t);
    notifyListeners();
  }

  Future<void> resetAll() async {
    traces.clear();
    _traceIndex.clear();
    await _saveToFile();
    notifyListeners();
  }
}
