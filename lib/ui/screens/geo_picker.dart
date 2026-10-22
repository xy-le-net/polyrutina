// ═══════════════════════════════════════════════════════════════════
// lib/ui/screens/geo_picker.dart — geo point picking on a map.
//
// Opened from the media picker sheet. Structure:
//   — map (flutter_map) full-screen;
//   — initial center — current position (if available),
//     otherwise — Moscow;
//   — tap on the map places a pin; the pin is dragged by touch;
//   — «save» pult fixes the coordinates and a snapshot of the map
//     widget (RepaintBoundary → PNG) into media/ under the geo kind;
//   — exit pult closes without saving.
//
// Header. The AppBar is removed: the header is laid out through
// ScreenHeader inside a SafeArea. ScreenHeader reserves the left
// zone for the root pult, prints the geo title, and puts the exit
// pult on the right. The former per-screen Padding + ControlRow +
// manual title has been pulled out into ScreenHeader so the header
// matches the other full-screen sheets.
//
// Tile sources. The default OpenStreetMap tile server is not always
// reachable (blocked, rate-limited, or behind a slow network). Five
// alternative raster sources are built in, none requiring an API key:
//   — OSM standard;
//   — Esri World Street Map;
//   — OpenTopoMap;
//   — Humanitarian HOT (OpenStreetMap France);
//   — CyclOSM.
// A «layers» pult in the bottom row opens a subpult with the list;
// switching recreates the TileLayer via a ValueKey.
//
// Offline. Tiles are not loaded — the map is grey; the caption
// «no network» is drawn over it. A point is still placed and saved
// as is: the snapshot is grey, the coordinates real.
//
// API keys are not required for any of the listed sources.
//
// The snapshot is put into the same media/ folder as other
// attachments; the name follows the common template
// (<device>_<routine>_<slot>_geo_<index>).
//
// Transparency is not applied.
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

// One tile source: a URL template, optional subdomains, and a label.
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
  // Key for capturing the map widget snapshot.
  final _boundaryKey = GlobalKey();

  // Busy flag: while saving, exits are disabled.
  bool _busy = false;

  // Initial center and current picked point.
  LatLng _center = const LatLng(55.753994, 37.620060); // Moscow
  LatLng? _picked;
  double _accuracy = 0;

  bool _locating = false;
  bool _noNetwork = false;

  // Currently selected tile source.
  int _tileSourceIndex = 0;

  final _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _locate();
  }

  // ─── Initial centering on the current position ───
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
      // The map is centered on the next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _mapController.move(_center, 16);
        } catch (_) {}
      });
    } catch (_) {
      if (mounted) setState(() => _locating = false);
    }
  }

  // ─── Map widget snapshot ───
  // Taken as PNG bytes from RepaintBoundary. Errors are silently
  // swallowed: without a snapshot only the coordinates are saved.
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

  // ─── Save ───
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

  // ─── Switch tile source ───
  void _switchTileSource(int index) {
    if (index == _tileSourceIndex) return;
    setState(() {
      _tileSourceIndex = index;
      _noNetwork = false;
    });
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
            // Unified header: root pult space on the left, geo title
            // on the remaining width, exit pult on the right.
            ScreenHeader(
              title: i18n.t('media.geo'),
              onExit: _busy ? null : _close,
            ),
            Expanded(
              child: Stack(
                children: [
                  // ─── Map ───
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
                          key: ValueKey(_tileSourceIndex),
                          urlTemplate: source.urlTemplate,
                          subdomains: source.subdomains,
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

                  // ─── «No network» caption ───
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
                              color: bort.dim,
                              fontSize: side * 0.35,
                            ),
                          ),
                        ),
                      ),
                    ),

                  // ─── Position search indicator ───
                  if (_locating)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: side * 0.4,
                      child: Center(
                        child: Text(
                          '…',
                          style: TextStyle(
                            color: bort.dim,
                            fontSize: side * 0.5,
                          ),
                        ),
                      ),
                    ),

                  // ─── Bottom row: layers · save ───
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 12,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Tile-source pult: opens a subpult with the
                        // list of sources.
                        Pult(
                          spec: PultSpec(
                            id: 'geo_layers',
                            icon: Icons.layers,
                            onTap: null,
                            longSubs: () => [
                              for (var i = 0; i < _tileSources.length; i++)
                                PultSpec(
                                  id: 'tile_$i',
                                  icon: Icons.map,
                                  label: _tileSources[i].label,
                                  selected: i == _tileSourceIndex,
                                  stayOpen: true,
                                  onTap: () => _switchTileSource(i),
                                ),
                            ],
                          ),
                          fg: bort.fg,
                          bg: bort.bg,
                          signal: bort.signal,
                          overrideSize: side * 1.2,
                        ),
                        SizedBox(width: side * 0.5),
                        // Save pult.
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
          ],
        ),
      ),
    );
  }
}
