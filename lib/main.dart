// ═══════════════════════════════════════════════════════════════════
// main.dart — точка входа и управитель.
//
// Пять вкладок: поле, рутины, актор, рубка, журнал.
// Корневой пульт перетаскивается по восьми якорям.
// Все прочие пульты — единый класс Pult.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';

import 'data/database.dart';
import 'data/journal_repository.dart';
import 'data/operational_layer.dart';
import 'data/i18n.dart';
import 'ui/app_scope.dart';
import 'ui/pult.dart';
import 'ui/stub_tab.dart';
import 'ui/actor_tab.dart';
import 'ui/rubka_tab.dart';
import 'ui/journal_tab.dart';

void main() => runApp(const PolyRutinaApp());

class _TabItem {
  final IconData icon;
  final String labelKey;
  const _TabItem({required this.icon, required this.labelKey});
}

class PolyRutinaApp extends StatefulWidget {
  const PolyRutinaApp({super.key});
  @override
  State<PolyRutinaApp> createState() => _PolyRutinaAppState();
}

class _PolyRutinaAppState extends State<PolyRutinaApp>
    with WidgetsBindingObserver {
  late final AppDb _db;
  late final JournalRepository _journal;
  late final OperationalLayer _bort;
  final _pultState = PultState();

  I18n? _i18n;

  int _tab = 4;
  Offset? _dragOffset;
  bool _rootOpen = false;

  static const List<_TabItem> _tabs = [
    _TabItem(icon: Icons.map, labelKey: 'tab.field'),
    _TabItem(icon: Icons.checklist, labelKey: 'tab.routines'),
    _TabItem(icon: Icons.person, labelKey: 'tab.actor'),
    _TabItem(icon: Icons.dashboard, labelKey: 'tab.rubka'),
    _TabItem(icon: Icons.list, labelKey: 'tab.journal'),
  ];

  static const double _pultBase = 32.0;
  static const double _pultMax = 64.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _db = AppDb();
    _journal = JournalRepository(_db);
    _bort = OperationalLayer();
    _bort.addListener(_onBortChanged);
    _init();
  }

  void _onBortChanged() {
    if (mounted) setState(() => _tab = _bort.tab);
  }

  Future<void> _init() async {
    await _bort.init(_journal);
    _i18n = await I18n.load(_bort.lang);
    _tab = _bort.tab;
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
    }
  }

  Future<void> _switchTab(int i) async {
    _pultState.close();
    setState(() {
      _tab = i;
      _rootOpen = false;
    });
    await _bort.setSilent('tab', i.toString());
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

    final systemBrightness = MediaQuery.platformBrightnessOf(context);
    final brightness = _bort.effectiveBrightness(systemBrightness);
    final bg = _bort.currentBg(brightness);
    final fg = _bort.currentFg(brightness);
    final signal = _bort.currentSignal(brightness);
    final side = _pultSide(context);

    _pultState.baseSide = side;
    _pultState.maxSide = _pultMax;

    final appContext = AppContext(
      bort: _bort,
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
        brightness: brightness,
        colorScheme: ColorScheme.fromSeed(
          seedColor: fg,
          brightness: brightness,
        ).copyWith(surface: bg, onSurface: fg),
        scaffoldBackgroundColor: bg,
        textTheme: TextTheme(
          bodyMedium: TextStyle(color: fg),
          bodyLarge: TextStyle(color: fg),
          labelLarge: TextStyle(color: fg),
          titleMedium: TextStyle(color: fg),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderSide: BorderSide(color: fg)),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: fg)),
          focusedBorder:
              OutlineInputBorder(borderSide: BorderSide(color: fg, width: 2)),
          hintStyle: TextStyle(color: _bort.currentDim(brightness)),
        ),
        iconTheme: IconThemeData(color: fg),
      ),
      home: Builder(builder: (context) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(_bort.scale),
          ),
          child: AppScope(
            appContext: appContext,
            child: PultScope(
              state: _pultState,
              child: Scaffold(
                body: SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size =
                          Size(constraints.maxWidth, constraints.maxHeight);

                      final Offset pos;
                      if (_rootOpen && _dragOffset == null) {
                        pos = _anchorPosition(_bort.anchor, size, side);
                      } else {
                        pos = _dragOffset ??
                            _anchorPosition(_bort.anchor, size, side);
                      }

                      return PultLayer(
                        fg: fg,
                        bg: bg,
                        signal: signal,
                        child: Stack(
                          children: [
                            IndexedStack(
                              index: _tab,
                              children: const [
                                StubTab(), // поле
                                StubTab(), // рутины
                                ActorTab(), // актор
                                RubkaTab(),
                                JournalTab(),
                              ],
                            ),
                            Positioned(
                              left: pos.dx,
                              top: pos.dy,
                              child: _buildRootPult(
                                  fg, bg, signal, size, side, pos),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildRootPult(
    Color fg,
    Color bg,
    Color signal,
    Size size,
    double s,
    Offset pos,
  ) {
    if (!_rootOpen) {
      final current = _tabs[_tab];
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) {},
        onPanUpdate: (d) {
          setState(() {
            final base = _dragOffset ?? pos;
            _dragOffset = base + d.delta;
          });
        },
        onPanEnd: (d) {
          final p = _dragOffset ?? Offset.zero;
          final nearest = _nearestAnchor(p, size, s);
          setState(() => _dragOffset = null);
          _bort.setSilent('anchor', nearest);
        },
        onTapUp: (_) => setState(() => _rootOpen = true),
        child: _pultCore(current.icon, false, fg, bg, signal, s),
      );
    }

    final items = <Widget>[];
    for (var i = 0; i < _tabs.length; i++) {
      final t = _tabs[i];
      final active = _tab == i;
      items.add(
        Padding(
          padding: const EdgeInsets.all(2),
          child: GestureDetector(
            onTap: () => _switchTab(i),
            child: _pultCore(t.icon, active, fg, bg, signal, s * 2 / 3),
          ),
        ),
      );
    }

    final centerX = pos.dx + s / 2;
    final centerY = pos.dy + s / 2;
    final pushRight = centerX > size.width / 2;
    final pushDown = centerY <= size.height / 2;

    final maxW = pushRight ? (pos.dx + s) : (size.width - pos.dx);
    final maxH = pushDown ? (size.height - pos.dy - s) : (pos.dy + s);

    final layout = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
      child: _layoutPults(
        items,
        Size(maxW, maxH),
        s * 2 / 3 + 8,
        alignEnd: pushRight,
      ),
    );

    final dx = pushRight ? (s - maxW) : 0.0;
    final dy = pushDown ? s : -maxH;

    return Transform.translate(
      offset: Offset(dx, dy),
      child: SizedBox(
        width: maxW,
        height: maxH,
        child: Align(
          alignment: Alignment(
            pushRight ? 1.0 : -1.0,
            pushDown ? -1.0 : 1.0,
          ),
          child: layout,
        ),
      ),
    );
  }

  Widget _pultCore(
    IconData icon,
    bool selected,
    Color fg,
    Color bg,
    Color signal,
    double s,
  ) {
    final coreColor = selected ? signal : fg;
    final iconColor = bg;
    final borderW = s / 16;
    final rOuter = s * 0.18;
    final rInner = s * 0.14;
    final rCore = s * 0.10;

    Widget core = Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        color: coreColor,
        borderRadius: BorderRadius.circular(rCore),
      ),
      child: Center(
        child: Icon(icon, color: iconColor, size: s * 0.45),
      ),
    );

    core = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(rInner),
        border:
            Border.all(color: selected ? iconColor : coreColor, width: borderW),
      ),
      child: core,
    );

    core = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(rOuter),
        border: Border.all(color: coreColor, width: borderW),
      ),
      child: core,
    );

    return core;
  }

  Widget _layoutPults(
    List<Widget> items,
    Size available,
    double itemHeight, {
    bool alignEnd = false,
  }) {
    final n = items.length;
    if (n == 0) return const SizedBox.shrink();

    final cross = alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    if (n * itemHeight <= available.height) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: cross,
        children: items,
      );
    }

    final maxRows = (available.height / itemHeight).floor().clamp(1, n);
    final cols = (n / maxRows).ceil();

    final colWidgets = <Widget>[];
    for (var c = 0; c < cols; c++) {
      final colItems = <Widget>[];
      for (var r = 0; r < maxRows; r++) {
        final i = c * maxRows + r;
        if (i < n) colItems.add(items[i]);
      }
      colWidgets.add(
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: cross,
          children: colItems,
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: colWidgets,
    );
  }
}
