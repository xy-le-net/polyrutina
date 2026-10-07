// ═══════════════════════════════════════════════════════════════════
// root_pult.dart — корневой пульт (компас) и веер вкладок.
//
// Свёрнутый — икона компаса (Icons.explore). Касание открывает
// веер икон всех вкладок. Перетаскивание за любое место иконы.
//
// Перетаскивание. При начале жеста запоминается стартовая позиция
// (anchor). Дальше новое положение считается как anchor + накопленная
// дельта. Сие надёжнее, нежели прибавлять дельты к текущей позиции:
// при перестроении дерева виджетов текущее положение могло уже
// измениться, и дельта терялась.
//
// Развёрнутый — веер икон всех вкладок; текущая выделена сигнальным.
// Веер раскрывается в ту сторону, где есть место.
//
// Виджет stateless: состояние (открыт ли веер, позиция, стартовая
// позиция жеста) держит вызывающий (main.dart).
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

// Описание вкладки: икона и ключ словаря для подписи.
class RootTabItem {
  final IconData icon;
  final String labelKey;
  const RootTabItem({required this.icon, required this.labelKey});
}

class RootPult extends StatelessWidget {
  final List<RootTabItem> tabs;
  final int activeTab;
  final bool open;
  final double side;
  final Offset position;
  final Size area;
  final Color fg;
  final Color bg;
  final Color signal;

  // Обратные вызовы.
  // onDragStart — начало перетаскивания (запоминается стартовая позиция).
  // onDragUpdate — новая позиция (абсолютная).
  // onDragEnd — окончание (позиция для прилипания к якорю).
  final VoidCallback onDragStart;
  final void Function(Offset newPosition) onDragUpdate;
  final void Function(Offset position) onDragEnd;
  final VoidCallback onOpen;
  final void Function(int index) onSwitchTab;

  const RootPult({
    super.key,
    required this.tabs,
    required this.activeTab,
    required this.open,
    required this.side,
    required this.position,
    required this.area,
    required this.fg,
    required this.bg,
    required this.signal,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onOpen,
    required this.onSwitchTab,
  });

  @override
  Widget build(BuildContext context) {
    if (!open) {
      // Свёрнутый: компас, перетаскивается, касание открывает веер.
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => onDragStart(),
        onPanUpdate: (d) => onDragUpdate(position + d.delta),
        onPanEnd: (_) => onDragEnd(position),
        onTapUp: (_) => onOpen(),
        child: _core(Icons.explore, false, side),
      );
    }

    final items = <Widget>[];
    for (var i = 0; i < tabs.length; i++) {
      final t = tabs[i];
      final active = activeTab == i;
      items.add(
        Padding(
          padding: const EdgeInsets.all(2),
          child: GestureDetector(
            onTap: () => onSwitchTab(i),
            child: _core(t.icon, active, side * 2 / 3),
          ),
        ),
      );
    }

    final centerX = position.dx + side / 2;
    final centerY = position.dy + side / 2;
    final pushRight = centerX > area.width / 2;
    final pushDown = centerY <= area.height / 2;

    final maxW = pushRight ? (position.dx + side) : (area.width - position.dx);
    final maxH =
        pushDown ? (area.height - position.dy - side) : (position.dy + side);

    final layout = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
      child: _layout(
        items,
        Size(maxW, maxH),
        side * 2 / 3 + 8,
        alignEnd: pushRight,
      ),
    );

    final dx = pushRight ? (side - maxW) : 0.0;
    final dy = pushDown ? side : -maxH;

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

  // Ядро пульта: тройная вложенная обводка.
  Widget _core(IconData icon, bool selected, double s) {
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

  // Раскладка веера вкладок.
  Widget _layout(
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
