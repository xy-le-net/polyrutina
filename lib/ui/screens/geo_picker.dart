// ═══════════════════════════════════════════════════════════════════
// geo_picker.dart — выбор геоточки на своей карте.
//
// Открывается из листа выбора медиа. Устройство:
//   — карта (flutter_map, тайлы OpenStreetMap) на весь экран;
//   — начальный центр — текущая позиция (ежели доступна),
//     иначе — Москва;
//   — тап по карте ставит пин; пин перетаскивается касанием;
//   — кнопка «сохранить» фиксирует координаты и снимок виджета
//     карты (RepaintBoundary → PNG) в media/ родом geo;
//   — кнопка ухода закрывает без сохранения.
//
// Без сети. Тайлы не подгружаются — карта серая; поверх выводится
// надпись «нет сети». Точка ставится и сохраняется как есть: снимок
// серый, координаты настоящие.
//
// Ключей API не требуется: тайлы OSM доступны напрямую.
//
// Снимок кладётся в ту же папку media/, что и прочие вложения;
// имя — по общему образцу (<устройство>_<рутина>_<слот>_geo_<индекс>).
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/trace_layer.dart';
import '../core/app_scope.dart';
import '../pults/pult_core.dart';

Future<void> showGeoPicker({
  required BuildContext context,
  required int objectId,
  required String slot,
}) async {
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => _GeoPickerScreen(objectId: objectId, slot: slot),
    ),
  );
}

class _GeoPickerScreen extends StatefulWidget {
  final int objectId;
  final String slot;
  const _GeoPickerScreen({required this.objectId, required this.slot});

  @override
  State<_GeoPickerScreen> createState() => _GeoPickerScreenState();
}

class _GeoPickerScreenState extends State<_GeoPickerScreen> {
  // Ключ для захвата снимка виджета карты.
  final _boundaryKey = GlobalKey();

  // Снимок карты в байтах — по «сохранить».
  bool _busy = false;

  // Начальный центр и текущая выбранная точка.
  LatLng _center = const LatLng(55.753994, 37.620060); // Москва
  LatLng? _picked;
  double _accuracy = 0;

  bool _locating = false;
  bool _noNetwork = false;

  final _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _locate();
  }

  // ─── Первоначальное центрирование по текущей позиции ───
  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() => _locating = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _center = LatLng(pos.latitude, pos.longitude);
        _accuracy = pos.accuracy;
        _locating = false;
      });
      // Карта центрируется при следующем кадре.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _mapController.move(_center, 16);
        } catch (_) {}
      });
    } catch (_) {
      if (mounted) setState(() => _locating = false);
    }
  }

  // ─── Снимок виджета карты ───
  // Берётся PNG-байтами из RepaintBoundary. Ошибки тихо гасятся:
  // без снимка сохранится только координата.
  Future<ui.Image?> _captureImage() async {
    try {
      final boundary =
          _boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return null;
      return await boundary.toImage(pixelRatio: 2.0);
    } catch (_) {
      return null;
    }
  }

  // ─── Сохранение ───
  // Снимок кладётся в media/ рядом с прочими вложениями; имя —
  // по общему образцу. Координаты и путь кладутся в TraceFile.
  Future<void> _save() async {
    if (_busy) return;
    final latLng = _picked;
    if (latLng == null) return;

    setState(() => _busy = true);
    final app = AppScope.of(context);

    try {
      final img = await _captureImage();
      String path = '';
      String name = '';

      if (img != null) {
        final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          final idx = app.bort.nextExportIndex(
            'media_${widget.objectId}_${widget.slot}_geo',
          );
          name =
              '${app.bort.deviceId}_${widget.objectId}_${widget.slot}'
              '_geo_$idx.png';
          final dir = await getApplicationDocumentsDirectory();
          final media = Directory(p.join(dir.path, 'media'));
          if (!await media.exists()) await media.create(recursive: true);
          final file = File(p.join(media.path, name));
          await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
          path = file.path;
        }
      }

      await app.traceLayer.attachFile(
        app.journal,
        objectId: widget.objectId,
        slot: widget.slot,
        file: TraceFile(
          kind: MediaKind.geo,
          path: path,
          name: name,
          lat: latLng.latitude,
          lon: latLng.longitude,
          acc: _accuracy > 0 ? _accuracy : null,
        ),
      );
    } catch (_) {}

    if (mounted) Navigator.of(context).pop();
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    final side = PultScope.of(context).smallSide;

    return Scaffold(
      backgroundColor: bort.bg,
      appBar: AppBar(
        backgroundColor: bort.bg,
        foregroundColor: bort.fg,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: side * 1.4,
        title: Text(i18n.t('media.geo'), style: TextStyle(color: bort.fg)),
        actions: [
          Pult(
            spec: PultSpec(
              id: 'geo_cancel',
              icon: Icons.close,
              onTap: _busy ? null : _close,
            ),
            fg: bort.fg,
            bg: bort.bg,
            signal: bort.signal,
            overrideSize: side * bort.kPultSmall,
          ),
          SizedBox(width: side * 0.4),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // ─── Карта ───
            RepaintBoundary(
              key: _boundaryKey,
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _center,
                  initialZoom: 16,
                  onTap: (_, p) {
                    setState(() => _picked = p);
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'polyrutina',
                    errorTileCallback: (_, __, ___) {
                      if (mounted && !_noNetwork) {
                        setState(() => _noNetwork = true);
                      }
                    },
                  ),
                  if (_picked != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _picked!,
                          width: 40,
                          height: 40,
                          child: Icon(
                            Icons.place,
                            color: bort.signal,
                            size: 40,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),

            // ─── Надпись «нет сети» ───
            if (_noNetwork)
              Positioned(
                left: 0,
                right: 0,
                top: side * 0.4,
                child: Center(
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: side * 0.3,
                      vertical: side * 0.1,
                    ),
                    color: bort.bg,
                    child: Text(
                      i18n.t('media.no_network'),
                      style: TextStyle(color: bort.dim, fontSize: side * 0.35),
                    ),
                  ),
                ),
              ),

            // ─── Индикатор поиска позиции ───
            if (_locating)
              Positioned(
                left: 0,
                right: 0,
                top: side * 0.4,
                child: Center(
                  child: Text(
                    '…',
                    style: TextStyle(color: bort.dim, fontSize: side * 0.5),
                  ),
                ),
              ),

            // ─── Пульт сохранения ───
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Pult(
                    spec: PultSpec(
                      id: 'geo_save',
                      icon: _busy ? Icons.hourglass_top : Icons.check,
                      selected: _picked != null,
                      onTap: (_busy || _picked == null) ? null : _save,
                    ),
                    fg: _picked != null ? bort.fg : bort.dim,
                    bg: bort.bg,
                    signal: bort.signal,
                    overrideSize: side * 1.2,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
