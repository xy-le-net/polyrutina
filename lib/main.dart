// ═══════════════════════════════════════════════════════════════════
// main.dart — entry point and governor.
//
// Startup order: journal (init without subscription), bort, trace,
// field, routine, dictionary. Then — journal.start().
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
// timer, immediately save layers (bort, routine, trace, field).
// Return (resumed): re-read the system brightness, re-resolve the
// theme, and consume any pending actions from notifications.
//
// Tabs. Touching the «routines» tab always leads to the routine
// list: if the card is open, popUntil the first route.
//
// Field migration. During init, after the field layer is ready, the
// root node is created (if missing) and legacy routines/traces are
// attached to it.
//
// Notifications. The NotificationService is initialized on startup.
// NotificationManager is instantiated to observe the ticker and
// update ongoing notifications. When the app resumes, it checks for
// a pending action (e.g. the user tapped "stop" on an ongoing
// notification while the app was in the background) and applies the
// corresponding stop operation.
//
// System back. PopScope.canPop is always FALSE: the handler owns
// the outcome. _handleBack closes the card if one is open, or
// switches to the routines tab if another tab is active; on the
// routines tab with no card it absorbs the press.
//
// Root pult — hardcoded in the top-left corner. Touch opens the
// single left-side sheet of subpults (pult_sheet.dart) with tab
// kinds.
//
// Scopes and listeners. Six point scopes (BortScope, RoutineScope,
// TraceScope, FieldScope, TickerScope, I18nScope) wrap the
// navigator tree.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/database.dart';
import 'data/field_layer.dart';
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
import 'ui/services/notification_manager.dart';
import 'ui/services/notification_service.dart';
import 'ui/tabs/days_tab.dart';
import 'ui/tabs/field_tab.dart';
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
  late final FieldLayer _fieldLayer;
  late final AppTicker _ticker;
  late final NotificationManager _notificationManager;
  final _pultState = PultState();
  final _navigatorKey = GlobalKey<NavigatorState>();

  I18n? _i18n;

  int _tab = 1;
  int? _openedRoutineId;
  bool _sheetOpen = false;

  VoidCallback? _onTickerTick;

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
    NotificationService.init();
    _db = AppDb();
    _journal = JournalLayer(_db);
    _bort = OperationalLayer();
    _traceLayer = TraceLayer();
    _fieldLayer = FieldLayer();
    _routineLayer = RoutineLayer();
    _ticker = AppTicker();

    _onTickerTick = () => _bort.tickBort();
    _ticker.addListener(_onTickerTick!);

    _bort.addListener(_onBortChanged);
    _init();
  }

  String _computeBortSignature() {
    return '${_bort.themeName}|'
        '${_bort.scale.toStringAsFixed(4)}|'
        '${_bort.showFieldTab}|'
        '${_bort.showArtelTab}|'
        '${_bort.systemBrightness.name}|'
        '${_bort.lang}|'
        '${_bort.colorToHex(_bort.bg)}|'
        '${_bort.colorToHex(_bort.bgsignal)}|'
        '${_bort.colorToHex(_bort.mid)}|'
        '${_bort.colorToHex(_bort.fg)}|'
        '${_bort.colorToHex(_bort.fgsignal)}';
  }

  void _onBortChanged() {
    final s = _computeBortSignature();
    if (s == _bortSignature) return;
    _bortSignature = s;
    if (_i18n != null && _i18n!.lang != _bort.lang) {
      _reloadI18n();
    }
    if (mounted) setState(() {});
  }

  Future<void> _init() async {
    final systemBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    await _journal.init();
    await _bort.init(systemBrightness);
    await _traceLayer.init(_journal);
    await _fieldLayer.init(_journal);
    await _fieldLayer.createRootIfNeeded(_journal);
    await _routineLayer.init(_journal, _traceLayer, _fieldLayer);
    _routineLayer.migrateFieldParents();
    _i18n = await I18n.load(_bort.lang);
    _journal.start();
    _bort.setLastRereadId(await _journal.lastEntryId());
    _tab = 1;
    _bortSignature = _computeBortSignature();

    _notificationManager = NotificationManager(
      bort: _bort,
      routineLayer: _routineLayer,
      ticker: _ticker,
    );

    if (mounted) setState(() {});
  }

  Future<void> _reloadI18n() async {
    final i18n = await I18n.load(_bort.lang);
    if (mounted) setState(() => _i18n = i18n);
  }

  Future<void> _refreshAll() async {
    if (mounted) setState(() {});
  }

  Future<void> _handlePendingNotificationAction() async {
    final action = await NotificationService.consumePendingAction();
    if (action == null) return;

    if (action == 'stop_shift' && _bort.onShift) {
      await _journal.log(
        type: 3, // actor
        body: '{"action":"shift_stop"}',
      );
      _bort.stopShift();
      for (final r in _routineLayer.routines) {
        for (final b in r.blocks) {
          if (b.isRunning) {
            await _routineLayer.pauseBlock(_journal, r.id, b.kind);
          }
        }
      }
    } else if (action == 'stop_routine') {
      final rId = _routineLayer.currentRoutineId;
      if (rId != null) {
        final r = _routineLayer.findRoutine(rId);
        if (r != null) {
          for (final b in r.blocks) {
            if (b.isRunning) {
              await _routineLayer.pauseBlock(_journal, rId, b.kind);
            }
          }
        }
      }
    }

    await NotificationService.cancelAll();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_onTickerTick != null) {
      _ticker.removeListener(_onTickerTick!);
    }
    _notificationManager.dispose();
    _bort.removeListener(_onBortChanged);
    _bort.dispose();
    _routineLayer.dispose();
    _traceLayer.dispose();
    _fieldLayer.dispose();
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
      _fieldLayer.saveNow();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _refreshSystemBrightness();
      _handlePendingNotificationAction();
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
    if (_openedRoutineId != null) {
      _navigatorKey.currentState?.popUntil((r) => r.isFirst);
    }
    if (_tab != i) setState(() => _tab = i);
  }

  Future<void> _openRoutine(int id) async {
    setState(() => _openedRoutineId = id);
    await _navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => RoutineCard(routineId: id)),
    );
    if (mounted) setState(() => _openedRoutineId = null);
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
      signal: _bort.fgsignal,
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
        return const FieldTab();
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
      return;
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
      fieldLayer: _fieldLayer,
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
          hintStyle: TextStyle(color: _bort.mid),
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
                child: FieldScope(
                  fieldLayer: _fieldLayer,
                  child: TickerScope(
                    ticker: _ticker,
                    child: I18nScope(
                      i18n: _i18n!,
                      child: PultScope(
                        state: _pultState,
                        child: MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                            textScaler: TextScaler.linear(_bort.scale),
                          ),
                          child: AnnotatedRegion<SystemUiOverlayStyle>(
                            value: _overlayStyle(
                              _effectiveBrightness(systemBrightness),
                            ),
                            child: ColoredBox(
                              color: _bort.bg,
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
                                          signal: _bort.fgsignal,
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
              ),
            ),
          ),
        );
      },
      home: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          _handleBack();
        },
        child: Scaffold(body: _tabBody()),
      ),
    );
  }
}
