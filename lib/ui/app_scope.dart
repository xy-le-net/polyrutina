// ═══════════════════════════════════════════════════════════════════
// app_scope.dart — контекст приложения для вкладок.
//
// Вкладки берут из сего контекста слои и словарь, а также два
// обратных вызова: перезапрос интерфейса и перезагрузку словаря.
//
// Слои:
//   bort         — состояние интерфейса, цвета, коэффициенты;
//   routineLayer — рутины и их блоки;
//   traceLayer   — следы;
//   journal      — слой журнала (чтение, запись, регистрация слоёв).
//
// Метод toggleBlockWithShift — пуск блока с правилом связи смены
// и рутины: пуск рутины при остановленной смене запускает смену.
// Обратного правила нет.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../data/journal_layer.dart';
import '../data/journal_types.dart';
import '../data/operational_layer.dart';
import '../data/routine_layer.dart';
import '../data/trace_layer.dart';
import '../data/i18n.dart';

class AppContext {
  final OperationalLayer bort;
  final RoutineLayer routineLayer;
  final TraceLayer traceLayer;
  final JournalLayer journal;
  final I18n i18n;
  final Future<void> Function() refresh;
  final Future<void> Function() reloadI18n;

  const AppContext({
    required this.bort,
    required this.routineLayer,
    required this.traceLayer,
    required this.journal,
    required this.i18n,
    required this.refresh,
    required this.reloadI18n,
  });

  // ─── Пуск блока с правилом связи смены ───
  // Ежели пускаем блок (а не останавливаем), и смена не идёт —
  // запускаем смену. Обратного нет: пуск смены рутину не пускает.
  // Остановка смены гасит рутину — то правило живёт в обработчике
  // пульса смены (вкладка рутин).
  Future<void> toggleBlockWithShift(int routineId, String kind) async {
    final r = routineLayer.findRoutine(routineId);
    if (r == null) return;
    final b = r.blockOf(kind);
    if (b == null) return;

    // Пускаем, а не гасим.
    final willStart = !b.isRunning;

    if (willStart && !bort.onShift) {
      await journal.log(
        type: JournalType.actor,
        body: '{"action":"shift_start"}',
      );
      bort.startShift();
    }
    await routineLayer.toggleBlock(journal, routineId, kind);
  }
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
