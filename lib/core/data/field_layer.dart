import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:polyrutina/core/data/atomic_json.dart';
import 'package:polyrutina/core/data/database.dart';
import 'package:polyrutina/core/data/journal_layer.dart';
import 'package:polyrutina/core/domain/journal_types.dart';

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
  int? rootId; // The ID of the default buffer root (field).
  int? activeFieldId; // The currently active field (root node ID).

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
      activeFieldId = (data['active_field_id'] as num?)?.toInt();
      final list = data['nodes'];
      if (list is List) {
        for (final e in list) {
          if (e is! Map) continue;
          try {
            final n = FieldNode.fromJson(Map<String, dynamic>.from(e));
            nodes[n.id] = n;
            // Preserve the first root as the default.
            if (n.isRoot && rootId == null) rootId = n.id;
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
      'active_field_id': activeFieldId,
      'nodes': nodes.values.map((n) => n.toJson()).toList(),
    };
    await atomicWriteJson(target, data);
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _saveToFile();
  }

  void setActiveField(int id) {
    if (activeFieldId == id) return;
    activeFieldId = id;
    _scheduleSave();
    notifyListeners();
  }

  void _applyEntry(JournalData e) {
    try {
      final data = jsonDecode(e.body) as Map<String, dynamic>;
      final action = data['action'] as String?;

      switch (action) {
        case 'reset':
          nodes.clear();
          rootId = null;
          activeFieldId = null;
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
          if (isRoot && rootId == null) {
            rootId = id;
            activeFieldId ??= id;
          }
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
            if (activeFieldId == id) {
              activeFieldId = rootId;
            }
          }
          break;
      }
      if (activeFieldId == null || !nodes.containsKey(activeFieldId)) {
        activeFieldId = (rootId != null && nodes.containsKey(rootId))
            ? rootId
            : null;
      }
    } catch (_) {}
    notifyListeners();
  }

  void _resetMemory() {
    nodes.clear();
    rootId = null;
    activeFieldId = null;
    notifyListeners();
  }

  Future<FieldNode> createRootIfNeeded(
    JournalLayer journal, {
    String name = 'Field',
  }) async {
    if (rootId != null && nodes.containsKey(rootId)) {
      activeFieldId ??= rootId;
      return nodes[rootId]!;
    }

    final id = await journal.log(
      type: JournalType.fieldNode,
      body: jsonEncode({'action': 'create', 'name': name, 'is_root': true}),
    );

    _scheduleSave();
    notifyListeners();
    return nodes[id]!;
  }

  Future<FieldNode> createField(JournalLayer journal, String name) async {
    final id = await journal.log(
      type: JournalType.fieldNode,
      body: jsonEncode({'action': 'create', 'name': name, 'is_root': true}),
    );
    _scheduleSave();
    notifyListeners();
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
    _scheduleSave();
    notifyListeners();
    return nodes[id]!;
  }

  Future<void> renameNode(JournalLayer journal, int id, String name) async {
    final n = nodes[id];
    if (n == null) return;
    n.name = name;
    if (n.isRoot && (rootId == null || !nodes.containsKey(rootId))) {
      rootId = id;
    }
    if (activeFieldId == null || !nodes.containsKey(activeFieldId)) {
      if (rootId != null && nodes.containsKey(rootId)) {
        activeFieldId = rootId;
      }
    }
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
    if (isDescendant(parentId, childId)) return;

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

  bool isDescendant(int potentialDescendant, int ancestor) {
    if (potentialDescendant == ancestor) return true;
    final node = nodes[potentialDescendant];
    if (node == null) return false;
    for (final p in node.parents) {
      if (isDescendant(p, ancestor)) return true;
    }
    return false;
  }

  Future<void> deleteNode(
    JournalLayer journal,
    int id, {
    bool burn = false,
  }) async {
    final node = nodes[id];
    if (node == null) return;
    // The default root is protected; other roots can be deleted.
    if (node.isRoot && node.id == rootId) return;

    await journal.transaction(() async {
      if (burn) {
        final children = List<int>.from(node.children);
        for (final cId in children) {
          await deleteNode(journal, cId, burn: true);
        }
      } else {
        // Reattach children to the default root before removing this node.
        final target = rootId;
        if (target != null && target != id) {
          for (final cId in node.children) {
            await attachNode(journal, cId, target);
          }
        }
      }

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
    });

    _scheduleSave();
    notifyListeners();
  }
}
