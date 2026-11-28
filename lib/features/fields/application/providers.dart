import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polyrutina/features/fields/application/field_layer.dart';

final fieldLayerProvider = ChangeNotifierProvider<FieldLayer>(
  (ref) => FieldLayer(),
);
