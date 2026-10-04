// ═══════════════════════════════════════════════════════════════════
// main.dart — точка входа приложения.
//
// Пять вкладок: поле, рутины, актор, рубка, журнал.
// Корневой пульт перетаскивается по восьми якорям, не уходит за экран.
// Рубка делится на блоки: оформление, интерфейс, данные.
// Блок данных: перечитать, очистить (журнал), сброс (кэш борта).
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:table_view_ex/table_view_ex.dart';

import 'data/database.dart';
import 'data/journal_repository.dart';
import 'data/operational_layer.dart';
import 'data/i18n.dart';

void main() => runApp(const PolyRutinaApp());

class _JournalWidthCalculator implements TableViewExWidthCalculator {
  @override
  List<double> calculateColumnWidths(
    double maxWidth,
    List<TableViewExColumnConfig> columnDefinitions,
  ) {
    return columnDefinitions.map((col) {
      switch (col.key) {
        case 'id':
          return 60.0;
        case 'time':
          return 160.0;
        case 'type':
          return 90.0;
        case 'flags':
          return 60.0;
        case 'body':
          return 400.0;
        default:
          return 120.0;
      }
    }).toList();
  }
}

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

  I18n? _i18n;

  List<JournalData> _entries = [];
  int _journalCount = 0;
  int _journalBytes = 0;

  final _inputController = TextEditingController();

  int _tab = 4;
  Offset? _dragOffset;

  bool _menuOpen = false;
  bool _typeMenuOpen = false;
  bool _flagsMenuOpen = false;

  // Блок «данные».
  // _dataSub: null | 'journal' | 'cache'.
  // _journalMode: null | 'synced' | 'all'.
  String? _dataSub;
  String? _journalMode;

  List<TableViewExColumnConfig> _columns = [];
  final _widthCalculator = _JournalWidthCalculator();

  static const List<_TabItem> _tabs = [
    _TabItem(icon: Icons.map, labelKey: 'tab.field'),
    _TabItem(icon: Icons.checklist, labelKey: 'tab.routines'),
    _TabItem(icon: Icons.person, labelKey: 'tab.actor'),
    _TabItem(icon: Icons.dashboard, labelKey: 'tab.rubka'),
    _TabItem(icon: Icons.list, labelKey: 'tab.journal'),
  ];

  static const List<IconData> _typeIcons = [
    Icons.circle_outlined,
    Icons.checklist,
    Icons.timer_outlined,
    Icons.person_outline,
    Icons.tune,
  ];

  static const List<IconData> _flagIcons = [
    Icons.access_time,
    Icons.warning_amber,
    Icons.star_border,
    Icons.help_outline,
    Icons.fitness_center,
    Icons.phone_android,
    Icons.cloud_done,
  ];

  static const double _basePultSide = 32.0;
  static const double _pultMaxSide = 64.0;
  static const double _smallPultRatio = 2.0 / 3.0;
  static const double _pultRowHeight = 52.0;

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
    _rebuildColumns();
    _tab = _bort.tab;
    _inputController.text = _bort.draft('console');
    await _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bort.removeListener(_onBortChanged);
    _inputController.dispose();
    _db.close();
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

  Future<void> _refresh() async {
    final entries = await _journal.recent(limit: 50);
    final sz = await _journal.size();
    if (mounted) {
      setState(() {
        _entries = entries;
        _journalCount = sz.count;
        _journalBytes = sz.bytes;
      });
    }
  }

  void _openOnly({
    bool menu = false,
    bool type = false,
    bool flags = false,
  }) {
    setState(() {
      _menuOpen = menu;
      _typeMenuOpen = type;
      _flagsMenuOpen = flags;
      _dataSub = null;
      _journalMode = null;
    });
  }

  void _closeAll() => _openOnly();

  Future<void> _switchTab(int i) async {
    _closeAll();
    setState(() => _tab = i);
    await _bort.setSilent('tab', i.toString());
  }

  void _rebuildColumns() {
    _columns = [
      TableViewExColumnConfig(
        key: 'id',
        widgetBuilder: () => Text(_i18n!.t('col.id')),
        minWidth: 50,
      ),
      TableViewExColumnConfig(
        key: 'time',
        widgetBuilder: () => Text(_i18n!.t('col.time')),
        minWidth: 120,
      ),
      TableViewExColumnConfig(
        key: 'type',
        widgetBuilder: () => Text(_i18n!.t('col.type')),
        minWidth: 70,
      ),
      TableViewExColumnConfig(
        key: 'flags',
        widgetBuilder: () => Text(_i18n!.t('col.flags')),
        minWidth: 50,
      ),
      TableViewExColumnConfig(
        key: 'body',
        widgetBuilder: () => Text(_i18n!.t('col.body')),
        minWidth: 200,
      ),
    ];
  }

  Future<void> _sendInput() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    _bort.clearDraft('console');

    await _journal.log(
      type: _bort.selectedType,
      body: text,
      flags: _bort.selectedFlags,
    );

    if (_bort.selectedType == JournalType.bort) {
      await _bort.applyJournalDeltas();
    }

    if (_bort.selectedType == JournalType.bort && text.contains('lang=')) {
      _i18n = await I18n.load(_bort.lang);
      _rebuildColumns();
    }

    await _refresh();
  }

  Widget _buildCell(BuildContext context, int colIndex, int rowIndex) {
    final e = _entries[rowIndex];
    final when = DateTime.fromMillisecondsSinceEpoch(e.time * 1000);
    final t =
        '${when.day.toString().padLeft(2, '0')}.${when.month.toString().padLeft(2, '0')} '
        '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
    const typeKeys = [
      'type.trace',
      'type.routine',
      'type.timer',
      'type.actor',
      'type.bort',
    ];
    final typeName = (e.type >= 0 && e.type < typeKeys.length)
        ? _i18n!.t(typeKeys[e.type])
        : '?';

    final String text;
    switch (colIndex) {
      case 0:
        text = '#${e.id}';
        break;
      case 1:
        text = t;
        break;
      case 2:
        text = typeName;
        break;
      case 3:
        text = '${e.flags}';
        break;
      case 4:
        text = e.body;
        break;
      default:
        text = '';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(text, overflow: TextOverflow.ellipsis, maxLines: 1),
    );
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

  // ─── Обработчики блока «данные» ───

  Future<void> _onReload() async {
    await _bort.reloadFromJournal();
    _i18n = await I18n.load(_bort.lang);
    _rebuildColumns();
    _inputController.text = _bort.draft('console');
    await _refresh();
  }

  Future<void> _onJournalCleanup() async {
    if (_journalMode == 'synced') {
      await _journal.deleteSynced();
    } else if (_journalMode == 'all') {
      await _journal.clearAll();
    }
    setState(() {
      _dataSub = null;
      _journalMode = null;
    });
    await _refresh();
  }

  Future<void> _onCacheCleanup() async {
    await _bort.resetCache();
    _i18n = await I18n.load(_bort.lang);
    _rebuildColumns();
    _inputController.text = _bort.draft('console');
    setState(() {
      _dataSub = null;
      _tab = _bort.tab;
    });
  }

  String _fmtNum(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  Widget _wrapTab(Widget child) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (_) {
        if (_menuOpen || _dataSub != null || _typeMenuOpen || _flagsMenuOpen) {
          _closeAll();
        }
      },
      child: child,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Пульт — единая отрисовка.
  // ═══════════════════════════════════════════════════════════════
  Widget _pult(
    IconData icon,
    bool selected,
    Color fg,
    Color bg,
    Color signal,
    double s, {
    String? label,
    double? availLeft,
    double? availRight,
  }) {
    final coreColor = selected ? signal : fg;
    final iconColor = bg;
    final borderW = s / 16;

    final innerBorderColor = selected ? iconColor : coreColor;
    final outerBorderColor = coreColor;

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
        border: Border.all(color: innerBorderColor, width: borderW),
      ),
      child: core,
    );

    core = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(rOuter),
        border: Border.all(color: outerBorderColor, width: borderW),
      ),
      child: core,
    );

    if (label == null) return core;

    final labelWidth = (label.length * s * 0.4 + 16).clamp(s * 1.5, s * 6);
    final right = availRight ?? 0;
    final left = availLeft ?? 0;
    final placeLeft = (right < labelWidth) && (left >= labelWidth);

    final labelWidget = Container(
      height: s * 0.75,
      decoration: BoxDecoration(
        color: coreColor,
        borderRadius: placeLeft
            ? BorderRadius.horizontal(left: Radius.circular(rOuter))
            : BorderRadius.horizontal(right: Radius.circular(rOuter)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        label,
        style: TextStyle(color: iconColor),
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );

    if (placeLeft) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [labelWidget, core],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [core, labelWidget],
    );
  }

  Widget _pultNumber(
    String number,
    bool selected,
    Color fg,
    Color bg,
    Color signal,
    double s, {
    String? label,
    double? availLeft,
    double? availRight,
  }) {
    final coreColor = selected ? signal : fg;
    final iconColor = bg;
    final borderW = s / 16;

    final innerBorderColor = selected ? iconColor : coreColor;
    final outerBorderColor = coreColor;

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
        child: Text(
          number,
          style: TextStyle(color: iconColor, fontFamily: 'monospace'),
        ),
      ),
    );

    core = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(rInner),
        border: Border.all(color: innerBorderColor, width: borderW),
      ),
      child: core,
    );

    core = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(rOuter),
        border: Border.all(color: outerBorderColor, width: borderW),
      ),
      child: core,
    );

    if (label == null) return core;

    final labelWidth = (label.length * s * 0.4 + 16).clamp(s * 1.5, s * 6);
    final right = availRight ?? 0;
    final left = availLeft ?? 0;
    final placeLeft = (right < labelWidth) && (left >= labelWidth);

    final labelWidget = Container(
      height: s * 0.75,
      decoration: BoxDecoration(
        color: coreColor,
        borderRadius: placeLeft
            ? BorderRadius.horizontal(left: Radius.circular(rOuter))
            : BorderRadius.horizontal(right: Radius.circular(rOuter)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(label,
          style: TextStyle(color: iconColor),
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          maxLines: 1),
    );

    if (placeLeft) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [labelWidget, core],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [core, labelWidget],
    );
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

  double _pultSide() {
    final systemScale = MediaQuery.textScalerOf(context).scale(1.0);
    final raw = _basePultSide * systemScale * _bort.scale;
    return raw > _pultMaxSide ? _pultMaxSide : raw;
  }

  double _smallPultSide() => _pultSide() * _smallPultRatio;

  // ═══════════════════════════════════════════════════════════════
  // Пульт с подпультами над собою.
  //
  // Родитель стоит внизу. Подпульты — над ним, столбцом.
  // Столбец центрируется по родителю (не по всей строке).
  // Подписи обрезаются многоточием, не вылезают за экран.
  // ═══════════════════════════════════════════════════════════════
  Widget _pultWithSubs({
    required String label,
    required IconData parentIcon,
    required bool parentActive,
    required VoidCallback onParentTap,
    required Color fg,
    required Color bg,
    required Color signal,
    required double side,
    required List<Widget>? subs,
    required VoidCallback? onConfirm,
    required bool confirmMode,
  }) {
    // Родительский пульт.
    final parent = GestureDetector(
      onTap: () {
        if (confirmMode && onConfirm != null) {
          onConfirm();
        } else {
          onParentTap();
        }
      },
      child: confirmMode
          ? _pult(Icons.delete_forever, true, fg, bg, signal, side * 1.3)
          : _pult(parentIcon, parentActive, fg, bg, signal, side),
    );

    // Узел «подпульты + родитель» — центрируется по горизонтали.
    final pultColumn = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (subs != null && subs.isNotEmpty) ...[
          for (final s in subs)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: s,
            ),
        ],
        parent,
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          width: 140,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label, style: TextStyle(color: fg)),
          ),
        ),
        // Место под пульт и подпульты: ограничено остатком ширины,
        // дабы подписи подпультов обрезались, а не вылезали.
        Expanded(
          child: Align(
            alignment: Alignment.topLeft,
            child: pultColumn,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_i18n == null) return const SizedBox.shrink();

    final systemBrightness = MediaQuery.platformBrightnessOf(context);
    final brightness = _bort.effectiveBrightness(systemBrightness);
    final bg = _bort.currentBg(brightness);
    final fg = _bort.currentFg(brightness);
    final signal = _bort.currentSignal(brightness);

    final rootSide = _pultSide();
    final smallSide = _smallPultSide();

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
          child: Scaffold(
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size =
                      Size(constraints.maxWidth, constraints.maxHeight);

                  final Offset pos;
                  if (_menuOpen && _dragOffset == null) {
                    pos = _anchorPosition(_bort.anchor, size, rootSide);
                  } else {
                    pos = _dragOffset ??
                        _anchorPosition(_bort.anchor, size, rootSide);
                  }

                  return Stack(
                    children: [
                      IndexedStack(
                        index: _tab,
                        children: [
                          _wrapTab(_buildStub(fg, brightness)),
                          _wrapTab(_buildStub(fg, brightness)),
                          _wrapTab(_buildStub(fg, brightness)),
                          _wrapTab(_buildRubkaTab(
                              fg, brightness, smallSide, bg, signal)),
                          _wrapTab(_buildJournalTab(fg, brightness, smallSide)),
                        ],
                      ),
                      Positioned(
                        left: pos.dx,
                        top: pos.dy,
                        child: _buildMultiPult(
                          fg,
                          bg,
                          signal,
                          size,
                          rootSide,
                          smallSide,
                          pos: pos,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildMultiPult(
    Color fg,
    Color bg,
    Color signal,
    Size size,
    double rootSide,
    double smallSide, {
    required Offset pos,
  }) {
    if (!_menuOpen) {
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
          final nearest = _nearestAnchor(p, size, rootSide);
          setState(() => _dragOffset = null);
          _bort.setSilent('anchor', nearest);
        },
        onTapUp: (_) => _openOnly(menu: true),
        child: _pult(current.icon, false, fg, bg, signal, rootSide),
      );
    }

    final showLabels = _bort.labelsSystem;
    const tabKeys = [
      'tab.field',
      'tab.routines',
      'tab.actor',
      'tab.rubka',
      'tab.journal',
    ];

    final centerX = pos.dx + rootSide / 2;
    final centerY = pos.dy + rootSide / 2;
    final pushRight = centerX > size.width / 2;
    final pushDown = centerY <= size.height / 2;

    final maxW = pushRight ? (pos.dx + rootSide) : (size.width - pos.dx);
    final maxH =
        pushDown ? (size.height - pos.dy - rootSide) : (pos.dy + rootSide);

    final items = <Widget>[];
    for (var i = 0; i < _tabs.length; i++) {
      final t = _tabs[i];
      final active = _tab == i;
      final label = showLabels ? _i18n!.t(tabKeys[i]) : null;
      items.add(
        Padding(
          padding: const EdgeInsets.all(2),
          child: GestureDetector(
            onTap: () {
              _switchTab(i);
            },
            child: _pult(t.icon, active, fg, bg, signal, smallSide,
                label: label,
                availLeft: pos.dx,
                availRight: size.width - pos.dx - rootSide),
          ),
        ),
      );
    }

    final layout = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
      child: _layoutPults(
        items,
        Size(maxW, maxH),
        smallSide + 8,
        alignEnd: pushRight,
      ),
    );

    final dx = pushRight ? (rootSide - maxW) : 0.0;
    final dy = pushDown ? rootSide : -maxH;

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

  Widget _buildJournalTab(Color fg, Brightness brightness, double smallSide) {
    final bg = _bort.currentBg(brightness);
    final signal = _bort.currentSignal(brightness);

    return LayoutBuilder(builder: (context, constraints) {
      final availForPanelH = constraints.maxHeight - _pultRowHeight - 16;
      final availForPanelW = constraints.maxWidth - 16;

      return Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: ViewOnlyTableViewEx(
                  columnDefinitions: _columns,
                  showHeader: true,
                  contentRowsCount: _entries.length,
                  rowSpanBuilder: (rowIndex) => const FixedSpanExtent(44),
                  columnWidthCalculator: _widthCalculator,
                  contentCellWidgetBuilder: (ctx, col, row) => DefaultTextStyle(
                    style: TextStyle(color: fg),
                    child: _buildCell(ctx, col, row),
                  ),
                  onSortRequested: (colIndex) {},
                  enableColumnWidthResize: true,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
                child: TextField(
                  controller: _inputController,
                  style: TextStyle(color: fg),
                  decoration: InputDecoration(
                    hintText: _i18n!.t('input.hint'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                  ),
                  onChanged: (v) => _bort.setDraft('console', v),
                  onSubmitted: (_) => _sendInput(),
                ),
              ),
              SizedBox(
                height: _pultRowHeight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => _openOnly(type: !_typeMenuOpen),
                        child: _pult(
                          _typeIcons[
                              JournalType.all.indexOf(_bort.selectedType)],
                          _typeMenuOpen,
                          fg,
                          bg,
                          signal,
                          smallSide,
                          availLeft: 8,
                          availRight: constraints.maxWidth - 8 - smallSide,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _openOnly(flags: !_flagsMenuOpen),
                        child: _pultNumber(
                          '${_bort.selectedFlags}',
                          _flagsMenuOpen,
                          fg,
                          bg,
                          signal,
                          smallSide,
                          availLeft: 8 + smallSide + 8,
                          availRight: constraints.maxWidth -
                              8 -
                              smallSide -
                              8 -
                              smallSide,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _sendInput,
                        tooltip: _i18n!.t('button.send'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_typeMenuOpen)
            Positioned(
              left: 0,
              right: 0,
              bottom: _pultRowHeight,
              child: Container(
                color: bg,
                padding: const EdgeInsets.all(8),
                child: _layoutPults(
                  _buildTypePanelItems(fg, bg, signal, smallSide),
                  Size(availForPanelW, availForPanelH),
                  smallSide + 8,
                ),
              ),
            ),
          if (_flagsMenuOpen)
            Positioned(
              left: 0,
              right: 0,
              bottom: _pultRowHeight,
              child: Container(
                color: bg,
                padding: const EdgeInsets.all(8),
                child: _layoutPults(
                  _buildFlagsPanelItems(fg, bg, signal, smallSide),
                  Size(availForPanelW, availForPanelH),
                  smallSide + 8,
                ),
              ),
            ),
        ],
      );
    });
  }

  List<Widget> _buildTypePanelItems(
      Color fg, Color bg, Color signal, double side) {
    const typeKeys = [
      'type.trace',
      'type.routine',
      'type.timer',
      'type.actor',
      'type.bort',
    ];
    final items = <Widget>[];
    for (var i = 0; i < JournalType.all.length; i++) {
      final t = JournalType.all[i];
      final active = t == _bort.selectedType;
      items.add(
        GestureDetector(
          onTap: () => setState(() {
            _bort.setInt('selected_type', t);
            _typeMenuOpen = false;
          }),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: _pult(_typeIcons[i], active, fg, bg, signal, side,
                label: _bort.labelsSystem ? _i18n!.t(typeKeys[i]) : null),
          ),
        ),
      );
    }
    return items;
  }

  List<Widget> _buildFlagsPanelItems(
      Color fg, Color bg, Color signal, double side) {
    const flagKeys = [
      'flag.urgent',
      'flag.emergency',
      'flag.important',
      'flag.disputable',
      'flag.complexOp',
      'flag.local',
      'flag.synced',
    ];
    final items = <Widget>[];
    for (var i = 0; i < JournalFlag.all.length; i++) {
      final bit = JournalFlag.all[i];
      final active = (_bort.selectedFlags & bit) != 0;
      items.add(
        GestureDetector(
          onTap: () => setState(() {
            _bort.setInt('selected_flags', _bort.selectedFlags ^ bit);
          }),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: _pult(_flagIcons[i], active, fg, bg, signal, side,
                label: _bort.labelsSystem ? _i18n!.t(flagKeys[i]) : null),
          ),
        ),
      );
    }
    return items;
  }

  Widget _buildRubkaTab(Color fg, Brightness brightness, double smallSide,
      Color bg, Color signal) {
    final dim = _bort.currentDim(brightness);

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth > 640;

      final blocks = <Widget>[
        _buildBlock(
          titleKey: 'block.appearance',
          isOpen: _bort.blockAppearance,
          onToggle: () =>
              _bort.setBool('block_appearance', !_bort.blockAppearance),
          fg: fg,
          dim: dim,
          brightness: brightness,
          children: <Widget>[
            _themeRow(fg, dim, brightness, bg, signal, smallSide),
            _settingRow('bg_day', fg, dim, brightness, smallSide),
            _settingRow('bg_night', fg, dim, brightness, smallSide),
            _settingRow('fg_day', fg, dim, brightness, smallSide),
            _settingRow('fg_night', fg, dim, brightness, smallSide),
            _settingRow('dim_day', fg, dim, brightness, smallSide),
            _settingRow('dim_night', fg, dim, brightness, smallSide),
            _settingRow('signal_day', fg, dim, brightness, smallSide),
            _settingRow('signal_night', fg, dim, brightness, smallSide),
          ],
        ),
        _buildBlock(
          titleKey: 'block.interface',
          isOpen: _bort.blockInterface,
          onToggle: () =>
              _bort.setBool('block_interface', !_bort.blockInterface),
          fg: fg,
          dim: dim,
          brightness: brightness,
          children: <Widget>[
            _settingRow('scale', fg, dim, brightness, smallSide),
            _settingRow('lang', fg, dim, brightness, smallSide),
            _settingRow('labels_system', fg, dim, brightness, smallSide),
            _settingRow('labels_field', fg, dim, brightness, smallSide),
          ],
        ),
        _buildBlock(
          titleKey: 'block.data',
          isOpen: _bort.blockData,
          onToggle: () => _bort.setBool('block_data', !_bort.blockData),
          fg: fg,
          dim: dim,
          brightness: brightness,
          children: [
            // ─── Размер журнала ───
            Row(
              children: [
                SizedBox(
                  width: 140,
                  child: Text(_i18n!.t('bort.journal'),
                      style: TextStyle(color: fg)),
                ),
                Expanded(
                  child: Text(
                    '${_fmtNum(_journalCount)} ${_i18n!.t('bort.entries')}   '
                    '${_fmtNum(_journalBytes)} ${_i18n!.t('bort.bytes')}',
                    style: TextStyle(color: fg, fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ─── 1. Перечитать ───
            Row(
              children: [
                SizedBox(
                  width: 140,
                  child: Text(_i18n!.t('bort.reload'),
                      style: TextStyle(color: fg)),
                ),
                GestureDetector(
                  onTap: _onReload,
                  child: _pult(Icons.refresh, false, fg, bg, signal, smallSide),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ─── 2. Очистить (журнал) ───
            _pultWithSubs(
              label: _i18n!.t('bort.cleanup'),
              parentIcon: Icons.delete_outline,
              parentActive: _dataSub == 'journal',
              onParentTap: () => setState(() {
                _dataSub = (_dataSub == 'journal') ? null : 'journal';
                _journalMode = null;
              }),
              fg: fg,
              bg: bg,
              signal: signal,
              side: smallSide,
              confirmMode: false,
              onConfirm: null,
              subs: _dataSub == 'journal'
                  ? [
                      // Синхронизированное
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (_journalMode == 'synced') {
                            _onJournalCleanup();
                          } else {
                            setState(() => _journalMode = 'synced');
                          }
                        },
                        child: _journalMode == 'synced'
                            ? _pult(Icons.delete_forever, true, fg, bg, signal,
                                smallSide * 1.3)
                            : _pult(
                                Icons.cloud_done,
                                false,
                                fg,
                                bg,
                                signal,
                                smallSide,
                                label: _bort.labelsSystem
                                    ? _i18n!.t('bort.synced')
                                    : null,
                              ),
                      ),
                      // Всё
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (_journalMode == 'all') {
                            _onJournalCleanup();
                          } else {
                            setState(() => _journalMode = 'all');
                          }
                        },
                        child: _journalMode == 'all'
                            ? _pult(Icons.delete_forever, true, fg, bg, signal,
                                smallSide * 1.3)
                            : _pult(
                                Icons.select_all,
                                false,
                                fg,
                                bg,
                                signal,
                                smallSide,
                                label: _bort.labelsSystem
                                    ? _i18n!.t('bort.all')
                                    : null,
                              ),
                      ),
                    ]
                  : null,
            ),
            const SizedBox(height: 12),

            // ─── 3. Сброс (кэш) ───
            _pultWithSubs(
              label: _i18n!.t('bort.reset'),
              parentIcon: Icons.cleaning_services,
              parentActive: _dataSub == 'cache',
              onParentTap: () => setState(() {
                _dataSub = (_dataSub == 'cache') ? null : 'cache';
              }),
              fg: fg,
              bg: bg,
              signal: signal,
              side: smallSide,
              confirmMode: _dataSub == 'cache',
              onConfirm: _onCacheCleanup,
              subs: null,
            ),
          ],
        ),
      ];

      if (wide) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 80, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Column(children: [blocks[0], blocks[2]])),
              const SizedBox(width: 24),
              Expanded(child: Column(children: [blocks[1]])),
            ],
          ),
        );
      }

      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 80, 16, 16),
        children: blocks,
      );
    });
  }

  Widget _themeRow(Color fg, Color dim, Brightness brightness, Color bg,
      Color signal, double side) {
    const options = ['system', 'dark', 'light'];
    const optionLabels = {
      'system': 'theme.system',
      'dark': 'theme.dark',
      'light': 'theme.light',
    };
    const optionIcons = {
      'system': Icons.brightness_auto,
      'dark': Icons.dark_mode,
      'light': Icons.light_mode,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_i18n!.t('bort.theme'), style: TextStyle(color: fg)),
                Text('theme', style: TextStyle(color: dim, fontSize: 11)),
              ],
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              children: options.map((o) {
                final active = _bort.theme == o;
                return GestureDetector(
                  onTap: () => _bort.setSilent('theme', o),
                  child: _pult(
                    optionIcons[o]!,
                    active,
                    fg,
                    bg,
                    signal,
                    side,
                    label:
                        _bort.labelsSystem ? _i18n!.t(optionLabels[o]!) : null,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlock({
    required String titleKey,
    required bool isOpen,
    required VoidCallback onToggle,
    required List<Widget> children,
    required Color fg,
    required Color dim,
    required Brightness brightness,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: dim),
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(
                      _i18n!.t(titleKey),
                      style: TextStyle(
                        color: dim,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      isOpen ? Icons.expand_less : Icons.expand_more,
                      color: dim,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            if (isOpen) ...[
              const SizedBox(height: 8),
              ...children,
            ],
          ],
        ),
      ),
    );
  }

  Widget _settingRow(
      String key, Color fg, Color dim, Brightness brightness, double side) {
    final type = OperationalLayer.settingTypes[key] ?? 'string';
    final value = _bort.allAsStrings[key] ?? '';
    final bg = _bort.currentBg(brightness);
    final signal = _bort.currentSignal(brightness);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_i18n!.t('bort.$key'), style: TextStyle(color: fg)),
                Text(key, style: TextStyle(color: dim, fontSize: 11)),
              ],
            ),
          ),
          Expanded(
            child: _buildSettingField(
                key, type, value, fg, dim, brightness, bg, signal, side),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingField(
    String key,
    String type,
    String value,
    Color fg,
    Color dim,
    Brightness brightness,
    Color bg,
    Color signal,
    double side,
  ) {
    switch (type) {
      case 'bool':
        final b = value == 'true';
        return Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: () => _bort.setBool(key, !b),
            child: _pult(b ? Icons.check : Icons.circle_outlined, b, fg, bg,
                signal, side),
          ),
        );
      case 'color':
        final c = _parseColor(value) ?? Colors.transparent;
        return Row(
          children: [
            Expanded(
              child: _BortField(
                keyName: key,
                initial: value,
                fg: fg,
                readOnly: false,
                onChanged: (v) => _bort.setDraft(key, v),
                onCommit: (v) => _bort.set(key, v),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: c,
                border: Border.all(color: fg),
              ),
            ),
          ],
        );
      case 'string':
      default:
        return _BortField(
          keyName: key,
          initial: value,
          fg: fg,
          readOnly: OperationalLayer.readOnlyKeys.contains(key),
          onChanged: (v) => _bort.setDraft(key, v),
          onCommit: (v) async {
            await _bort.set(key, v);
            if (key == 'lang') {
              _i18n = await I18n.load(_bort.lang);
              _rebuildColumns();
            }
          },
        );
    }
  }

  Color? _parseColor(String s) {
    var t = s.trim();
    if (t.startsWith('#')) t = t.substring(1);
    if (t.length != 6) return null;
    final v = int.tryParse(t, radix: 16);
    if (v == null) return null;
    return Color(0xFF000000 | v);
  }

  Widget _buildStub(Color fg, Brightness brightness) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _i18n!.t('stub.title'),
            style: TextStyle(color: fg, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            _i18n!.t('stub.text'),
            style: TextStyle(color: _bort.currentDim(brightness)),
          ),
        ],
      ),
    );
  }
}

class _BortField extends StatefulWidget {
  final String keyName;
  final String initial;
  final Color fg;
  final bool readOnly;
  final void Function(String value)? onChanged;
  final Future<void> Function(String value) onCommit;

  const _BortField({
    required this.keyName,
    required this.initial,
    required this.fg,
    required this.readOnly,
    required this.onCommit,
    this.onChanged,
  });

  @override
  State<_BortField> createState() => _BortFieldState();
}

class _BortFieldState extends State<_BortField> {
  late final TextEditingController _ctrl;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant _BortField old) {
    super.didUpdateWidget(old);
    if (old.initial != widget.initial && !_focus.hasFocus) {
      _ctrl.text = widget.initial;
    }
  }

  Future<void> _commit() async {
    final v = _ctrl.text.trim();
    if (v == widget.initial) return;
    await widget.onCommit(v);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      focusNode: _focus,
      readOnly: widget.readOnly,
      style: TextStyle(color: widget.fg),
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      onChanged: widget.onChanged,
      onSubmitted: (_) => _commit(),
    );
  }
}
