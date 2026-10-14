// ═══════════════════════════════════════════════════════════════════
// block.dart — единый блок для карточки рутины и рубки.
//
// Устройство:
//   — рамка со сглаженными углами;
//   — заголовок слева вверху;
//   — значок свёртки в левом верхнем углу, сигнального цвета,
//     слегка выступает за контур (на четверть) — как ярлык;
//   — содержимое под заголовком (скрывается при свёртке);
//   — необязательные виджеты в углах: правый верхний (таймер)
//     и правый нижний (пульс).
//
// Касание заголовка либо значка — свернуть/развернуть, ежели
// canCollapse. Итог карточки сворачивать нельзя — значок не выводится.
//
// Обслуживает блоки рубки: те же рамки, заголовок, сворачивание;
// углы не используются.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

class Block extends StatelessWidget {
  final String title;
  final Widget? child;
  final bool collapsed;
  final bool canCollapse;
  final VoidCallback? onToggleCollapsed;

  // Правые углы: необязательные виджеты.
  final Widget? cornerRightTop;
  final Widget? cornerRightBottom;

  // Цвета.
  final Color bg;
  final Color dim;
  final Color fg;
  final Color signal;

  // Размеры.
  final double titleSize;
  final double pad;
  final double gap;
  final double strokeW;
  final double radiusW;
  // Активный блок (идущий) — сигнальная рамка.
  final bool active;
  // Резерв снизу под пульс в углу.
  final double reserveBottom;

  const Block({
    super.key,
    required this.title,
    this.child,
    this.collapsed = false,
    this.canCollapse = true,
    this.onToggleCollapsed,
    this.cornerRightTop,
    this.cornerRightBottom,
    required this.bg,
    required this.dim,
    required this.fg,
    required this.signal,
    required this.titleSize,
    required this.pad,
    required this.gap,
    required this.strokeW,
    required this.radiusW,
    this.active = false,
    this.reserveBottom = 0,
  });

  @override
  Widget build(BuildContext context) {
    final isCollapsed = canCollapse && collapsed;
    // Значок свёртки: сигнального цвета, чуть выступает за контур.
    final markSize = titleSize * 1.2;

    return Container(
      margin: EdgeInsets.only(bottom: gap),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: active ? fg : dim, width: strokeW),
        borderRadius: BorderRadius.circular(radiusW),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              pad + markSize * 0.75,
              pad,
              pad,
              pad + reserveBottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Заголовок — кликабелен для сворачивания.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: canCollapse ? onToggleCollapsed : null,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(color: dim, fontSize: titleSize),
                        ),
                      ),
                      if (cornerRightTop != null) ...[
                        const SizedBox(width: 8),
                        cornerRightTop!,
                      ],
                    ],
                  ),
                ),
                if (!isCollapsed && child != null) ...[
                  SizedBox(height: pad * 0.5),
                  child!,
                ],
              ],
            ),
          ),
          // Значок свёртки — левый верхний угол.
          if (canCollapse)
            Positioned(
              left: -markSize * 0.25,
              top: -markSize * 0.25,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onToggleCollapsed,
                child: Container(
                  width: markSize,
                  height: markSize,
                  decoration: BoxDecoration(
                    color: signal,
                    borderRadius: BorderRadius.circular(markSize * 0.2),
                  ),
                  child: Icon(
                    collapsed ? Icons.unfold_more : Icons.unfold_less,
                    color: bg,
                    size: markSize * 0.7,
                  ),
                ),
              ),
            ),
          // Пульс — правый нижний угол. По тому же краю, что и
          // верхний: right = pad (совпадает с концом паддинга,
          // где выстроен cornerRightTop), bottom = pad.
          if (cornerRightBottom != null)
            Positioned(right: pad, bottom: pad, child: cornerRightBottom!),
        ],
      ),
    );
  }
}
