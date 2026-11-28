class ImportArchiveEntry {
  const ImportArchiveEntry({
    required this.name,
    required this.isFile,
    required this.content,
  });

  final String name;
  final bool isFile;
  final List<int> content;
}

abstract interface class ImportArchiveReader {
  Future<List<ImportArchiveEntry>> read(String path);
}
