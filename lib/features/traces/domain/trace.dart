class TraceKind {
  static const String text = 'text';
  static const String checklist = 'checklist';
}

class MediaKind {
  static const String audio = 'audio';
  static const String photo = 'photo';
  static const String video = 'video';
  static const String geo = 'geo';
  static const String file = 'file';

  static const List<String> all = [audio, photo, video, geo, file];
}

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
    'items': items.map((item) => item.toJson()).toList(),
    'parents': parents,
    'children': children,
    'files': files.map((file) => file.toJson()).toList(),
    'field_parents': fieldParents,
    'deleted': deleted,
  };

  factory Trace.fromJson(int id, Map<String, dynamic> json) => Trace(
    id: id,
    kind: json['kind'] as String? ?? TraceKind.text,
    slot: json['slot'] as String? ?? '',
    text: json['text'] as String? ?? '',
    items:
        (json['items'] as List?)
            ?.map((item) => TraceItem.fromJson(item as Map<String, dynamic>))
            .toList() ??
        [],
    parents:
        (json['parents'] as List?)?.map((id) => (id as num).toInt()).toList() ??
        [],
    children:
        (json['children'] as List?)
            ?.map((id) => (id as num).toInt())
            .toList() ??
        [],
    files:
        (json['files'] as List?)
            ?.map((file) => TraceFile.fromJson(file as Map<String, dynamic>))
            .toList() ??
        [],
    fieldParents:
        (json['field_parents'] as List?)
            ?.map((id) => (id as num).toInt())
            .toList() ??
        [],
    deleted: json['deleted'] as bool? ?? false,
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

  factory TraceItem.fromJson(Map<String, dynamic> json) => TraceItem(
    text: json['text'] as String? ?? '',
    done: json['done'] as bool? ?? false,
    parents:
        (json['parents'] as List?)?.map((id) => (id as num).toInt()).toList() ??
        [],
    children:
        (json['children'] as List?)
            ?.map((id) => (id as num).toInt())
            .toList() ??
        [],
  );
}

class TraceFile {
  String kind;
  String path;
  String name;
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

  factory TraceFile.fromJson(Map<String, dynamic> json) => TraceFile(
    kind: json['kind'] as String? ?? 'file',
    path: json['path'] as String? ?? '',
    name: json['name'] as String? ?? '',
    lat: (json['lat'] as num?)?.toDouble(),
    lon: (json['lon'] as num?)?.toDouble(),
    acc: (json['acc'] as num?)?.toDouble(),
  );
}
