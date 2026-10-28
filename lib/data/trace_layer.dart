// ═══════════════════════════════════════════════════════════════════
// trace_layer.dart — trace layer.
//
// A trace is a universal entity: a note, a comment, a checklist,
// an attachment to a file.
//
// Journal entry body (kind trace):
//   {
//     "kind": "text" | "checklist",
//     "slot": "work",
//     "text": "...",
//     "items": [...],
//     "parents": [...],
//     "children": [...],
//     "files": [{"kind":"audio","path":"...","name":"..."}],
//     "field_parents": [...],
//     "deleted": true
//   }
//
// slot — routine block kind. kind — display form (text | checklist).
// Media live in files: a list of {kind (audio, photo, video, geo,
// file), path, name}. Files are copied into the application; the
// trace body keeps the path. For the "geo" kind no separate json
// file is written: coordinates (lat, lon, acc) go straight into
// TraceFile.
//
// fieldParents. Identifiers of the field nodes (graph vertices) to
// which this trace is attached. An empty list means the trace is
// unattached (legacy state); the UI treats such a trace as belonging
// to the root field node.
//
// Cache. Written with a 200 ms debounce, through a .tmp file and
// a rename (json_io.dart). A crash mid-write cannot leave a
// half-written cache.
//
// Index. A map _kindSlotIndex is maintained to accelerate
// findFirstByKindSlot lookups, mapping «parentId|kind|slot» to the
// minimal trace ID. The index is rebuilt on load, reset, and after
// deletions/detachments; updated incrementally on creation, attach,
// and corrections.
//
// Transparency is not applied.
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
import 'json_io.dart';

// ─── Trace display form ───
class TraceKind {
  static const String text = 'text';
  static const String checklist = 'checklist';
}

// ─── Media kinds ───
class MediaKind {
  static const String audio = 'audio';
  static const String photo = 'photo';
  static const String video = 'video';
  static const String geo = 'geo';
  static const String file = 'file';

  static const List<String> all = [audio, photo, video, geo, file];
}

// ─── One trace in memory ───
class Trace {
  final int id;
  String kind;
  String slot;
  String text;
  List<TraceItem> items;
  List<int> parents;
  List<int> children;
  List<TraceFile> files;
  List<int> fieldParents;
  bool deleted;

