// ═══════════════════════════════════════════════════════════════════
// rubka_tab.dart — вкладка рубки.
//
// Четыре блока: артель, оформление, интерфейс, данные. Оформление
// и интерфейс, данные — вынесены в отдельные виджеты
// (rubka_appearance.dart, rubka_interface.dart, rubka_data.dart).
// Здесь — лишь сборка блоков и раскладка.
//
// Дубликаты, что прежде жили в сем файле (повторы _refreshSize,
// _slotTicks, _settingRow, _langRow, _pultRow, _midnightRow),
// устранены: всякая частность — в своём виджете.
//
// Артель — поле «полночь» (чч:мм).
//
// Широкий экран: блоки идут слева направо, сверху вниз — как текст.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/block.dart';
import '../core/bort_field.dart';
import '../pults/pult_core.dart';
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
      child: _midnightRow(context, fg, side),
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

        Widget cell(Widget child) => SizedBox(width: colW, child: child);

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(hPad, 80, hPad, 16),
          child: Wrap(
            spacing: spacing,
            runSpacing: 0,
            children: [
              cell(artel),
              cell(appearance),
              cell(interface),
              cell(data),
            ],
          ),
        );
      },
    );
  }

  // ─── Полночь: единственная частность, оставшаяся здесь ───
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
}
