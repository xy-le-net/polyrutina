// ═══════════════════════════════════════════════════════════════════
// root_pult.dart — корневой пульт (компас) и панель вкладок.
//
// Корневой пульт жёстко привязан к левому верхнему углу: без
// перетаскивания, без выбора якоря. Размер — side.
//
// Касание открывает панель вкладок: вертикальная колонка у левого
// края, как подпульт медиа. Тап мимо — закрыть, тап по вкладке —
// переключить и закрыть.
//
// Панель рисуется тут же, в Stack, локально для виджета. Никаких
// внешних слоёв и перетаскивания.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import 'pult_core.dart';

class RootTabItem {
  final IconData icon;
  final String labelKey;
  const RootTabItem({required this.icon, required this.labelKey});
}

class RootPult extends StatefulWidget {
  final List<RootTabItem> tabs;
  final int activeTab;
  final double side;
  final Color fg;
  final Color bg;
  final Color signal;
  final bool labelsSystem;
  final String Function(String key) translate;
  final void Function(int index) onSwitchTab;

  const RootPult({
    super.key,
    required this.tabs,
    required this.activeTab,
    required this.side,
    required this.fg,
    required this.bg,
    required this.signal,
    required this.labelsSystem,
    required this.translate,
    required this.onSwitchTab,
  });

  @override
  State<RootPult> createState() => _RootPultState();
}

class _RootPultState extends State<RootPult> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    if (!_open) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (_) => setState(() => _open = true),
        child: _core(Icons.explore, false, widget.side),
      );
    }

    final side = widget.side;

    // ─── Панель вкладок у левого края ───
    final items = <Widget>[];
    for (var i = 0; i < widget.tabs.length; i++) {
      final t = widget.tabs[i];
      final active = widget.activeTab == i;
      final label = widget.labelsSystem ? widget.translate(t.labelKey) : null;
      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: Pult(
            spec: PultSpec(
              id: 'tab_$i',
              icon: t.icon,
              label: label,
              selected: active,
              onTap: () {
                setState(() => _open = false);
                widget.onSwitchTab(i);
              },
            ),
            fg: widget.fg,
            bg: widget.bg,
            signal: widget.signal,
            overrideSize: side,
          ),
        ),
      );
    }

    final panelWidth = side + 160;

    return Stack(
      children: [
        // Подложка: тап мимо — закрыть.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = false),
            child: Container(color: widget.bg.withAlpha(200)),
          ),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          left: 0,
          width: panelWidth,
          child: Container(
            color: widget.bg,
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: items,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Ядро пульта: тройная вложенная обводка.
  Widget _core(IconData icon, bool selected, double s) {
    final coreColor = selected ? widget.signal : widget.fg;
    final iconColor = widget.bg;
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

    return core;
  }
}
