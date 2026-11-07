// ═══════════════════════════════════════════════════════════════════
// rubka_control.dart — «control» block in the rubka.
//
// Contents, top to bottom:
//
//   — midnight;
//   — bort: a row with today's active time; tap on the time opens
//     the bort history dialog;
//   — shift: a checkbox «смена», and when it is on, a row with
//     today's shift time that opens the shift history;
//   — separator;
//   — mutexes: routines and slots, and the shift mutex only when
//     the shift checkbox is on (the stored value is preserved
//     while the checkbox is off, and simply hidden);
//   — separator;
//   — map scale.
//
// The bort-history row moved here from the «data» block; the «artel»
// block is finally abolished and has no successor.
//
// Toggling the shift off is handled inside operational_layer: the
// running shift stops, an actor entry is written to the journal,
// but no routine is paused — the spec says the mutex is deliberately
// ignored on that transition. Toggling it on restores the historical
// series.
//
// Tapping the shift checkbox while the shift is running is allowed
// and behaves exactly as if the user pressed «stop» first, then
// unchecked: the entry is written, the running blocks are left
// alone.
//
// Labels use HelpLabel; each setting has a `help.<key>` text in the
// dictionary. Section subheadings (mutexes) also use HelpLabel.
// Block title is a regular collapse mark and stays as-is.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/block.dart';
import '../core/bort_field.dart';
import '../core/format.dart';
import '../core/help_label.dart';
import '../pults/pult_core.dart';
import '../pults/pult_tick.dart';
import '../services/action_dialog.dart';

class RubkaControl extends StatelessWidget {
  final int parity;

  const RubkaControl({super.key, this.parity = 2});

  // Shared label column width, matching the other rubka blocks.
  static const double _labelW = 140.0;

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

    final rowPad = EdgeInsets.symmetric(vertical: side * 0.1);

    Widget divider() => Padding(
      padding: EdgeInsets.symmetric(vertical: side * 0.3),
      child: Container(height: strokeW, color: mid),
    );

    // ─── Label + control row ───
    Widget row({
      required String helpKey,
      required String label,
      required Widget control,
    }) {
      return Padding(
        padding: rowPad,
        child: Row(
          children: [
            HelpLabel(
              helpKey: helpKey,
              text: label,
              width: _labelW,
              style: TextStyle(color: fg),
            ),
            Expanded(child: control),
          ],
        ),
      );
    }

    // ─── Section heading ───
    Widget section(String helpKey, String text) {
      return Padding(
        padding: EdgeInsets.only(top: side * 0.3, bottom: side * 0.1),
        child: HelpLabel(
          helpKey: helpKey,
          text: text,
          style: TextStyle(color: mid, fontSize: side * 0.35),
        ),
      );
    }

    // ─── Midnight ───
    final midnightRow = row(
      helpKey: 'bort.midnight',
      label: i18n.t('bort.midnight'),
      control: BortField(
        initial: bort.midnight,
        fg: fg,
        readOnly: false,
        onChanged: (v) => bort.setDraft('midnight', v),
        onCommit: (v) async => bort.set('midnight', v),
      ),
    );

