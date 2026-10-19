// ═══════════════════════════════════════════════════════════════════
// media_picker.dart — media selection and addition sheet.
//
// Five kinds: audio, photo, video, geo, file. Audio — via a
// separate dialog (audio_dialog.dart). The rest — here.
//
// Opened via the single left-side sheet (pult_sheet.dart) —
// the same as all other subpults. The former
// showModalBottomSheet is removed.
//
// The file is copied to media/ with a template name:
//   <device>_<routine id>_<slot>_<kind>_<index>.<ext>
//
// Photo/video series: after returning from the system camera
// the sheet does not close — it opens again. Exit — «back».
//
// Geo. No separate json file is written: coordinates are in
// the trace file structure (TraceFile). The geo point is picked
// on a custom map (geo_picker.dart): a tap on the map,
// confirmation — a widget snapshot and coordinates are put into
// media/ as the geo kind.
//
// Application context (AppContext) is taken BEFORE awaits.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/trace_layer.dart';
import '../core/app_scope.dart';
import '../pults/pult_core.dart';
import '../pults/pult_sheet.dart';
import '../screens/geo_picker.dart';
import 'audio_dialog.dart';

Future<void> showMediaPicker({
  required BuildContext context,
  required int objectId,
  required String slot,
}) async {
  final app = AppScope.of(context);
  final i18n = app.i18n;
  final bort = app.bort;
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
        onTap: () => _addPhotoLoop(app, objectId, slot),
      ),
      PultSpec(
        id: 'pick_${MediaKind.video}',
        icon: Icons.videocam_outlined,
        label: i18n.t('media.video'),
        onTap: () => _addVideoLoop(app, objectId, slot),
      ),
      PultSpec(
        id: 'pick_${MediaKind.geo}',
        icon: Icons.place_outlined,
        label: i18n.t('media.geo'),
        // The geo point is picked on a custom map (geo_picker.dart):
        // a tap on the map, confirmation — a widget snapshot and
        // coordinates are put into media/ as the geo kind. The former
        // direct geolocator call is removed: the user did not see
        // where the point was placed.
        onTap: () =>
            showGeoPicker(context: context, objectId: objectId, slot: slot),
      ),
      PultSpec(
        id: 'pick_${MediaKind.file}',
        icon: Icons.attach_file,
        label: i18n.t('media.file'),
        onTap: () => _addFile(app, objectId, slot),
      ),
    ],
    fg: bort.fg,
    bg: bort.bg,
    signal: bort.signal,
    side: side,
  );
}

// ─── Copying and attaching ───
Future<void> _attach(
  AppContext app, {
  required int objectId,
  required String slot,
  required String kind,
  required String sourcePath,
  required String ext,
}) async {
  final bort = app.bort;

  final idx = bort.nextExportIndex('media_${objectId}_${slot}_$kind');
  final base = '${bort.deviceId}_${objectId}_${slot}_${kind}_$idx$ext';
  final name = _safe(base);

  final dir = await getApplicationDocumentsDirectory();
  final media = Directory(p.join(dir.path, 'media'));
  if (!await media.exists()) await media.create(recursive: true);
  final target = File(p.join(media.path, name));

  try {
    await File(sourcePath).copy(target.path);
  } catch (_) {
    return;
  }

  await app.traceLayer.attachFile(
    app.journal,
    objectId: objectId,
    slot: slot,
    file: TraceFile(kind: kind, path: target.path, name: name),
  );
}

// Replacing forbidden characters with an uppercase «X».
String _safe(String s) {
  final bad = RegExp(r'[\\/:*?"<>|]');
  return s.replaceAllMapped(bad, (_) => 'X');
}

// ─── Photo: series ───
Future<void> _addPhotoLoop(AppContext app, int objectId, String slot) async {
  while (true) {
    final took = await _pickOncePhoto(app, objectId, slot);
    if (!took) return;
  }
}

Future<bool> _pickOncePhoto(AppContext app, int objectId, String slot) async {
  try {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.camera);
    if (x == null) return false;
    final ext = p.extension(x.path);
    await _attach(
      app,
      objectId: objectId,
      slot: slot,
      kind: MediaKind.photo,
      sourcePath: x.path,
      ext: ext.isEmpty ? '.jpg' : ext,
    );
    return true;
  } catch (_) {
    return false;
  }
}

// ─── Video: series ───
Future<void> _addVideoLoop(AppContext app, int objectId, String slot) async {
  while (true) {
    final took = await _pickOnceVideo(app, objectId, slot);
    if (!took) return;
  }
}

Future<bool> _pickOnceVideo(AppContext app, int objectId, String slot) async {
  try {
    final picker = ImagePicker();
    final x = await picker.pickVideo(source: ImageSource.camera);
    if (x == null) return false;
    final ext = p.extension(x.path);
    await _attach(
      app,
      objectId: objectId,
      slot: slot,
      kind: MediaKind.video,
      sourcePath: x.path,
      ext: ext.isEmpty ? '.mp4' : ext,
    );
    return true;
  } catch (_) {
    return false;
  }
}

// ─── File ───
Future<void> _addFile(AppContext app, int objectId, String slot) async {
  try {
    final r = await FilePicker.platform.pickFiles();
    if (r == null || r.files.isEmpty) return;
    final f = r.files.first;
    if (f.path == null) return;
    final ext = p.extension(f.path!);
    await _attach(
      app,
      objectId: objectId,
      slot: slot,
      kind: MediaKind.file,
      sourcePath: f.path!,
      ext: ext,
    );
  } catch (_) {}
}

// The former direct geolocator call is removed: the user did not see
// where the point was placed. Now — a custom map (geo_picker.dart),
// where the point is confirmed visually, and a snapshot of the map
// widget is saved along with the coordinates.
