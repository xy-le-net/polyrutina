// ═══════════════════════════════════════════════════════════════════
// main.dart — entry point and governor.
//
// Startup order: journal (init without subscription), bort, layers,
// dictionary. Then — journal.start().
//
// Default tab — «routines». The «field» and «artel» tabs are hidden
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
// system brightness and re-resolve the theme.
//
// Tabs. Touching the «routines» tab always leads to the routine
// list: if the card is open, popUntil the first route. The field
// and artel tabs are stubs while hidden.
//
// Sheet guard. _sheetOpen prevents subpults from stacking: while a
// sheet is open, further sheet requests are ignored.
//
// System back. PopScope intercepts back: if a card is open, close
// it; otherwise if not on the routines tab, switch to routines;
// otherwise let the system pop (normal app close).
//
// Root pult — hardcoded in the top-left corner. Touch opens the
// single left-side sheet of subpults (pult_sheet.dart) with tab
// kinds. PultLayer is removed.
//
// Scopes and listeners. Five point scopes (BortScope, RoutineScope,
// TraceScope, TickerScope, I18nScope) wrap the navigator tree. All
// inner views obtain their dependencies from them and rebuild only
// on the relevant layer. Consequently, main no longer listens to
// the routine, trace, or journal layers. The bort listener remains,
// but it is filtered: setState fires only when the MaterialApp or
// tab bar actually needs to re-read bort state — theme name, scale,
// tab visibility, system brightness, and the five color roles.
// Everything else (shift transitions, midnight, block collapse) is
// consumed by widgets under BortScope without touching main.
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
import 'ui/core/control_row.dart';
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

  int _tab = 1;
  int? _openedRoutineId;
  bool _sheetOpen = false;

  VoidCallback? _onTickerTick;

  // Signature of bort fields that feed MaterialApp (theme colors,
  // scale, system brightness) or the tab bar (showFieldTab,
  // showArtelTab). Unchanged signature — no setState.
  String _bortSignature = '';

  static const List<RootTabItem> _allTabs = [
    RootTabItem(icon: Icons.map, labelKey: 'tab.field'),
    RootTabItem(icon: Icons.checklist, labelKey: 'tab.routines'),
    RootTabItem(icon: Icons.calendar_month, labelKey: 'tab.days'),
    RootTabItem(icon: Icons.groups, labelKey: 'tab.artel'),
    RootTabItem(icon: Icons.dashboard, labelKey: 'tab.rubka'),
  ];

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
    _init();
  }

  // ─── Bort signature ───
  // Everything MaterialApp reads at build time, plus what the tab
  // bar needs. Color hex strings are computed here so that any
  // change to bg/bgdim/dim/fg/signal (custom theme edits, system
  // brightness switch) triggers a rebuild.
  String _computeBortSignature() {
    return '${_bort.themeName}|'
        '${_bort.scale.toStringAsFixed(4)}|'
        '${_bort.showFieldTab}|'
        '${_bort.showArtelTab}|'
        '${_bort.systemBrightness.name}|'
        '${_bort.colorToHex(_bort.bg)}|'
        '${_bort.colorToHex(_bort.bgdim)}|'
        '${_bort.colorToHex(_bort.dim)}|'
        '${_bort.colorToHex(_bort.fg)}|'
        '${_bort.colorToHex(_bort.signal)}';
  }

  void _onBortChanged() {
    final s = _computeBortSignature();
    if (s == _bortSignature) return;
    _bortSignature = s;
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
    _bort.setLastRereadId(await _journal.lastEntryId());
    _tab = 1;
    _bortSignature = _computeBortSignature();
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
    _bort.removeListener(_onBortChanged);
    _bort.dispose();
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

    if (i == 1) {
      if (cardOpen) {
        _navigatorKey.currentState?.popUntil((r) => r.isFirst);
      }
      if (_tab != 1) setState(() => _tab = 1);
      return;
    }

    if (cardOpen) {
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
    if (_sheetOpen) return;
    final ctx = _navigatorKey.currentContext;
    if (ctx == null) return;
    final side = _pultState.smallSide;
    final labels = _bort.labelsButtons;
    _sheetOpen = true;
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
    ).whenComplete(() {
      _sheetOpen = false;
    });
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

  Widget _tabBody() {
    switch (_tab) {
      case 0:
        return const StubTab();
      case 1:
        return const RoutinesTab();
      case 2:
        return const DaysTab();
      case 3:
        return const StubTab();
      case 4:
      default:
        return const RubkaTab();
    }
  }

  void _handleBack() {
    if (_openedRoutineId != null) {
      _navigatorKey.currentState?.popUntil((r) => r.isFirst);
      return;
    }
    if (_tab != 1) {
      setState(() => _tab = 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_i18n == null) return const SizedBox.shrink();

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
          centerTitle: false,
          titleSpacing: rootReserve,
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
          child: BortScope(
            bort: _bort,
            child: RoutineScope(
              routineLayer: _routineLayer,
              child: TraceScope(
                traceLayer: _traceLayer,
                child: TickerScope(
                  ticker: _ticker,
                  child: I18nScope(
                    i18n: _i18n!,
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
                  ),
                ),
              ),
            ),
          ),
        );
      },
      home: PopScope(
        canPop: _tab == 1 && _openedRoutineId == null,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          _handleBack();
        },
        child: Scaffold(body: _tabBody()),
      ),
    );
  }
}
