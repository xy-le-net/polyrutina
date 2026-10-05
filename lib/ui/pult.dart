// ═══════════════════════════════════════════════════════════════════
// pult.dart — единый пульт, контекст и слой.
//
// Назначение: единая кнопка во всём приложении. Пульт рисуется
// как тройная вложенная обводка с ядром посередине — так он
// узнаваем в любом месте, поверх любого фона.
//
// Три сущности в файле:
//   PultSpec  — описание пульта: икона, подпись, что делать по касанию;
//   PultState — общее состояние всех пультов: кто открыт, кто ждёт
//               подтверждения, каковы размеры;
//   Pult      — собственно виджет;
//   PultLayer — слой поверх всего приложения, где рисуются подпульты
//               и подтверждения. Он охватывает все маршруты, потому
//               подпульты видны поверх любой вкладки.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

// ─── Спецификация пульта ───
// Поля:
//   id          — имя (для сравнения в подтверждениях);
//   icon        — икона ядра;
//   label       — текстовая подпись справа (необязательно);
//   labelWidget — своя подпись справа, перебивает label;
//   selected    — выделен ли (ядро — сигнального цвета);
//   subsBuilder — построитель подпультов; ежели задан, касание
//                 открывает веер подпультов, а не зовёт onTap;
//   confirm     — ежели истина, касание сперва просит подтверждения
//                 увеличенным пультом поверх;
//   onTap       — действие по касанию;
//   stayOpen    — не закрывать веер подпультов после касания
//                 (нужно для множественного выбора: флаги журнала).
class PultSpec {
  final String id;
  final IconData icon;
  final String? label;
  final Widget? labelWidget;
  final bool selected;
  final List<PultSpec> Function()? subsBuilder;
  final bool confirm;
  final VoidCallback? onTap;
  final bool stayOpen;

  const PultSpec({
    required this.id,
    required this.icon,
    this.label,
    this.labelWidget,
    this.selected = false,
    this.subsBuilder,
    this.confirm = false,
    this.onTap,
    this.stayOpen = false,
  });
}

// ─── Общее состояние пультов ───
// Один PultState на всё приложение. Хранит, какой пульт ныне открыл
// веер подпультов (parentKey), какой ждёт подтверждения (confirmingId),
// и каковы базовые размеры.
//
// Размеры: baseSide задаётся сверху (из main.dart, чрез ползунок
// scale и системный масштаб); side — то, что применяется, ограниченное
// сверху maxSide. Сие позволяет ползунку не разгонять интерфейс
// до абсурда.
class PultState extends ChangeNotifier {
  GlobalKey? parentKey;
  List<PultSpec> Function()? subsBuilder;

  String? confirmingId;
  GlobalKey? confirmingKey;
  VoidCallback? confirmingAction;
  IconData? confirmingIcon;

  double baseSide = 32;
  double maxSide = 64;

  double get side => baseSide > maxSide ? maxSide : baseSide;
  double get smallSide => side * 2 / 3;

  // Открыть веер подпультов над указанным пультом.
  // При сем снимается всякое незавершённое подтверждение: два
  // состояния разом несовместимы.
  void open(GlobalKey key, List<PultSpec> Function() builder) {
    parentKey = key;
    subsBuilder = builder;
    confirmingId = null;
    confirmingKey = null;
    confirmingAction = null;
    confirmingIcon = null;
    notifyListeners();
  }

  // Закрыть всё: и веер, и подтверждение.
  void close() {
    parentKey = null;
    subsBuilder = null;
    confirmingId = null;
    confirmingKey = null;
    confirmingAction = null;
    confirmingIcon = null;
    notifyListeners();
  }

  // Запросить подтверждение для действия. Веер подпультов при сем
  // закрывается — подтверждение показывается одно.
  void askConfirm(
      String id, GlobalKey key, VoidCallback action, IconData icon) {
    confirmingId = id;
    confirmingKey = key;
    confirmingAction = action;
    confirmingIcon = icon;
    parentKey = null;
    subsBuilder = null;
    notifyListeners();
  }

  bool isConfirming(String id) => confirmingId == id;

  // Исполнить подтверждённое. Проверка id нужна на случай, ежели
  // пользователь успел переключиться на другое подтверждение.
  void runConfirm(String id) {
    if (confirmingId != id) return;
    final a = confirmingAction;
    close();
    a?.call();
  }
}

// ─── Провайдер ───
// Наследственный уведомитель: всякий, кто зовёт PultScope.of(context),
// подписывается на изменения PultState и получает перерисовку.
class PultScope extends InheritedNotifier<PultState> {
  const PultScope({
    super.key,
    required PultState state,
    required super.child,
  }) : super(notifier: state);

  static PultState of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<PultScope>();
    assert(s != null, 'PultScope не найден');
    return s!.notifier!;
  }
}

