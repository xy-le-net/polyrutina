// ═══════════════════════════════════════════════════════════════════
// main.dart — точка входа и управитель.
//
// Порядок пуска: журнал открывает базу и подписывается на поток;
// слои регистрируются в нём и читают кэши; JournalLayer тотчас
// раздаёт накопленные записи.
//
// Вложенность. AppScope, PultScope, PultLayer живут в MaterialApp.builder —
// внутри MaterialApp, но поверх всех маршрутов. Сие устраняет разрыв
// подписок при возврате из маршрута и позволяет подпультам видеть
// всё дерево.
//
// Корневой пульт (компас) — в том же слое. Перетаскивание: при начале
// жеста запоминается стартовая позиция (_dragStartPosition), при
// движении — anchor + дельта, при окончании — прилипание к якорю.
//
// Открытая рутина. Когда карточка рутины открыта и пользователь
// переключает вкладку, карточка снимается с навигатора, а номер
// запоминается (_openedRoutineId). При возврате на вкладку Рутины —
// карточка открывается вновь.
//
// Единый тикер. AppTicker создаётся здесь, утилизируется здесь,
// передаётся в AppContext. Виджеты слушают его, а не заводят
// собственные Timer.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'ui/routines_tab.dart';
import 'ui/routine_card.dart';
import 'data/database.dart';
import 'data/journal_layer.dart';
import 'data/operational_layer.dart';
import 'data/routine_layer.dart';
import 'data/trace_layer.dart';
import 'data/ticker.dart';
import 'data/i18n.dart';
import 'ui/app_scope.dart';
import 'ui/pult.dart';
import 'ui/root_pult.dart';
import 'ui/stub_tab.dart';
import 'ui/rubka_tab.dart';
import 'ui/journal_tab.dart';

void main() => runApp(const PolyRutinaApp());

class PolyRutinaApp extends StatefulWidget {
  const PolyRutinaApp({super.key});
  @override
  State<PolyRutinaApp> createState() => _PolyRutinaAppState();
}

class _PolyRutinaAppState extends State<PolyRutinaApp>
    with WidgetsBindingObserver {
  // ─── Слои ───
  late final AppDb _db;
  late final JournalLayer _journal;
  late final OperationalLayer _bort;
  late final RoutineLayer _routineLayer;
  late final TraceLayer _traceLayer;
  late final AppTicker _ticker;
  final _pultState = PultState();

  // Ключ навигатора — дабы уметь снимать карточку рутины из кода.
  final _navigatorKey = GlobalKey<NavigatorState>();

  I18n? _i18n;
  int _tab = 4;

  // Позиция корневого пульта при перетаскивании.
  Offset? _dragOffset;
  // Стартовая позиция жеста: anchor + дельта считается от неё.
  Offset? _dragStartPosition;
  bool _rootOpen = false;

  // Номер открытой рутины (для восстановления при возврате на Рутины).
  int? _openedRoutineId;

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
    await _bort.init(_journal, systemBrightness);
    await _routineLayer.init(_journal);
    await _traceLayer.init(_journal);
    _i18n = await I18n.load(_bort.lang);
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
      _bort.saveNow();
      _routineLayer.saveNow();
      _traceLayer.saveNow();
    }
  }

  // ─── Смена вкладки ───
  // Ежели открыта карточка рутины и идёт переключение на иную вкладку,
  // карточка снимается с навигатора, её номер запоминается. При
  // возврате на Рутины — открывается вновь.
  Future<void> _switchTab(int i) async {
    _pultState.close();

    final cardOpen = _openedRoutineId != null;
    final sameRoutines = i == 1 && cardOpen;

    if (sameRoutines) {
      // Уже на Рутинах с открытой карточкой — ничего не делаем.
      setState(() => _rootOpen = false);
      return;
    }

    if (cardOpen && i != 1) {
      // Уходим с Рутин — снимаем карточку, помним номер.
      _navigatorKey.currentState?.popUntil((r) => r.isFirst);
    }

    setState(() {
      _tab = i;
      _rootOpen = false;
    });
    _bort.setSilent('tab', i.toString());

    if (i == 1 && _openedRoutineId != null) {
      // Возврат на Рутины — открываем прежнюю карточку.
      final id = _openedRoutineId!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => RoutineCard(routineId: id),
          ),
        );
      });
    }
  }

  // Открытие карточки рутины — запоминаем номер.
  Future<void> _openRoutine(int id) async {
    _openedRoutineId = id;
    await _navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => RoutineCard(routineId: id),
      ),
    );
    // Возврат из карточки: обнуляем память.
    _openedRoutineId = null;
  }

  // ─── Восемь якорей ───
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

  @override
  Widget build(BuildContext context) {
    if (_i18n == null) return const SizedBox.shrink();

    final side = _pultSide(context);
    _pultState.baseSide = side;
    _pultState.maxSide = _pultMax;

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
          enabledBorder:
              OutlineInputBorder(borderSide: BorderSide(color: _bort.fg)),
          focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: _bort.fg, width: 2)),
          hintStyle: TextStyle(color: _bort.dim),
        ),
        iconTheme: IconThemeData(color: _bort.fg),
      ),
      builder: (context, child) {
        final systemBrightness = MediaQuery.platformBrightnessOf(context);
        _bort.setSystemBrightness(systemBrightness);

        return AppScope(
          appContext: appContext,
          child: PultScope(
            state: _pultState,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(_bort.scale),
              ),
              child: PultLayer(
                fg: _bort.fg,
                bg: _bort.bg,
                signal: _bort.signal,
                child: SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size =
                          Size(constraints.maxWidth, constraints.maxHeight);
                      final pos = _dragOffset ??
                          _anchorPosition(_bort.anchor, size, side);
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
                              side: side,
                              position: pos,
                              area: size,
                              fg: _bort.fg,
                              bg: _bort.bg,
                              signal: _bort.signal,
                              onDragStart: () {
                                _dragStartPosition = pos;
                              },
                              onDragUpdate: (newPos) {
                                final start = _dragStartPosition ?? pos;
                                final delta = newPos - pos;
                                setState(() {
                                  _dragOffset = start + delta;
                                });
                              },
                              onDragEnd: (p) {
                                final nearest = _nearestAnchor(p, size, side);
                                setState(() {
                                  _dragOffset = null;
                                  _dragStartPosition = null;
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
