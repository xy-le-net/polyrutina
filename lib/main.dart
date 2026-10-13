// ═══════════════════════════════════════════════════════════════════
// main.dart — точка входа и управитель.
//
// Порядок пуска: журнал (init без подписки), борт, слои, словарь.
// Затем — journal.start(): подписка заводится ПОСЛЕ регистрации
// всех слоёв, дабы ранние записи не пропустились.
//
// Действие пользователя. Listener вокруг всего дерева ловит всякое
// касание — борт получает сигнал (pulseBort).
//
// Время борта. Подписка на тикер: борт тикает, а раз в тридцать
// секунд сверяет полночь.
//
// Системная строка. Цвет знаков и фона выставляется от действующей
// темы борта при всякой перестройке — дабы значки не пропадали
// при смене гаммы.
//
// Корневой пульт — на треть меньше базового (rootSide).
//
// Вложенность. AppScope, PultScope, PultLayer — в MaterialApp.builder.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'data/database.dart';
import 'data/journal_layer.dart';
import 'data/operational_layer.dart';
import 'data/routine_layer.dart';
import 'data/trace_layer.dart';
import 'data/ticker.dart';
import 'data/i18n.dart';
import 'ui/core/app_scope.dart';
import 'ui/pults/pult_core.dart';
import 'ui/pults/pult_layer.dart';
import 'ui/pults/root_pult.dart';
import 'ui/tabs/routines_tab.dart';
import 'ui/tabs/journal_tab.dart';
import 'ui/tabs/rubka_tab.dart';
import 'ui/tabs/stub_tab.dart';
import 'ui/cards/routine_card.dart';

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
  int _tab = 4;

  // Перетаскивание компаса.
  Offset? _dragOffset;
  Offset? _dragStartPultPos;
  Offset? _dragStartGlobal;
  bool _rootOpen = false;

  // Открытая рутина.
  int? _openedRoutineId;

  VoidCallback? _onTickerTick;

  static const List<RootTabItem> _tabs = [
    RootTabItem(icon: Icons.map, labelKey: 'tab.field'),
    RootTabItem(icon: Icons.checklist, labelKey: 'tab.routines'),
    RootTabItem(icon: Icons.groups, labelKey: 'tab.artel'),
    RootTabItem(icon: Icons.dashboard, labelKey: 'tab.rubka'),
    RootTabItem(icon: Icons.list, labelKey: 'tab.journal'),
  ];

  static const double _pultBase = 32.0;
  static const double _pultMax = 64.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _db = AppDb();
    _journal = JournalLayer(_db);
    _bort = OperationalLayer();
    _routineLayer = RoutineLayer();
    _traceLayer = TraceLayer();
    _ticker = AppTicker();

    _onTickerTick = () => _bort.tickBort();
    _ticker.addListener(_onTickerTick!);

    _bort.addListener(_onBortChanged);
    _routineLayer.addListener(_onLayerChanged);
    _traceLayer.addListener(_onLayerChanged);
    _journal.addListener(_onLayerChanged);
    _init();
  }

  void _onBortChanged() {
    if (mounted) setState(() => _tab = _bort.tab);
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
    // Подписка на журнал — после регистрации всех слоёв.
    _journal.start();
    if (mounted) setState(() => _tab = _bort.tab);
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
    _bort.removeListener(_onBortChanged);
    _routineLayer.removeListener(_onLayerChanged);
    _traceLayer.removeListener(_onLayerChanged);
    _journal.removeListener(_onLayerChanged);
    _routineLayer.dispose();
    _traceLayer.dispose();
    _journal.dispose();
    _ticker.dispose();
    _db.close();
    _pultState.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      _bort.bortLastActionAt = 0;
      _bort.saveNow();
      _routineLayer.saveNow();
      _traceLayer.saveNow();
    }
  }

  Future<void> _switchTab(int i) async {
    _pultState.close();
    _bort.pulseBort();

    final cardOpen = _openedRoutineId != null;
    final sameRoutines = i == 1 && cardOpen;

    if (sameRoutines) {
      setState(() => _rootOpen = false);
      return;
    }

    if (cardOpen && i != 1) {
      _navigatorKey.currentState?.popUntil((r) => r.isFirst);
    }

    setState(() {
      _tab = i;
      _rootOpen = false;
    });
    _bort.setSilent('tab', i.toString());

    if (i == 1 && _openedRoutineId != null) {
      final id = _openedRoutineId!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => RoutineCard(routineId: id)),
        );
      });
    }
  }

  Future<void> _openRoutine(int id) async {
    _pultState.close();
    _openedRoutineId = id;
    await _navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => RoutineCard(routineId: id)),
    );
    _openedRoutineId = null;
  }

  Offset _anchorPosition(String anchor, Size size, double s) {
    const m = 6.0;
    switch (anchor) {
      case 'tl':
        return const Offset(m, m);
      case 'tc':
        return Offset((size.width - s) / 2, m);
      case 'tr':
        return Offset(size.width - s - m, m);
      case 'lc':
        return Offset(m, (size.height - s) / 2);
      case 'rc':
        return Offset(size.width - s - m, (size.height - s) / 2);
      case 'bl':
        return Offset(m, size.height - s - m);
      case 'bc':
        return Offset((size.width - s) / 2, size.height - s - m);
      case 'br':
        return Offset(size.width - s - m, size.height - s - m);
      default:
        return Offset(size.width - s - m, m);
    }
  }

  String _nearestAnchor(Offset pos, Size size, double s) {
    const keys = ['tl', 'tc', 'tr', 'lc', 'rc', 'bl', 'bc', 'br'];
    var best = double.infinity;
    var bestKey = 'tr';
    for (final a in keys) {
      final p = _anchorPosition(a, size, s);
      final d = (p - pos).distanceSquared;
      if (d < best) {
        best = d;
        bestKey = a;
      }
    }
    return bestKey;
  }

  double _pultSide(BuildContext context) {
    final systemScale = MediaQuery.textScalerOf(context).scale(1.0);
    final raw = _pultBase * systemScale * _bort.scale;
    return raw > _pultMax ? _pultMax : raw;
  }

  // ─── Системная строка: цвет знаков и фона от борта ───
  void _syncSystemUi(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: _bort.bg,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: _bort.bg,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
    );
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
        brightness: _bort.systemBrightness,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _bort.fg,
          brightness: _bort.systemBrightness,
        ).copyWith(surface: _bort.bg, onSurface: _bort.fg),
        scaffoldBackgroundColor: _bort.bg,
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
        // Цвета системной строки — от действующей темы борта.
        _syncSystemUi(
          _bort.themeName == 'system'
              ? systemBrightness
              : (_bort.themeName == 'night'
                    ? Brightness.dark
                    : Brightness.light),
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
                child: PultLayer(
                  fg: _bort.fg,
                  bg: _bort.bg,
                  signal: _bort.signal,
                  child: SafeArea(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final size = Size(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
                        final pos =
                            _dragOffset ??
                            _anchorPosition(_bort.anchor, size, rootSide);
                        return Stack(
                          children: [
                            child ?? const SizedBox.shrink(),
                            Positioned(
                              left: pos.dx,
                              top: pos.dy,
                              child: RootPult(
                                tabs: _tabs,
                                activeTab: _tab,
                                open: _rootOpen,
                                side: rootSide,
                                position: pos,
                                area: size,
                                fg: _bort.fg,
                                bg: _bort.bg,
                                signal: _bort.signal,
                                labelsSystem: _bort.labelsSystem,
                                translate: (k) => _i18n!.t(k),
                                onDragStart: (global) {
                                  _dragStartPultPos = pos;
                                  _dragStartGlobal = global;
                                },
                                onDragUpdate: (global) {
                                  final start = _dragStartPultPos ?? pos;
                                  final g0 = _dragStartGlobal ?? global;
                                  setState(() {
                                    _dragOffset = start + (global - g0);
                                  });
                                },
                                onDragEnd: () {
                                  final p = _dragOffset ?? pos;
                                  final nearest = _nearestAnchor(
                                    p,
                                    size,
                                    rootSide,
                                  );
                                  setState(() {
                                    _dragOffset = null;
                                    _dragStartPultPos = null;
                                    _dragStartGlobal = null;
                                  });
                                  _bort.setSilent('anchor', nearest);
                                },
                                onOpen: () => setState(() => _rootOpen = true),
                                onSwitchTab: (i) => _switchTab(i),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
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
            StubTab(),
            RoutinesTab(),
            StubTab(),
            RubkaTab(),
            JournalTab(),
          ],
        ),
      ),
    );
  }
}
