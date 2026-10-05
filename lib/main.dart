// ═══════════════════════════════════════════════════════════════════
// main.dart — точка входа и управитель.
//
// Назначение: собрать всё воедино — слои (журнал, борт, слой рутин,
// словарь), общий пульт состояния PultState, пять вкладок, корневой
// пульт, перетаскиваемый по восьми якорям.
//
// Ключевое решение: корневой пульт лежит в MaterialApp.builder,
// а не в home. Сие означает, что пульт виден поверх любого маршрута —
// в том числе поверх открытой карточки рутины. Порядок вложенности:
//   PultLayer  — слой подпультов и подтверждений (поверх всего);
//     LayoutBuilder — знает размер экрана;
//       Stack
//         child (весь интерфейс, включая текущий маршрут) — снизу;
//         корневой пульт — сверху.
// Сим веер подпультов PultLayer окажется поверх корневого пульта,
// что и требуется.
//
// Пять вкладок: поле, рутины, актор, рубка, журнал.
// Активная вкладка и её номер берутся из борта.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'ui/routines_tab.dart';
import 'data/database.dart';
import 'data/journal_repository.dart';
import 'data/operational_layer.dart';
import 'data/routine_layer.dart';
import 'data/i18n.dart';
import 'ui/app_scope.dart';
import 'ui/pult.dart';
import 'ui/stub_tab.dart';
import 'ui/actor_tab.dart';
import 'ui/rubka_tab.dart';
import 'ui/journal_tab.dart';

void main() => runApp(const PolyRutinaApp());

