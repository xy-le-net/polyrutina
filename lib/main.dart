// ═══════════════════════════════════════════════════════════════════
// main.dart — точка входа и управитель.
//
// Порядок пуска: журнал (init без подписки), борт, слои, словарь.
// Затем — journal.start().
//
// Вкладка по умолчанию. При каждом запуске открывается вкладка
// «рутины». Пометка о вкладке в файле борта не читается; поле
// bort.tab в сем приложении более не употребительно.
//
// Вкладки: поле, рутины, дни, артель, рубка. Вкладка журнала
// упразднена; слой JournalLayer жив внутри и кормит прочие слои.
//
// Действие пользователя. Listener вокруг дерева ловит касание —
// борт получает сигнал (pulseBort).
//
// Время борта. Подписка на тикер: борт тикает, раз в тридцать
// секунд сверяет полночь.
//
// Системная строка. Стиль overlay-полосы — от темы борта.
//
// Корневой пульт — жёстко в левом верхнем углу. Касание открывает
// единый левосторонний лист подпультов (pult_sheet.dart) с родами
// вкладок. PultLayer упразднён.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/database.dart';
import 'data/i18n.dart';
import 'data/journal_layer.dart';
import 'data/operational_layer.dart';
import 'data/routine_layer.dart';
import 'data/ticker.dart';
import 'data/trace_layer.dart';
import 'ui/cards/routine_card.dart';
import 'ui/core/app_scope.dart';
import 'ui/pults/pult_core.dart';
import 'ui/pults/pult_sheet.dart';
import 'ui/pults/root_pult.dart';
import 'ui/tabs/days_tab.dart';
import 'ui/tabs/routines_tab.dart';
import 'ui/tabs/rubka_tab.dart';
import 'ui/tabs/stub_tab.dart';

void main() => runApp(const PolyRutinaApp());

class PolyRutinaApp extends StatefulWidget {
  const PolyRutinaApp({super.key});
  @override
  State<PolyRutinaApp> createState() => _PolyRutinaAppState();
}

