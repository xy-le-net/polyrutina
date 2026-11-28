import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polyrutina/features/routines/application/routine_layer.dart';

final routineLayerProvider = ChangeNotifierProvider<RoutineLayer>(
  (ref) => RoutineLayer(),
);
