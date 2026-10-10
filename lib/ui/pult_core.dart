// ═══════════════════════════════════════════════════════════════════
// pult_core.dart — ядро пультов: спецификация, состояние, провайдер,
// виджет Pult.
//
// Сущности:
//   PultSpec  — описание пульта;
//   PultState — состояние;
//   PultScope — провайдер состояния;
//   Pult      — суперкнопка (тройная вложенная обводка).
//
// Подпись пульта — с подложкою. labelBg задаёт её заливку; без
// заданья — заливка ядра. labelSideLeft — подпись слева.
//
// centerText — текст в ядре вместо иконы. Число выводится моноширинно
// и центруется по вертикали с поправкою на высоту строки.
//
// Касание снимает фокус с полей и уведомляет борт (pulseBort).
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import 'app_scope.dart';

// ─── Спецификация пульта ───
class PultSpec {
  final String id;
  final IconData icon;
  final String? label;
  final Color? labelBg;
  final String? centerText;
  final bool selected;
  final List<PultSpec> Function()? subsBuilder;
  final List<PultSpec> Function()? longSubs;
  final bool confirm;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool stayOpen;

  const PultSpec({
    required this.id,
    required this.icon,
    this.label,
    this.labelBg,
    this.centerText,
    this.selected = false,
    this.subsBuilder,
    this.longSubs,
    this.confirm = false,
    this.onTap,
    this.onLongPress,
    this.stayOpen = false,
  });
}

// ─── Состояние пультов ───
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
    String id,
    GlobalKey key,
    VoidCallback action,
    IconData icon,
  ) {
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
  const PultScope({super.key, required PultState state, required super.child})
    : super(notifier: state);

  static PultState of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<PultScope>();
    assert(s != null, 'PultScope не найден');
    return s!.notifier!;
  }
}

// ═══════════════════════════════════════════════════════════════════
// Pult — суперкнопка.
// ═══════════════════════════════════════════════════════════════════
class Pult extends StatefulWidget {
  final PultSpec spec;
  final double? overrideSize;
  final bool insideLayer;
  final bool labelSideLeft;
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
    this.labelSideLeft = false,
  });

  @override
  State<Pult> createState() => _PultState();
}

class _PultState extends State<Pult> {
  final _coreKey = GlobalKey();

  void _pulseBort() {
    try {
      AppScope.of(context).pulseBort();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final state = PultScope.of(context);
    final side =
        widget.overrideSize ??
        (widget.insideLayer ? state.smallSide : state.side);
    final selected = widget.spec.selected;

    final coreColor = selected ? widget.signal : widget.fg;
    final iconColor = widget.bg;

    final borderW = side / 16;
    final rOuter = side * 0.18;
    final rInner = side * 0.14;
    final rCore = side * 0.10;

    final iconSize = selected ? side * 0.60 : side * 0.45;
    final hasCenter = widget.spec.centerText != null;

    Widget core = Container(
      key: _coreKey,
      width: side,
      height: side,
      decoration: BoxDecoration(
        color: coreColor,
        borderRadius: BorderRadius.circular(rCore),
      ),
      child: Center(
        child: hasCenter
            ? Padding(
                // Небольшая поправка: моноширинная цифра в ядре
                // выравнивается по вертикали.
                padding: EdgeInsets.only(bottom: side * 0.04),
                child: Text(
                  widget.spec.centerText!,
                  style: TextStyle(
                    color: iconColor,
                    fontFamily: 'monospace',
                    fontSize: iconSize,
                    height: 1.0,
                    decoration: TextDecoration.none,
                  ),
                ),
              )
            : Icon(widget.spec.icon, color: iconColor, size: iconSize),
      ),
    );

    core = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(rInner),
        border: Border.all(
          color: selected ? iconColor : coreColor,
          width: borderW,
        ),
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

    Widget content;
    final screenW = MediaQuery.of(context).size.width;
    final maxLabelW = screenW - side - 32;
    final hasLabel = widget.spec.label != null;

    if (!hasLabel || maxLabelW < side * 1.5) {
      content = core;
    } else {
      final painter = TextPainter(
        text: TextSpan(
          text: widget.spec.label!,
          style: TextStyle(fontSize: side * 0.4),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final textW = painter.width * 1.2;
      final desired = textW + 12;
      final labelWidth = desired.clamp(side * 1.5, maxLabelW);

      final borderRadius = widget.labelSideLeft
          ? const BorderRadius.horizontal(left: Radius.circular(6))
          : const BorderRadius.horizontal(right: Radius.circular(6));

      final labelWidget = Container(
        height: side * 0.75,
        width: labelWidth,
        decoration: BoxDecoration(
          color: widget.spec.labelBg ?? coreColor,
          borderRadius: borderRadius,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.noScaling),
          child: Align(
            alignment: widget.labelSideLeft
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: Text(
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
        children: widget.labelSideLeft
            ? [labelWidget, core]
            : [core, labelWidget],
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
      onLongPress: () {
        FocusManager.instance.primaryFocus?.unfocus();
        _pulseBort();
        if (widget.spec.longSubs != null) {
          state.open(_coreKey, widget.spec.longSubs!);
          return;
        }
        widget.spec.onLongPress?.call();
      },
      child: content,
    );
  }

  void _handleTap(PultState state) {
    FocusManager.instance.primaryFocus?.unfocus();
    _pulseBort();

    if (widget.insideLayer) {
      widget.spec.onTap?.call();
      if (!widget.spec.stayOpen) state.close();
      return;
    }

    if (widget.spec.confirm) {
      if (state.isConfirming(widget.spec.id)) return;
      if (widget.spec.onTap != null) {
        state.askConfirm(
          widget.spec.id,
          _coreKey,
          widget.spec.onTap!,
          widget.spec.icon,
        );
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
