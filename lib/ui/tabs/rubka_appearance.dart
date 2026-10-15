// ═══════════════════════════════════════════════════════════════════
// rubka_appearance.dart — блок «оформление» в рубке.
//
// Четыре пульта темы: система, день, ночь, своя. Текущая — отмечена.
//
// Поля пяти ролей (bg, bgdim, dim, fg, signal) — токмо для «своей»
// темы и показываются всегда, независимо от того, какая тема
// действует: править свою можно, стоя в любой другой. День и ночь
// не правятся, полей не имеют.
//
// Подблок с коэффициентами размеров из рубки упразднён:
// коэффициенты остаются в файле борта и в умолчаниях, но не
// правятся отсюда.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/theme_store.dart';
import '../core/app_scope.dart';
import '../core/bort_field.dart';
import '../core/block.dart';
import '../pults/pult_core.dart';

class RubkaAppearance extends StatelessWidget {
  const RubkaAppearance({super.key});

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

    return Block(
      title: i18n.t('block.appearance'),
      collapsed: !bort.blockAppearance,
      onToggleCollapsed: () =>
          set('block_appearance', (!bort.blockAppearance).toString()),
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
          _themeRow(context, fg, dim, bg, signal, side),
          // Поля «своей» темы — всегда, вне зависимости от действующей.
          _sectionTitle(i18n.t('theme.custom'), dim, side),
          _colorRow(context, 'custom', 'bg', fg, dim, bg, signal, side),
          _colorRow(context, 'custom', 'bgdim', fg, dim, bg, signal, side),
          _colorRow(context, 'custom', 'dim', fg, dim, bg, signal, side),
          _colorRow(context, 'custom', 'fg', fg, dim, bg, signal, side),
          _colorRow(context, 'custom', 'signal', fg, dim, bg, signal, side),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text, Color dim, double side) {
    return Padding(
      padding: EdgeInsets.only(top: side * 0.3, bottom: side * 0.1),
      child: Text(
        text,
        style: TextStyle(color: dim, fontSize: side * 0.35),
      ),
    );
  }

  // ─── Четыре пульта темы рядом ───
  Widget _themeRow(
    BuildContext context,
    Color fg,
    Color dim,
    Color bg,
    Color signal,
    double side,
  ) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    final showLabels = bort.labelsButtons;

    final names = ['system', 'day', 'night', 'custom'];
    final icons = [
      Icons.brightness_auto,
      Icons.light_mode_outlined,
      Icons.dark_mode_outlined,
      Icons.palette_outlined,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(i18n.t('bort.theme'), style: TextStyle(color: fg)),
          ),
          Expanded(
            child: Wrap(
              spacing: side * 0.15,
              runSpacing: side * 0.15,
              children: [
                for (var i = 0; i < names.length; i++)
                  Pult(
                    spec: PultSpec(
                      id: 'theme_${names[i]}',
                      icon: icons[i],
                      label: showLabels ? i18n.t('theme.${names[i]}') : null,
                      selected: bort.themeName == names[i],
                      onTap: () => bort.set('theme', names[i]),
                    ),
                    fg: fg,
                    bg: bg,
                    signal: signal,
                    overrideSize: side,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _colorRow(
    BuildContext context,
    String themeName,
    String role,
    Color fg,
    Color dim,
    Color bg,
    Color signal,
    double side,
  ) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final key = 'theme.$themeName.$role';
    final value = bort.allAsStrings[key] ?? '';
    final c = parseColor(value) ?? Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(role, style: TextStyle(color: fg)),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: BortField(
                    initial: value,
                    fg: fg,
                    readOnly: false,
                    onChanged: (v) => bort.setDraft(key, v),
                    onCommit: (v) async => bort.set(key, v),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: c,
                    border: Border.all(color: fg),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
