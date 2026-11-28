import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:polyrutina/core/localization/providers.dart';
import 'package:polyrutina/features/settings/application/providers.dart';
import 'package:polyrutina/features/traces/application/providers.dart';
import 'package:polyrutina/shared/application/provider_read.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:polyrutina/features/traces/application/trace_layer.dart';
import 'package:polyrutina/features/traces/domain/geo_location.dart';
import 'package:polyrutina/core/application/providers.dart';
import 'package:polyrutina/shared/presentation/widgets/bort_field.dart';
import 'package:polyrutina/shared/presentation/bort_metrics.dart';
import 'package:polyrutina/shared/presentation/control_row.dart';
import 'package:polyrutina/shared/presentation/widgets/dialog_frame.dart';
import 'package:polyrutina/shared/presentation/pults/pult_core.dart';

Future<void> showGeoPicker({
  required BuildContext context,
  required int objectId,
  required String slot,
}) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
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

class _GeoPickerScreen extends ConsumerStatefulWidget {
  final int objectId;
  final String slot;
  const _GeoPickerScreen({required this.objectId, required this.slot});

  @override
  ConsumerState<_GeoPickerScreen> createState() => _GeoPickerScreenState();
}

class _GeoPickerScreenState extends ConsumerState<_GeoPickerScreen> {
  final _boundaryKey = GlobalKey();
  final _addressController = TextEditingController();
  final _addressFocus = FocusNode();
  bool _busy = false;
  bool _searchingAddress = false;
  String? _addressMessage;

  // Use Moscow when location is unavailable.
  LatLng _center = const LatLng(55.753994, 37.620060);
  LatLng? _picked;
  double _accuracy = 0;

  bool _locating = false;
  bool _noNetwork = false;
  bool _userTouched = false;

  int _tileSourceIndex = 0;
  final Set<int> _triedSources = {0};
  bool _userSwitched = false;

  final _mapController = MapController();
  StreamSubscription<GeoCoordinates>? _positionStream;

