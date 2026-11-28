import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polyrutina/features/settings/application/operational_layer.dart';

final operationalLayerProvider = ChangeNotifierProvider<OperationalLayer>(
  (ref) => OperationalLayer(),
);
