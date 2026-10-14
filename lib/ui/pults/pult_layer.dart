// ═══════════════════════════════════════════════════════════════════
// pult_layer.dart — слой поверх всего приложения.
//
// Подпульты. По нажатию пульта с subsBuilder открывается панель
// подпультов (PultSubsPanel): вертикальная колонка у левого либо
// правого края, смотря где исходный пульт.
//
// Подтверждение (confirm). Внутри панели подтверждаемый пульт
// вырастает на месте — отдельного слоя нет. Вне панели (пульт сам
// просит подтверждения) — тот же рост, слой не нужен.
//
// Кнопка «назад». PopScope перехватывает: коли панель открыта либо
// идёт подтверждение — закрыть, не покидая экран.
//
// Тап по затемнённой подложке — закрыть.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import 'pult_core.dart';
import 'pult_subs_panel.dart';

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
    final open = state.subsBuilder != null || state.confirmingId != null;

    return PopScope(
      canPop: !open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) state.close();
      },
      child: Stack(
        key: _layerKey,
        children: [
          widget.child,
          if (state.subsBuilder != null) _buildSubs(context, state),
        ],
      ),
    );
  }

  // ─── Панель подпультов ───
  Widget _buildSubs(BuildContext context, PultState state) {
    final subs = state.subsBuilder!.call();
    if (subs.isEmpty) return const SizedBox.shrink();

    final local = _parentLocal(state.parentKey);
    final size = _parentSize(state.parentKey);
    if (local == null || size == null) return const SizedBox.shrink();

    final screenW = MediaQuery.of(context).size.width;
    final side = state.smallSide;

    // Сторона панели: пульт в правой половине — панель справа,
    // иначе слева. Подписи встают к центру.
    final parentCenter = local.dx + size.width / 2;
    final fromRight = parentCenter > screenW / 2;

    final panelWidth = side + 160;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => state.close(),
            child: Container(color: widget.bg.withAlpha(200)),
          ),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          left: fromRight ? null : 0,
          right: fromRight ? 0 : null,
          width: panelWidth,
          child: Container(
            color: widget.bg,
            child: SafeArea(
              child: PultSubsPanel(
                subs: subs,
                fg: widget.fg,
                bg: widget.bg,
                signal: widget.signal,
                side: side,
                labelSideLeft: fromRight,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
