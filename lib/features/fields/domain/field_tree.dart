import 'package:polyrutina/features/fields/domain/field_node.dart';

class FieldTree {
  const FieldTree._();

  static bool canAttach(Map<int, FieldNode> nodes, int childId, int parentId) {
    final child = nodes[childId];
    if (child == null || nodes[parentId] == null) return false;
    if (child.parents.contains(parentId)) return false;
    return !isDescendant(nodes, parentId, childId);
  }

  static bool attach(Map<int, FieldNode> nodes, int childId, int parentId) {
    if (!canAttach(nodes, childId, parentId)) return false;
    nodes[childId]!.parents.add(parentId);
    nodes[parentId]!.children.add(childId);
    return true;
  }

  static bool detach(Map<int, FieldNode> nodes, int childId, int parentId) {
    final child = nodes[childId];
    final parent = nodes[parentId];
    if (child == null || parent == null || !child.parents.contains(parentId)) {
      return false;
    }
    child.parents.remove(parentId);
    parent.children.remove(childId);
    return true;
  }

  static FieldNode? remove(Map<int, FieldNode> nodes, int id) {
    final node = nodes.remove(id);
    if (node == null) return null;
    for (final parentId in node.parents) {
      nodes[parentId]?.children.remove(id);
    }
    for (final childId in node.children) {
      nodes[childId]?.parents.remove(id);
    }
    return node;
  }

  static bool isDescendant(
    Map<int, FieldNode> nodes,
    int potentialDescendant,
    int ancestor,
  ) {
    final visited = <int>{};
    final pending = <int>[potentialDescendant];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (current == ancestor) return true;
      if (!visited.add(current)) continue;
      pending.addAll(nodes[current]?.parents ?? const []);
    }
    return false;
  }
}
