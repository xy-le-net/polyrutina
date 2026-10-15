// ═══════════════════════════════════════════════════════════════════
// rubka_tab.dart — вкладка рубки.
//
// Четыре блока: артель, оформление, интерфейс, данные. Оформление,
// интерфейс и данные вынесены в отдельные виджеты (rubka_appearance,
// rubka_interface, rubka_data). Здесь — лишь сборка блоков, раскладка
// и поле «полночь» с чекбоксами показа вкладок.
//
// Артель. Поле «полночь» (чч:мм) — начало технических суток.
// Два чекбокса: показ вкладки «поле» и показ вкладки «артель».
// По умолчанию обе скрыты; при отметке вкладка появляется в меню.
//
// Раскладка.
//   Узкий экран (менее 640): блоки в один столбец сверху вниз.
//   Широкий экран: два столбца равной ширины, блоки стыкуются
//   без вертикальных промежутков — каждое гнездо тянется по высоте
//   своей колонны, остаток заполняет пустота внутри рамки соседа,
//   ежели разница высот. Столбцы: левый — артель, интерфейс;
//   правый — оформление, данные.
//
// Прозрачность не применяется.
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
          _tabTickRow(
            context,
            'show_field_tab',
            i18n.t('bort.show_field_tab'),
            fg,
            bg,
            signal,
            side,
          ),
          _tabTickRow(
            context,
            'show_artel_tab',
            i18n.t('bort.show_artel_tab'),
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

        // Два столбца. Внутри — без вертикальных промежутков:
        // Block уже имеет нижний отступ (gap) внутри себя, а Column
        // располагает их вплотную. Разница высот столбцов не создаёт
        // промежутков между блоками, лишь свободное место внизу
        // короткого столбца.
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

  // ─── Чекбокс показа вкладки ───
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
