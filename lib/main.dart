// ═══════════════════════════════════════════════════════════════════
// main.dart — точка входа и управитель.
//
// Порядок пуска: журнал открывает базу и подписывается на поток;
// слои регистрируются в нём и читают кэши; JournalLayer тотчас
// раздаёт накопленные записи. Сим восстанавливается состояние.
//
// Вложенность виджетов. AppScope, PultScope, PultLayer живут
// в MaterialApp.builder — внутри MaterialApp, но поверх всех
// маршрутов. Сие устраняет разрыв подписок при возврате из маршрута
// (карточки рутины) и позволяет подпультам видеть всё дерево.
//
// Корневой пульт (компас) — в том же слое.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'ui/routines_tab.dart';
import 'data/database.dart';
import 'data/journal_layer.dart';
import 'data/operational_layer.dart';
import 'data/routine_layer.dart';
import 'data/trace_layer.dart';
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
  final _pultState = PultState();

  I18n? _i18n;

  int _tab = 4;
  Offset? _dragOffset;
  bool _rootOpen = false;

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

  Future<void> _switchTab(int i) async {
    _pultState.close();
    setState(() {
      _tab = i;
      _rootOpen = false;
    });
    _bort.setSilent('tab', i.toString());
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
        return const Offset(m, m);
    }
  }

  String _nearestAnchor(Offset pos, Size size, double s) {
    const keys = ['tl', 'tc', 'tr', 'lc', 'rc', 'bl', 'bc', 'br'];
    var best = double.infinity;
    var bestKey = 'tl';
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
      i18n: _i18n!,
      refresh: _refreshAll,
      reloadI18n: _reloadI18n,
    );

    return MaterialApp(
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
      // AppScope, PultScope, PultLayer живут здесь — внутри MaterialApp,
      // но поверх любого маршрута.
      builder: (context, child) {
        // Системная гамма сообщается борту.
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
                              onOpen: () => setState(() => _rootOpen = true),
                              onSwitchTab: (i) => _switchTab(i),
                              onDragUpdate: (newPos) =>
                                  setState(() => _dragOffset = newPos),
                              onDragEnd: (p) {
                                final nearest = _nearestAnchor(p, size, side);
                                setState(() => _dragOffset = null);
                                _bort.setSilent('anchor', nearest);
                              },
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
            StubTab(), // поле (карта) — заглушка
            RoutinesTab(), // рутины
            StubTab(), // артель — заглушка
            RubkaTab(),
            JournalTab(),
          ],
        ),
      ),
    );
  }
}
