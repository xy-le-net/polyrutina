// ═══════════════════════════════════════════════════════════════════
// app_scope.dart — контекст приложения и точечные области видимости.
//
// AppContext — неизменный набор зависимостей и делегатов. Живёт
// столько же, сколько приложение; пересоздаётся при смене языка
// (и то — в пределах одного кадра).
//
// AppScope (InheritedWidget) отдаёт AppContext. Уведомляет лишь
// при смене самого контекста, а не при изменениях слоёв: обновления
// UI идут чрез точечные области (см. ниже).
//
// Точечные области:
//   BortScope    — OperationalLayer: тема, смена, время борта.
//   RoutineScope — RoutineLayer: карточки, списки, дни.
//   TraceScope   — TraceLayer: поля следов, чек-листы, медиа.
//   TickerScope  — AppTicker: таймеры и мигание двоеточия.
//   I18nScope    — словарь: строки интерфейса.
//
// Каждая область — InheritedNotifier (I18n — InheritedWidget).
// Виджет, читающий слой, зависит от соответственной области и
// пересобирается лишь при её изменении.
//
// toggleBlockWithShift и toggleShift — делегаты AppContext: связь
// смены и рутин чрез журнал (род actor).
//
// pulseBort — уведомить борт о действии пользователя.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/i18n.dart';
import '../../data/journal_layer.dart';
import '../../data/journal_types.dart';
import '../../data/operational_layer.dart';
import '../../data/routine_layer.dart';
import '../../data/ticker.dart';
import '../../data/trace_layer.dart';

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

    // The mutex flag lives in the operational layer; the routine
    // layer merely obeys. When mutex is off, other blocks keep
    // running.
    await routineLayer.toggleBlock(
      journal,
      routineId,
      kind,
      mutex: bort.mutexRoutines,
      mutexSlots: bort.mutexSlots,
    );
  }

  // ─── Смена ───
  Future<void> toggleShift() async {
    final going = !bort.onShift;
    await journal.log(
      type: JournalType.actor,
      body: '{"action":"${going ? 'shift_start' : 'shift_stop'}"}',
    );
    if (going) {
      bort.startShift();
      return;
    }
    bort.stopShift();
    // Walk every routine, not only the current one: with routine
    // mutex off, several blocks may be running at once, and all of
    // them must stop when the shift stops. The routine layer is the
    // single source of truth for which blocks are running; the bort
    // keeps no parallel list.
    for (final r in routineLayer.routines) {
      for (final b in r.blocks) {
        if (b.isRunning) {
          await routineLayer.pauseBlock(journal, r.id, b.kind);
        }
      }
    }
  }

  // ─── Действие пользователя ───
  void pulseBort() {
    bort.pulseBort();
  }
}

// ─── AppScope: постоянный контекст ───
// Уведомляет токмо при смене самого AppContext (по полям). Изменения
// слоёв сюда не доходят: обновление UI идёт чрез точечные области.
class AppScope extends InheritedWidget {
  final AppContext appContext;

  const AppScope({super.key, required this.appContext, required super.child});

  static AppContext of(BuildContext c) {
    final scope = c.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope не найден');
    return scope!.appContext;
  }

  @override
  bool updateShouldNotify(covariant AppScope old) {
    // Tear-off методов в Dart стабилен: сравнение по ссылке
    // корректно и для делегатов (refresh, reloadI18n, openRoutine).
    return old.appContext.bort != appContext.bort ||
        old.appContext.routineLayer != appContext.routineLayer ||
        old.appContext.traceLayer != appContext.traceLayer ||
        old.appContext.journal != appContext.journal ||
        old.appContext.ticker != appContext.ticker ||
        old.appContext.i18n != appContext.i18n ||
        old.appContext.refresh != appContext.refresh ||
        old.appContext.reloadI18n != appContext.reloadI18n ||
        old.appContext.openRoutine != appContext.openRoutine;
  }
}

// ─── BortScope ───
// Подписчики: тема, смена, время борта, коллапсы блоков.
class BortScope extends InheritedNotifier<OperationalLayer> {
  const BortScope({
    super.key,
    required OperationalLayer bort,
    required super.child,
  }) : super(notifier: bort);

  static OperationalLayer of(BuildContext c) {
    final s = c.dependOnInheritedWidgetOfExactType<BortScope>();
    assert(s != null, 'BortScope не найден');
    return s!.notifier!;
  }
}

// ─── RoutineScope ───
// Подписчики: RoutineCard, RoutinePlate, RoutinesTab, DaysTab.
class RoutineScope extends InheritedNotifier<RoutineLayer> {
  const RoutineScope({
    super.key,
    required RoutineLayer routineLayer,
    required super.child,
  }) : super(notifier: routineLayer);

  static RoutineLayer of(BuildContext c) {
    final s = c.dependOnInheritedWidgetOfExactType<RoutineScope>();
    assert(s != null, 'RoutineScope не найден');
    return s!.notifier!;
  }
}

// ─── TraceScope ───
// Подписчики: TraceField, ChecklistScreen, RoutineCard (по _hasTrace),
// MediaViewer (при удалении).
class TraceScope extends InheritedNotifier<TraceLayer> {
  const TraceScope({
    super.key,
    required TraceLayer traceLayer,
    required super.child,
  }) : super(notifier: traceLayer);

  static TraceLayer of(BuildContext c) {
    final s = c.dependOnInheritedWidgetOfExactType<TraceScope>();
    assert(s != null, 'TraceScope не найден');
    return s!.notifier!;
  }
}

// ─── TickerScope ───
// Подписчики: Pulse, TimerText, RoutineCard, RoutinesTab, ShiftRow.
class TickerScope extends InheritedNotifier<AppTicker> {
  const TickerScope({
    super.key,
    required AppTicker ticker,
    required super.child,
  }) : super(notifier: ticker);

  static AppTicker of(BuildContext c) {
    final s = c.dependOnInheritedWidgetOfExactType<TickerScope>();
    assert(s != null, 'TickerScope не найден');
    return s!.notifier!;
  }
}

// ─── I18nScope ───
// Подписчики: всё, что печатает строки. I18n меняется редко — при
// смене языка; сие редкое событие и пересобирает подписчиков.
class I18nScope extends InheritedWidget {
  final I18n i18n;

  const I18nScope({super.key, required this.i18n, required super.child});

  static I18n of(BuildContext c) {
    final s = c.dependOnInheritedWidgetOfExactType<I18nScope>();
    assert(s != null, 'I18nScope не найден');
    return s!.i18n;
  }

  @override
  bool updateShouldNotify(I18nScope old) => old.i18n != i18n;
}
