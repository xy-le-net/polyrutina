// ═══════════════════════════════════════════════════════════════════
// rubka_appearance.dart — «appearance» block in the rubka.
//
// Four theme pults: system, day, night, custom. The current one is
// marked.
//
// The routine's day is determined as follows: completedAt, otherwise
// scheduledAt, otherwise lastPulseAt, otherwise createdAt. The
// priority is exactly this: completion > schedule > pulse > creation.
// The assigned date outranks the pulse on purpose: a routine pinned
// to a particular day must appear on that day, not on the day it
// happened to be started. One routine — exactly one mark.
//
// Scopes. Dependencies are read from point scopes: BortScope (theme
// name, labels flag, per-theme colors) and I18nScope (strings). The
// former AppScope reading did not subscribe to bort notifications
// (AppScope.updateShouldNotify compares only the appContext fields,
// which do not change on bort mutations); as a result this widget
// never rebuilt, and the block appeared frozen in its initial
// collapsed state — the «phantom» behaviour reported in the review.
//
// The coefficients subblock has been removed from the rubka: the
// coefficients remain in the bort file and in the defaults, but are
// not edited from here.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/theme_store.dart';
import '../core/app_scope.dart';
import '../core/block.dart';
import '../core/bort_field.dart';
import '../pults/pult_core.dart';

class RubkaAppearance extends StatelessWidget {
  const RubkaAppearance({super.key});

  @override
  Widget build(BuildContext context) {
    final bort = BortScope.of(context);
    final i18n = I18nScope.of(context);
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
          // «Custom» theme fields — always, regardless of the active
          // theme.
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

  // ─── Four theme pults side by side ───
  Widget _themeRow(
    BuildContext context,
    Color fg,
    Color dim,
    Color bg,
    Color signal,
    double side,
  ) {
    final bort = BortScope.of(context);
    final i18n = I18nScope.of(context);
    final showLabels = bort.labelsButtons;

    // «invers» — the custom palette flipped by the same rule as the
    // running-block inverse (bg↔fg, bgdim↔dim, signal kept); it is
    // computed on read from the custom colors, so editing custom
    // updates it automatically. Placed after custom — «под пункт
    // своя» — matching the theme_store resolution.
    final names = ['system', 'day', 'night', 'custom', 'invers'];
    final icons = [
      Icons.brightness_auto,
      Icons.light_mode_outlined,
      Icons.dark_mode_outlined,
      Icons.palette_outlined,
      Icons.invert_colors,
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
    final bort = BortScope.of(context);
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
