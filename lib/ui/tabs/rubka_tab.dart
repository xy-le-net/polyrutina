// ═══════════════════════════════════════════════════════════════════
// rubka_tab.dart — rubka tab.
//
// Four blocks: artel, appearance, interface, data. Appearance,
// interface, and data are extracted into separate widgets
// (rubka_appearance, rubka_interface, rubka_data). Here — only
// block assembly, layout, and the «midnight» field with tab
// visibility checkboxes.
//
// Artel. The «midnight» field (hh:mm) — the start of the technical
// day. Two checkboxes: show the «field» tab and show the «artel»
// tab. Both hidden by default; when checked, the tab appears in
// the menu.
//
// Layout.
//   Narrow screen (less than 640): blocks in one column top to bottom.
//   Wide screen: two columns of equal width, blocks joined without
//   vertical gaps — each slot stretches by its column height, the
//   remainder fills the emptiness inside the neighbor's frame if
//   there is a height difference. Columns: left — artel, interface;
//   right — appearance, data.
//
// Simplifications: the two identical calls to _tabTickRow are
// replaced by a loop over the list of keys (the label is derived
// from the key as 'bort.$key').
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/block.dart';
import '../core/bort_field.dart';
import '../pults/pult_core.dart';
import '../pults/pult_tick.dart';
import 'rubka_appearance.dart';
import 'rubka_data.dart';
import 'rubka_interface.dart';

class RubkaTab extends StatelessWidget {
  const RubkaTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    final fg = bort.fg;
    final dim = bort.dim;
    final bg = bort.bg;
    final signal = bort.signal;
    final side = PultScope.of(context).smallSide;

    final titleSize = side * bort.kTitle;
    final pad = side * bort.kFramePad;
    final gap = side * bort.kBlockGap;
    final strokeW = side * bort.kStroke;
    final radiusW = side * bort.kRadius;

    void set(String key, String value) => bort.set(key, value);

    // ─── Artel block: midnight + tab visibility checkboxes ───
    final artel = Block(
      title: i18n.t('block.artel'),
      collapsed: !bort.blockArtel,
      onToggleCollapsed: () =>
          set('block_artel', (!bort.blockArtel).toString()),
      bg: bg,
      dim: dim,
      fg: fg,
      signal: signal,
      titleSize: titleSize,
      pad: pad,
      gap: gap,
      strokeW: strokeW,
      radiusW: radiusW,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _midnightRow(context, fg, side),
          // Tab visibility checkboxes — generated via a loop.
          for (final key in const ['show_field_tab', 'show_artel_tab'])
            _tabTickRow(
              context,
              key,
              i18n.t('bort.$key'),
              fg,
              bg,
              signal,
              side,
            ),
        ],
      ),
    );

    const appearance = RubkaAppearance();

    final interface = Block(
      title: i18n.t('block.interface'),
      collapsed: !bort.blockInterface,
      onToggleCollapsed: () =>
          set('block_interface', (!bort.blockInterface).toString()),
      bg: bg,
      dim: dim,
      fg: fg,
      signal: signal,
      titleSize: titleSize,
      pad: pad,
      gap: gap,
      strokeW: strokeW,
      radiusW: radiusW,
      child: RubkaInterface(onSet: set),
    );

    final data = Block(
      title: i18n.t('block.data'),
      collapsed: !bort.blockData,
      onToggleCollapsed: () => set('block_data', (!bort.blockData).toString()),
      bg: bg,
      dim: dim,
      fg: fg,
      signal: signal,
      titleSize: titleSize,
      pad: pad,
      gap: gap,
      strokeW: strokeW,
      radiusW: radiusW,
      child: const RubkaData(),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final wide = width > 640;

        if (!wide) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 80, 16, 16),
            children: [artel, appearance, interface, data],
          );
        }

        const hPad = 16.0;
        const spacing = 16.0;
        final colW = (width - hPad * 2 - spacing) / 2;

        // Two columns. Inside — without vertical gaps: Block already
        // has a bottom margin (gap) inside itself, and Column places
        // them flush. The height difference between columns does not
        // create gaps between blocks, only empty space at the bottom
        // of the shorter column.
        Widget col(List<Widget> children) => SizedBox(
          width: colW,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(hPad, 80, hPad, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              col([artel, interface]),
              const SizedBox(width: spacing),
              col([appearance, data]),
            ],
          ),
        );
      },
    );
  }

  // ─── Midnight: the only particular left here ───
  Widget _midnightRow(BuildContext context, Color fg, double side) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(i18n.t('bort.midnight'), style: TextStyle(color: fg)),
          ),
          Expanded(
            child: BortField(
              initial: bort.midnight,
              fg: fg,
              readOnly: false,
              onCommit: (v) async {
                // Validate hh:mm format.
                final ok = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(v);
                if (!ok) return;
                bort.set('midnight', v);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── Tab visibility checkbox ───
  Widget _tabTickRow(
    BuildContext context,
    String key,
    String label,
    Color fg,
    Color bg,
    Color signal,
    double side,
  ) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final value = (bort.allAsStrings[key] ?? 'false') == 'true';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: TextStyle(color: fg)),
          ),
          PultTick(
            id: 'tick_$key',
            value: value,
            binary: true,
            fg: fg,
            bg: bg,
            signal: signal,
            overrideSize: side,
            onTap: () => bort.setBool(key, !value),
          ),
        ],
      ),
    );
  }
}
