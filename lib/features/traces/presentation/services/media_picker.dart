import 'dart:io';

import 'package:polyrutina/core/localization/providers.dart';
import 'package:polyrutina/features/settings/application/providers.dart';
import 'package:polyrutina/features/traces/application/providers.dart';
import 'package:polyrutina/core/application/providers.dart';
import 'package:polyrutina/shared/application/provider_read.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:polyrutina/features/traces/application/trace_layer.dart';
import 'package:polyrutina/shared/application/format.dart';
import 'package:polyrutina/shared/presentation/pults/pult_core.dart';
import 'package:polyrutina/shared/presentation/pults/pult_sheet.dart';
import 'package:polyrutina/features/traces/presentation/screens/geo_picker.dart';
import 'package:polyrutina/features/traces/presentation/screens/windows_camera_capture.dart';
import 'package:polyrutina/features/traces/presentation/services/audio_dialog.dart';

Future<void> showMediaPicker({
  required BuildContext context,
  required int objectId,
  required String slot,
}) async {
  final i18n = readProvider(context, i18nProvider)!;
  final bort = readProvider(context, operationalLayerProvider);
  final side = PultScope.of(context).smallSide;

  showPultSheet(
    context: context,
    subs: [
      PultSpec(
        id: 'pick_${MediaKind.audio}',
        icon: Icons.mic_none,
        label: i18n.t('media.audio'),
        onTap: () => showAudioDialog(context, objectId: objectId, slot: slot),
      ),
      PultSpec(
        id: 'pick_${MediaKind.photo}',
        icon: Icons.photo_camera_outlined,
        label: i18n.t('media.photo'),
        onTap: () => _addPhotoLoop(context, objectId, slot),
      ),
      PultSpec(
        id: 'pick_${MediaKind.video}',
        icon: Icons.videocam_outlined,
        label: i18n.t('media.video'),
        onTap: () => _addVideoLoop(context, objectId, slot),
      ),
      PultSpec(
        id: 'pick_${MediaKind.geo}',
        icon: Icons.place_outlined,
        label: i18n.t('media.geo'),
        // The geo point is picked on a custom map (geo_picker.dart):
        // a tap on the map, confirmation — a widget snapshot and
        // coordinates are put into media/ as the geo kind.
        onTap: () =>
            showGeoPicker(context: context, objectId: objectId, slot: slot),
      ),
      PultSpec(
        id: 'pick_${MediaKind.file}',
        icon: Icons.attach_file,
        label: i18n.t('media.file'),
        onTap: () => _addFile(context, objectId, slot),
      ),
    ],
    fg: bort.fg,
    bg: bort.bg,
    signal: bort.fgsignal,
    side: side,
  );
}

Future<void> _attach(
  BuildContext context, {
  required int objectId,
  required String slot,
  required String kind,
  required String sourcePath,
  required String ext,
}) async {
  final bort = readProvider(context, operationalLayerProvider);
  final traceLayer = readProvider(context, traceLayerProvider);
  final journal = readProvider(context, journalLayerProvider);

  final idx = bort.nextMediaIndex();
  final base = '${kind}_${idx}_${bort.deviceId}_${bort.firstRunUnixSec}$ext';
  final name = safeFileName(base);

  final dir = await getApplicationDocumentsDirectory();
  final media = Directory(p.join(dir.path, 'media'));
  if (!await media.exists()) await media.create(recursive: true);
  final target = File(p.join(media.path, name));
  final tmp = File('${target.path}.tmp');

  try {
    // Atomic copy: write to .tmp, then rename onto the final name.
    await File(sourcePath).copy(tmp.path);
    await tmp.rename(target.path);
  } catch (error, stackTrace) {
    try {
      if (await tmp.exists()) await tmp.delete();
    } catch (cleanupError, cleanupStackTrace) {
      debugPrint(
        'Temporary media cleanup failed: $cleanupError\n$cleanupStackTrace',
      );
    }
    Error.throwWithStackTrace(error, stackTrace);
  }

  await traceLayer.attachFile(
    journal,
    objectId: objectId,
    slot: slot,
    file: TraceFile(kind: kind, path: target.path, name: name),
  );
}

Future<void> _addPhotoLoop(
  BuildContext context,
  int objectId,
  String slot,
) async {
  while (true) {
    final took = await _pickOncePhoto(context, objectId, slot);
    if (!took) return;
  }
}

Future<bool> _pickOncePhoto(
  BuildContext context,
  int objectId,
  String slot,
) async {
  try {
    final x = Platform.isWindows
        ? await captureWindowsCamera(context, video: false)
        : await ImagePicker().pickImage(source: ImageSource.camera);
    if (x == null || !context.mounted) return false;
    final ext = p.extension(x.path);
    await _attach(
      context,
      objectId: objectId,
      slot: slot,
      kind: MediaKind.photo,
      sourcePath: x.path,
      ext: ext.isEmpty ? '.jpg' : ext,
    );
    return true;
  } catch (error, stackTrace) {
    if (context.mounted) _showMediaError(context, error, stackTrace);
    return false;
  }
}

Future<void> _addVideoLoop(
  BuildContext context,
  int objectId,
  String slot,
) async {
  while (true) {
    final took = await _pickOnceVideo(context, objectId, slot);
    if (!took) return;
  }
}

Future<bool> _pickOnceVideo(
  BuildContext context,
  int objectId,
  String slot,
) async {
  try {
    final x = Platform.isWindows
        ? await captureWindowsCamera(context, video: true)
        : await ImagePicker().pickVideo(source: ImageSource.camera);
    if (x == null || !context.mounted) return false;
    final ext = p.extension(x.path);
    await _attach(
      context,
      objectId: objectId,
      slot: slot,
      kind: MediaKind.video,
      sourcePath: x.path,
      ext: ext.isEmpty ? '.mp4' : ext,
    );
    return true;
  } catch (error, stackTrace) {
    if (context.mounted) _showMediaError(context, error, stackTrace);
    return false;
  }
}

void _showMediaError(
  BuildContext context,
  Object error,
  StackTrace stackTrace,
) {
  debugPrint('Media capture failed: $error\n$stackTrace');
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(
        readProvider(context, i18nProvider)!.t('media.capture_failed'),
      ),
    ),
  );
}

Future<void> _addFile(BuildContext context, int objectId, String slot) async {
  try {
    final r = await FilePicker.platform.pickFiles();
    if (r == null || r.files.isEmpty || !context.mounted) return;
    final f = r.files.first;
    if (f.path == null) return;
    final ext = p.extension(f.path!);
    await _attach(
      context,
      objectId: objectId,
      slot: slot,
      kind: MediaKind.file,
      sourcePath: f.path!,
      ext: ext,
    );
  } catch (error, stackTrace) {
    if (context.mounted) _showMediaError(context, error, stackTrace);
  }
}

// where the point was placed. Now — a custom map (geo_picker.dart),
// where the point is confirmed visually, and a snapshot of the map
// widget is saved along with the coordinates.
