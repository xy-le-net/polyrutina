// ═══════════════════════════════════════════════════════════════════
// main.dart — entry point and governor.
//
// Startup order: journal, bort, trace, field (with root creation),
// routine, dictionary, overdue scheduler, notification manager.
// Then — journal.start(). Finally — a one-pass reconciliation of
// deferred notices and overdue routines.
//
// Field tab merged into routines. The separate «field» tab has been
// removed; the tree is now built on top of the routines tab.
//
// Artel tab removed. The former stub has been abolished together
// with its block in the rubka; the tab list now carries routines,
// days, and rubka only.
//
// Shade actions. The «stop» buttons on ongoing notifications do not
// open the app (showsUserInterface: false). The Android plugin calls
// the background isolate, which writes pending_action.json; the
// application reads and deletes that file. Two paths consume it:
//
//   — on resume (a prompt reaction when the user comes back);
//   — on a periodic 2-second timer (when the app is in the
//     foreground, the state is applied within two seconds; this is
//     slower than the ticker's 500 ms, and the poll cost is a single
//     `exists` call — no flicker, no per-tick I/O storm).
//
// Both paths go through _applyShadeAction, so the semantics are
// identical: stop the shift or the routine exactly as an in-app
// press does, honouring the mutexes (mutexShift on shift stop,
// mutexRoutines/mutexSlots on routine stop), and cancel the
// corresponding notification immediately.
//
// Overdue scheduler. A small adapter (_OverdueSchedulerImpl) is
// attached to RoutineLayer after init. On every mutation that can
// affect the deferred notice — schedule change, notice change,
// completion, deletion — the layer calls refresh or cancel; the
// adapter cancels the old schedule, and, when the routine is still
// unfinished and has a future notice moment, schedules a fresh one
// via NotificationService.scheduleOverdueNotice (zonedSchedule).
//
// Startup reconciliation (_reconcileOverdue). Once per launch, after
// init and language setup:
//
//   — cancel every scheduled notice for every routine (a clean
//     slate; the plugin's alarms survive app restarts, so a stale
//     one must not linger);
//   — for each unfinished routine with a date and a notice:
//       notice moment in the future → schedule it;
//       notice moment past, due in the future → audible push now;
//       both past → audible overdue push now (and every launch
//       thereafter, until the routine is completed).
//
// The push is routine-scoped (per-routine id), so several overdue
// routines coexist in the shade.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/database.dart';
import 'data/field_layer.dart';
import 'data/i18n.dart';
import 'data/journal_layer.dart';
import 'data/journal_types.dart';
import 'data/operational_layer.dart';
import 'data/routine.dart';
import 'data/routine_layer.dart';
import 'data/ticker.dart';
import 'data/trace_layer.dart';
import 'ui/cards/routine_card.dart';
import 'ui/core/app_scope.dart';
import 'ui/core/control_row.dart';
import 'ui/core/format.dart';
import 'ui/pults/pult_core.dart';
import 'ui/pults/pult_sheet.dart';
import 'ui/pults/root_pult.dart';
import 'ui/services/notification_manager.dart';
import 'ui/services/notification_service.dart';
import 'ui/tabs/days_tab.dart';
import 'ui/tabs/routines_tab.dart';
import 'ui/tabs/rubka_tab.dart';

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
  _OverdueSchedulerImpl? _scheduler;

  final _pultState = PultState();
  final _navigatorKey = GlobalKey<NavigatorState>();

  I18n? _i18n;
  String? _initError;

  int _tab = 0; // Routines
  int? _openedRoutineId;
  bool _sheetOpen = false;

  VoidCallback? _onTickerTick;
  String _bortSignature = '';

  // Periodic consumer of pending_action.json. Started on init.
  Timer? _pendingPollTimer;

  static const List<RootTabItem> _allTabs = [
    RootTabItem(icon: Icons.checklist, labelKey: 'tab.routines'),
    RootTabItem(icon: Icons.calendar_month, labelKey: 'tab.days'),
    RootTabItem(icon: Icons.dashboard, labelKey: 'tab.rubka'),
  ];

  bool _tabVisible(int i) => true;

  static const double _pultBase = 32.0;
  static const double _pultMax = 64.0;
  static const double _rootPad = 6.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.init().then((_) {
      NotificationService.payloadNotifier.addListener(_onNotificationTap);
      _onNotificationTap();
    });

    // Periodic safety net for shade actions. A prompt pass also
    // happens on resume (see didChangeAppLifecycleState).
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
    if (_i18n != null && _i18n!.lang != _bort.lang) {
      _reloadI18n();
    }
    if (mounted) setState(() {});
  }

  Future<void> _init() async {
    try {
      final systemBrightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;

      await _journal.init();
      await _bort.init(systemBrightness);
      await _traceLayer.init(_journal);

      _i18n = await I18n.load(_bort.lang);

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

      // Attach the overdue scheduler before anything else uses the
      // layer, then run the startup reconciliation.
      _scheduler = _OverdueSchedulerImpl(_i18n!);
      _routineLayer.scheduler = _scheduler;
      unawaited(_reconcileOverdue());

      _notificationManager = NotificationManager(
        bort: _bort,
        routineLayer: _routineLayer,
        fieldLayer: _fieldLayer,
        ticker: _ticker,
        i18n: _i18n!,
      );
    } catch (e, st) {
      debugPrint('INIT FAILED: $e\n$st');
      _initError = '$e';
    }

    if (mounted) setState(() {});
  }

  // ─── Startup reconciliation of deferred notices ───
  // Cancel every scheduled notice (clean slate), then re-evaluate
  // every unfinished routine with a date and a notice. See the file
  // header for the three branches.
  Future<void> _reconcileOverdue() async {
    final i18n = _i18n;
    if (i18n == null) return;

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    for (final r in _routineLayer.routines) {
      await NotificationService.cancelOverdueNotice(r.id);
    }

    for (final r in _routineLayer.routines) {
      if (r.completed) continue;
      final due = r.scheduledAt;
      if (due == null || due <= 0) continue;
      if (!r.noticeSet) continue;

      final moment = r.noticeMoment();
      if (moment == null) continue;

      if (moment > now) {
        // Future: schedule the deferred notice.
        await NotificationService.scheduleOverdueNotice(
          routineId: r.id,
          at: DateTime.fromMillisecondsSinceEpoch(moment * 1000),
          title: _overdueTitle(i18n, r),
          body: _overdueBody(i18n, r, overdue: false),
        );
      } else if (due > now) {
        // Notice moment passed, due still ahead: audible push now.
        await NotificationService.showOverdue(
          routineId: r.id,
          title: _overdueTitle(i18n, r),
          body: _overdueBody(i18n, r, overdue: false),
        );
      } else {
        // Both passed: audible overdue push now, and at every
        // startup until the routine is completed.
        await NotificationService.showOverdue(
          routineId: r.id,
          title: _overdueTitle(i18n, r),
          body: _overdueBody(i18n, r, overdue: true),
        );
      }
    }
  }

  String _overdueTitle(I18n i18n, Routine r) {
    if (r.name.isEmpty) return i18n.t('routine.no_name');
    return r.name;
  }

  String _overdueBody(I18n i18n, Routine r, {required bool overdue}) {
    final due = r.scheduledAt;
    final dueStr = due != null ? fmtDateFull(due, i18n.t) : '—';
    final prefix = overdue
        ? i18n.t('routine.overdue')
        : i18n.t('routine.notice_title');
    return '$prefix: $dueStr';
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

  // ─── Body-tap routing ───
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

  // ─── Pending shade action ───
  Future<void> _handlePendingNotificationAction() async {
    final data = await NotificationService.consumePendingAction();
    if (data == null) return;

    final action = data['action'] ?? '';
    final payload = data['payload'] ?? '';
    await _applyShadeAction(action, payload);

    if (mounted) setState(() {});
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

  @override
  Widget build(BuildContext context) {
    if (_i18n == null) {
      if (_initError == null) return const SizedBox.shrink();
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                'init failed:\n$_initError',
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          ),
        ),
      );
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
      afterJournalReset: _afterJournalReset,
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

// ─── Overdue scheduler adapter ───
// The layer knows only the contract (refresh / cancel); the adapter
// owns the formatting and the platform calls. Kept in main.dart so
// the layer stays UI-free.
class _OverdueSchedulerImpl implements OverdueScheduler {
  final I18n i18n;
  _OverdueSchedulerImpl(this.i18n);

  @override
  void refresh(Routine routine) {
    unawaited(_doRefresh(routine));
  }

  @override
  void cancel(int routineId) {
    unawaited(NotificationService.cancelOverdueNotice(routineId));
  }

  Future<void> _doRefresh(Routine r) async {
    await NotificationService.cancelOverdueNotice(r.id);
    if (r.completed) return;
    final due = r.scheduledAt;
    if (due == null || due <= 0) return;
    if (!r.noticeSet) return;

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

    // The moment already passed. Fire an audible push now, so that
    // setting a notice whose lead time is longer than the time left
    // before the due date does not silently do nothing. Startup
    // will fire again for the same routine (by design — see the
    // file header).
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