  @override
  void initState() {
    super.initState();
    _addressFocus.addListener(() {
      if (mounted) setState(() {});
    });
    _startTracking();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _addressController.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  void _startTracking() {
    setState(() => _locating = true);
    _positionStream = ref
        .read(geoRepositoryProvider)
        .watchPosition()
        .listen(
          (position) {
            if (!mounted || _userTouched) return;

            final point = LatLng(position.latitude, position.longitude);
            setState(() {
              _center = point;
              _picked = point;
              _accuracy = position.accuracy;
              _locating = false;
            });

            _mapController.move(point, _mapController.camera.zoom);
          },
          onError: (Object error) {
            if (mounted) setState(() => _locating = false);
          },
        );
  }

  Future<void> _locateCurrentPosition() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final position = await ref.read(geoRepositoryProvider).currentPosition();
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
            content: Text(
              readProvider(context, i18nProvider)!.t('media.location_failed'),
            ),
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

    setState(() {
      _searchingAddress = true;
      _addressMessage = null;
    });

    try {
      final results = await ref
          .read(geoRepositoryProvider)
          .searchAddress(
            query,
            language: readProvider(context, i18nProvider)!.lang,
          );

      if (results.isEmpty) {
        if (mounted) {
          setState(() {
            _addressMessage = readProvider(
              context,
              i18nProvider,
            )!.t('media.address_not_found');
          });
        }
        return;
      }

      if (!mounted) return;
      final metrics = BortMetrics.of(context, compact: true);
      final dialogWidth = math
          .min(
            metrics.unit(14),
            MediaQuery.sizeOf(context).width - metrics.unit(2.4),
          )
          .clamp(0.0, double.infinity)
          .toDouble();
      final result = await showDialog<GeoAddress>(
        context: context,
        builder: (ctx) => DialogFrame(
          onDismiss: () => Navigator.of(ctx).pop(),
          maxWidth: dialogWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DialogTitle(
                text: readProvider(
                  context,
                  i18nProvider,
                )!.t('media.search_address'),
              ),
              SizedBox(height: metrics.unit(0.4)),
              for (var index = 0; index < results.length; index++) ...[
                if (index > 0)
                  Divider(
                    height: metrics.unit(0.5),
                    color: readProvider(context, operationalLayerProvider).mid,
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(results[index].name),
                  onTap: () => Navigator.of(ctx).pop(results[index]),
                ),
              ],
            ],
          ),
        ),
      );
      if (result != null && mounted) {
        _positionStream?.cancel();
        final zoom = _mapController.camera.zoom.clamp(15.0, 19.0).toDouble();
        final point = LatLng(
          result.coordinates.latitude,
          result.coordinates.longitude,
        );
        setState(() {
          _center = point;
          _picked = point;
          _accuracy = 0;
          _userTouched = true;
          _addressController.text = result.name;
        });
        _mapController.move(point, zoom);
      }
    } catch (error, stackTrace) {
      debugPrint('Address search failed: $error\n$stackTrace');
      if (mounted) {
        setState(() {
          _addressMessage = readProvider(
            context,
            i18nProvider,
          )!.t('media.address_search_failed');
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

    try {
      final img = await _captureImage();
      String path = '';
      String name = '';

      if (img != null) {
        final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          final idx = readProvider(
            context,
            operationalLayerProvider,
          ).nextMediaIndex();
          name =
              'geo_$idx'
              '_${readProvider(context, operationalLayerProvider).deviceId}'
              '_${readProvider(context, operationalLayerProvider).firstRunUnixSec}.png';
          final dir = await getApplicationDocumentsDirectory();
          final media = Directory(p.join(dir.path, 'media'));
          if (!await media.exists()) await media.create(recursive: true);
          final file = File(p.join(media.path, name));
          await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
          path = file.path;
        }
      }

      await readProvider(context, traceLayerProvider).attachFile(
        readProvider(context, journalLayerProvider),
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
    final bort = readProvider(context, operationalLayerProvider);
    final i18n = readProvider(context, i18nProvider)!;
    final side = PultScope.of(context).smallSide;
    final metrics = BortMetrics.of(context, compact: true);
    final inputSize = metrics.textSize(
      _addressFocus.hasFocus ? BortTextRole.edit : BortTextRole.base,
    );

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
                        focusNode: _addressFocus,
                        style: bortInputTextStyle(
                          context,
                          color: bort.fg,
                          fontSize: inputSize,
                        ),
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _searchAddress(),
                        decoration: bortInputDecoration(
                          context,
                          borderColor: bort.fg,
                          hintText: i18n.t('media.search_address'),
                          fontSize: inputSize,
                          borderless: true,
                        ),
                      ),
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
                              // Keep the user's manual selection.
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
                                  fontSize: BortMetrics.of(
                                    context,
                                    compact: true,
                                  ).textSize(BortTextRole.caption),
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
                                  fontSize: BortMetrics.of(
                                    context,
                                    compact: true,
                                  ).textSize(BortTextRole.caption),
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
                                fontSize: BortMetrics.of(
                                  context,
                                  compact: true,
                                ).textSize(BortTextRole.header),
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

class GeoMapPreview extends ConsumerStatefulWidget {
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
  ConsumerState<GeoMapPreview> createState() => _GeoMapPreviewState();
}

class _GeoMapPreviewState extends ConsumerState<GeoMapPreview> {
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
      final position = await ref.read(geoRepositoryProvider).currentPosition();
      if (!mounted) return;
      _mapController.move(
        LatLng(position.latitude, position.longitude),
        _mapController.camera.zoom,
      );
    } catch (error, stackTrace) {
      debugPrint('Current location lookup failed: $error\n$stackTrace');
      if (mounted) {
        final i18n = readProvider(context, i18nProvider)!;
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
    final bort = readProvider(context, operationalLayerProvider);
    final i18n = readProvider(context, i18nProvider)!;
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
                      style: TextStyle(
                        color: bort.mid,
                        fontSize: BortMetrics.of(
                          context,
                          compact: true,
                        ).textSize(BortTextRole.caption),
                      ),
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