// ═══════════════════════════════════════════════════════════════════
// Pult — единая кнопка.
//
// Приём построения: три вложенных контейнера, каждый со своею
// обводкою и скруглением. От большего к меньшему:
//   внешний — обводка цвета ядра (всегда видна);
//   средний — обводка цвета фона, ежели пульт выделен (даёт
//             видимость двойного кольца при выделении);
//   внутренний — заливка ядра (сигнальная, ежели выделен;
//                основная иначе).
// Икона — цвета фона, дабы читаться на ядре.
//
// Размеры ядра, обводок и скруглений — доли от side. Величины
// подобраны так, чтобы пульт выглядел одинаково при любом масштабе.
// ═══════════════════════════════════════════════════════════════════
class Pult extends StatefulWidget {
  final PultSpec spec;
  // overrideSize — задать свой размер вместо взятого из PultState.
  // Нужно, скажем, для уменьшенных пультов в списке рутин.
  final double? overrideSize;
  // insideLayer — истина, ежели пульт нарисован внутри веера
  // подпультов. Сие меняет обработку касания: подпульт зовёт
  // своё действие и (ежели не stayOpen) закрывает веер.
  final bool insideLayer;
  final Color fg;
  final Color bg;
  final Color signal;

  const Pult({
    super.key,
    required this.spec,
    required this.fg,
    required this.bg,
    required this.signal,
    this.overrideSize,
    this.insideLayer = false,
  });

  @override
  State<Pult> createState() => _PultState();
}

class _PultState extends State<Pult> {
  // Ключ ядра: по нему PultLayer отыскивает, над каким местом
  // рисовать веер подпультов либо подтверждение.
  final _coreKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final state = PultScope.of(context);
    final side = widget.overrideSize ??
        (widget.insideLayer ? state.smallSide : state.side);
    final selected = widget.spec.selected;

    // Цвета: ядро — сигнальное при выделении, основное иначе.
    // Икона — цвет фона: читается на любом ядре.
    final coreColor = selected ? widget.signal : widget.fg;
    final iconColor = widget.bg;

    // Доли от side. Сии величины подобраны под общий вид пульта:
    //   borderW — толщина каждой из двух обводок;
    //   rOuter  — скругление внешней обводки;
    //   rInner  — скругление средней;
    //   rCore   — скругление ядра и иконы внутри.
    final borderW = side / 16;
    final rOuter = side * 0.18;
    final rInner = side * 0.14;
    final rCore = side * 0.10;

    // Ядро: заливка плюс икона посередине.
    Widget core = Container(
      key: _coreKey,
      width: side,
      height: side,
      decoration: BoxDecoration(
        color: coreColor,
        borderRadius: BorderRadius.circular(rCore),
      ),
      child: Center(
        child: Icon(widget.spec.icon, color: iconColor, size: side * 0.45),
      ),
    );

    // Средняя обводка: при выделении — цвета фона (даёт видимость
    // двойного кольца), иначе — цвета ядра (сливается с внешней,
    // и пульт кажется одноконтурным).
    core = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(rInner),
        border:
            Border.all(color: selected ? iconColor : coreColor, width: borderW),
      ),
      child: core,
    );

    // Внешняя обводка — всегда цвета ядра.
    core = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(rOuter),
        border: Border.all(color: coreColor, width: borderW),
      ),
      child: core,
    );

    // ─── Подпись справа ───
    // Ежели подписи нет либо ей не хватает места — показываем
    // токмо ядро. Иначе — ряд из ядра и подписи.
    //
    // Ширина подписи оценивается по длине текста: на одну букву
    // примерно 0.4 от side. Сие грубо, но для подписей в несколько
    // слов довольно. Виджет-подпись (коли задан) оценивается как
    // шесть знаков — компромисс.
    //
    // Максимальная ширина ограничена шириною экрана: подпись
    // не должна вылезать за край.
    Widget content;
    final screenW = MediaQuery.of(context).size.width;
    final maxLabelW = screenW - side - 32;
    final hasLabel =
        widget.spec.label != null || widget.spec.labelWidget != null;

    if (!hasLabel || maxLabelW < side * 1.5) {
      content = core;
    } else {
      final estimate = widget.spec.label?.length ??
          (widget.spec.labelWidget is Text
              ? ((widget.spec.labelWidget as Text).data?.length ?? 0)
              : 6);
      final desired = estimate * side * 0.4 + 16;
      final labelWidth = desired.clamp(side * 1.5, maxLabelW);

      // Подпись: прямоугольник заливки ядра, со сглаженными углами
      // токмо с правой стороны (слева она стыкуется с ядром).
      // Текст — цвета ядра.
      // ─── Подпись ───
      // Кегль задаётся явно от размера пульта (side * 0.4). Иначе
      // текст наследует размер из темы и умножается на textScaler
      // (в main.dart он равен _bort.scale), давая двойное увеличение:
      // подпись не помещается в отведённую полосу и обрезается.
      //
      // Обёртка MediaQuery с noScaling снимает внешний textScaler
      // для содержимого подписи. Сие правильно по той же причине:
      // side уже включает масштаб, повторное умножение излишне.
      // Обёртка общая — и для строковой подписи, и для своего виджета
      // (например, таймера на пульте актора).
      final labelWidget = Container(
        height: side * 0.75,
        width: labelWidth,
        decoration: BoxDecoration(
          color: coreColor,
          borderRadius: const BorderRadius.horizontal(
            right: Radius.circular(6),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.noScaling,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: widget.spec.labelWidget ??
                Text(
                  widget.spec.label!,
                  style: TextStyle(
                    color: iconColor,
                    fontSize: side * 0.4,
                  ),
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
          ),
        ),
      );
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [core, labelWidget],
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _handleTap(state),
      child: content,
    );
  }

  // ─── Обработка касания ───
  // Три пути:
  //   внутри слоя подпультов — зовём действие и, ежели не stayOpen,
  //     закрываем веер;
  //   с подтверждением — просим подтверждения (повторное касание
  //     того же пульта игнорируется, покуда ждём);
  //   с подпультами — открываем веер;
  //   простое — зовём действие.
  void _handleTap(PultState state) {
    if (widget.insideLayer) {
      widget.spec.onTap?.call();
      if (!widget.spec.stayOpen) state.close();
      return;
    }

    if (widget.spec.confirm) {
      if (state.isConfirming(widget.spec.id)) return;
      if (widget.spec.onTap != null) {
        state.askConfirm(
            widget.spec.id, _coreKey, widget.spec.onTap!, widget.spec.icon);
      }
      return;
    }

    if (widget.spec.subsBuilder != null) {
      state.open(_coreKey, widget.spec.subsBuilder!);
      return;
    }

    widget.spec.onTap?.call();
  }
}