  Trace({
    required this.id,
    this.kind = TraceKind.text,
    this.slot = '',
    this.text = '',
    List<TraceItem>? items,
    List<int>? parents,
    List<int>? children,
    List<TraceFile>? files,
    List<int>? fieldParents,
    this.deleted = false,
  }) : items = items ?? [],
       parents = parents ?? [],
       children = children ?? [],
       files = files ?? [],
       fieldParents = fieldParents ?? [];

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'slot': slot,
    'text': text,
    'items': items.map((e) => e.toJson()).toList(),
    'parents': parents,
    'children': children,
    'files': files.map((e) => e.toJson()).toList(),
    'field_parents': fieldParents,
    'deleted': deleted,
  };

  factory Trace.fromJson(int id, Map<String, dynamic> j) => Trace(
    id: id,
    kind: j['kind'] as String? ?? TraceKind.text,
    slot: j['slot'] as String? ?? '',
    text: j['text'] as String? ?? '',
    items:
        (j['items'] as List?)
            ?.map((e) => TraceItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    parents:
        (j['parents'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [],
    children:
        (j['children'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [],
    files:
        (j['files'] as List?)
            ?.map((e) => TraceFile.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    fieldParents:
        (j['field_parents'] as List?)
            ?.map((e) => (e as num).toInt())
            .toList() ??
        [],
    deleted: j['deleted'] as bool? ?? false,
  );
}

class TraceItem {
  String text;
  bool done;
  List<int> parents;
  List<int> children;

  TraceItem({
    required this.text,
    this.done = false,
    List<int>? parents,
    List<int>? children,
  }) : parents = parents ?? [],
       children = children ?? [];

  Map<String, dynamic> toJson() => {
    'text': text,
    'done': done,
    'parents': parents,
    'children': children,
  };

  factory TraceItem.fromJson(Map<String, dynamic> j) => TraceItem(
    text: j['text'] as String? ?? '',
    done: j['done'] as bool? ?? false,
    parents:
        (j['parents'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [],
    children:
        (j['children'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [],
  );
}

class TraceFile {
  String kind;
  String path;
  String name;

  // For the "geo" kind: coordinates and accuracy go straight into
  // the trace body — no separate json file is needed.
  double? lat;
  double? lon;
  double? acc;

  TraceFile({
    required this.kind,
    required this.path,
    this.name = '',
    this.lat,
    this.lon,
    this.acc,
  });

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'path': path,
    'name': name,
    if (lat != null) 'lat': lat,
    if (lon != null) 'lon': lon,
    if (acc != null) 'acc': acc,
  };

  factory TraceFile.fromJson(Map<String, dynamic> j) => TraceFile(
    kind: j['kind'] as String? ?? 'file',
    path: j['path'] as String? ?? '',
    name: j['name'] as String? ?? '',
    lat: (j['lat'] as num?)?.toDouble(),
    lon: (j['lon'] as num?)?.toDouble(),
    acc: (j['acc'] as num?)?.toDouble(),
  );
}

class TraceLayer extends ChangeNotifier {
  final Map<int, Trace> traces = {};

  File? _file;
  Timer? _saveTimer;

  // ─── Index ───
  final Map<String, int> _kindSlotIndex = {};

  String _indexKey(int parentId, String kind, String slot) =>
      '$parentId|$kind|$slot';

  void _indexTrace(Trace t) {
    if (t.deleted) return;
    for (final pId in t.parents) {
      final key = _indexKey(pId, t.kind, t.slot);
      if (!_kindSlotIndex.containsKey(key) || t.id < _kindSlotIndex[key]!) {
        _kindSlotIndex[key] = t.id;
      }
    }
  }

  void _rebuildIndex() {
    _kindSlotIndex.clear();
    for (final t in traces.values) {
      _indexTrace(t);
    }
  }

  Future<void> init(JournalLayer journal) async {
    final dir = await getApplicationDocumentsDirectory();
    _file = File(p.join(dir.path, 'trace_layer.json'));
    await _loadFromFile();

    journal.register(
      name: 'trace',
      types: [JournalType.trace],
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

  Future<void> _loadFromFile() async {
    if (_file == null || !await _file!.exists()) return;
    try {
      final raw = await _file!.readAsString();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final list = data['traces'];
      if (list is List) {
        for (final e in list) {
          final m = e as Map<String, dynamic>;
          final id = (m['id'] as num).toInt();
          traces[id] = Trace.fromJson(id, m);
        }
      }
      _rebuildIndex();
    } catch (_) {}
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 200), () {
      _saveToFile();
    });
  }

  Future<void> _saveToFile() async {
    final target = _file;
    if (target == null) return;
    final data = <String, dynamic>{
      'traces': traces.values.map((t) => {'id': t.id, ...t.toJson()}).toList(),
    };
    await atomicWriteJson(target, data);
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _saveToFile();
  }

  void _applyEntry(JournalData e) {
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
        _indexTrace(existing);
        return;
      }

      if (traces.containsKey(e.id)) return;
      final newTrace = Trace.fromJson(e.id, data);
      traces[e.id] = newTrace;
      _indexTrace(newTrace);
    } catch (_) {}
  }

  void _resetMemory() {
    traces.clear();
    _rebuildIndex();
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

  Trace? findFirstBySlot(int objectId, String slot) {
    Trace? found;
    for (final t in traces.values) {
      if (t.deleted) continue;
      if (t.slot != slot) continue;
      if (!t.parents.contains(objectId)) continue;
      if (found == null || t.id < found.id) found = t;
    }
    return found;
  }

  Trace? findFirstByKindSlot(int objectId, String kind, String slot) {
    final indexId = _kindSlotIndex[_indexKey(objectId, kind, slot)];
    if (indexId != null) {
      final t = traces[indexId];
      if (t != null && !t.deleted) return t;
    }
    // Fallback to linear scan if index is stale, and repair it.
    Trace? found;
    for (final t in traces.values) {
      if (t.deleted) continue;
      if (t.kind != kind) continue;
      if (t.slot != slot) continue;
      if (!t.parents.contains(objectId)) continue;
      if (found == null || t.id < found.id) found = t;
    }
    if (found != null) {
      _kindSlotIndex[_indexKey(objectId, kind, slot)] = found.id;
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
      'items': [],
      'parents': parents,
      'children': [],
      'files': [],
      'field_parents': fieldParents,
    });
    final id = await journal.log(type: JournalType.trace, body: body);
    // Pre-insert so callers inside a journal transaction (import, in
    // particular) can find this trace immediately, before the journal
    // pumps. Without this, attachFile right after createText during a
    // transaction sees an empty traces map and silently returns,
    // leaving the file on disk unattached — the orphaned media.
    // _applyEntry skips entries already present in the map, so no
    // double-insert occurs when the pump eventually runs.
    final t = traces.putIfAbsent(
      id,
      () => Trace(
        id: id,
        slot: slot,
        text: text,
        parents: List<int>.from(parents),
        fieldParents: List<int>.from(fieldParents),
      ),
    );
    _indexTrace(t);
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
      'children': [],
      'files': [],
      'field_parents': fieldParents,
    });
    final id = await journal.log(type: JournalType.trace, body: body);
    // Same pre-insert rationale as in createText: the importer, while
    // inside a transaction, must see this checklist immediately.
    final t = traces.putIfAbsent(
      id,
      () => Trace(
        id: id,
        kind: TraceKind.checklist,
        slot: slot,
        items: [for (final s in items) TraceItem(text: s, done: false)],
        parents: List<int>.from(parents),
        fieldParents: List<int>.from(fieldParents),
      ),
    );
    _indexTrace(t);
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
    _rebuildIndex();
    await _updateBody(journal, traceId, t);
  }

  Future<void> attach(JournalLayer journal, int traceId, int objectId) async {
    final t = traces[traceId];
    if (t == null) return;
    if (t.parents.contains(objectId)) return;
    t.parents = [...t.parents, objectId];
    _indexTrace(t);
    await _updateBody(journal, traceId, t);
  }

  Future<void> detach(JournalLayer journal, int traceId, int objectId) async {
    final t = traces[traceId];
    if (t == null) return;
    t.parents = t.parents.where((x) => x != objectId).toList();
    _rebuildIndex();
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
    if (_file != null && await _file!.exists()) {
      await _file!.delete();
    }
    traces.clear();
    _rebuildIndex();
    await _saveToFile();
    notifyListeners();
  }
}
