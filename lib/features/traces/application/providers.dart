import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polyrutina/features/traces/data/geo_repository.dart';
import 'package:polyrutina/features/traces/application/trace_repository.dart';
import 'package:polyrutina/features/traces/data/json_trace_repository.dart';
import 'package:polyrutina/features/traces/application/trace_layer.dart';

final traceLayerProvider = ChangeNotifierProvider<TraceLayer>(
  (ref) => TraceLayer(ref.watch(traceRepositoryProvider)),
);

final traceRepositoryProvider = Provider<TraceRepository>(
  (ref) => JsonTraceRepository(),
);

final geoRepositoryProvider = Provider<GeoRepository>((ref) {
  final repository = GeolocatorGeoRepository();
  ref.onDispose(repository.close);
  return repository;
});