// Описание вкладки: икона и ключ словаря для подписи.
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
  // ─── Слои ───
  late final AppDb _db;
  late final JournalRepository _journal;
  late final OperationalLayer _bort;
  late final RoutineLayer _routineLayer;
  final _pultState = PultState();

  // Словарь; загружается асинхронно в _init. Покуда null —
  // приложение показывает пустой экран, ибо без словаря
  // строить подписи нечем.
  I18n? _i18n;

  int _tab = 4;
  // Смещение корневого пульта при перетаскивании; null — пульт
  // стоит по якорю. По окончании перетаскивания сбрасывается,
  // а якорь берётся ближайший.
  Offset? _dragOffset;
  // Открыт ли веер вкладок. Свёрнутый корневой пульт — одна икона;
  // развёрнутый — столбец икон всех пяти вкладок.
  bool _rootOpen = false;

  // Пять вкладок приложения.
  static const List<_TabItem> _tabs = [
    _TabItem(icon: Icons.map, labelKey: 'tab.field'),
    _TabItem(icon: Icons.checklist, labelKey: 'tab.routines'),
    _TabItem(icon: Icons.person, labelKey: 'tab.actor'),
    _TabItem(icon: Icons.dashboard, labelKey: 'tab.rubka'),
    _TabItem(icon: Icons.list, labelKey: 'tab.journal'),
  ];

  // Базовый размер пульта до умножения на масштаб. Верхний предел
  // нужен, дабы ползунок scale не разгонял интерфейс до абсурда.
  static const double _pultBase = 32.0;
  static const double _pultMax = 64.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _db = AppDb();
    _journal = JournalRepository(_db);
    _bort = OperationalLayer();
    _routineLayer = RoutineLayer();
    _bort.addListener(_onBortChanged);
    _routineLayer.addListener(_onRoutineChanged);
    _init();
  }

  // Смена вкладки идёт за бортом: номер вкладки хранится в борте
  // и восстанавливается при перезапуске.
  void _onBortChanged() {
    if (mounted) setState(() => _tab = _bort.tab);
  }

  // Слой рутин уведомляет при всякой мутации (создание, удаление,
  // переименование, пуск/пауза блока). Перерисовка нужна, ибо
  // карточки и списки берут данные отсюда.
  void _onRoutineChanged() {
    if (mounted) setState(() {});
  }

  // ─── Пуск ───
  // Порядок важен: сперва борт (он нужен слою рутин? нет, они
  // независимы), затем слой рутин, затем словарь по текущему языку.
  // После загрузки словаря зовём setState — иначе приложение так
  // и осталось бы с пустым экраном.
  Future<void> _init() async {
    await _bort.init(_journal);
    await _routineLayer.init(_journal);
    _i18n = await I18n.load(_bort.lang);
    if (mounted) {
      setState(() => _tab = _bort.tab);
    }
  }

  // Перезагрузка словаря: нужна при смене языка (из рубки).
  Future<void> _reloadI18n() async {
    final i18n = await I18n.load(_bort.lang);
    if (mounted) setState(() => _i18n = i18n);
  }

  // Общий перезапрос интерфейса. Оставлен на случай, ежели
  // кто-то из вкладок пожелает вызвать вручную.
  Future<void> _refreshAll() async {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bort.removeListener(_onBortChanged);
    _routineLayer.removeListener(_onRoutineChanged);
    _routineLayer.dispose();
    _db.close();
    _pultState.dispose();
    super.dispose();
  }

  // Сохранение при уходе приложения в фон либо при закрытии.
  // Три состояния охвачены нарочно: paused — на Android при
  // сворачивании, detached — при выгрузке, inactive — на iOS
  // при переходе в фон. Лишние срабатывания безвредны.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      _bort.saveNow();
      _routineLayer.saveNow();
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

  // ─── Восемь якорей ───
  // Корневой пульт прилипает к одному из восьми мест: четырём углам,
  // серединам сторон. Сие удобно на разных экранах и при разной
  // руке. m — отступ от края, дабы пульт не прилипал вплотную.
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

  // Ближайший якорь к текущему положению. Зовётся по окончании
  // перетаскивания: пульт прилипает к ближайшему.
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

  // Размер корневого пульта: базовый, умноженный на системный
  // масштаб и на ползунок scale из борта, ограниченный сверху.
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
      routineLayer: _routineLayer,
      journal: _journal,
      i18n: _i18n!,
      refresh: _refreshAll,
      reloadI18n: _reloadI18n,
    );

    // AppScope и PultScope — выше MaterialApp, дабы маршруты их видели.
    return AppScope(
      appContext: appContext,
      child: PultScope(
        state: _pultState,
        child: MediaQuery(
          // Внешний textScaler — множитель масштаба интерфейса.
          // Он применяется ко всем текстам приложения, кроме
          // подписей пультов: там side уже его учитывает, и повторное
          // умножение привело бы к обрезанию (см. pult.dart).
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(_bort.scale),
          ),
          child: MaterialApp(
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
                enabledBorder:
                    OutlineInputBorder(borderSide: BorderSide(color: fg)),
                focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: fg, width: 2)),
                hintStyle: TextStyle(color: _bort.currentDim(brightness)),
              ),
              iconTheme: IconThemeData(color: fg),
            ),
            // ─── Слой builder ───
            // Здесь и только здесь корневой пульт обретает своё
            // место: builder оборачивает навигатор, потому пульт
            // виден поверх любого маршрута. Порядок вложенности
            // изложен в комментарии к файлу.
            builder: (context, child) {
              return PultLayer(
                fg: fg,
                bg: bg,
                signal: signal,
                child: SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size =
                          Size(constraints.maxWidth, constraints.maxHeight);
                      // Позиция: либо за перетаскиванием, либо по якорю.
                      final pos = _dragOffset ??
                          _anchorPosition(_bort.anchor, size, side);
                      return Stack(
                        children: [
                          // Весь интерфейс — включая текущий маршрут.
                          // Ежели child null (например, при первичной
                          // сборке), ставим пустышку.
                          child ?? const SizedBox.shrink(),
                          // Корневой пульт — поверх маршрута, но под
                          // веером подпультов (PultLayer рисует веер
                          // после своего child, то есть поверх всего
                          // сего Stack).
                          Positioned(
                            left: pos.dx,
                            top: pos.dy,
                            child:
                                _buildRootPult(fg, bg, signal, size, side, pos),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              );
            },
            // home без пульта: всё содержимое вкладок.
            home: Scaffold(
              body: IndexedStack(
                index: _tab,
                children: const [
                  StubTab(), // поле
                  RoutinesTab(), // рутины
                  ActorTab(), // актор
                  RubkaTab(),
                  JournalTab(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Корневой пульт ───
  // Свёрнутый — икона текущей вкладки. Касание открывает веер всех
  // пяти вкладок. Перетаскивание — за любое место иконы: по окончании
  // пульт прилипает к ближайшему якорю.
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

    // Развёрнутый: столбец (либо несколько столбцов) икон всех
    // вкладок. Текущая выделена сигнальным.
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

    // Положение веера относительно пульта: в какую сторону есть
    // место, туда и раскрываем. Сим пульт у края не уводит веер
    // за пределы экрана.
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

  // ─── Ядро пульта ───
  // Тройная вложенная обводка: внешняя цвета ядра, средняя цвета
  // фона (при выделении) либо цвета ядра (иначе), ядро с иконой.
  // Пропорции — доли от s.
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

  // ─── Раскладка веера вкладок ───
  // Ежели все помещаются в столбец — столбец. Иначе — несколько
  // столбцов слева направо. alignEnd — прижать к правому краю
  // (когда веер раскрывается влево от пульта).
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
