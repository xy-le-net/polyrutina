import 'package:polyrutina/features/fields/domain/field_node.dart';

abstract interface class FieldAccess {
  Map<int, FieldNode> get nodes;
  int? get rootId;
}
