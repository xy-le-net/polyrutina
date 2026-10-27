// ═══════════════════════════════════════════════════════════════════
// lib/ui/screens/geo_picker.dart — geo point picking on a map.
//
// Opened from the media picker sheet. Structure:
//   — map (flutter_map) full-screen;
//   — initial center — current position (if available);
//   — live GPS tracking until the user touches the map. The marker
//     follows the position stream and stops on the first tap;
//   — tap on the map places a pin;
//   — «save» pult fixes the coordinates and a snapshot of the map
//     widget (RepaintBoundary → PNG) into media/ under the geo kind;
//   — exit pult closes without saving.
//
// Scale. The default zoom is calculated so that the smaller side of
// the screen corresponds to `bort.mapScale` meters (default 40). The
// formula depends on the latitude and the screen size.
//
// User-Agent. Changed to 'com.polyrutina.app' to avoid blocks from
// OSM tile servers.
//
// Tile sources. Five alternative raster sources are built in, none
// requiring an API key (OSM, Esri, OpenTopo, HOT, CyclOSM).
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
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
import '../core/screen_header.dart';
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

class _TileSource {
  final String label;
  final String urlTemplate;
  final List<String> subdomains;

  const _TileSource({
    required this.label,
    required this.urlTemplate,
    this.subdomains = const [],
  });
}

const List<_TileSource> _tileSources = [
  _TileSource(
    label: 'OSM',
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  ),
  _TileSource(
    label: 'Esri',
    urlTemplate:
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
  ),
  _TileSource(
    label: 'OpenTopo',
    urlTemplate: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
    subdomains: ['a', 'b', 'c'],
  ),
  _TileSource(
    label: 'HOT',
    urlTemplate: 'https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
    subdomains: ['a', 'b', 'c'],
  ),
  _TileSource(
    label: 'CyclOSM',
    urlTemplate:
        'https://{s}.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png',
    subdomains: ['a', 'b', 'c'],
  ),
];

class _GeoPickerScreen extends StatefulWidget {
  final int objectId;
  final String slot;
  const _GeoPickerScreen({required this.objectId, required this.slot});

  @override
  State<_GeoPickerScreen> createState() => _GeoPickerScreenState();
}

class _GeoPickerScreenState extends State<_GeoPickerScreen> {
  final _boundaryKey = GlobalKey();
  bool _busy = false;

  LatLng _center = const LatLng(55.753994, 37.620060); // Moscow fallback
  LatLng? _picked;
  double _accuracy = 0;

  bool _locating = false;
  bool _noNetwork = false;
  bool _userTouched = false;

  int _tileSourceIndex = 0;
  final Set<int> _triedSources = {0};
  bool _userSwitched = false;

  final _mapController = MapController();
  StreamSubscription<Position>? _positionStream;

  @override
  void initState() {
    super.initState();
    _startTracking();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  void _startTracking() {
    setState(() => _locating = true);

    // Request permission then listen to stream
    Geolocator.checkPermission()
        .then((perm) async {
          if (perm == LocationPermission.denied) {
            perm = await Geolocator.requestPermission();
          }
          if (perm == LocationPermission.denied ||
              perm == LocationPermission.deniedForever) {
            setState(() => _locating = false);
            return;
          }

          const locationSettings = LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 2,
          );

          _positionStream =
              Geolocator.getPositionStream(
                locationSettings: locationSettings,
              ).listen(
                (Position pos) {
                  if (!mounted || _userTouched) return;

                  final newPos = LatLng(pos.latitude, pos.longitude);
                  setState(() {
                    _center = newPos;
                    _picked = newPos;
                    _accuracy = pos.accuracy;
                    _locating = false;
                  });

                  _mapController.move(newPos, _mapController.camera.zoom);
                },
                onError: (e) {
                  if (mounted) setState(() => _locating = false);
                },
              );
        })
        .catchError((_) {
          if (mounted) setState(() => _locating = false);
        });
  }

