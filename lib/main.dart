import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'package:polyrutina/core/data/database.dart';
import 'package:polyrutina/core/data/field_layer.dart';
import 'package:polyrutina/core/localization/i18n.dart';
import 'package:polyrutina/core/data/journal_layer.dart';
import 'package:polyrutina/core/domain/journal_types.dart';
import 'package:polyrutina/core/application/operational_layer.dart';
import 'package:polyrutina/shared/models/routine.dart';
import 'package:polyrutina/features/routines/application/routine_layer.dart';
import 'package:polyrutina/core/application/ticker.dart';
import 'package:polyrutina/core/data/trace_layer.dart';
import 'package:polyrutina/features/routines/presentation/routine_card.dart';
import 'package:polyrutina/shared/presentation/app_layout.dart';
import 'package:polyrutina/shared/presentation/bort_metrics.dart';
import 'package:polyrutina/shared/presentation/app_scope.dart';
import 'package:polyrutina/shared/presentation/control_row.dart';
import 'package:polyrutina/shared/application/format.dart';
import 'package:polyrutina/shared/presentation/pults/pult_core.dart';
import 'package:polyrutina/shared/presentation/pults/pult_sheet.dart';
import 'package:polyrutina/shared/presentation/pults/root_pult.dart';
import 'package:polyrutina/shared/application/notification_manager.dart';
import 'package:polyrutina/core/application/notification_service.dart';
import 'package:polyrutina/features/days/presentation/days_tab.dart';
import 'package:polyrutina/features/routines/presentation/routines_tab.dart';
import 'package:polyrutina/features/export_import/presentation/rubka_tab.dart';
import 'package:polyrutina/features/export_import/presentation/report.dart';

void main() => runApp(const PolyRutinaApp());

class PolyRutinaApp extends StatefulWidget {
  const PolyRutinaApp({super.key});
  @override
  State<PolyRutinaApp> createState() => _PolyRutinaAppState();
}

