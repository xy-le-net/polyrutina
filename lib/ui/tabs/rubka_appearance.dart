// ═══════════════════════════════════════════════════════════════════
// lib/ui/tabs/rubka_appearance.dart — «appearance» block in the rubka.
//
// Three theme toggles replace the former five-theme row:
//   — «custom»: use the custom palette, overriding day/night;
//   — «day»: true selects day, false selects night;
//   — «autoswitch»: follow the system brightness.
//
// The custom role editor is shown only when the custom palette is
// enabled; otherwise it is hidden, so the block stays compact.
//
// Scopes. Dependencies are read from point scopes: BortScope (theme
// flags, labels flag, per-theme colors) and I18nScope (strings).
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/theme_store.dart';
import '../core/app_scope.dart';
import '../core/block.dart';
import '../core/bort_field.dart';
import '../pults/pult_core.dart';
import '../pults/pult_tick.dart';

class RubkaAppearance extends StatelessWidget {
  // Stable parity for the rubka block frame.
  final int parity;

  const RubkaAppearance({super.key, this.parity = 1});

  // Roles in the ladder order: bgsignal → bg → mid → fg → fgsignal.
  static const List<String> _roles = [
    'bgsignal',
    'bg',
    'mid',
    'fg',
    'fgsignal',
  ];

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
      child: Text(
        text,
        style: TextStyle(color: mid, fontSize: side * 0.35),
      ),
    );
  }

  // ─── Three theme toggles ───
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
      required String label,
      required bool value,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 140,
              child: Text(label, style: TextStyle(color: fg)),
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
          label: i18n.t('theme.custom'),
          value: bort.themeCustom,
          onTap: () => bort.setBool('theme_custom', !bort.themeCustom),
        ),
        toggle(
          id: 'theme_day',
          label: i18n.t('theme.day'),
          value: bort.themeDay,
          onTap: () => bort.setBool('theme_day', !bort.themeDay),
        ),
        toggle(
          id: 'theme_autoswitch',
          label: i18n.t('theme.autoswitch'),
          value: bort.themeAutoswitch,
          onTap: () => bort.setBool('theme_autoswitch', !bort.themeAutoswitch),
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
