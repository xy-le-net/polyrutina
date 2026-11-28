import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polyrutina/features/fields/application/field_repository.dart';
import 'package:polyrutina/features/fields/application/field_layer.dart';
import 'package:polyrutina/features/fields/data/json_field_repository.dart';

final fieldRepositoryProvider = Provider<FieldRepository>(
  (ref) => JsonFieldRepository(),
);

final fieldLayerProvider = ChangeNotifierProvider<FieldLayer>(
  (ref) => FieldLayer(ref.watch(fieldRepositoryProvider)),
);