class _AlwaysScrollbarBehavior extends MaterialScrollBehavior {
  const _AlwaysScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return Scrollbar(
      controller: details.controller,
      thumbVisibility: true,
      interactive: true,
      child: child,
    );
  }
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
  _OverdueSchedulerImpl? _scheduler;

  final _pultState = PultState();
  final _navigatorKey = GlobalKey<NavigatorState>();

  I18n? _i18n;
  String? _splashSlogan;
  String? _initError;
  // The main UI appears after successful initialization.
  bool _bootDone = false;

  // Keep the waiting screen in the loaded palette.
  Color get _splashBg => _bort.bg;

  int _tab = 0;
  int? _openedRoutineId;
  bool _sheetOpen = false;

  VoidCallback? _onTickerTick;
  String _bortSignature = '';

  // Poll pending notification actions.
  Timer? _pendingPollTimer;
  bool _pendingActionInProgress = false;

  static const List<RootTabItem> _allTabs = [
    RootTabItem(icon: Icons.checklist, labelKey: 'tab.routines'),
    RootTabItem(icon: Icons.calendar_month, labelKey: 'tab.days'),
    RootTabItem(icon: Icons.dashboard, labelKey: 'tab.rubka'),
  ];

  bool _tabVisible(int i) => true;

  static const double _rootPad = 6.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.init().then((_) {
      NotificationService.payloadNotifier.addListener(_onNotificationTap);
      _onNotificationTap();
    });

    _pendingPollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _handlePendingNotificationAction(),
    );

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
    return '${_bort.themeCustom}|'
        '${_bort.themeNight}|'
        '${_bort.themeAuto}|'
        '${_bort.scale.toStringAsFixed(4)}|'
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
    // Defer localization reload until cache-reset dialogs finish.
    if (_i18n != null && _i18n!.lang != _bort.lang) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reloadI18n();
      });
    }
    if (mounted) setState(() {});
  }

  Future<void> _init() async {
    final minimumSplashDuration = Future<void>.delayed(
      const Duration(seconds: 3),
    );
    try {
      // Load the default-language slogan before initializing app layers.
      try {
        final raw = await rootBundle.loadString('assets/defaults.json');
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final lang = data['lang'] as String? ?? 'ru';
        _i18n = await I18n.load(lang);
        _splashSlogan = _chooseSplashSlogan(_i18n!);
        if (mounted) setState(() {});
      } catch (_) {
        // Initialization retries the dictionary load after preferences load.
      }

      final systemBrightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;

      await _journal.init();
      await _bort.init(systemBrightness);
      await _traceLayer.init(_journal);

      final previousLang = _i18n?.lang;
      _i18n = await I18n.load(_bort.lang);
      if (previousLang != _i18n!.lang || _splashSlogan == null) {
        _splashSlogan = _chooseSplashSlogan(_i18n!);
      }

      await _fieldLayer.init(_journal);
      await _fieldLayer.createRootIfNeeded(
        _journal,
        name: _i18n!.t('field.root'),
      );

      await _routineLayer.init(_journal, _traceLayer, _fieldLayer);
      _routineLayer.migrateFieldParents();

      _bort.attachJournal(_journal);
      _journal.start();
      _bort.setLastRereadId(await _journal.lastEntryId());
      _tab = 0;
      _bortSignature = _computeBortSignature();

      // Configure and reconcile scheduled notifications.
      _scheduler = _OverdueSchedulerImpl(_i18n!);
      _routineLayer.scheduler = _scheduler;
      unawaited(_scheduler!.reconcile(_routineLayer.routines));

      _notificationManager = NotificationManager(
        bort: _bort,
        routineLayer: _routineLayer,
        fieldLayer: _fieldLayer,
        ticker: _ticker,
        i18n: _i18n!,
      );

      await minimumSplashDuration;
      _bootDone = true;
    } catch (e, st) {
      debugPrint('INIT FAILED: $e\n$st');
      _initError = '$e';
    }

    if (mounted) setState(() {});
  }

  Future<void> _afterJournalReset() async {
    if (_i18n == null) return;
    await _fieldLayer.createRootIfNeeded(
      _journal,
      name: _i18n!.t('field.root'),
    );
    final active = _fieldLayer.activeFieldId;
    final root = _fieldLayer.rootId;
    if (root != null &&
        (active == null || !_fieldLayer.nodes.containsKey(active))) {
      _fieldLayer.setActiveField(root);
    }
    if (mounted) setState(() {});
  }

  Future<void> _reloadI18n() async {
    final i18n = await I18n.load(_bort.lang);
    if (mounted) {
      setState(() {
        _i18n = i18n;
        _notificationManager?.dispose();
        _notificationManager = NotificationManager(
          bort: _bort,
          routineLayer: _routineLayer,
          fieldLayer: _fieldLayer,
          ticker: _ticker,
          i18n: i18n,
        );
        _scheduler = _OverdueSchedulerImpl(i18n);
        _routineLayer.scheduler = _scheduler;
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
      _switchTab(0);
    } else if (payload.startsWith('routine_')) {
      final idStr = payload.split('_').last;
      final rId = int.tryParse(idStr);
      if (rId != null) {
        _switchTab(0).then((_) => _openRoutine(rId));
      }
    }
  }

  Future<void> _handlePendingNotificationAction() async {
    if (_pendingActionInProgress) return;
    _pendingActionInProgress = true;
    try {
      final data = await NotificationService.consumePendingAction();
      if (data == null) return;

      final action = data['action'] ?? '';
      final payload = data['payload'] ?? '';
      await _applyShadeAction(action, payload);

      if (mounted) setState(() {});
    } finally {
      _pendingActionInProgress = false;
    }
  }

  Future<void> _applyShadeAction(String action, String payload) async {
    if (action == 'stop_shift' && payload.startsWith('shift_')) {
      if (!_bort.shiftEnabled) {
        await NotificationService.cancelShift();
        return;
      }
      if (_bort.onShift(0)) {
        await _journal.log(
          type: JournalType.actor,
          body: '{"action":"shift_stop","field_id":0}',
        );
        _bort.stopShift(0);

        if (_bort.mutexShift) {
          for (final r in _routineLayer.routines) {
            for (final b in r.blocks) {
              if (b.isRunning) {
                await _routineLayer.pauseBlock(_journal, r.id, b.kind);
              }
            }
          }
        }
      }
      await NotificationService.cancelShift();
      return;
    }

    if (action == 'stop_routine' && payload.startsWith('routine_')) {
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
      await NotificationService.cancelRoutine();
      return;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.payloadNotifier.removeListener(_onNotificationTap);
    _pendingPollTimer?.cancel();
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
    final navigator = _navigatorKey.currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.popUntil((r) => r.isFirst);
    }
    if (_tab != i) setState(() => _tab = i);
  }

  Future<void> _openRoutine(int id, {bool autofocusName = false}) async {
    setState(() => _openedRoutineId = id);
    await _navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            RoutineCard(routineId: id, autofocusName: autofocusName),
      ),
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
    return BortMetrics.calculateSide(
      platformScale: systemScale,
      appScale: _bort.scale,
    );
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
    return _bort.bg.computeLuminance() > 0.5
        ? Brightness.light
        : Brightness.dark;
  }

  Widget _tabBody() {
    switch (_tab) {
      case 0:
        return const RoutinesTab();
      case 1:
        return const DaysTab();
      case 2:
      default:
        return const RubkaTab();
    }
  }

  void _handleBack() {
    if (_openedRoutineId != null) {
      _navigatorKey.currentState?.popUntil((r) => r.isFirst);
      return;
    }
    if (_tab != 0) {
      setState(() => _tab = 0);
      return;
    }
  }

  void _handleEscape() {
    final navigator = _navigatorKey.currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return;
    }
    _handleBack();
  }

  // Show the app icon and an optional localized slogan during startup.
  String? _chooseSplashSlogan(I18n i18n) {
    final parts = i18n
        .t('slogans')
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.isEmpty ? null : parts[Random().nextInt(parts.length)];
  }

  Widget _waitingScreen() {
    final fg = _splashBg.computeLuminance() > 0.5
        ? Colors.black87
        : Colors.white70;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: _splashBg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: Image.asset('assets/icon.png', fit: BoxFit.contain),
                  ),
                ),
                if (_splashSlogan != null) ...[
                  const SizedBox(height: 24),
                  Text(
                    _splashSlogan!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: fg,
                      fontSize: BortMetrics.fontSizeForSide(
                        BortMetrics.baseSide * _bort.scale,
                        BortTextRole.base,
                      ),
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorScreen() {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              'init failed:\n$_initError',
              style: TextStyle(
                color: Colors.red,
                fontSize: BortMetrics.fontSizeForSide(
                  BortMetrics.baseSide * _bort.scale,
                  BortTextRole.caption,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_bootDone) {
      if (_initError != null) return _errorScreen();
      return _waitingScreen();
    }

    if (_i18n == null) {
      // Keep the startup screen visible if localization is unavailable.
      return _waitingScreen();
    }

    if (!_tabVisible(_tab)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_tabVisible(_tab)) {
          setState(() => _tab = 0);
        }
      });
    }

    final side = _pultSide(context);
    _pultState.baseSide = side;
    _pultState.maxSide = BortMetrics.maxSide;

    final rootControlSide = side * 2 / 3;
    final rootSide = rootControlSide * ControlRow.enlargementScale;
    final rootReserve = ControlRow.reserve(rootControlSide, rootPad: _rootPad);
    final brightness = _effectiveBrightness(_bort.systemBrightness);
    final textTheme = BortMetrics.normalizeTextTheme(
      ThemeData(useMaterial3: true, brightness: brightness).textTheme,
      BortMetrics.fontSizeForSide(side, BortTextRole.base),
    ).apply(bodyColor: _bort.fg, displayColor: _bort.fg);

    late final AppContext appContext;
    appContext = AppContext(
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
      exportRoutine: (routineId, context) async {
        await ReportBuilder.buildSingle(
          appContext,
          _i18n!,
          routineId,
          uiContext: context,
        );
      },
      afterJournalReset: _afterJournalReset,
    );

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: _i18n!.t('app.title'),
      debugShowCheckedModeBanner: false,
      scrollBehavior: const _AlwaysScrollbarBehavior(),
      theme: ThemeData(
        useMaterial3: true,
        brightness: brightness,
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
        textTheme: textTheme,
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderSide: BorderSide(color: _bort.fg)),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: _bort.fg),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: _bort.bgsignal, width: 2),
          ),
          hintStyle: TextStyle(color: _bort.mid),
        ),
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: _bort.bgsignal,
          selectionColor: _bort.bgsignal.withValues(alpha: 0.35),
          selectionHandleColor: _bort.bgsignal,
        ),
        iconTheme: IconThemeData(color: _bort.fg),
      ),
      builder: (context, child) {
        final systemBrightness = MediaQuery.platformBrightnessOf(context);
        _bort.setSystemBrightness(systemBrightness);
        SystemChrome.setSystemUIOverlayStyle(
          _overlayStyle(_effectiveBrightness(systemBrightness)),
        );

        return DefaultTextStyle.merge(
          style: const TextStyle(fontWeight: FontWeight.normal),
          child: CallbackShortcuts(
            bindings: {
              if (defaultTargetPlatform == TargetPlatform.windows ||
                  defaultTargetPlatform == TargetPlatform.linux ||
                  defaultTargetPlatform == TargetPlatform.macOS)
                const SingleActivator(LogicalKeyboardKey.escape): _handleEscape,
            },
            child: AppScope(
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
                              data: MediaQuery.of(
                                context,
                              ).copyWith(textScaler: TextScaler.noScaling),
                              child: AnnotatedRegion<SystemUiOverlayStyle>(
                                value: _overlayStyle(
                                  _effectiveBrightness(systemBrightness),
                                ),
                                child: ColoredBox(
                                  color: _bort.bg,
                                  child: Listener(
                                    behavior: HitTestBehavior.translucent,
                                    onPointerDown: (event) {
                                      _bort.pulseBort();
                                      if (event.kind ==
                                              PointerDeviceKind.mouse &&
                                          (event.buttons &
                                                  kSecondaryMouseButton) !=
                                              0) {
                                        _handleEscape();
                                      }
                                    },
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
        child: Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: appScreenMaxWidth(side)),
              child: _tabBody(),
            ),
          ),
        ),
      ),
    );
  }
}

