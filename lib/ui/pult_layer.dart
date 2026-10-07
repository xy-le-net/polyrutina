// ═══════════════════════════════════════════════════════════════════
// pult_layer.dart — слой поверх всего приложения.
//
// Рисует веер подпультов над родительским пультом и подтверждение
// увеличенным пультом.
//
// Веер. Иконы — ровным столбцом. Подписи выступают сбоку от иконы:
//   пульт в правой половине экрана — подписи слева;
//   в левой или по центру — подписи справа.
// Ряд целиком может сдвинуться, дабы уместиться с подписями,
// но столбец икон остаётся ровным.
//
// Ежели весь ряд с подписями не умещается по ширине — подписи
// не показываются вовсе, одни иконы.
//
// Перехватчик касаний: касание мимо закрывает веер либо отменяет
// подтверждение. Ставится, только коли что-то открыто.
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

  // ─── Веер подпультов ───
  Widget _buildSubs(BuildContext context, PultState state) {
    final local = _parentLocal(state.parentKey);
    final size = _parentSize(state.parentKey);
    if (local == null || size == null) return const SizedBox.shrink();

    final subs = state.subsBuilder!.call();
    if (subs.isEmpty) return const SizedBox.shrink();

    final side = state.smallSide;
    final itemH = side + 12;
    final screenW = MediaQuery.of(context).size.width;

    // Сколько строк в столбце поместится над родительским пультом.
    final availAbove = local.dy - 8;
    final rowsPerCol = (availAbove / itemH).floor().clamp(1, subs.length);
    final cols = (subs.length / rowsPerCol).ceil();

    // ─── Сторона подписей ───
    // Пульт в правой половине — подписи слева; иначе справа.
    final parentCenter = local.dx + size.width / 2;
    final labelsLeft = parentCenter > screenW / 2;

    // Проверка подписей: ежели хоть одна длинная и весь ряд
    // не умещается — отказываемся от подписей вовсе.
    double maxLabelW = 0;
    bool anyLabel = false;
    for (final s in subs) {
      if (s.label != null) {
        anyLabel = true;
        final w = s.label!.length * side * 0.4 + 16;
        if (w > maxLabelW) maxLabelW = w;
      }
    }
    final colWWithLabels = side + (anyLabel ? maxLabelW : 0) + 16;
    final totalWWithLabels = cols * colWWithLabels;
    final fitsWithLabels = anyLabel && (totalWWithLabels < screenW - 16);

    final colW = fitsWithLabels ? colWWithLabels : (side + 16);

    // ─── Построение столбцов ───
    // Иконы — ровным столбцом. Подписи выступают сбоку.
    final colWidgets = <Widget>[];
    for (var c = 0; c < cols; c++) {
      final colItems = <Widget>[];
      for (var r = 0; r < rowsPerCol; r++) {
        final i = c * rowsPerCol + r;
        if (i >= subs.length) break;
        final s = subs[i];
        final spec = fitsWithLabels
            ? s
            : PultSpec(
                id: s.id,
                icon: s.icon,
                centerText: s.centerText,
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
              // Подпись встаёт слева от иконы, ежели так решено.
              labelSideLeft: labelsLeft,
            ),
          ),
        );
      }
      colWidgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                labelsLeft ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
    if (left < 8) left = 8;

    // Вертикальное положение: над родительским пультом.
    final totalH = rowsPerCol * itemH;
    double top = local.dy - totalH - 6;
    if (top < 8) top = 8;

    // Порядок столбцов: при подписях слева столбцы разворачиваем,
    // дабы первый столбец был у пульта.
    final ordered = labelsLeft ? colWidgets.reversed.toList() : colWidgets;

    return Positioned(
      left: left,
      top: top,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: ordered,
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
