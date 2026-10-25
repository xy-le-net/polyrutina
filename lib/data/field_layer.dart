// ═══════════════════════════════════════════════════════════════════
// field_layer.dart — field layer (graph of nodes).
//
// Holds the tree/graph of field nodes. The root node is created on
// first run.
//
// Registered in JournalLayer for the fieldNode kind (type 5).
//
// Nodes form a directed acyclic graph (DAG). A node can have multiple
// parents. Deleting a node can either "shake" its children to its
// parents (default) or "burn" them recursively.
//
// Cache is written with a 200 ms debounce, through a .tmp file and
// a rename. A crash mid-write cannot leave a half-written cache.
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

class FieldNode {
  final int id;
  String name;
  List<int> parents;
  List<int> children;
  bool isRoot;

  FieldNode({
    required this.id,
    this.name = '',
    List<int>? parents,
    List<int>? children,
    this.isRoot = false,
  }) : parents = parents ?? [],
       children = children ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'parents': parents,
    'children': children,
    'is_root': isRoot,
  };

  factory FieldNode.fromJson(Map<String, dynamic> j) {
    final id = (j['id'] as num?)?.toInt();
    if (id == null) throw const FormatException('FieldNode: missing id');
    return FieldNode(
      id: id,
      name: j['name'] as String? ?? '',
      parents:
          (j['parents'] as List?)?.map((e) => (e as num).toInt()).toList() ??
          [],
      children:
          (j['children'] as List?)?.map((e) => (e as num).toInt()).toList() ??
          [],
      isRoot: j['is_root'] as bool? ?? false,
    );
  }
}

class FieldLayer extends ChangeNotifier {
  final Map<int, FieldNode> nodes = {};
  int? rootId;

  File? _file;
  Timer? _saveTimer;

