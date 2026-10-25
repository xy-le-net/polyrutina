// ═══════════════════════════════════════════════════════════════════
// lib/ui/tabs/rubka_tab.dart — rubka tab.
//
// Four blocks: artel, appearance, interface, data. Appearance,
// interface, and data are extracted into separate widgets
// (rubka_appearance, rubka_interface, rubka_data). Here — block
// assembly, layout, and the «artel» block body.
//
// Artel. The shift row is the first line — fgsignal-colored in full
// and refreshed on every ticker beat, so the running total keeps
// pace with the wall clock. Then: midnight field (HH:MM) — the
// start of the technical day. Under «взаимоисключение» — two
// checkboxes: «рутины» (global pause of every other block) and
// «слоты» (same-routine pause, ignored when «рутины» is on). Under
// «блоки» — two checkboxes for tab visibility («поле» and
// «артель»).
//
// Layout.
//   Narrow screen (under 640): blocks in a single column, top down.
//   Wide screen: two equal-width columns; blocks butt together
//   without vertical gaps. Columns: left — artel, interface;
//   right — appearance, data.
//
// Scopes. BortScope and I18nScope for the rubka itself;
// TickerScope for the shift row's live refresh.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/block.dart';
import '../core/bort_field.dart';
import '../core/control_row.dart';
import '../core/format.dart';
import '../pults/pult_core.dart';
import '../pults/pult_tick.dart';
import '../services/action_dialog.dart';
import 'rubka_appearance.dart';
import 'rubka_data.dart';
import 'rubka_interface.dart';

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

    final artel = Block(
      title: i18n.t('block.artel'),
      collapsed: !bort.blockArtel,
      onToggleCollapsed: () =>
          set('block_artel', (!bort.blockArtel).toString()),
      bg: bg,
      dim: mid,
      fg: fg,
      signal: fgsignal,
      titleSize: titleSize,
      pad: pad,
      gap: gap,
      strokeW: strokeW,
      radiusW: radiusW,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Shift row — first line of the block, fgsignal-colored in
          // full, refreshed by the ticker so the number ticks.
          _shiftRow(context, side),
          _midnightRow(context, fg, side),
          _sectionHeader(i18n.t('bort.mutex'), mid, side),
          _tabTickRow(
            context,
            'mutex_routines',
            i18n.t('bort.mutex_routines'),
            fg,
            bg,
            fgsignal,
            side,
          ),
          _tabTickRow(
            context,
            'mutex_slots',
            i18n.t('bort.mutex_slots'),
            fg,
            bg,
            fgsignal,
            side,
          ),
          _sectionHeader(i18n.t('bort.blocks'), mid, side),
          _tabTickRow(
            context,
            'show_field_tab',
            i18n.t('bort.show_field_tab'),
            fg,
            bg,
            fgsignal,
            side,
          ),
          _tabTickRow(
            context,
            'show_artel_tab',
            i18n.t('bort.show_artel_tab'),
            fg,
            bg,
            fgsignal,
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
      dim: mid,
      fg: fg,
      signal: fgsignal,
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
      dim: mid,
      fg: fg,
      signal: fgsignal,
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
            padding: EdgeInsets.fromLTRB(
              16,
              ControlRow.reserve(side) + 8,
              16,
              16,
            ),
            children: [artel, appearance, interface, data],
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
              col([artel, interface]),
              const SizedBox(width: spacing),
              col([appearance, data]),
            ],
          ),
        );
      },
    );
  }

  // ─── Midnight: the start of the technical day ───
  Widget _midnightRow(BuildContext context, Color fg, double side) {
    final bort = BortScope.of(context);
    final i18n = I18nScope.of(context);

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

  // ─── Section header ───
  // A plain label above a group of checkboxes. Left without a pult
  // of its own — it names the group, not a value.
  Widget _sectionHeader(String label, Color mid, double side) {
    return Padding(
      padding: EdgeInsets.only(top: side * 0.2, bottom: side * 0.05),
      child: Text(
        label,
        style: TextStyle(color: mid, fontSize: side * 0.35),
      ),
    );
  }

  // ─── Shift row: fgsignal-colored in full, refreshed on the ticker ───
  // AnimatedBuilder re-reads BortScope inside the builder, so both
  // the ticker (2 Hz) and any bort mutation (start/stop/pulse)
  // trigger a fresh read of shiftSecondsNow. Without this, an idle
  // running shift would sit on a stale «0м» until the next tap.
  Widget _shiftRow(BuildContext context, double side) {
    final ticker = TickerScope.of(context);
    return AnimatedBuilder(
      animation: ticker,
      builder: (context, _) {
        final bort = BortScope.of(context);
        final i18n = I18nScope.of(context);
        final sec = bort.shiftSecondsNow;
        final value = sec <= 0 ? '0${i18n.t('time.m')}' : fmtTime(sec, i18n.t);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showTimeHistory(context, key: 'shift'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 140,
                  child: Text(
                    i18n.t('bort.shift'),
                    style: TextStyle(
                      color: bort.fgsignal,
                      decoration: TextDecoration.underline,
                      decorationColor: bort.fgsignal,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      color: bort.fgsignal,
                      fontFamily: 'monospace',
                      decoration: TextDecoration.underline,
                      decorationColor: bort.fgsignal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Checkbox (binary) ───
  Widget _tabTickRow(
    BuildContext context,
    String key,
    String label,
    Color fg,
    Color bg,
    Color signal,
    double side,
  ) {
    final bort = BortScope.of(context);
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
