// ═══════════════════════════════════════════════════════════════════
// root_pult.dart — корневой пульт (компас) и веер вкладок.
//
// Свёрнутый — компас. Касание открывает веер; перетаскивание — за
// любое место иконы.
//
// Перетаскивание. onDragStart / onDragUpdate получают ГЛОБАЛЬНЫЕ
// координаты пальца. Вызывающий (main) запоминает стартовую точку и
// считает позицию как старт + (текущее − стартовое). Сие надёжнее
// прежнего накопления дельт: положение виджета не участвует в
// арифметике, дерево можно перестраивать свободно.
//
// Подписи вкладок. Показываются справа от иконы, ежели labelsSystem.
// Строка подписи берётся чрез translate(labelKey).
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

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

  // Подписи.
  final bool labelsSystem;
  final String Function(String key) translate;

  // Обратные вызовы перетаскивания — глобальные координаты.
  final void Function(Offset globalPosition) onDragStart;
  final void Function(Offset globalPosition) onDragUpdate;
  final VoidCallback onDragEnd;
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
    required this.labelsSystem,
    required this.translate,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onOpen,
    required this.onSwitchTab,
  });

  @override
  Widget build(BuildContext context) {
    if (!open) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) => onDragStart(d.globalPosition),
        onPanUpdate: (d) => onDragUpdate(d.globalPosition),
        onPanEnd: (_) => onDragEnd(),
        onTapUp: (_) => onOpen(),
        child: _core(Icons.explore, false, side),
      );
    }

    final items = <Widget>[];
    for (var i = 0; i < tabs.length; i++) {
      final t = tabs[i];
      final active = activeTab == i;
      final label = labelsSystem ? translate(t.labelKey) : null;
      items.add(
        Padding(
          padding: const EdgeInsets.all(2),
          child: GestureDetector(
            onTap: () => onSwitchTab(i),
            child: _tabItem(t.icon, label, active, side * 2 / 3),
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

  // ─── Икона вкладки, при нужде — с подписью ───
  Widget _tabItem(IconData icon, String? label, bool active, double s) {
    final core = _core(icon, active, s);
    if (label == null || label.isEmpty) return core;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        core,
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: active ? signal : fg,
            fontSize: s * 0.35,
          ),
        ),
      ],
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