  Future<void> init(JournalLayer journal) async {
    final dir = await getApplicationDocumentsDirectory();
    _file = File(p.join(dir.path, 'field_layer.json'));
    await _loadFromFile();

    journal.register(
      name: 'field',
      types: [JournalType.fieldNode],
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
      final list = data['nodes'];
      if (list is List) {
        for (final e in list) {
          if (e is! Map) continue;
          try {
            final n = FieldNode.fromJson(Map<String, dynamic>.from(e));
            nodes[n.id] = n;
            if (n.isRoot) rootId = n.id;
          } catch (_) {
            // Skip a single malformed node; keep the rest.
          }
        }
      }
    } catch (_) {}
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 200), _saveToFile);
  }

  Future<void> _saveToFile() async {
    final target = _file;
    if (target == null) return;
    final data = <String, dynamic>{
      'nodes': nodes.values.map((n) => n.toJson()).toList(),
    };
    final tmp = File('${target.path}.tmp');
    try {
      await tmp.writeAsString(jsonEncode(data), flush: true);
      await tmp.rename(target.path);
    } catch (_) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _saveToFile();
  }

  void _applyEntry(JournalData e) {
    try {
      final data = jsonDecode(e.body) as Map<String, dynamic>;
      final action = data['action'] as String?;

      switch (action) {
        case 'reset':
          nodes.clear();
          rootId = null;
          break;
        case 'create':
          final bodyId = (data['id'] as num?)?.toInt();
          final id = bodyId ?? e.id;
          final name = data['name'] as String? ?? '';
          final parents =
              (data['parents'] as List?)
                  ?.map((x) => (x as num).toInt())
                  .toList() ??
              [];
          final isRoot = data['is_root'] as bool? ?? false;

          if (!nodes.containsKey(id)) {
            nodes[id] = FieldNode(
              id: id,
              name: name,
              parents: parents,
              isRoot: isRoot,
            );
            for (final pId in parents) {
              nodes[pId]?.children.add(id);
            }
          }
          if (isRoot) rootId = id;
          break;
        case 'rename':
          final id = (data['id'] as num).toInt();
          nodes[id]?.name = data['name'] as String? ?? '';
          break;
        case 'attach':
          final childId = (data['id'] as num).toInt();
          final parentId = (data['parent'] as num).toInt();
          final child = nodes[childId];
          final parent = nodes[parentId];
          if (child != null && parent != null) {
            if (!child.parents.contains(parentId)) child.parents.add(parentId);
            if (!parent.children.contains(childId)) {
              parent.children.add(childId);
            }
          }
          break;
        case 'detach':
          final childId = (data['id'] as num).toInt();
          final parentId = (data['parent'] as num).toInt();
          final child = nodes[childId];
          final parent = nodes[parentId];
          if (child != null && parent != null) {
            child.parents.remove(parentId);
            parent.children.remove(childId);
          }
          break;
        case 'delete':
          final id = (data['id'] as num).toInt();
          final node = nodes.remove(id);
          if (node != null) {
            for (final pId in node.parents) {
              nodes[pId]?.children.remove(id);
            }
            for (final cId in node.children) {
              nodes[cId]?.parents.remove(id);
            }
          }
          break;
      }
    } catch (_) {}
  }

  void _resetMemory() {
    nodes.clear();
    rootId = null;
    notifyListeners();
  }

  // ─── Mutations ───

  Future<FieldNode> createRootIfNeeded(JournalLayer journal) async {
    if (rootId != null && nodes.containsKey(rootId)) {
      return nodes[rootId]!;
    }

    final id = await journal.log(
      type: JournalType.fieldNode,
      body: jsonEncode({'action': 'create', 'name': 'Корень', 'is_root': true}),
    );

    if (!nodes.containsKey(id)) {
      final n = FieldNode(id: id, name: 'Корень', isRoot: true);
      nodes[id] = n;
      rootId = id;
      _scheduleSave();
      notifyListeners();
    }
    return nodes[id]!;
  }

  Future<FieldNode> createNode(
    JournalLayer journal, {
    required String name,
    required int parentId,
  }) async {
    final id = await journal.log(
      type: JournalType.fieldNode,
      body: jsonEncode({
        'action': 'create',
        'name': name,
        'parents': [parentId],
      }),
    );
    if (!nodes.containsKey(id)) {
      final n = FieldNode(id: id, name: name, parents: [parentId]);
      nodes[id] = n;
      nodes[parentId]?.children.add(id);
      _scheduleSave();
      notifyListeners();
    }
    return nodes[id]!;
  }

  Future<void> renameNode(JournalLayer journal, int id, String name) async {
    final n = nodes[id];
    if (n == null) return;
    n.name = name;
    await journal.log(
      type: JournalType.fieldNode,
      body: jsonEncode({'action': 'rename', 'id': id, 'name': name}),
    );
    _scheduleSave();
    notifyListeners();
  }

  Future<void> attachNode(
    JournalLayer journal,
    int childId,
    int parentId,
  ) async {
    final child = nodes[childId];
    final parent = nodes[parentId];
    if (child == null || parent == null) return;
    if (child.parents.contains(parentId)) return;

    // Prevent cycles
    if (_isDescendant(parentId, childId)) return;

    child.parents.add(parentId);
    parent.children.add(childId);
    await journal.log(
      type: JournalType.fieldNode,
      body: jsonEncode({'action': 'attach', 'id': childId, 'parent': parentId}),
    );
    _scheduleSave();
    notifyListeners();
  }

  Future<void> detachNode(
    JournalLayer journal,
    int childId,
    int parentId,
  ) async {
    final child = nodes[childId];
    final parent = nodes[parentId];
    if (child == null || parent == null) return;
    if (!child.parents.contains(parentId)) return;

    child.parents.remove(parentId);
    parent.children.remove(childId);
    await journal.log(
      type: JournalType.fieldNode,
      body: jsonEncode({'action': 'detach', 'id': childId, 'parent': parentId}),
    );
    _scheduleSave();
    notifyListeners();
  }

  bool _isDescendant(int potentialDescendant, int ancestor) {
    if (potentialDescendant == ancestor) return true;
    final node = nodes[potentialDescendant];
    if (node == null) return false;
    for (final p in node.parents) {
      if (_isDescendant(p, ancestor)) return true;
    }
    return false;
  }

  Future<void> deleteNode(
    JournalLayer journal,
    int id, {
    bool burn = false,
  }) async {
    final node = nodes[id];
    if (node == null || node.isRoot) return;

    if (burn) {
      // Recursively delete children
      final children = List<int>.from(node.children);
      for (final cId in children) {
        await deleteNode(journal, cId, burn: true);
      }
    } else {
      // Shake children to parents
      for (final cId in node.children) {
        for (final pId in node.parents) {
          await attachNode(journal, cId, pId);
        }
      }
    }

    // Delete this node
    nodes.remove(id);
    for (final pId in node.parents) {
      nodes[pId]?.children.remove(id);
    }
    for (final cId in node.children) {
      nodes[cId]?.parents.remove(id);
    }

    await journal.log(
      type: JournalType.fieldNode,
      body: jsonEncode({'action': 'delete', 'id': id}),
    );
    _scheduleSave();
    notifyListeners();
  }
}
