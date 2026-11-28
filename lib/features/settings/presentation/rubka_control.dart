import 'package:polyrutina/core/localization/providers.dart';
import 'package:polyrutina/features/settings/application/providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:polyrutina/shared/presentation/widgets/block.dart';
import 'package:polyrutina/shared/presentation/bort_metrics.dart';
import 'package:polyrutina/shared/presentation/widgets/bort_field.dart';
import 'package:polyrutina/shared/application/format.dart';
import 'package:polyrutina/shared/presentation/help_label.dart';
import 'package:polyrutina/shared/presentation/widgets/link_text.dart';
import 'package:polyrutina/shared/presentation/pults/pult_core.dart';
import 'package:polyrutina/shared/presentation/pults/pult_tick.dart';
import 'package:polyrutina/features/settings/presentation/action_dialog.dart';

class RubkaControl extends ConsumerWidget {
  final int parity;

  const RubkaControl({super.key, this.parity = 2});

  static const double _labelW = 140.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bort = ref.watch(operationalLayerProvider);
    final i18n = ref.watch(i18nProvider)!;
    final fg = bort.fg;
    final mid = bort.mid;
    final bg = bort.bg;
    final fgsignal = bort.fgsignal;
    final side = PultScope.of(context).smallSide;

    final metrics = BortMetrics.of(context, compact: true);
    final titleSize = metrics.textSize(BortTextRole.header);
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
          style: TextStyle(
            color: mid,
            fontSize: metrics.textSize(BortTextRole.caption),
          ),
        ),
      );
    }

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
              child: LinkText(
                text: bort.bortTime <= 0
                    ? '0${i18n.t('time.m')}'
                    : fmtTime(bort.bortTime, i18n.t),
                fontSize: metrics.textSize(BortTextRole.base),
                fontFamily: 'monospace',
                onTap: () => showTimeHistory(context, key: 'bort'),
              ),
            ),
          ),
        ],
      ),
    );

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
          LinkText(
            text: shiftTimeStr,
            fontSize: metrics.textSize(BortTextRole.base),
            fontFamily: 'monospace',
            onTap: () => showTimeHistory(context, key: 'shift', fieldId: 0),
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

    final scaleRow = row(
      helpKey: 'bort.scale',
      label: i18n.t('bort.scale'),
      control: BortField(
        initial: bort.scale.toStringAsFixed(2),
        fg: fg,
        readOnly: false,
        onChanged: (v) => bort.setDraft('scale', v),
        onCommit: (v) async => bort.set('scale', v),
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
          scaleRow,
        ],
      ),
    );
  }
}