// ═══════════════════════════════════════════════════════════════════
// PultLayer — слой поверх всего приложения.
//
// Он охватывает все маршруты (передан в MaterialApp.builder), потому
// подпульты видны поверх любой вкладки и поверх любого модального
// окна. Устроен как Stack: сперва дитя (весь интерфейс), затем
// полупрозрачный перехватчик касаний (закрыть веер по касанию мимо),
// затем сам веер подпультов и подтверждение.
//
// Позиционирование веера и подтверждения — относительно ключа ядра
// родительского пульта. Сие позволяет рисовать их точно над тем
// местом, где пульт.
// ═══════════════════════════════════════════════════════════════════
class PultLayer extends StatefulWidget {
  final Widget child;
  final Color fg;
  final Color bg;
  final Color signal;

  const PultLayer({
    super.key,
    required this.child,
    required this.fg,
    required this.bg,
    required this.signal,
  });

  @override
  State<PultLayer> createState() => _PultLayerState();
}

class _PultLayerState extends State<PultLayer> {
  final _layerKey = GlobalKey();

  // Начало координат слоя в глобальных координатах экрана.
  Offset _layerOffset() {
    final ctx = _layerKey.currentContext;
    if (ctx == null) return Offset.zero;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return Offset.zero;
    return box.localToGlobal(Offset.zero);
  }

  // Локальное положение родительского пульта внутри слоя.
  Offset? _parentLocal(GlobalKey? key) {
    final ctx = key?.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return box.localToGlobal(Offset.zero) - _layerOffset();
  }

  // Размер родительского пульта: нужен, дабы выровнять веер
  // либо подтверждение по его центру.
  Size? _parentSize(GlobalKey? key) {
    final ctx = key?.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return box.size;
  }

