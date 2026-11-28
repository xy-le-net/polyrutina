import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:polyrutina/features/export_import/application/import_archive_reader.dart';
import 'package:polyrutina/features/export_import/application/import_media_repository.dart';
import 'package:polyrutina/features/export_import/application/import_service.dart';
import 'package:polyrutina/features/export_import/data/local_import_media_repository.dart';
import 'package:polyrutina/features/export_import/data/zip_import_archive_reader.dart';

final importArchiveReaderProvider = Provider<ImportArchiveReader>(
  (ref) => ZipImportArchiveReader(),
);

final importMediaRepositoryProvider = Provider<ImportMediaRepository>(
  (ref) => LocalImportMediaRepository(),
);

final archiveImportServiceProvider = Provider<ArchiveImportService>(
  (ref) => ArchiveImportService(
    archiveReader: ref.watch(importArchiveReaderProvider),
    mediaRepository: ref.watch(importMediaRepositoryProvider),
  ),
);
