// ═══════════════════════════════════════════════════════════════════
// main.dart — entry point and governor.
//
// Startup order: journal, bort, trace, field (with root creation),
// routine, dictionary, notification manager. Then — journal.start().
//
// Dictionary initialization must occur BEFORE the field layer creates
// its default root, so that the root name can be localized.
//
// Notification routing. When the user taps the body of a notification,
// NotificationService.payloadNotifier is triggered. main.dart listens
// and switches to the routines tab, optionally opening the routine
// card. When the user presses the "stop" button in the notification,
// the action is saved to a file by the background isolate; main.dart
// reads it on resume via consumePendingAction and stops the shift
// or routine.
//
// Mutex shift. If mutex_shift is enabled (true), stopping a shift
// does not affect routines, and vice versa. If disabled (false),
// stopping a shift stops all routines belonging to the field's
// subtree.
//
// Lifecycle. When the app goes to background, all layers are saved,
// the journal state is flushed, and the ticker is paused to save
// battery. On resume, the ticker restarts and brightness is refreshed.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/database.dart';
import 'data/field_layer.dart';
import 'data/i18n.dart';
import 'data/journal_layer.dart';
import 'data/journal_types.dart';
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
  NotificationManager? _notificationManager;
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
    NotificationService.init().then((_) {
      NotificationService.payloadNotifier.addListener(_onNotificationTap);
    });

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

    // Load dictionary before field initialization to localize the root name.
    _i18n = await I18n.load(_bort.lang);

    await _fieldLayer.init(_journal);
    await _fieldLayer.createRootIfNeeded(
      _journal,
      name: _i18n!.t('field.root'),
    );

    await _routineLayer.init(_journal, _traceLayer, _fieldLayer);
    _routineLayer.migrateFieldParents();

    _journal.start();
    _bort.setLastRereadId(await _journal.lastEntryId());
    _tab = 1;
    _bortSignature = _computeBortSignature();

    _notificationManager = NotificationManager(
      bort: _bort,
      routineLayer: _routineLayer,
      fieldLayer: _fieldLayer,
      ticker: _ticker,
      i18n: _i18n!,
    );

    if (mounted) setState(() {});
  }

  Future<void> _reloadI18n() async {
    final i18n = await I18n.load(_bort.lang);
    if (mounted) {
      setState(() {
        _i18n = i18n;
        // Recreate manager with new i18n
        _notificationManager?.dispose();
        _notificationManager = NotificationManager(
          bort: _bort,
          routineLayer: _routineLayer,
          fieldLayer: _fieldLayer,
          ticker: _ticker,
          i18n: i18n,
        );
      });
    }
  }

  Future<void> _refreshAll() async {
    if (mounted) setState(() {});
  }

  void _onNotificationTap() {
    final payload = NotificationService.payloadNotifier.value;
    if (payload == null) return;
    NotificationService.payloadNotifier.value = null;

    if (payload.startsWith('shift_')) {
      _switchTab(1);
    } else if (payload.startsWith('routine_')) {
      final idStr = payload.split('_').last;
      final rId = int.tryParse(idStr);
      if (rId != null) {
        _switchTab(1).then((_) => _openRoutine(rId));
      }
    }
  }

  Future<void> _handlePendingNotificationAction() async {
    final data = await NotificationService.consumePendingAction();
    if (data == null) return;

    final action = data['action'];
    final payload = data['payload'] ?? '';

    if (action == 'stop_shift' && payload.startsWith('shift_')) {
      final fId = int.tryParse(payload.split('_').last);
      if (fId != null && _bort.onShift(fId)) {
        await _journal.log(
          type: JournalType.actor,
          body: '{"action":"shift_stop","field_id":$fId}',
        );
        _bort.stopShift(fId);

        if (!_bort.mutexShift) {
          for (final r in _routineLayer.routines) {
            bool inField = false;
            for (final parentId in r.fieldParents) {
              if (_fieldLayer.isDescendant(parentId, fId)) {
                inField = true;
                break;
              }
            }
            if (!inField) continue;

            for (final b in r.blocks) {
              if (b.isRunning) {
                await _routineLayer.pauseBlock(_journal, r.id, b.kind);
              }
            }
          }
        }
      }
    } else if (action == 'stop_routine' && payload.startsWith('routine_')) {
      final rId = int.tryParse(payload.split('_').last);
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
    NotificationService.payloadNotifier.removeListener(_onNotificationTap);
    if (_onTickerTick != null) {
      _ticker.removeListener(_onTickerTick!);
    }
    _notificationManager?.dispose();
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
      _journal.saveNow();
      _ticker.pause();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _ticker.resume();
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
