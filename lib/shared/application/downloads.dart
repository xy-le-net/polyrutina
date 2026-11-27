import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _downloadsChannel = MethodChannel('polyrutina/downloads');

class SavedDownload {
  const SavedDownload({required this.name, required this.location});

  final String name;
  final String location;
}

Future<Directory> _polyrutinaDownloadsDirectory() async {
  final downloads = await getDownloadsDirectory();
  if (downloads == null) {
    throw UnsupportedError('Downloads directory is unavailable');
  }
  final directory = Directory(p.join(downloads.path, 'polyrutina'));
  await directory.create(recursive: true);
  return directory;
}

Future<File> _availableTarget(Directory directory, String fileName) async {
  final name = p.basename(fileName);
  final extension = p.extension(name);
  final stem = p.basenameWithoutExtension(name);
  var target = File(p.join(directory.path, name));
  var suffix = 1;
  while (await target.exists()) {
    target = File(p.join(directory.path, '${stem}_$suffix$extension'));
    suffix++;
  }
  return target;
}

Future<SavedDownload> saveFileToDownloads(File source) async {
  if (Platform.isAndroid) {
    final name = await _downloadsChannel.invokeMethod<String>(
      'saveFile',
      {'sourcePath': source.path, 'fileName': p.basename(source.path)},
    );
    if (name == null) {
      throw StateError('Android did not return the saved file name');
    }
    return SavedDownload(
      name: name,
      location: 'Downloads/polyrutina/$name',
    );
  }

  final directory = await _polyrutinaDownloadsDirectory();
  final target = await _availableTarget(directory, p.basename(source.path));
  await source.copy(target.path);
  return SavedDownload(name: p.basename(target.path), location: target.path);
}

Future<SavedDownload> saveTextToDownloads(String fileName, String text) async {
  if (Platform.isAndroid) {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'polyrutina_',
    );
    try {
      final temporaryFile = File(
        p.join(temporaryDirectory.path, p.basename(fileName)),
      );
      await temporaryFile.writeAsString(text);
      return await saveFileToDownloads(temporaryFile);
    } finally {
      await temporaryDirectory.delete(recursive: true);
    }
  }

  final directory = await _polyrutinaDownloadsDirectory();
  final target = await _availableTarget(directory, fileName);
  await target.writeAsString(text);
  return SavedDownload(name: p.basename(target.path), location: target.path);
}
