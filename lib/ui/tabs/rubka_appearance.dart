// ═══════════════════════════════════════════════════════════════════
// lib/ui/tabs/rubka_appearance.dart — «appearance» block in the rubka.
//
// Three theme toggles:
//   — «custom»: use the custom palette;
//   — «night»: force the night palette (mutually exclusive with auto);
//   — «auto»: follow the system brightness (mutually exclusive with
//     night). With both off, day is used.
//
// The custom role editor is shown only when the custom palette is
// enabled. The custom palette is now stored in its night form (see
// theme_store.dart); the editor therefore writes to the same entry,
// and the visible day view is the mirror. No logic change is needed
// here: the fields are the same five roles, the stored hex strings
// come from ThemeStore.toFlatStrings() and go back through
// applyThemeKey.
//
// Labels use HelpLabel; the three theme toggles each have a
// `help.theme.*` text. Role labels (bg, fg, …) stay plain — they are
// not settings, only slots of the palette; the section heading above
// carries the group help.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/theme_store.dart';
import '../core/app_scope.dart';
import '../core/block.dart';
import '../core/bort_field.dart';
import '../core/help_label.dart';
import '../pults/pult_core.dart';
import '../pults/pult_tick.dart';

class RubkaAppearance extends StatelessWidget {
  final int parity;

  const RubkaAppearance({super.key, this.parity = 1});

  static const List<String> _roles = [
    'bgsignal',
    'bg',
    'mid',
    'fg',
    'fgsignal',
  ];

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

    void set(String key, String value) => bort.set(key, value);

    return Block(
      title: i18n.t('block.appearance'),
      collapsed: !bort.blockAppearance,
      onToggleCollapsed: () =>
          set('block_appearance', (!bort.blockAppearance).toString()),
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
          _themeRow(context, fg, mid, bg, fgsignal, side),
          if (bort.themeCustom) ...[
            _sectionTitle(i18n.t('theme.custom'), mid, side),
            for (final role in _roles)
              _colorRow(context, 'custom', role, fg, mid, bg, fgsignal, side),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String text, Color mid, double side) {
    return Padding(
      padding: EdgeInsets.only(top: side * 0.3, bottom: side * 0.1),
      child: HelpLabel(
        helpKey: 'theme.custom',
        text: text,
        style: TextStyle(color: mid, fontSize: side * 0.35),
      ),
    );
  }

  Widget _themeRow(
    BuildContext context,
    Color fg,
    Color mid,
    Color bg,
    Color fgsignal,
    double side,
  ) {
    final bort = BortScope.of(context);
    final i18n = I18nScope.of(context);

    Widget toggle({
      required String id,
      required String helpKey,
      required String label,
      required bool value,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            HelpLabel(
              helpKey: helpKey,
              text: label,
              width: _labelW,
              style: TextStyle(color: fg),
            ),
            PultTick(
              id: id,
              value: value,
              binary: true,
              fg: fg,
              bg: bg,
              signal: fgsignal,
              overrideSize: side,
              onTap: onTap,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        toggle(
          id: 'theme_custom',
          helpKey: 'theme.custom',
          label: i18n.t('theme.custom'),
          value: bort.themeCustom,
          onTap: () => bort.setBool('theme_custom', !bort.themeCustom),
        ),
        toggle(
          id: 'theme_night',
          helpKey: 'theme.night',
          label: i18n.t('theme.night'),
          value: bort.themeNight,
          onTap: () => bort.setBool('theme_night', !bort.themeNight),
        ),
        toggle(
          id: 'theme_auto',
          helpKey: 'theme.auto',
          label: i18n.t('theme.auto'),
          value: bort.themeAuto,
          onTap: () => bort.setBool('theme_auto', !bort.themeAuto),
        ),
      ],
    );
  }

  Widget _colorRow(
    BuildContext context,
    String themeName,
    String role,
    Color fg,
    Color mid,
    Color bg,
    Color fgsignal,
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
            width: _labelW,
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
