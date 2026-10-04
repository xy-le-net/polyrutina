// ═══════════════════════════════════════════════════════════════════
// app_scope.dart — контекст приложения для вкладок.
//
// Вкладки берут из сего контекста: борт, слой рутин, журнал, i18n,
// обратные вызовы (перечесть данные, сменить язык).
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../data/journal_repository.dart';
import '../data/operational_layer.dart';
import '../data/routine_layer.dart';
import '../data/i18n.dart';

class AppContext {
  final OperationalLayer bort;
  final RoutineLayer routineLayer;
  final JournalRepository journal;
  final I18n i18n;
  final Future<void> Function() refresh;
  final Future<void> Function() reloadI18n;

  const AppContext({
    required this.bort,
    required this.routineLayer,
    required this.journal,
    required this.i18n,
    required this.refresh,
    required this.reloadI18n,
  });
}

class AppScope extends InheritedWidget {
  final AppContext appContext;

  const AppScope({
    super.key,
    required this.appContext,
    required super.child,
  });

  static AppContext of(BuildContext c) {
    final scope = c.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope не найден');
    return scope!.appContext;
  }

  @override
  bool updateShouldNotify(covariant AppScope oldWidget) {
    return true;
  }
}
