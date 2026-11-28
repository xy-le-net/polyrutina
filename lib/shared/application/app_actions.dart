import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class AppActions {
  final Future<void> Function() refresh;
  final Future<void> Function() reloadI18n;
  final Future<void> Function(int routineId, {bool autofocusName}) openRoutine;
  final Future<void> Function(int routineId, BuildContext context)
  exportRoutine;
  final Future<void> Function() afterJournalReset;

  const AppActions({
    required this.refresh,
    required this.reloadI18n,
    required this.openRoutine,
    required this.exportRoutine,
    required this.afterJournalReset,
  });
}

final appActionsProvider = StateProvider<AppActions?>((ref) => null);

AppActions appActionsOf(BuildContext context) {
  final actions = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(appActionsProvider);
  assert(actions != null, 'Application actions are not initialized');
  return actions!;
}
