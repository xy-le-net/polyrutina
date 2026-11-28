import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:polyrutina/core/data/journal_layer.dart';
import 'package:polyrutina/core/domain/journal_entry.dart';
import 'package:polyrutina/core/domain/journal_types.dart';
import 'package:polyrutina/features/fields/application/field_repository.dart';
import 'package:polyrutina/features/fields/application/field_access.dart';
import 'package:polyrutina/features/fields/domain/field_node.dart';
import 'package:polyrutina/features/fields/domain/field_tree.dart';

export 'package:polyrutina/features/fields/domain/field_node.dart';

class FieldLayer extends ChangeNotifier implements FieldAccess {
  FieldLayer(this._repository);

  final FieldRepository _repository;
  @override
  final Map<int, FieldNode> nodes = {};
  @override
  int? rootId;
  int? activeFieldId;

  Timer? _saveTimer;
  int _lastJournalId = 0;

  Future<void> init(JournalLayer journal) async {
    final cache = await _repository.load();
    _lastJournalId = cache.needsJournalReplay ? 0 : cache.lastJournalId;
    activeFieldId = cache.activeFieldId;
    for (final node in cache.nodes) {
      nodes[node.id] = node;
      if (node.isRoot && rootId == null) rootId = node.id;
    }

    journal.register(
      name: 'field',
      types: [JournalType.fieldNode],
      apply: _applyEntry,
      reset: _resetMemory,
      initialLastId: _lastJournalId,
      onProgress: (id) {
        _lastJournalId = id;
        _scheduleSave();
      },
    );
    if (cache.needsJournalReplay) {
      journal.clearMark('field');
      await journal.pump();
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 200), _saveToFile);
  }

  Future<void> _saveToFile() async {
    await _repository.save(
      activeFieldId: activeFieldId,
      nodes: nodes.values.toList(),
      lastJournalId: _lastJournalId,
    );
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

  void _applyEntry(JournalEntry e) {
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
    if (child == null ||
        parent == null ||
        !FieldTree.attach(nodes, childId, parentId)) {
      return;
    }
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
    if (child == null ||
        parent == null ||
        !FieldTree.detach(nodes, childId, parentId)) {
      return;
    }
    await journal.log(
      type: JournalType.fieldNode,
      body: jsonEncode({'action': 'detach', 'id': childId, 'parent': parentId}),
    );
    _scheduleSave();
    notifyListeners();
  }

  bool isDescendant(int potentialDescendant, int ancestor) {
    return FieldTree.isDescendant(nodes, potentialDescendant, ancestor);
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

      FieldTree.remove(nodes, id);

      await journal.log(
        type: JournalType.fieldNode,
        body: jsonEncode({'action': 'delete', 'id': id}),
      );
    });

    _scheduleSave();
    notifyListeners();
  }
}
