// ═══════════════════════════════════════════════════════════════════
// rubka_tab.dart — rubka tab.
//
// Four blocks: appearance, interface, data, permissions. The former
// «artel» block and its contents (shift row, midnight, map scale,
// mutex ticks, tab visibility) have been abolished together with
// the artel tab.
//
// Layout. Narrow: single column. Wide: two columns (interface and
// data on the left, appearance and permissions on the right) with
// chessboard frame parity.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/block.dart';
import '../core/control_row.dart';
import '../pults/pult_core.dart';
import 'rubka_appearance.dart';
import 'rubka_data.dart';
import 'rubka_interface.dart';
import 'rubka_permissions.dart';

class RubkaTab extends StatelessWidget {
  const RubkaTab({super.key});

  @override
  Widget build(BuildContext context) {
    final bort = BortScope.of(context);
    final i18n = I18nScope.of(context);
    final fg = bort.fg;
    final mid = bort.mid;
    final bg = bort.bg;
    final fgsignal = bort.fgsignal;
    final side = PultScope.of(context).smallSide;

    final titleSize = side * bort.kTitle;
    final pad = side * bort.kFramePad;
    final gap = side * bort.kBlockGap;
    final strokeW = side * bort.kStroke;
    final radiusW = side * bort.kRadius;

    void set(String key, String value) => bort.set(key, value);

    final interface = Block(
      title: i18n.t('block.interface'),
      collapsed: !bort.blockInterface,
      onToggleCollapsed: () =>
          set('block_interface', (!bort.blockInterface).toString()),
      bg: bg,
      dim: mid,
      fg: fg,
      signal: fgsignal,
      titleSize: titleSize,
      pad: pad,
      gap: gap,
      strokeW: strokeW,
      radiusW: radiusW,
      parity: 1,
      child: RubkaInterface(onSet: set),
    );

    final data = Block(
      title: i18n.t('block.data'),
      collapsed: !bort.blockData,
      onToggleCollapsed: () => set('block_data', (!bort.blockData).toString()),
      bg: bg,
      dim: mid,
      fg: fg,
      signal: fgsignal,
      titleSize: titleSize,
      pad: pad,
      gap: gap,
      strokeW: strokeW,
      radiusW: radiusW,
      parity: 2,
      child: const RubkaData(),
    );

    const appearanceBlock = RubkaAppearance(parity: 3);
    const permissionsBlock = RubkaPermissions();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final wide = width > 640;

        if (!wide) {
          return ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              ControlRow.reserve(side) + 8,
              16,
              16,
            ),
            children: [
              const BlockWrapper(parity: 0, child: appearanceBlock),
              BlockWrapper(parity: 1, child: interface),
              BlockWrapper(parity: 0, child: data),
              const BlockWrapper(parity: 1, child: permissionsBlock),
            ],
          );
        }

        const hPad = 16.0;
        const spacing = 16.0;
        final colW = (width - hPad * 2 - spacing) / 2;

        Widget col(List<Widget> children) => SizedBox(
          width: colW,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        );

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            hPad,
            ControlRow.reserve(side) + 8,
            hPad,
            16,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              col([
                BlockWrapper(parity: 0, child: interface),
                BlockWrapper(parity: 1, child: data),
              ]),
              const SizedBox(width: spacing),
              col([
                const BlockWrapper(parity: 1, child: appearanceBlock),
                const BlockWrapper(parity: 0, child: permissionsBlock),
              ]),
            ],
          ),
        );
      },
    );
  }
}

// Helper to override parity for strict alternation.
class BlockWrapper extends StatelessWidget {
  final int parity;
  final Widget child;
  const BlockWrapper({super.key, required this.parity, required this.child});

  @override
  Widget build(BuildContext context) {
    if (child is Block) {
      final b = child as Block;
      return Block(
        key: b.key,
        title: b.title,
        collapsed: b.collapsed,
        canCollapse: b.canCollapse,
        onToggleCollapsed: b.onToggleCollapsed,
        cornerRightTop: b.cornerRightTop,
        cornerRightBottom: b.cornerRightBottom,
        bg: b.bg,
        dim: b.dim,
        fg: b.fg,
        signal: b.signal,
        titleSize: b.titleSize,
        pad: b.pad,
        gap: b.gap,
        strokeW: b.strokeW,
        radiusW: b.radiusW,
        active: b.active,
        parity: parity,
        reserveBottom: b.reserveBottom,
        child: b.child,
      );
    } else if (child is RubkaAppearance) {
      return RubkaAppearance(parity: parity);
    } else if (child is RubkaPermissions) {
      return RubkaPermissions(parity: parity);
    }
    return child;
  }
}
