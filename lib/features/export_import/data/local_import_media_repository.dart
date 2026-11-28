import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:polyrutina/features/export_import/application/import_media_repository.dart';

class LocalImportMediaRepository implements ImportMediaRepository {
  @override
  Future<String> save(String fileName, List<int> bytes) async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, 'media'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final target = File(p.join(directory.path, fileName));
    try {
      await target.writeAsBytes(bytes, flush: true);
      return target.path;
    } catch (_) {
      if (await target.exists()) await target.delete();
      rethrow;
    }
  }

  @override
  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
