// ═══════════════════════════════════════════════════════════════════
// media_picker.dart — подпульт выбора и добавления медиа.
//
// Пять родов: аудио, фото, видео, место, файл. Каждый — средствами
// телефона чрез тонкие зависимости:
//   photo/video — image_picker,
//   audio       — record,
//   geo         — geolocator,
//   file        — file_picker.
//
// Файл копируется в папку приложения media/ с именем по образцу:
//   <устройство>_<номер рутины>_<слот>_<род>_<индекс>.<расш>
// Индекс не уменьшается при удалении: берётся из счётчика борта.
//
// Серия фото/видео. После возврата из системной съёмки подпульт
// не закрывается: открывается снова, дабы делать серию. Выход —
// кнопкою «назад» либо закрытием подпутя.
//
// Место. Отдельный json-файл не пишется: координаты (широта,
// долгота, точность) кладутся прямо в TraceFile.
//
// AppContext берётся ДО awaits — дабы BuildContext не тянулся
// чрез асинхронные промежутки.
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
import 'package:record/record.dart';

import '../../data/trace_layer.dart';
import '../core/app_scope.dart';
import '../pults/pult_core.dart';

Future<void> showMediaPicker({
  required BuildContext context,
  required int objectId,
  required String slot,
  required Color fg,
  required Color dim,
  required Color bg,
  required Color signal,
  required double side,
}) async {
  final app = AppScope.of(context);
  final i18n = app.i18n;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: bg,
    builder: (sheetContext) {
      final pultSide = side * 0.9;
      final items = <(String, IconData, String, Future<void> Function())>[
        (
          MediaKind.audio,
          Icons.mic_none,
          i18n.t('media.audio'),
          () => _addAudio(context, objectId, slot),
        ),
        (
          MediaKind.photo,
          Icons.photo_camera_outlined,
          i18n.t('media.photo'),
          () => _addPhotoLoop(app, objectId, slot),
        ),
        (
          MediaKind.video,
          Icons.videocam_outlined,
          i18n.t('media.video'),
          () => _addVideoLoop(app, objectId, slot),
        ),
        (
          MediaKind.geo,
          Icons.place_outlined,
          i18n.t('media.geo'),
          () => _addGeo(app, objectId, slot),
        ),
        (
          MediaKind.file,
          Icons.attach_file,
          i18n.t('media.file'),
          () => _addFile(app, objectId, slot),
        ),
      ];

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: side * 0.2,
            runSpacing: side * 0.15,
            children: [
              for (final it in items)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Pult(
                      spec: PultSpec(
                        id: 'pick_${it.$1}',
                        icon: it.$2,
                        onTap: () async {
                          Navigator.of(sheetContext).pop();
                          await it.$4();
                        },
                      ),
                      fg: fg,
                      bg: bg,
                      signal: signal,
                      overrideSize: pultSide,
                    ),
                    SizedBox(height: side * 0.1),
                    Text(
                      it.$3,
                      style: TextStyle(color: dim, fontSize: side * 0.32),
                    ),
                  ],
                ),
            ],
          ),
        ),
      );
    },
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

// ─── Замена запретных знаков заглавною «X» ───
String _safe(String s) {
  final bad = RegExp(r'[\\/:*?"<>|]');
  return s.replaceAllMapped(bad, (_) => 'X');
}

// ─── Фото: серия ───
// После каждой съёмки — снова открыть камеру. Выход — «назад».
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
// Отдельный файл не пишется: координаты кладутся прямо в тело следа.
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

// ─── Аудио ───
Future<void> _addAudio(BuildContext c, int objectId, String slot) async {
  await showDialog<void>(
    context: c,
    barrierDismissible: false,
    builder: (_) => _AudioDialog(objectId: objectId, slot: slot),
  );
}

class _AudioDialog extends StatefulWidget {
  final int objectId;
  final String slot;
  const _AudioDialog({required this.objectId, required this.slot});

  @override
  State<_AudioDialog> createState() => _AudioDialogState();
}

class _AudioDialogState extends State<_AudioDialog> {
  final _rec = AudioRecorder();
  bool _running = false;
  String? _path;
  String? _name;

  Future<void> _start() async {
    try {
      if (!await _rec.hasPermission()) return;
      final dir = await getApplicationDocumentsDirectory();
      final media = Directory(p.join(dir.path, 'media'));
      if (!await media.exists()) await media.create(recursive: true);
      if (!mounted) return;
      final app = AppScope.of(context);
      final idx = app.bort.nextExportIndex(
        'media_${widget.objectId}_${widget.slot}_audio',
      );
      final name = _safe(
        '${app.bort.deviceId}_${widget.objectId}_${widget.slot}'
        '_audio_$idx.m4a',
      );
      final path = p.join(media.path, name);
      await _rec.start(const RecordConfig(), path: path);
      if (!mounted) return;
      setState(() {
        _running = true;
        _path = path;
        _name = name;
      });
    } catch (_) {}
  }

  Future<void> _stop({required bool attach}) async {
    try {
      await _rec.stop();
      if (!mounted) return;
      final path = _path;
      final name = _name;
      if (attach && path != null && name != null) {
        final app = AppScope.of(context);
        await app.traceLayer.attachFile(
          app.journal,
          objectId: widget.objectId,
          slot: widget.slot,
          file: TraceFile(kind: MediaKind.audio, path: path, name: name),
        );
      }
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _rec.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final i18n = app.i18n;
    final bort = app.bort;
    final side = PultScope.of(context).smallSide;
    return Dialog(
      backgroundColor: bort.bg,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              i18n.t('media.audio'),
              style: TextStyle(color: bort.fg, fontSize: side * 0.4),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Pult(
                  spec: PultSpec(
                    id: 'audio_toggle',
                    icon: _running ? Icons.stop : Icons.fiber_manual_record,
                    selected: _running,
                    onTap: _running
                        ? () => _stop(attach: true)
                        : () => _start(),
                  ),
                  fg: bort.fg,
                  bg: bort.bg,
                  signal: bort.signal,
                  overrideSize: side * 1.2,
                ),
                const SizedBox(width: 16),
                Pult(
                  spec: PultSpec(
                    id: 'audio_cancel',
                    icon: Icons.close,
                    onTap: () => _running
                        ? _stop(attach: false)
                        : Navigator.of(context).pop(),
                  ),
                  fg: bort.fg,
                  bg: bort.bg,
                  signal: bort.signal,
                  overrideSize: side,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
