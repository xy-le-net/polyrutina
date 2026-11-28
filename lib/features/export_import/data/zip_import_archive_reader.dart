import 'package:archive/archive_io.dart';

import 'package:polyrutina/features/export_import/application/import_archive_reader.dart';

class ZipImportArchiveReader implements ImportArchiveReader {
  @override
  Future<List<ImportArchiveEntry>> read(String path) async {
    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeBuffer(input);
      return [
        for (final file in archive.files)
          ImportArchiveEntry(
            name: file.name,
            isFile: file.isFile,
            content: List<int>.from(file.content as List<int>),
          ),
      ];
    } finally {
      await input.close();
    }
  }
}
