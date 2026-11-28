import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

T readProvider<T>(BuildContext context, ProviderListenable<T> provider) {
  return ProviderScope.containerOf(context, listen: false).read(provider);
}
