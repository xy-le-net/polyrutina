// ═══════════════════════════════════════════════════════════════════
// main.dart — точка входа приложения.
//
// Пять вкладок: поле, рутины, актор, рубка, журнал.
// Переключение — корневым пультом, перетаскиваемым по восьми якорям.
// Рубка делится на блоки: оформление, интерфейс, данные.
// Внизу журнала: поле ввода, пульт рода, пульт флагов, отправка.
//
// Состояние интерфейса хранится полностью в борте: блоки рубки,
// выбор рода и флагов, черновики полей и консоли, тема.
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

  // Контроллер консоли. Черновик хранится в борте: 'console'.
  final _inputController = TextEditingController();

  int _tab = 4;
  Offset? _dragOffset;
  bool _menuOpen = false;

  bool _cleanupOpen = false;
  String? _cleanupTarget;

  bool _typeMenuOpen = false;
  bool _flagsMenuOpen = false;

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
  static const double _pultRowHeight = 52.0;
  static const double _labelGap = 8.0;

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
    // Восстановим черновик консоли.
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

  Future<void> _switchTab(int i) async {
    setState(() {
      _tab = i;
      _cleanupOpen = false;
      _cleanupTarget = null;
      _typeMenuOpen = false;
      _flagsMenuOpen = false;
    });
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

  Offset _expandedPosition(
      String anchor, Size size, bool horizontal, double s) {
    const m = 6.0;
    const gap = 4.0;
    final one = s + 2 * gap;
    final five = 5 * one;
    final w = horizontal ? five : one;
    final h = horizontal ? one : five;

    double left;
    if (anchor == 'tl' || anchor == 'bl' || anchor == 'lc') {
      left = m;
    } else if (anchor == 'tr' || anchor == 'br' || anchor == 'rc') {
      left = size.width - m - w;
    } else {
      left = (size.width - w) / 2;
    }

    double top;
    if (anchor == 'tl' || anchor == 'tr' || anchor == 'tc') {
      top = m;
    } else if (anchor == 'bl' || anchor == 'br' || anchor == 'bc') {
      top = size.height - m - h;
    } else {
      top = (size.height - h) / 2;
    }

    return Offset(left, top);
  }

  Future<void> _doCleanup() async {
    if (_cleanupTarget == 'journal') {
      await _journal.clearAll();
      setState(() {
        _cleanupOpen = false;
        _cleanupTarget = null;
      });
      await _refresh();
    } else if (_cleanupTarget == 'bort') {
      await _bort.resetToDefaults();
      _i18n = await I18n.load(_bort.lang);
      _rebuildColumns();
      _inputController.text = _bort.draft('console');
      setState(() {
        _cleanupOpen = false;
        _cleanupTarget = null;
        _tab = _bort.tab;
      });
    }
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
        if (_menuOpen || _cleanupOpen || _typeMenuOpen || _flagsMenuOpen) {
          setState(() {
            _menuOpen = false;
            _cleanupOpen = false;
            _cleanupTarget = null;
            _typeMenuOpen = false;
            _flagsMenuOpen = false;
          });
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
    double s, {
    String? label,
  }) {
    BoxBorder? border;
    if (selected) {
      border = Border.all(color: bg, width: 2);
    }

    Widget core = Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        color: fg,
        border: border,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, color: bg, size: s * 0.55),
    );

    if (selected) {
      core = Container(
        decoration: BoxDecoration(
          border: Border.all(color: fg, width: 2),
          borderRadius: BorderRadius.circular(7),
        ),
        child: core,
      );
    }

    if (label == null) return core;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        core,
        Container(
          height: s * 0.75,
          decoration: BoxDecoration(
            color: fg,
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(6),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.centerLeft,
          child: Text(label, style: TextStyle(color: bg)),
        ),
      ],
    );
  }

  Widget _pultNumber(
    String number,
    bool selected,
    Color fg,
    Color bg,
    double s, {
    String? label,
  }) {
    BoxBorder? border;
    if (selected) {
      border = Border.all(color: bg, width: 2);
    }

    Widget core = Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        color: fg,
        border: border,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Text(
          number,
          style: TextStyle(color: bg, fontFamily: 'monospace'),
        ),
      ),
    );

    if (selected) {
      core = Container(
        decoration: BoxDecoration(
          border: Border.all(color: fg, width: 2),
          borderRadius: BorderRadius.circular(7),
        ),
        child: core,
      );
    }

    if (label == null) return core;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        core,
        Container(
          height: s * 0.75,
          decoration: BoxDecoration(
            color: fg,
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(6),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.centerLeft,
          child: Text(label, style: TextStyle(color: bg)),
        ),
      ],
    );
  }

  Widget _layoutPults(
    List<Widget> items,
    Size available,
    double itemHeight,
  ) {
    final columnHeight = items.length * itemHeight;
    if (columnHeight <= available.height) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items,
      );
    }
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: items,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_i18n == null) return const SizedBox.shrink();

    // Системная яркость + тема из борта = эффективная.
    final systemBrightness = MediaQuery.platformBrightnessOf(context);
    final brightness = _bort.effectiveBrightness(systemBrightness);
    final bg = _bort.currentBg(brightness);
    final fg = _bort.currentFg(brightness);

    final systemScale = MediaQuery.textScalerOf(context).scale(1.0);
    final rawSide = _basePultSide * systemScale * _bort.scale;
    final pultSide = rawSide > _pultMaxSide ? _pultMaxSide : rawSide;

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
                    final horizontal = _expandHorizontal(_bort.anchor, size);
                    pos = _expandedPosition(
                        _bort.anchor, size, horizontal, pultSide);
                  } else {
                    pos = _dragOffset ??
                        _anchorPosition(_bort.anchor, size, pultSide);
                  }

                  return Stack(
                    children: [
                      IndexedStack(
                        index: _tab,
                        children: [
                          _wrapTab(_buildStub(fg, brightness)),
                          _wrapTab(_buildStub(fg, brightness)),
                          _wrapTab(_buildStub(fg, brightness)),
                          _wrapTab(_buildRubkaTab(fg, brightness)),
                          _wrapTab(_buildJournalTab(fg, brightness)),
                        ],
                      ),
                      Positioned(
                        left: pos.dx,
                        top: pos.dy,
                        child: _buildMultiPult(fg, bg, size, pultSide),
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

  bool _expandHorizontal(String anchor, Size size) {
    if (anchor == 'tc' || anchor == 'bc') return true;
    if (anchor == 'lc' || anchor == 'rc') return false;
    return size.width < size.height;
  }

  Widget _buildMultiPult(Color fg, Color bg, Size size, double s) {
    if (!_menuOpen) {
      final current = _tabs[_tab];
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) {},
        onPanUpdate: (d) {
          setState(() {
            final base = _dragOffset ?? _anchorPosition(_bort.anchor, size, s);
            _dragOffset = base + d.delta;
          });
        },
        onPanEnd: (d) {
          final pos = _dragOffset ?? Offset.zero;
          final nearest = _nearestAnchor(pos, size, s);
          setState(() => _dragOffset = null);
          _bort.setSilent('anchor', nearest);
        },
        onTapUp: (_) => setState(() => _menuOpen = true),
        child: _pult(current.icon, false, fg, bg, s),
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
              setState(() => _menuOpen = false);
            },
            child: _pult(t.icon, active, fg, bg, s, label: label),
          ),
        ),
      );
    }

    final availW = size.width - _labelGap;
    final availH = size.height - _labelGap;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: availW, maxHeight: availH),
      child: _layoutPults(items, Size(availW, availH), s + 8),
    );
  }

  Widget _buildJournalTab(Color fg, Brightness brightness) {
    final bg = _bort.currentBg(brightness);
    final systemScale = MediaQuery.textScalerOf(context).scale(1.0);
    final rawSide = _basePultSide * systemScale * _bort.scale;
    final pultSide = rawSide > _pultMaxSide ? _pultMaxSide : rawSide;

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
                        onTap: () => setState(() {
                          _typeMenuOpen = !_typeMenuOpen;
                          _flagsMenuOpen = false;
                        }),
                        child: _pult(
                          _typeIcons[
                              JournalType.all.indexOf(_bort.selectedType)],
                          _typeMenuOpen,
                          fg,
                          bg,
                          pultSide,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(() {
                          _flagsMenuOpen = !_flagsMenuOpen;
                          _typeMenuOpen = false;
                        }),
                        child: _pultNumber(
                          '${_bort.selectedFlags}',
                          _flagsMenuOpen,
                          fg,
                          bg,
                          pultSide,
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
                  _buildTypePanelItems(fg, bg, pultSide),
                  Size(availForPanelW, availForPanelH),
                  pultSide + 8,
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
                  _buildFlagsPanelItems(fg, bg, pultSide),
                  Size(availForPanelW, availForPanelH),
                  pultSide + 8,
                ),
              ),
            ),
        ],
      );
    });
  }

  List<Widget> _buildTypePanelItems(Color fg, Color bg, double pultSide) {
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
            child: _pult(_typeIcons[i], active, fg, bg, pultSide,
                label: _bort.labelsSystem ? _i18n!.t(typeKeys[i]) : null),
          ),
        ),
      );
    }
    return items;
  }

  List<Widget> _buildFlagsPanelItems(Color fg, Color bg, double pultSide) {
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
            child: _pult(_flagIcons[i], active, fg, bg, pultSide,
                label: _bort.labelsSystem ? _i18n!.t(flagKeys[i]) : null),
          ),
        ),
      );
    }
    return items;
  }

  // ─── Вкладка «рубка» ───
  Widget _buildRubkaTab(Color fg, Brightness brightness) {
    final dim = _bort.currentDim(brightness);
    final bg = _bort.currentBg(brightness);

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
            // Пульт выбора темы: три варианта.
            _themeRow(fg, dim, brightness, bg),
            _settingRow('bg_day', fg, dim, brightness),
            _settingRow('bg_night', fg, dim, brightness),
            _settingRow('fg_day', fg, dim, brightness),
            _settingRow('fg_night', fg, dim, brightness),
            _settingRow('dim_day', fg, dim, brightness),
            _settingRow('dim_night', fg, dim, brightness),
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
            _settingRow('scale', fg, dim, brightness),
            _settingRow('lang', fg, dim, brightness),
            _settingRow('labels_system', fg, dim, brightness),
            _settingRow('labels_field', fg, dim, brightness),
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
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 140,
                  child: Text(_i18n!.t('bort.cleanup'),
                      style: TextStyle(color: fg)),
                ),
                GestureDetector(
                  onTap: () => setState(() => _cleanupOpen = !_cleanupOpen),
                  child: _pult(Icons.delete_outline, _cleanupOpen, fg, bg, 32),
                ),
              ],
            ),
            if (_cleanupOpen) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(width: 140),
                  GestureDetector(
                    onTap: () => setState(() => _cleanupTarget = 'journal'),
                    child: _pult(
                        Icons.list, _cleanupTarget == 'journal', fg, bg, 32),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _cleanupTarget = 'bort'),
                    child:
                        _pult(Icons.tune, _cleanupTarget == 'bort', fg, bg, 32),
                  ),
                ],
              ),
              if (_cleanupTarget != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const SizedBox(width: 140),
                    GestureDetector(
                      onTap: _doCleanup,
                      child: _pult(Icons.delete_forever, true, fg, bg, 44),
                    ),
                  ],
                ),
              ],
            ],
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

  // ─── Строка выбора темы ───
  Widget _themeRow(Color fg, Color dim, Brightness brightness, Color bg) {
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
                    32,
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

  Widget _settingRow(String key, Color fg, Color dim, Brightness brightness) {
    final type = OperationalLayer.settingTypes[key] ?? 'string';
    final value = _bort.allAsStrings[key] ?? '';
    final bg = _bort.currentBg(brightness);

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
            child:
                _buildSettingField(key, type, value, fg, dim, brightness, bg),
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
  ) {
    switch (type) {
      case 'bool':
        final b = value == 'true';
        return Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: () => _bort.setBool(key, !b),
            child:
                _pult(b ? Icons.check : Icons.circle_outlined, b, fg, bg, 32),
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

// ═══════════════════════════════════════════════════════════════════
// _BortField — поле значения одного параметра борта.
// Поддерживает черновик: текст, ещё не поданный.
// ═══════════════════════════════════════════════════════════════════
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
