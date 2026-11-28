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

  factory FieldNode.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as num?)?.toInt();
    if (id == null) throw const FormatException('FieldNode: missing id');
    return FieldNode(
      id: id,
      name: json['name'] as String? ?? '',
      parents:
          (json['parents'] as List?)
              ?.map((id) => (id as num).toInt())
              .toList() ??
          [],
      children:
          (json['children'] as List?)
              ?.map((id) => (id as num).toInt())
              .toList() ??
          [],
      isRoot: json['is_root'] as bool? ?? false,
    );
  }
}
