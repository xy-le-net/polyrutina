// ═══════════════════════════════════════════════════════════════════
// rubka_control.dart — «control» block in the rubka.
//
// Contents, top to bottom:
//
//   — midnight;
//   — bort: a row with today's active time; tap on the time opens
//     the bort history dialog;
//   — shift: the word «смена» with a checkbox; when the shift is
//     on, today's shift time follows the word in parentheses, one
//     space apart. The word opens help; the time in parentheses
//     opens the shift history (the parentheses themselves are not
//     underlined, only the time inside);
//   — separator;
//   — mutexes: routines and slots, and the shift mutex only when
//     the shift checkbox is on (the stored value is preserved
//     while the checkbox is off, and simply hidden);
//   — separator;
//   — map scale.
//
// Pult width. Every Pult placed inside an Expanded is wrapped in
// Align(centerLeft): under the tight width constraint that Expanded
// supplies, the pult's internal Container would otherwise stretch
// to fill the row (and the GestureDetector, opaque, would swallow
// taps across the whole width). Align loosens the constraint so
// the pult keeps its natural size and hit area.
//
// Toggling the shift off is handled inside operational_layer: the
// running shift stops, an actor entry is written to the journal,
// but no routine is paused — the spec says the mutex is deliberately
// ignored on that transition. Toggling it on restores the historical
// series.
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
            child: Align(
              alignment: Alignment.centerLeft,
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
          ),
        ],
      ),
    );

    // ─── Shift: word + «(time)» on one line, checkbox at right ───
    final shiftTimeStr = bort.shiftSecondsNow(0) <= 0
        ? '0${i18n.t('time.m')}'
        : fmtTime(bort.shiftSecondsNow(0), i18n.t);

    final shiftLabel = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HelpLabel(
          helpKey: 'bort.shift',
          text: i18n.t('bort.shift'),
          width: side * 2.5,
          style: TextStyle(color: fg),
        ),
        if (bort.shiftEnabled) ...[
          Text(
            ' (',
            style: TextStyle(color: fgsignal, fontFamily: 'monospace'),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showTimeHistory(context, key: 'shift', fieldId: 0),
            child: Text(
              shiftTimeStr,
              style: TextStyle(
                color: fgsignal,
                fontFamily: 'monospace',
                decoration: TextDecoration.underline,
                decorationColor: fgsignal,
                decorationThickness: 1.0,
              ),
            ),
          ),
          Text(
            ')',
            style: TextStyle(color: fgsignal, fontFamily: 'monospace'),
          ),
        ],
      ],
    );

    final shiftRow = Padding(
      padding: rowPad,
      child: Row(
        children: [
          SizedBox(
            width: _labelW,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: shiftLabel,
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: PultTick(
                id: 'shift_enabled',
                value: bort.shiftEnabled,
                binary: true,
                fg: fg,
                bg: bg,
                signal: fgsignal,
                overrideSize: side,
                onTap: () => bort.setBool('shift_enabled', !bort.shiftEnabled),
              ),
            ),
          ),
        ],
      ),
    );

    // ─── Mutexes ───
    final mutexes = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        section('bort.mutexes', i18n.t('bort.mutexes')),
        row(
          helpKey: 'bort.mutex_routines',
          label: i18n.t('bort.mutex_routines'),
          control: Align(
            alignment: Alignment.centerLeft,
            child: PultTick(
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
        ),
        row(
          helpKey: 'bort.mutex_slots',
          label: i18n.t('bort.mutex_slots'),
          control: Align(
            alignment: Alignment.centerLeft,
            child: PultTick(
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
        ),
        if (bort.shiftEnabled)
          row(
            helpKey: 'bort.mutex_shift',
            label: i18n.t('bort.mutex_shift'),
            control: Align(
              alignment: Alignment.centerLeft,
              child: PultTick(
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
          shiftRow,
          divider(),
          mutexes,
          divider(),
          mapScaleRow,
        ],
      ),
    );
  }
}
