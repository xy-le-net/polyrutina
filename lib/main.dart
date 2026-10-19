// ═══════════════════════════════════════════════════════════════════
// main.dart — entry point and governor.
//
// Startup order: journal (init without subscription), bort, layers,
// dictionary. Then — journal.start().
//
// Default tab — «routines». There is no tab note in the bort file:
// the tab field is removed. The «field» and «artel» tabs are hidden
// by default; their display is toggled in the rubka («artel» block).
//
// User action. A Listener around the tree catches touches — the
// bort receives a signal (pulseBort).
//
// Bort time. Subscription to the ticker: the bort ticks and checks
// midnight every thirty seconds.
//
// Lifecycle. Departure (paused, detached, inactive): stop the bort
// timer, immediately save layers. Return (resumed): re-read the
// system brightness and re-resolve the theme — in the background
// the system could have switched light to dark. System brightness
// change (without backgrounding) — via didChangePlatformBrightness.
//
// System bar. Overlay strip style — from the bort theme.
//
// Root pult — hardcoded in the top-left corner. Touch opens the
// single left-side sheet of subpults (pult_sheet.dart) with tab
// kinds. PultLayer is removed.
//
// Transparency is not applied.
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
import 'ui/core/control_row.dart'; // Added for unified title spacing
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

  // Default tab — routines (index 1 in the full list).
  int _tab = 1;

  int? _openedRoutineId;

  VoidCallback? _onTickerTick;

  // ─── Tab list ───
  // Order: field, routines, days, artel, rubka. This same index
  // corresponds to _tab. The display of the field and artel tabs is
  // controlled by bort flags (rubka → artel).
  static const List<RootTabItem> _allTabs = [
    RootTabItem(icon: Icons.map, labelKey: 'tab.field'),
    RootTabItem(icon: Icons.checklist, labelKey: 'tab.routines'),
    RootTabItem(icon: Icons.calendar_month, labelKey: 'tab.days'),
    RootTabItem(icon: Icons.groups, labelKey: 'tab.artel'),
    RootTabItem(icon: Icons.dashboard, labelKey: 'tab.rubka'),
  ];

  // Is the tab with this number visible under the current flags.
  bool _tabVisible(int i) {
    if (i == 0) return _bort.showFieldTab;
    if (i == 3) return _bort.showArtelTab;
    return true;
  }

  static const double _pultBase = 32.0;
  static const double _pultMax = 64.0;
  static const double _rootPad = 6.0;

  @override
  void initState() {
    super.initState();
    // Lifecycle observer: departure — save layers, return —
    // re-resolve the theme (in the background the system could
    // have changed the scheme).
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
    // Reread mark — at the current end of the journal: the
    // «reread» button becomes active only if something was added
    // to the journal afterwards.
    _bort.setLastRereadId(await _journal.lastEntryId());
    // Default tab — «routines»; if «field» and «artel» are
    // hidden, index 1 still leads to routines.
    _tab = 1;
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

  // ─── Application lifecycle ───
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

  @override
  void didChangePlatformBrightness() {
    _refreshSystemBrightness();
  }

  void _refreshSystemBrightness() {
    final b = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    _bort.setSystemBrightness(b);
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
    final labels = _bort.labelsButtons;
    showPultSheet(
      context: ctx,
      subs: [
        for (var i = 0; i < _allTabs.length; i++)
          if (_tabVisible(i))
            PultSpec(
              id: 'tab_$i',
              icon: _allTabs[i].icon,
              label: labels ? _i18n!.t(_allTabs[i].labelKey) : null,
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

  // ─── Tab body assembly by number ───
  // Indices: 0 — field, 1 — routines, 2 — days, 3 — artel, 4 — rubka.
  // Hidden tabs remain as stubs in their places: the index does not
  // shift, hence _tab always has the same meaning.
  Widget _tabBody() {
    switch (_tab) {
      case 0:
        return const StubTab(); // field
      case 1:
        return const RoutinesTab();
      case 2:
        return const DaysTab();
      case 3:
        return const StubTab(); // artel
      case 4:
      default:
        return const RubkaTab();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_i18n == null) return const SizedBox.shrink();

    // If the current tab is hidden — force a switch to routines.
    if (!_tabVisible(_tab)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_tabVisible(_tab)) {
          setState(() => _tab = 1);
        }
      });
    }

    final side = _pultSide(context);
    _pultState.baseSide = side;
    _pultState.maxSide = _pultMax;

    final rootSide = side * 2 / 3;
    // Use the unified reserve calculation for the AppBar title.
    final rootReserve = ControlRow.reserve(rootSide, rootPad: _rootPad);

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
          centerTitle: false, // Force left alignment for titles
          titleSpacing: rootReserve, // Unified spacing
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
                      // Root pult — hardcoded in the top-left corner.
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
      home: Scaffold(body: _tabBody()),
    );
  }
}
