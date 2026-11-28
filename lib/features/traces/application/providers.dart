import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polyrutina/features/traces/data/geo_repository.dart';
import 'package:polyrutina/features/traces/application/trace_layer.dart';

final traceLayerProvider = ChangeNotifierProvider<TraceLayer>(
  (ref) => TraceLayer(),
);

final geoRepositoryProvider = Provider<GeoRepository>((ref) {
  final repository = GeolocatorGeoRepository();
  ref.onDispose(repository.close);
  return repository;
});
