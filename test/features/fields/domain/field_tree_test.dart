import 'package:flutter_test/flutter_test.dart';
import 'package:polyrutina/features/fields/domain/field_node.dart';
import 'package:polyrutina/features/fields/domain/field_tree.dart';

void main() {
  test(
    'keeps parent and child edges consistent when attaching and detaching',
    () {
      final nodes = {1: FieldNode(id: 1), 2: FieldNode(id: 2)};

      expect(FieldTree.attach(nodes, 2, 1), isTrue);
      expect(nodes[2]!.parents, [1]);
      expect(nodes[1]!.children, [2]);
      expect(FieldTree.detach(nodes, 2, 1), isTrue);
      expect(nodes[2]!.parents, isEmpty);
      expect(nodes[1]!.children, isEmpty);
    },
  );

  test('rejects cycle-forming and duplicate edges', () {
    final nodes = {
      1: FieldNode(id: 1),
      2: FieldNode(id: 2, parents: [1]),
    };
    nodes[1]!.children.add(2);

    expect(FieldTree.canAttach(nodes, 1, 2), isFalse);
    expect(FieldTree.attach(nodes, 2, 1), isFalse);
    expect(nodes[2]!.parents, [1]);
  });

  test('cycle checks terminate for malformed cached graphs', () {
    final nodes = {
      1: FieldNode(id: 1, parents: [2]),
      2: FieldNode(id: 2, parents: [1]),
      3: FieldNode(id: 3),
    };

    expect(FieldTree.isDescendant(nodes, 1, 3), isFalse);
    expect(FieldTree.isDescendant(nodes, 2, 1), isTrue);
  });

  test('removing a node unlinks it from both directions', () {
    final nodes = {
      1: FieldNode(id: 1, children: [2]),
      2: FieldNode(id: 2, parents: [1], children: [3]),
      3: FieldNode(id: 3, parents: [2]),
    };

    final removed = FieldTree.remove(nodes, 2);

    expect(removed?.id, 2);
    expect(nodes[1]!.children, isEmpty);
    expect(nodes[3]!.parents, isEmpty);
    expect(nodes.containsKey(2), isFalse);
  });
}
