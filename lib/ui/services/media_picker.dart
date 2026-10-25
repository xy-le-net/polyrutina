// ═══════════════════════════════════════════════════════════════════
// lib/ui/services/media_picker.dart — media selection and addition.
//
// Five kinds: audio, photo, video, geo, file. Audio — via a
// separate dialog (audio_dialog.dart). The rest — here.
//
// Opened via the single left-side sheet (pult_sheet.dart) —
// the same as all other subpults. The former
// showModalBottomSheet is removed.
//
// The file is copied to media/ with a template name:
//   <kind>_<index>_<deviceId>_<firstRun>.<ext>
// The index is a monotone per-device counter (InstallStore),
// independent of routine ids, so compaction does not invalidate
// names. Forbidden characters are replaced by safeFileName
// (format.dart) — one shared implementation for the whole app.
//
// Atomic copy. The file is first copied into <target>.tmp, then
// renamed onto the final name. A crash mid-copy cannot leave a
// half-written media file under the canonical name; the trace
// body (if written) points to a whole file, not a torn one.
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
import '../core/format.dart';
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
        // coordinates are put into media/ as the geo kind.
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
    signal: bort.fgsignal,
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
  } catch (_) {
    try {
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {}
    return;
  }

  await app.traceLayer.attachFile(
    app.journal,
    objectId: objectId,
    slot: slot,
    file: TraceFile(kind: kind, path: target.path, name: name),
  );
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
