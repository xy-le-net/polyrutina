// ═══════════════════════════════════════════════════════════════════
// pult_layer.dart — слой поверх всего приложения.
//
// Подпульты. По нажатию пульта с subsBuilder открывается всплывающая
// панель у левого либо правого края экрана — смотря где исходный
// пульт. Внутри — вертикальная колонка пультов, прокручивается.
// Тап по затемнённой подложке — закрыть.
//
// Подтверждение (confirm). Увеличенный пульт показывается над
// родителем — отдельным слоем.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import 'pult_core.dart';

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
        if (state.subsBuilder != null) _buildSubs(context, state),
        if (state.confirmingId != null) _buildConfirm(context, state),
      ],
    );
  }

  // ─── Всплывающая панель подпультов ───
  Widget _buildSubs(BuildContext context, PultState state) {
    final subs = state.subsBuilder!.call();
    if (subs.isEmpty) return const SizedBox.shrink();

    final local = _parentLocal(state.parentKey);
    final size = _parentSize(state.parentKey);
    if (local == null || size == null) return const SizedBox.shrink();

    final screenW = MediaQuery.of(context).size.width;
    final side = state.smallSide;

    // Сторона панели: пульт в правой половине — панель справа,
    // иначе слева. Подписи встают с внутренней стороны (к центру).
    final parentCenter = local.dx + size.width / 2;
    final fromRight = parentCenter > screenW / 2;

    final panelWidth = side + 24;

    final items = <Widget>[];
    for (final s in subs) {
      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: Pult(
            spec: s,
            fg: widget.fg,
            bg: widget.bg,
            signal: widget.signal,
            insideLayer: true,
            overrideSize: side,
            // Подпись с внутренней стороны панели.
            labelSideLeft: fromRight,
          ),
        ),
      );
    }

    return Stack(
      children: [
        // Подложка: тап мимо — закрыть.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => state.close(),
            child: Container(color: widget.bg.withAlpha(200)),
          ),
        ),
        // Панель.
        Positioned(
          top: 0,
          bottom: 0,
          left: fromRight ? null : 0,
          right: fromRight ? 0 : null,
          width: panelWidth,
          child: Container(
            color: widget.bg,
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: fromRight
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: items,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Подтверждение: увеличенный пульт над родителем ───
  Widget _buildConfirm(BuildContext context, PultState state) {
    final local = _parentLocal(state.confirmingKey);
    final size = _parentSize(state.confirmingKey);
    if (local == null || size == null) return const SizedBox.shrink();

    final side = state.side * 1.3;
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;

    double left = local.dx + (size.width - side) / 2;
    if (left < 8) left = 8;
    if (left + side > screenW - 8) left = screenW - 8 - side;

    double top = local.dy - side - 8;
    if (top < 8) top = local.dy + size.height + 8;
    if (top + side > screenH - 8) top = screenH - 8 - side;

    final icon = state.confirmingIcon ?? Icons.delete_forever;

    return Stack(
      children: [
        // Подложка: тап мимо — отмена.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => state.close(),
            child: Container(color: widget.bg.withAlpha(160)),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => state.runConfirm(state.confirmingId!),
            child: _confirmBody(icon, side),
          ),
        ),
      ],
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
