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
