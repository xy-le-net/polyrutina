// ═══════════════════════════════════════════════════════════════════
// app_scope.dart — контекст приложения для вкладок.
//
// Вкладки берут из сего контекста слои, тикер и словарь, а также
// обратные вызовы: перезапрос интерфейса, перезагрузку словаря,
// открытие карточки рутины.
//
// Слои:
//   bort         — состояние интерфейса;
//   routineLayer — рутины и их блоки;
//   traceLayer   — следы;
//   journal      — слой журнала;
//   ticker       — единый тикер (500 мс) для всех таймеров
//                  и мелькания двоеточия.
//
// openRoutine — открытие карточки рутины чрез навигатор, что живёт
// в main. Нужно для восстановления открытой карточки при возврате
// на вкладку Рутины.
//
// toggleBlockWithShift — пуск блока при остановленной смене запускает
// смену. Обратного нет.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../data/journal_layer.dart';
import '../data/journal_types.dart';
import '../data/operational_layer.dart';
import '../data/routine_layer.dart';
import '../data/trace_layer.dart';
import '../data/ticker.dart';
import '../data/i18n.dart';

class AppContext {
  final OperationalLayer bort;
  final RoutineLayer routineLayer;
  final TraceLayer traceLayer;
  final JournalLayer journal;
  final AppTicker ticker;
  final I18n i18n;
  final Future<void> Function() refresh;
  final Future<void> Function() reloadI18n;
  final Future<void> Function(int routineId) openRoutine;

  const AppContext({
    required this.bort,
    required this.routineLayer,
    required this.traceLayer,
    required this.journal,
    required this.ticker,
    required this.i18n,
    required this.refresh,
    required this.reloadI18n,
    required this.openRoutine,
  });

  // ─── Пуск блока рутины с правилом связи ───
  // Ежели блок идёт — обычная пауза (без смены).
  // Ежели блок стоит — сперва, коли смена не идёт, запускаем смену;
  // затем пускаем блок (слой сам гасит прочие рутины).
  Future<void> toggleBlockWithShift(int routineId, String kind) async {
    final r = routineLayer.findRoutine(routineId);
    if (r == null) return;
    final b = r.blockOf(kind);
    if (b == null) return;

    final going = !b.isRunning;

    if (going && !bort.onShift) {
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
