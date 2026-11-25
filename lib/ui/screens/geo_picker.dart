import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/trace_layer.dart';
import '../core/app_scope.dart';
import '../core/control_row.dart';
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

class _AddressResult {
  final String name;
  final LatLng point;

  const _AddressResult({required this.name, required this.point});
}

List<PultSpec> _tileSourceSpecs(
  int selectedIndex,
  ValueChanged<int> onSelect, {
  required String prefix,
}) => [
  for (var i = 0; i < _tileSources.length; i++)
    PultSpec(
      id: '${prefix}_tile_$i',
      icon: Icons.map,
      label: _tileSources[i].label,
      selected: i == selectedIndex,
      onTap: () => onSelect(i),
    ),
];

double _calculateMapZoom(
  double lat,
  double smallerSideMeters,
  double screenPixels,
) {
  if (smallerSideMeters <= 0 || screenPixels <= 0) return 19;
  final scale =
      (screenPixels * 156543.03392 * math.cos(lat * math.pi / 180)) /
      smallerSideMeters;
  return (math.log(scale) / math.ln2).clamp(2.0, 19.0).toDouble();
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
  static DateTime? _lastAddressRequest;

  final _boundaryKey = GlobalKey();
  final _addressController = TextEditingController();
  bool _busy = false;
  bool _searchingAddress = false;
  String? _addressMessage;

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
    _addressController.dispose();
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

  Future<void> _locateCurrentPosition() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('Location permission was denied');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      final point = LatLng(position.latitude, position.longitude);
      _positionStream?.cancel();
      setState(() {
        _center = point;
        _picked = point;
        _accuracy = position.accuracy;
        _userTouched = true;
      });
      _mapController.move(point, _mapController.camera.zoom);
    } catch (error, stackTrace) {
      debugPrint('Current location lookup failed: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(AppScope.of(context).i18n.t('media.location_failed')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _searchAddress() async {
    final query = _addressController.text.trim();
    if (_searchingAddress || query.isEmpty) return;

    final app = AppScope.of(context);
    setState(() {
      _searchingAddress = true;
      _addressMessage = null;
    });

    try {
      final previousRequest = _lastAddressRequest;
      if (previousRequest != null) {
        final elapsed = DateTime.now().difference(previousRequest);
        if (elapsed < const Duration(seconds: 1)) {
          await Future<void>.delayed(const Duration(seconds: 1) - elapsed);
        }
      }
      _lastAddressRequest = DateTime.now();

      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'jsonv2',
        'limit': '5',
        'q': query,
        'accept-language': app.i18n.lang,
      });
      final response = await http
          .get(
            uri,
            headers: {
              'User-Agent':
                  'polyrutina/0.1.1 (https://github.com/xy-le-net/polyrutina)',
            },
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw HttpException(
          'Address search returned HTTP ${response.statusCode}',
        );
      }

      final data = jsonDecode(response.body);
      if (data is! List) {
        throw const FormatException('Invalid address search response');
      }
      final results = <_AddressResult>[];
      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;
        final lat = double.tryParse(item['lat']?.toString() ?? '');
        final lon = double.tryParse(item['lon']?.toString() ?? '');
        final name = item['display_name'];
        if (lat == null ||
            lon == null ||
            lat < -90 ||
            lat > 90 ||
            lon < -180 ||
            lon > 180 ||
            name is! String) {
          continue;
        }
        results.add(_AddressResult(name: name, point: LatLng(lat, lon)));
      }

      if (results.isEmpty) {
        if (mounted) {
          setState(() {
            _addressMessage = app.i18n.t('media.address_not_found');
          });
        }
        return;
      }

      if (!mounted) return;
      final result = await showDialog<_AddressResult>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: app.bort.fgsignal,
              width: PultScope.of(context).smallSide * app.bort.kStroke,
            ),
            borderRadius: BorderRadius.circular(
              PultScope.of(context).smallSide * app.bort.kRadius * 1.15,
            ),
          ),
          backgroundColor: app.bort.bg,
          title: Text(app.i18n.t('media.search_address')),
          content: SizedBox(
            width: 420,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: results.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = results[index];
                return ListTile(
                  title: Text(item.name),
                  onTap: () => Navigator.of(context).pop(item),
                );
              },
            ),
          ),
        ),
      );
      if (result != null && mounted) {
        _positionStream?.cancel();
        final zoom = _mapController.camera.zoom.clamp(15.0, 19.0).toDouble();
        setState(() {
          _center = result.point;
          _picked = result.point;
          _accuracy = 0;
          _userTouched = true;
          _addressController.text = result.name;
        });
        _mapController.move(result.point, zoom);
      }
    } catch (error, stackTrace) {
      debugPrint('Address search failed: $error\n$stackTrace');
      if (mounted) {
        setState(() {
          _addressMessage = app.i18n.t('media.address_search_failed');
        });
      }
    } finally {
      if (mounted) setState(() => _searchingAddress = false);
    }
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

  void _onTileError(int sourceIndex) {
    if (!mounted || sourceIndex != _tileSourceIndex) return;
    if (_userSwitched) {
      if (!_noNetwork) setState(() => _noNetwork = true);
      return;
    }
    for (var i = 0; i < _tileSources.length; i++) {
      if (!_triedSources.contains(i)) {
        _switchTileSource(i);
        return;
      }
    }
    if (!_noNetwork) setState(() => _noNetwork = true);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    final side = PultScope.of(context).smallSide;

    final sourceIndex = _tileSourceIndex;
    final source = _tileSources[sourceIndex];

    return Scaffold(
      backgroundColor: bort.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8, right: 6),
              child: ControlRow(
                rootSide: side,
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _addressController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _searchAddress(),
                        decoration: InputDecoration(
                          hintText: i18n.t('media.search_address'),
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            vertical: side * 0.1,
                          ),
                        ),
                      ),
                    ),
                    Pult(
                      spec: PultSpec(
                        id: 'header_exit',
                        icon: Icons.keyboard_arrow_down,
                        onTap: _busy ? null : _close,
                      ),
                      fg: bort.fg,
                      bg: bort.bg,
                      signal: bort.fgsignal,
                      overrideSize: side * bort.kPultSmall,
                    ),
                  ],
                ),
              ),
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
                            initialZoom: _calculateMapZoom(
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
                              userAgentPackageName: 'com.example.polyrutina',
                              errorTileCallback: (_, __, ___) =>
                                  _onTileError(sourceIndex),
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
                      if (_addressMessage != null)
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
                                _addressMessage!,
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
                                subsBuilder: () => _tileSourceSpecs(
                                  _tileSourceIndex,
                                  (i) => _switchTileSource(i, byUser: true),
                                  prefix: 'geo',
                                ),
                              ),
                              fg: bort.fg,
                              bg: bort.bg,
                              signal: bort.fgsignal,
                              overrideSize: side * 1.2,
                            ),
                            SizedBox(width: side * 0.5),
                            Pult(
                              spec: PultSpec(
                                id: 'geo_locate',
                                icon: _locating
                                    ? Icons.hourglass_top
                                    : Icons.gps_fixed,
                                onTap: _locateCurrentPosition,
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

class GeoMapPreview extends StatefulWidget {
  final double latitude;
  final double longitude;
  final String? fallbackImagePath;

  const GeoMapPreview({
    super.key,
    required this.latitude,
    required this.longitude,
    this.fallbackImagePath,
  });

  @override
  State<GeoMapPreview> createState() => _GeoMapPreviewState();
}

class _GeoMapPreviewState extends State<GeoMapPreview> {
  final _mapController = MapController();
  final Set<int> _triedSources = {0};
  int _tileSourceIndex = 0;
  bool _noNetwork = false;
  bool _locating = false;
  bool _userSwitched = false;

  @override
  void didUpdateWidget(covariant GeoMapPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latitude == widget.latitude &&
        oldWidget.longitude == widget.longitude) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _mapController.move(
          LatLng(widget.latitude, widget.longitude),
          _mapController.camera.zoom,
        );
      }
    });
  }

  void _switchTileSource(int index, {bool byUser = false}) {
    if (index == _tileSourceIndex) return;
    if (byUser) _userSwitched = true;
    _triedSources.add(index);
    setState(() {
      _tileSourceIndex = index;
      _noNetwork = false;
    });
  }

  void _onTileError(int sourceIndex) {
    if (!mounted || sourceIndex != _tileSourceIndex) return;
    if (_noNetwork) return;
    if (!_userSwitched) {
      for (var i = 0; i < _tileSources.length; i++) {
        if (!_triedSources.contains(i)) {
          _switchTileSource(i);
          return;
        }
      }
    }
    setState(() => _noNetwork = true);
  }

  Future<void> _locateCurrentPosition() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('Location permission was denied');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      _mapController.move(
        LatLng(position.latitude, position.longitude),
        _mapController.camera.zoom,
      );
    } catch (error, stackTrace) {
      debugPrint('Current location lookup failed: $error\n$stackTrace');
      if (mounted) {
        final i18n = AppScope.of(context).i18n;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(i18n.t('media.location_failed'))),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    final side = PultScope.of(context).smallSide;
    final point = LatLng(widget.latitude, widget.longitude);
    final sourceIndex = _tileSourceIndex;
    final source = _tileSources[sourceIndex];
    final fallbackPath = widget.fallbackImagePath;
    final hasFallback =
        _noNetwork &&
        fallbackPath != null &&
        fallbackPath.isNotEmpty &&
        File(fallbackPath).existsSync();

    return LayoutBuilder(
      builder: (context, constraints) {
        final smallerSidePx = math.min(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        return Stack(
          children: [
            Positioned.fill(
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: point,
                  initialZoom: _calculateMapZoom(
                    point.latitude,
                    bort.mapScale.toDouble(),
                    smallerSidePx,
                  ),
                ),
                children: [
                  TileLayer(
                    key: ValueKey(sourceIndex),
                    urlTemplate: source.urlTemplate,
                    subdomains: source.subdomains,
                    userAgentPackageName: 'com.example.polyrutina',
                    errorTileCallback: (_, __, ___) =>
                        _onTileError(sourceIndex),
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: point,
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
            if (hasFallback)
              Positioned.fill(
                child: Image.file(File(fallbackPath), fit: BoxFit.cover),
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
                      style: TextStyle(color: bort.mid, fontSize: side * 0.35),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: side * 0.25,
              right: side * 0.25,
              child: Column(
                children: [
                  Pult(
                    spec: PultSpec(
                      id: 'geo_preview_layers',
                      icon: Icons.layers,
                      subsBuilder: () => _tileSourceSpecs(
                        _tileSourceIndex,
                        (i) => _switchTileSource(i, byUser: true),
                        prefix: 'geo_preview',
                      ),
                    ),
                    fg: bort.fg,
                    bg: bort.bg,
                    signal: bort.fgsignal,
                    overrideSize: side,
                  ),
                  SizedBox(height: side * 0.25),
                  Pult(
                    spec: PultSpec(
                      id: 'geo_preview_locate',
                      icon: _locating ? Icons.hourglass_top : Icons.gps_fixed,
                      onTap: _locateCurrentPosition,
                    ),
                    fg: bort.fg,
                    bg: bort.bg,
                    signal: bort.fgsignal,
                    overrideSize: side,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
