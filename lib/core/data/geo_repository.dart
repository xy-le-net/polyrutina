import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class GeoCoordinates {
  final double latitude;
  final double longitude;
  final double accuracy;

  const GeoCoordinates({
    required this.latitude,
    required this.longitude,
    this.accuracy = 0,
  });
}

class GeoAddress {
  final String name;
  final GeoCoordinates coordinates;

  const GeoAddress({required this.name, required this.coordinates});
}

abstract interface class GeoRepository {
  Stream<GeoCoordinates> watchPosition();
  Future<GeoCoordinates> currentPosition();
  Future<List<GeoAddress>> searchAddress(
    String query, {
    required String language,
  });
  void close();
}

class GeolocatorGeoRepository implements GeoRepository {
  static DateTime? _lastAddressRequest;

  final http.Client _client;

  GeolocatorGeoRepository({http.Client? client})
    : _client = client ?? http.Client();

  @override
  Stream<GeoCoordinates> watchPosition() async* {
    await _ensureLocationPermission();
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 2,
    );
    await for (final position in Geolocator.getPositionStream(
      locationSettings: settings,
    )) {
      yield _coordinates(position);
    }
  }

  @override
  Future<GeoCoordinates> currentPosition() async {
    await _ensureLocationPermission();
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).timeout(const Duration(seconds: 15));
    return _coordinates(position);
  }

  Future<void> _ensureLocationPermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Location permission was denied');
    }
  }

  GeoCoordinates _coordinates(Position position) => GeoCoordinates(
    latitude: position.latitude,
    longitude: position.longitude,
    accuracy: position.accuracy,
  );

  @override
  Future<List<GeoAddress>> searchAddress(
    String query, {
    required String language,
  }) async {
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
      'accept-language': language,
    });
    final response = await _client
        .get(
          uri,
          headers: {
            'User-Agent':
                'polyrutina/0.1.1 (https://github.com/xy-le-net/polyrutina)',
          },
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw Exception('Address search returned HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    if (data is! List) {
      throw const FormatException('Invalid address search response');
    }
    final addresses = <GeoAddress>[];
    for (final item in data) {
      final address = _parseAddress(item);
      if (address != null) addresses.add(address);
    }
    return addresses;
  }

  GeoAddress? _parseAddress(Object? item) {
    if (item is! Map<String, dynamic>) return null;
    final latitude = double.tryParse(item['lat']?.toString() ?? '');
    final longitude = double.tryParse(item['lon']?.toString() ?? '');
    final name = item['display_name'];
    if (latitude == null ||
        longitude == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180 ||
        name is! String) {
      return null;
    }
    return GeoAddress(
      name: name,
      coordinates: GeoCoordinates(latitude: latitude, longitude: longitude),
    );
  }

  @override
  void close() {
    _client.close();
  }
}