    // ─── Bort: a tappable link that shows today's time ───
    final bortRow = Padding(
      padding: rowPad,
      child: Row(
        children: [
          HelpLabel(
            helpKey: 'bort.bort',
            text: i18n.t('bort.bort'),
            width: _labelW,
            style: TextStyle(color: fg),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => showTimeHistory(context, key: 'bort'),
              child: Text(
                bort.bortTime <= 0
                    ? '0${i18n.t('time.m')}'
                    : fmtTime(bort.bortTime, i18n.t),
                style: TextStyle(
                  color: fgsignal,
                  fontFamily: 'monospace',
                  decoration: TextDecoration.underline,
                  decorationColor: fgsignal,
                  decorationThickness: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // ─── Shift: checkbox, and a time row when enabled ───
    final shiftCheckRow = Padding(
      padding: rowPad,
      child: Row(
        children: [
          HelpLabel(
            helpKey: 'bort.shift',
            text: i18n.t('bort.shift'),
            width: _labelW,
            style: TextStyle(color: fg),
          ),
          PultTick(
            id: 'shift_enabled',
            value: bort.shiftEnabled,
            binary: true,
            fg: fg,
            bg: bg,
            signal: fgsignal,
            overrideSize: side,
            onTap: () => bort.setBool('shift_enabled', !bort.shiftEnabled),
          ),
        ],
      ),
    );

    final shiftTimeRow = bort.shiftEnabled
        ? Padding(
            padding: rowPad,
            child: Row(
              children: [
                // Empty label column: this row is a continuation of
                // the checkbox row above, not a new setting.
                const SizedBox(width: _labelW),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        showTimeHistory(context, key: 'shift', fieldId: 0),
                    child: Text(
                      bort.shiftSecondsNow(0) <= 0
                          ? '0${i18n.t('time.m')}'
                          : fmtTime(bort.shiftSecondsNow(0), i18n.t),
                      style: TextStyle(
                        color: fgsignal,
                        fontFamily: 'monospace',
                        decoration: TextDecoration.underline,
                        decorationColor: fgsignal,
                        decorationThickness: 1.0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        : const SizedBox.shrink();

    // ─── Mutexes ───
    // Shift mutex is hidden while the checkbox is off. The stored
    // value is preserved; it simply does not apply.
    final mutexes = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        section('bort.mutexes', i18n.t('bort.mutexes')),
        row(
          helpKey: 'bort.mutex_routines',
          label: i18n.t('bort.mutex_routines'),
          control: PultTick(
            id: 'mutex_routines',
            value: bort.mutexRoutines,
            binary: true,
            fg: fg,
            bg: bg,
            signal: fgsignal,
            overrideSize: side,
            onTap: () => bort.setBool('mutex_routines', !bort.mutexRoutines),
          ),
        ),
        row(
          helpKey: 'bort.mutex_slots',
          label: i18n.t('bort.mutex_slots'),
          control: PultTick(
            id: 'mutex_slots',
            value: bort.mutexSlots,
            binary: true,
            fg: fg,
            bg: bg,
            signal: fgsignal,
            overrideSize: side,
            onTap: () => bort.setBool('mutex_slots', !bort.mutexSlots),
          ),
        ),
        if (bort.shiftEnabled)
          row(
            helpKey: 'bort.mutex_shift',
            label: i18n.t('bort.mutex_shift'),
            control: PultTick(
              id: 'mutex_shift',
              value: bort.mutexShift,
              binary: true,
              fg: fg,
              bg: bg,
              signal: fgsignal,
              overrideSize: side,
              onTap: () => bort.setBool('mutex_shift', !bort.mutexShift),
            ),
          ),
      ],
    );

    // ─── Map scale ───
    final mapScaleRow = row(
      helpKey: 'bort.map_scale',
      label: i18n.t('bort.map_scale'),
      control: BortField(
        initial: bort.mapScale.toString(),
        fg: fg,
        readOnly: false,
        onChanged: (v) => bort.setDraft('map_scale', v),
        onCommit: (v) async => bort.set('map_scale', v),
      ),
    );

    return Block(
      title: i18n.t('block.control'),
      collapsed: !bort.blockControl,
      onToggleCollapsed: () =>
          bort.setBool('block_control', !bort.blockControl),
      bg: bg,
      dim: mid,
      fg: fg,
      signal: fgsignal,
      titleSize: titleSize,
      pad: pad,
      gap: gap,
      strokeW: strokeW,
      radiusW: radiusW,
      parity: parity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          midnightRow,
          bortRow,
          shiftCheckRow,
          if (bort.shiftEnabled) shiftTimeRow,
          divider(),
          mutexes,
          divider(),
          mapScaleRow,
        ],
      ),
    );
  }
}