  double _calculateZoom(
    double lat,
    double smallerSideMeters,
    double screenPixels,
  ) {
    // metersPerPixel = 156543.03392 * cos(lat * pi / 180) / 2^zoom
    // smallerSideMeters / screenPixels = metersPerPixel
    // 2^zoom = (screenPixels * 156543.03392 * cos(lat)) / smallerSideMeters
    final scale =
        (screenPixels * 156543.03392 * math.cos(lat * math.pi / 180)) /
        smallerSideMeters;
    return math.log(scale) / math.ln2;
  }

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
          final idx = app.bort.nextMediaIndex();
          name =
              'geo_$idx'
              '_${app.bort.deviceId}'
              '_${app.bort.firstRunUnixSec}.png';
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

  void _switchTileSource(int index, {bool byUser = false}) {
    if (index == _tileSourceIndex) return;
    if (byUser) _userSwitched = true;
    _triedSources.add(index);
    setState(() {
      _tileSourceIndex = index;
      _noNetwork = false;
    });
  }

  void _autoFallbackIfNeeded() {
    if (_userSwitched) return;
    for (var i = 0; i < _tileSources.length; i++) {
      if (!_triedSources.contains(i)) {
        _switchTileSource(i);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    final side = PultScope.of(context).smallSide;

    final source = _tileSources[_tileSourceIndex];

    return Scaffold(
      backgroundColor: bort.bg,
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: i18n.t('media.geo'),
              onExit: _busy ? null : _close,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final smallerSidePx = math.min(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );

                  return Stack(
                    children: [
                      RepaintBoundary(
                        key: _boundaryKey,
                        child: FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: _center,
                            initialZoom: _calculateZoom(
                              _center.latitude,
                              bort.mapScale.toDouble(),
                              smallerSidePx,
                            ),
                            onTap: (_, p) {
                              // Stop tracking on first tap
                              _positionStream?.cancel();
                              setState(() {
                                _userTouched = true;
                                _picked = p;
                              });
                            },
                          ),
                          children: [
                            TileLayer(
                              key: ValueKey(_tileSourceIndex),
                              urlTemplate: source.urlTemplate,
                              subdomains: source.subdomains,
                              userAgentPackageName: 'com.polyrutina.app',
                              errorTileCallback: (_, __, ___) {
                                if (!mounted) return;
                                if (_noNetwork) return;
                                setState(() => _noNetwork = true);
                                _autoFallbackIfNeeded();
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
                                      color: bort.fgsignal,
                                      size: 40,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
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
                                style: TextStyle(
                                  color: bort.mid,
                                  fontSize: side * 0.35,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_locating)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: side * 0.4,
                          child: Center(
                            child: Text(
                              '…',
                              style: TextStyle(
                                color: bort.mid,
                                fontSize: side * 0.5,
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 12,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Pult(
                              spec: PultSpec(
                                id: 'geo_layers',
                                icon: Icons.layers,
                                subsBuilder: () => [
                                  for (var i = 0; i < _tileSources.length; i++)
                                    PultSpec(
                                      id: 'tile_$i',
                                      icon: Icons.map,
                                      label: _tileSources[i].label,
                                      selected: i == _tileSourceIndex,
                                      onTap: () =>
                                          _switchTileSource(i, byUser: true),
                                    ),
                                ],
                              ),
                              fg: bort.fg,
                              bg: bort.bg,
                              signal: bort.fgsignal,
                              overrideSize: side * 1.2,
                            ),
                            SizedBox(width: side * 0.5),
                            Pult(
                              spec: PultSpec(
                                id: 'geo_save',
                                icon: _busy ? Icons.hourglass_top : Icons.check,
                                selected: _picked != null,
                                onTap: (_busy || _picked == null)
                                    ? null
                                    : _save,
                              ),
                              fg: _picked != null ? bort.fg : bort.mid,
                              bg: bort.bg,
                              signal: bort.fgsignal,
                              overrideSize: side * 1.2,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