// Adapt routine scheduling to the platform notification service.
class _OverdueSchedulerImpl implements OverdueScheduler {
  final I18n i18n;
  Future<void> _tail = Future<void>.value();

  _OverdueSchedulerImpl(this.i18n);

  @override
  void refresh(Routine routine) {
    unawaited(_enqueue(() => _doRefresh(routine)));
  }

  @override
  void cancel(int routineId) {
    unawaited(
      _enqueue(() => NotificationService.cancelOverdueNotice(routineId)),
    );
  }

  Future<void> reconcile(Iterable<Routine> routines) {
    final snapshot = List<Routine>.of(routines);
    return _enqueue(() async {
      for (final routine in snapshot) {
        await NotificationService.cancelOverdueNotice(routine.id);
      }
      for (final routine in snapshot) {
        await _updateNotice(routine);
      }
    });
  }

  Future<void> _enqueue(Future<void> Function() action) {
    // Replace notifications in order to avoid stale alarms.
    final next = _tail.then((_) async {
      try {
        await action();
      } catch (e, st) {
        debugPrint('Overdue notification update failed: $e\n$st');
      }
    });
    _tail = next;
    return next;
  }

  Future<void> _doRefresh(Routine r) async {
    await NotificationService.cancelOverdueNotice(r.id);
    await _updateNotice(r);
  }

  Future<void> _updateNotice(Routine r) async {
    if (r.completed) return;
    final due = r.scheduledAt;
    if (due == null || due <= 0) return;

    final moment = r.noticeMoment();
    if (moment == null) return;

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    if (moment > now) {
      await NotificationService.scheduleOverdueNotice(
        routineId: r.id,
        at: DateTime.fromMillisecondsSinceEpoch(moment * 1000),
        title: _title(r),
        body: _body(r, overdue: false),
      );
      return;
    }

    // Notify immediately when the requested lead time has already passed.
    await NotificationService.showOverdue(
      routineId: r.id,
      title: _title(r),
      body: _body(r, overdue: due <= now),
    );
  }

  String _title(Routine r) {
    if (r.name.isEmpty) return i18n.t('routine.no_name');
    return r.name;
  }

  String _body(Routine r, {required bool overdue}) {
    final due = r.scheduledAt;
    final dueStr = due != null ? fmtDateFull(due, i18n.t) : '—';
    final prefix = overdue
        ? i18n.t('routine.overdue')
        : i18n.t('routine.notice_title');
    return '$prefix: $dueStr';
  }
}