  @override
  Widget build(BuildContext context) {
    final state = PultScope.of(context);

    return Stack(
      key: _layerKey,
      children: [
        // Дите: весь интерфейс.
        widget.child,

        // Перехватчик касаний. Виден токмо, когда что-то открыто.
        // Касание мимо закрывает веер либо отменяет подтверждение.
        if (state.subsBuilder != null || state.confirmingId != null)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => state.close(),
            ),
          ),

        if (state.subsBuilder != null) _buildSubs(context, state),
        if (state.confirmingId != null) _buildConfirm(context, state),
      ],
    );
  }

  // ─── Построение веера подпультов ───
  // Раскладка: подпульты становятся над родительским пультом,
  // столбцами по столько, сколько помещается по высоте. Ежели
  // не помещаются в один столбец — раскладываются в несколько
  // столбцов слева направо.
  //
  // Подписи показываются, коли у всех есть текст и суммарная ширина
  // ряда не превышает ширину экрана с запасом.
  //
  // Позиция веера ограничена сверху и снизу, дабы не ушёл за экран.
  Widget _buildSubs(BuildContext context, PultState state) {
    final local = _parentLocal(state.parentKey);
    final size = _parentSize(state.parentKey);
    if (local == null || size == null) return const SizedBox.shrink();

    final subs = state.subsBuilder!.call();
    if (subs.isEmpty) return const SizedBox.shrink();

    final side = state.smallSide;
    final itemH = side + 12;
    final screenW = MediaQuery.of(context).size.width;

    // Сколько подпультов поместится по высоте над родительским.
    final availAbove = local.dy - 8;
    final rowsPerCol = (availAbove / itemH).floor().clamp(1, subs.length);
    final cols = (subs.length / rowsPerCol).ceil();

    // Оценка ширины подписей: нужно решить, показывать ли их.
    bool anyLabel = false;
    double maxLabelW = 0;
    for (final s in subs) {
      if (s.label != null) {
        anyLabel = true;
        final w = s.label!.length * side * 0.4 + 16;
        if (w > maxLabelW) maxLabelW = w;
      }
    }
    final colW = side + (anyLabel ? maxLabelW : 0) + 16;
    // Подписи показываются всегда, когда заданы. Прежняя проверка
    // «totalW < screenW - 16» прятала их при узком экране или
    // при длинных именах (флаги журнала: «синхронизировано»).
    // Коли ряд окажется шире экрана, положение всё равно
    // ограничится по краям ниже — подписи не пропадут,
    // а самый крайний столбец чуть сдвинется.
    final showLabels = anyLabel;

    // Раскладываем подпульты по столбцам. Коли подписи не помещаются,
    // подменяем спецификацию на безымянную — так подпульты теснее.
    final colWidgets = <Widget>[];
    for (var c = 0; c < cols; c++) {
      final colItems = <Widget>[];
      for (var r = 0; r < rowsPerCol; r++) {
        final i = c * rowsPerCol + r;
        if (i >= subs.length) break;
        final s = subs[i];
        final spec = showLabels
            ? s
            : PultSpec(
                id: s.id,
                icon: s.icon,
                selected: s.selected,
                confirm: s.confirm,
                onTap: s.onTap,
                stayOpen: s.stayOpen,
              );
        colItems.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Pult(
              spec: spec,
              fg: widget.fg,
              bg: widget.bg,
              signal: widget.signal,
              insideLayer: true,
              overrideSize: side,
            ),
          ),
        );
      }
      colWidgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: colItems,
          ),
        ),
      );
    }

    // Горизонтальное положение: по центру родительского пульта,
    // с ограничением по краям экрана.
    final rowW = cols * colW;
    double left = local.dx + (size.width - rowW) / 2;
    if (left < 8) left = 8;
    if (left + rowW > screenW - 8) left = screenW - 8 - rowW;

    // Вертикальное положение: над родительским пультом,
    // с ограничением сверху.
    final totalH = rowsPerCol * itemH;
    double top = local.dy - totalH - 6;
    if (top < 8) top = 8;

    return Positioned(
      left: left,
      top: top,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: colWidgets,
      ),
    );
  }

  // ─── Построение подтверждения ───
  // Увеличенный пульт (в 1.3 раза против обычного) с иконою
  // подтверждаемого действия. Касание по нему исполняет действие.
  // Показывается над родительским пультом, а ежели там тесно —
  // под ним.
  Widget _buildConfirm(BuildContext context, PultState state) {
    final local = _parentLocal(state.confirmingKey);
    final size = _parentSize(state.confirmingKey);
    if (local == null || size == null) return const SizedBox.shrink();

    final side = state.side * 1.3;
    final screenW = MediaQuery.of(context).size.width;

    double left = local.dx + (size.width - side) / 2;
    if (left < 8) left = 8;
    if (left + side > screenW - 8) left = screenW - 8 - side;

    double top = local.dy - side - 8;
    if (top < 8) top = local.dy + size.height + 8;

    final icon = state.confirmingIcon ?? Icons.delete_forever;

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => state.runConfirm(state.confirmingId!),
        child: _confirmBody(icon, side),
      ),
    );
  }

  // Вид подтверждения: та же тройная обводка, но с сигнальным
  // ядром. Сим подтверждение тотчас отличимо от обычного пульта.
  Widget _confirmBody(IconData icon, double side) {
    final coreColor = widget.signal;
    final iconColor = widget.bg;
    final borderW = side / 16;
    final rOuter = side * 0.18;
    final rInner = side * 0.14;
    final rCore = side * 0.10;

    Widget core = Container(
      width: side,
      height: side,
      decoration: BoxDecoration(
        color: coreColor,
        borderRadius: BorderRadius.circular(rCore),
      ),
      child: Center(
        child: Icon(icon, color: iconColor, size: side * 0.5),
      ),
    );

    core = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(rInner),
        border: Border.all(color: iconColor, width: borderW),
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
}
