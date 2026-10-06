// ═══════════════════════════════════════════════════════════════════
// pult.dart — единый пульт, чекбокс, контекст и слой.
//
// Сущности:
//   PultSpec  — описание пульта;
//   PultState — состояние (кто открыт, кто ждёт подтверждения, размеры);
//   PultScope — провайдер состояния;
//   Pult      — суперкнопка (тройная обводка);
//   PultTick  — чекбокс на базе Pult;
//   PultLayer — слой поверх всего приложения (подпульты, подтверждения).
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
//                 открывает веер, а не зовёт onTap;
//   confirm     — касание сперва просит подтверждения;
//   onTap       — действие по короткому касанию;
//   onLongPress — действие по долгому нажатию (перебивает onTap);
//   stayOpen    — не закрывать веер подпультов после касания
//                 (для множественного выбора).
class PultSpec {
  final String id;
  final IconData icon;
  final String? label;
  final Widget? labelWidget;
  final bool selected;
  final List<PultSpec> Function()? subsBuilder;
  final bool confirm;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
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
    this.onLongPress,
    this.stayOpen = false,
  });
}

// ─── Общее состояние пультов ───
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

  void open(GlobalKey key, List<PultSpec> Function() builder) {
    parentKey = key;
    subsBuilder = builder;
    confirmingId = null;
    confirmingKey = null;
    confirmingAction = null;
    confirmingIcon = null;
    notifyListeners();
  }

  void close() {
    parentKey = null;
    subsBuilder = null;
    confirmingId = null;
    confirmingKey = null;
    confirmingAction = null;
    confirmingIcon = null;
    notifyListeners();
  }

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

  void runConfirm(String id) {
    if (confirmingId != id) return;
    final a = confirmingAction;
    close();
    a?.call();
  }
}

// ─── Провайдер ───
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
// Pult — суперкнопка. Тройная вложенная обводка.
// ═══════════════════════════════════════════════════════════════════
class Pult extends StatefulWidget {
  final PultSpec spec;
  final double? overrideSize;
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
  final _coreKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final state = PultScope.of(context);
    final side = widget.overrideSize ??
        (widget.insideLayer ? state.smallSide : state.side);
    final selected = widget.spec.selected;

    final coreColor = selected ? widget.signal : widget.fg;
    final iconColor = widget.bg;

    final borderW = side / 16;
    final rOuter = side * 0.18;
    final rInner = side * 0.14;
    final rCore = side * 0.10;

    // Сигнальный пульт: икона крупнее на треть.
    final iconSize = selected ? side * 0.60 : side * 0.45;

    Widget core = Container(
      key: _coreKey,
      width: side,
      height: side,
      decoration: BoxDecoration(
        color: coreColor,
        borderRadius: BorderRadius.circular(rCore),
      ),
      child: Center(
        child: Icon(widget.spec.icon, color: iconColor, size: iconSize),
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

    // Подпись справа.
    Widget content;
    final screenW = MediaQuery.of(context).size.width;
    final maxLabelW = screenW - side - 32;
    final hasLabel =
        widget.spec.label != null || widget.spec.labelWidget != null;

    if (!hasLabel || maxLabelW < side * 1.5) {
      content = core;
    } else {
      double textW;
      final labelText = widget.spec.label;
      if (labelText != null) {
        final painter = TextPainter(
          text: TextSpan(
            text: labelText,
            style: TextStyle(fontSize: side * 0.4),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        textW = painter.width;
      } else {
        textW = 6 * side * 0.4;
      }
      final desired = textW + 16;
      final labelWidth = desired.clamp(side * 1.5, maxLabelW);

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
                    decoration: TextDecoration.none,
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

    if (widget.insideLayer) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _handleTap(state),
        child: content,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _handleTap(state),
      onLongPress: widget.spec.onLongPress,
      child: content,
    );
  }

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
// PultTick — чекбокс на базе Pult.
//
// Два режима:
//   binary — кружок приглушённый (не отмечено) / галочка сигнальная
//            (отмечено). Для обычных чекбоксов.
//   небинарный — кружок приглушённый (отмечать нечего) / галочка
//                приглушённая (всё отмечено) / сигнальное число
//                (сколько осталось отметить). Для пульта чек-листа.
//
// Число в небинарном режиме заменяет икону: цифра на месте знака.
// ═══════════════════════════════════════════════════════════════════
class PultTick extends StatelessWidget {
  final String id;
  final bool value; // отмечено либо всё отмечено
  final bool binary; // true — бинарный; false — небинарный
  final int badge; // число неотмеченных (небинарный, > 0)
  final Color fg;
  final Color bg;
  final Color signal;
  final double? overrideSize;
  final VoidCallback? onTap;

  const PultTick({
    super.key,
    required this.id,
    required this.value,
    this.binary = true,
    this.badge = 0,
    required this.fg,
    required this.bg,
    required this.signal,
    this.overrideSize,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Икона по состоянию.
    final IconData icon;
    final bool selected;
    if (binary) {
      icon = value ? Icons.check : Icons.circle_outlined;
      selected = value;
    } else {
      if (badge > 0) {
        // Сигнальное число заменяет икону — рисуем Text внутри Pult
        // чрез labelWidget не выйдет (там справа подпись), потому
        // используем готовую икону и цвет: цифру покажем подписью.
        icon = Icons.circle_outlined;
        selected = true;
      } else if (value) {
        icon = Icons.check_box_outlined;
        selected = false;
      } else {
        icon = Icons.circle_outlined;
        selected = false;
      }
    }

    return Pult(
      spec: PultSpec(
        id: id,
        icon: icon,
        label: (!binary && badge > 0) ? '$badge' : null,
        selected: selected,
        onTap: onTap,
      ),
      fg: fg,
      bg: bg,
      signal: signal,
      overrideSize: overrideSize,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// PultLayer — слой поверх всего приложения.
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

  Offset _layerOffset() {
    final ctx = _layerKey.currentContext;
    if (ctx == null) return Offset.zero;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return Offset.zero;
    return box.localToGlobal(Offset.zero);
  }

  Offset? _parentLocal(GlobalKey? key) {
    final ctx = key?.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return box.localToGlobal(Offset.zero) - _layerOffset();
  }

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
        widget.child,
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

  Widget _buildSubs(BuildContext context, PultState state) {
    final local = _parentLocal(state.parentKey);
    final size = _parentSize(state.parentKey);
    if (local == null || size == null) return const SizedBox.shrink();

    final subs = state.subsBuilder!.call();
    if (subs.isEmpty) return const SizedBox.shrink();

    final side = state.smallSide;
    final itemH = side + 12;
    final screenW = MediaQuery.of(context).size.width;

    final availAbove = local.dy - 8;
    final rowsPerCol = (availAbove / itemH).floor().clamp(1, subs.length);
    final cols = (subs.length / rowsPerCol).ceil();

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
    final showLabels = anyLabel;

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

    final rowW = cols * colW;
    double left = local.dx + (size.width - rowW) / 2;
    if (left < 8) left = 8;
    if (left + rowW > screenW - 8) left = screenW - 8 - rowW;

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
