// ═══════════════════════════════════════════════════════════════════
// media_picker.dart — лист выбора и добавления медиа.
//
// Пять родов: аудио, фото, видео, место, файл. Аудио — отдельным
// диалогом (audio_dialog.dart). Прочие — здесь.
//
// Открывается единым левосторонним листом (pult_sheet.dart) —
// тем же, что и все прочие подпульты. Прежний showModalBottomSheet
// упразднён.
//
// Файл копируется в media/ с именем по образцу:
//   <устройство>_<номер рутины>_<слот>_<род>_<индекс>.<расш>
//
// Серия фото/видео: после возврата из системной съёмки лист
// не закрывается — открывается снова. Выход — «назад».
//
// Место. Отдельный json-файл не пишется: координаты в TraceFile.
//
// AppContext берётся ДО awaits.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/trace_layer.dart';
import '../core/app_scope.dart';
import '../pults/pult_core.dart';
import '../pults/pult_sheet.dart';
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
        onTap: () => _addGeo(app, objectId, slot),
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

// ─── Копирование и прикрепление ───
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

String _safe(String s) {
  final bad = RegExp(r'[\\/:*?"<>|]');
  return s.replaceAllMapped(bad, (_) => 'X');
}

// ─── Фото: серия ───
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

// ─── Видео: серия ───
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

// ─── Файл ───
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

// ─── Геопозиция ───
Future<void> _addGeo(AppContext app, int objectId, String slot) async {
  try {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }
    final pos = await Geolocator.getCurrentPosition();
    final bort = app.bort;
    final idx = bort.nextExportIndex('media_${objectId}_${slot}_geo');
    final name = _safe('${bort.deviceId}_${objectId}_${slot}_geo_$idx');
    await app.traceLayer.attachFile(
      app.journal,
      objectId: objectId,
      slot: slot,
      file: TraceFile(
        kind: MediaKind.geo,
        path: '',
        name: name,
        lat: pos.latitude,
        lon: pos.longitude,
        acc: pos.accuracy,
      ),
    );
  } catch (_) {}
}