class _PolyRutinaAppState extends State<PolyRutinaApp>
    with WidgetsBindingObserver {
  late final AppDb _db;
  late final JournalLayer _journal;
  late final OperationalLayer _bort;
  late final RoutineLayer _routineLayer;
  late final TraceLayer _traceLayer;
  late final AppTicker _ticker;
  final _pultState = PultState();
  final _navigatorKey = GlobalKey<NavigatorState>();

  I18n? _i18n;

  // Вкладка по умолчанию — рутины.
  int _tab = 1;

  int? _openedRoutineId;

  VoidCallback? _onTickerTick;

  static const List<RootTabItem> _tabs = [
    RootTabItem(icon: Icons.map, labelKey: 'tab.field'),
    RootTabItem(icon: Icons.checklist, labelKey: 'tab.routines'),
    RootTabItem(icon: Icons.calendar_month, labelKey: 'tab.days'),
    RootTabItem(icon: Icons.groups, labelKey: 'tab.artel'),
    RootTabItem(icon: Icons.dashboard, labelKey: 'tab.rubka'),
  ];

  static const double _pultBase = 32.0;
  static const double _pultMax = 64.0;

  static const double _rootPad = 6.0;

  @override
  void initState() {
    super.initState();
    // Наблюдатель жизненного цикла: уход — запись слоёв, возврат —
    // переразрешение темы (в фоне система могла сменить гамму).
    WidgetsBinding.instance.addObserver(this);
    _db = AppDb();
    _journal = JournalLayer(_db);
    _bort = OperationalLayer();
    _routineLayer = RoutineLayer();
    _traceLayer = TraceLayer();
    _ticker = AppTicker();

    _onTickerTick = () => _bort.tickBort();
    _ticker.addListener(_onTickerTick!);

    _bort.addListener(_onLayerChanged);
    _routineLayer.addListener(_onLayerChanged);
    _traceLayer.addListener(_onLayerChanged);
    _journal.addListener(_onLayerChanged);
    _init();
  }

  void _onLayerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _init() async {
    final systemBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    await _journal.init();
    await _bort.init(systemBrightness);
    await _routineLayer.init(_journal, _traceLayer);
    await _traceLayer.init(_journal);
    _i18n = await I18n.load(_bort.lang);
    _journal.start();
    // Метка перечитывания — на текущий конец журнала: кнопка
    // «перечитать» становится активной, лишь ежели после сего
    // в журнал что-то добавилось.
    _bort.setLastRereadId(await _journal.lastEntryId());
    if (mounted) setState(() {});
  }

  Future<void> _reloadI18n() async {
    final i18n = await I18n.load(_bort.lang);
    if (mounted) setState(() => _i18n = i18n);
  }

  Future<void> _refreshAll() async {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_onTickerTick != null) {
      _ticker.removeListener(_onTickerTick!);
    }
    _bort.removeListener(_onLayerChanged);
    _routineLayer.removeListener(_onLayerChanged);
    _traceLayer.removeListener(_onLayerChanged);
    _journal.removeListener(_onLayerChanged);
    _bort.dispose();
    _routineLayer.dispose();
    _traceLayer.dispose();
    _journal.dispose();
    _ticker.dispose();
    _db.close();
    _pultState.dispose();
    super.dispose();
  }

  // ─── Жизненный цикл приложения ───
  // Уход (paused, detached, inactive): остановка таймера борта,
  // немедленная запись слоёв.
  // Возврат (resumed): перечитать системную гамму и переразрешить
  // тему — в фоне система могла сменить светлую на тёмную или
  // обратно, и без сего фон и элементы остались бы в прежней схеме.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      _bort.bortLastActionAt = 0;
      _bort.saveNow();
      _routineLayer.saveNow();
      _traceLayer.saveNow();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _refreshSystemBrightness();
    }
  }

  // ─── Смена системной гаммы ───
  // Зовётся при смене светлой/тёмной темы системы. Слой борта
  // переразрешает действующую тему («система»), прочие темы
  // остаются как были.
  @override
  void didChangePlatformBrightness() {
    _refreshSystemBrightness();
  }

  void _refreshSystemBrightness() {
    final b = WidgetsBinding
        .instance
        .platformDispatcher
        .platformBrightness;
    _bort.setSystemBrightness(b);
    // setSystemBrightness уведомляет слушателей токмо ежели гамма
    // впрямь изменилась; но при возврате из фона фон мог отстать
    // и без смены значения — принудительная перерисовка не лишня.
    if (mounted) setState(() {});
  }

  Future<void> _switchTab(int i) async {
    _bort.pulseBort();

    final cardOpen = _openedRoutineId != null;
    final sameRoutines = i == 1 && cardOpen;

    if (sameRoutines) return;

    if (cardOpen && i != 1) {
      _navigatorKey.currentState?.popUntil((r) => r.isFirst);
    }

    setState(() => _tab = i);
  }

  Future<void> _openRoutine(int id) async {
    setState(() {});
    _openedRoutineId = id;
    await _navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => RoutineCard(routineId: id)),
    );
    _openedRoutineId = null;
  }

  void _openTabsSheet() {
    final ctx = _navigatorKey.currentContext;
    if (ctx == null) return;
    final side = _pultState.smallSide;
    final labels = _bort.labelsSystem;
    showPultSheet(
      context: ctx,
      subs: [
        for (var i = 0; i < _tabs.length; i++)
          PultSpec(
            id: 'tab_$i',
            icon: _tabs[i].icon,
            label: labels ? _i18n!.t(_tabs[i].labelKey) : null,
            selected: _tab == i,
            onTap: () => _switchTab(i),
          ),
      ],
      fg: _bort.fg,
      bg: _bort.bg,
      signal: _bort.signal,
      side: side,
    );
  }

  double _pultSide(BuildContext context) {
    final systemScale = MediaQuery.textScalerOf(context).scale(1.0);
    final raw = _pultBase * systemScale * _bort.scale;
    return raw > _pultMax ? _pultMax : raw;
  }

  SystemUiOverlayStyle _overlayStyle(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: _bort.bg,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: _bort.bg,
      systemNavigationBarIconBrightness: dark
          ? Brightness.light
          : Brightness.dark,
    );
  }

  Brightness _effectiveBrightness(Brightness systemBrightness) {
    if (_bort.themeName == 'system') return systemBrightness;
    if (_bort.themeName == 'night') return Brightness.dark;
    if (_bort.themeName == 'custom') return Brightness.dark;
    return Brightness.light;
  }

  @override
  Widget build(BuildContext context) {
    if (_i18n == null) return const SizedBox.shrink();

    final side = _pultSide(context);
    _pultState.baseSide = side;
    _pultState.maxSide = _pultMax;

    final rootSide = side * 2 / 3;

    final appContext = AppContext(
      bort: _bort,
      routineLayer: _routineLayer,
      traceLayer: _traceLayer,
      journal: _journal,
      ticker: _ticker,
      i18n: _i18n!,
      refresh: _refreshAll,
      reloadI18n: _reloadI18n,
      openRoutine: _openRoutine,
    );

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: _i18n!.t('app.title'),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: _effectiveBrightness(_bort.systemBrightness),
        colorScheme: ColorScheme.fromSeed(
          seedColor: _bort.fg,
          brightness: _effectiveBrightness(_bort.systemBrightness),
        ).copyWith(surface: _bort.bg, onSurface: _bort.fg),
        scaffoldBackgroundColor: _bort.bg,
        appBarTheme: AppBarTheme(
          backgroundColor: _bort.bg,
          foregroundColor: _bort.fg,
          elevation: 0,
          titleSpacing: rootSide + _rootPad + 4,
          systemOverlayStyle: _overlayStyle(
            _effectiveBrightness(_bort.systemBrightness),
          ),
        ),
        textTheme: TextTheme(
          bodyMedium: TextStyle(color: _bort.fg),
          bodyLarge: TextStyle(color: _bort.fg),
          labelLarge: TextStyle(color: _bort.fg),
          titleMedium: TextStyle(color: _bort.fg),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderSide: BorderSide(color: _bort.fg)),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: _bort.fg),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: _bort.fg, width: 2),
          ),
          hintStyle: TextStyle(color: _bort.dim),
        ),
        iconTheme: IconThemeData(color: _bort.fg),
      ),
      builder: (context, child) {
        final systemBrightness = MediaQuery.platformBrightnessOf(context);
        _bort.setSystemBrightness(systemBrightness);
        SystemChrome.setSystemUIOverlayStyle(
          _overlayStyle(_effectiveBrightness(systemBrightness)),
        );

        return AppScope(
          appContext: appContext,
          child: PultScope(
            state: _pultState,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(_bort.scale)),
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _bort.pulseBort(),
                child: SafeArea(
                  child: Stack(
                    children: [
                      child ?? const SizedBox.shrink(),
                      // Корневой пульт — жёстко в левом верхнем углу.
                      Positioned(
                        left: _rootPad,
                        top: _rootPad,
                        child: RootPult(
                          side: rootSide,
                          fg: _bort.fg,
                          bg: _bort.bg,
                          signal: _bort.signal,
                          onOpen: _openTabsSheet,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
      home: Scaffold(
        body: IndexedStack(
          index: _tab,
          children: const [
            StubTab(), // поле
            RoutinesTab(), // рутины
            DaysTab(), // дни
            StubTab(), // артель
            RubkaTab(), // рубка
          ],
        ),
      ),
    );
  }
}
