// ═══════════════════════════════════════════════════════════════════
// rubka_appearance.dart — «appearance» block in the rubka.
//
// Four theme pults: system, day, night, custom. The current one is
// marked.
//
// Fields for the five roles (bg, bgdim, dim, fg, signal) — only for
// the «custom» theme, always shown regardless of the active theme:
// the custom theme can be edited while standing in any other. Day
// and night are not editable and have no fields.
//
// The sub-block with size coefficients from the rubka is abolished:
// coefficients remain in the bort file and defaults, but are not
// edited from here.
//
// Simplifications: unused parameters (dim in _themeRow; dim, bg,
// signal in _colorRow) are removed. The five repeated calls to
// _colorRow are replaced by a loop over the role names.
//
// Transparency is not applied.
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
          _themeRow(context, fg, bg, signal, side),
          // Fields for the «custom» theme — always shown, regardless
          // of the active theme.
          _sectionTitle(i18n.t('theme.custom'), dim, side),
          // The five color roles are generated via a loop to avoid
          // repetition.
          for (final role in const ['bg', 'bgdim', 'dim', 'fg', 'signal'])
            _colorRow(context, 'custom', role, fg, side),
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

  // ─── Four theme pults in a row ───
  Widget _themeRow(
    BuildContext context,
    Color fg,
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

  // ─── Color role row (hex input + preview) ───
  // Only fg and side are used by the row's UI.
  Widget _colorRow(
    BuildContext context,
    String themeName,
    String role,
    Color fg,
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
                // Color preview square.
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
