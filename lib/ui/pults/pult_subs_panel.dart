// ═══════════════════════════════════════════════════════════════════
// pult_subs_panel.dart — единая панель подпультов.
//
// Вертикальная колонка пультов с подписями. Вписывается в край
// экрана: слева, справа либо сверху. Используется PultLayer (для
// side-панелей по краю) и RootPult (для меню вкладок сверху).
//
// Тап по затемнённой подложке — закрыть.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import 'pult_core.dart';

class PultSubsPanel extends StatelessWidget {
  final List<PultSpec> subs;
  final Color fg;
  final Color bg;
  final Color signal;
  final double side;
  final bool labelSideLeft;

  const PultSubsPanel({
    super.key,
    required this.subs,
    required this.fg,
    required this.bg,
    required this.signal,
    required this.side,
    this.labelSideLeft = false,
  });

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (final s in subs) {
      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: Pult(
            spec: s,
            fg: fg,
            bg: bg,
            signal: signal,
            insideLayer: true,
            overrideSize: side,
            labelSideLeft: labelSideLeft,
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: labelSideLeft
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: items,
      ),
    );
  }
}
