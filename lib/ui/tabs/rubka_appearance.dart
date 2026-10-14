// ═══════════════════════════════════════════════════════════════════
// rubka_appearance.dart — блок «оформление» в рубке.
//
// Вынесен из rubka_tab.
//
// Тема. Четыре пульта рядом: как в системе, день, ночь, своя.
// Текущая — отмечена. Правка цветов — токмо у «своей». День и ночь
// вшиты, полей у них нет.
//
// «Своя»: пять цветов — bg, bgdim, dim, fg, signal. Умолчания —
// инклюзивные, различимы при дальтонизме.
//
// Коэффициенты размеров: десять полей.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/theme_store.dart';
import '../core/app_scope.dart';
import '../core/bort_field.dart';
import '../pults/pult_core.dart';

class RubkaAppearance extends StatelessWidget {
  final void Function(String key, String value) onSet;

  const RubkaAppearance({super.key, required this.onSet});

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _themeRow(context, fg, dim, bg, signal, side),
        _sectionTitle(i18n.t('theme.custom'), dim, side),
        _colorRow(context, 'custom', 'bg', fg, dim, bg, signal, side),
        _colorRow(context, 'custom', 'bgdim', fg, dim, bg, signal, side),
        _colorRow(context, 'custom', 'dim', fg, dim, bg, signal, side),
        _colorRow(context, 'custom', 'fg', fg, dim, bg, signal, side),
        _colorRow(context, 'custom', 'signal', fg, dim, bg, signal, side),
        _sectionTitle(i18n.t('block.appearance'), dim, side),
        _kRow(context, 'k_pult', fg, dim, bg, signal, side),
        _kRow(context, 'k_pult_small', fg, dim, bg, signal, side),
        _kRow(context, 'k_block_gap', fg, dim, bg, signal, side),
        _kRow(context, 'k_frame_pad', fg, dim, bg, signal, side),
        _kRow(context, 'k_title', fg, dim, bg, signal, side),
        _kRow(context, 'k_number', fg, dim, bg, signal, side),
        _kRow(context, 'k_number_small', fg, dim, bg, signal, side),
        _kRow(context, 'k_name', fg, dim, bg, signal, side),
        _kRow(context, 'k_radius', fg, dim, bg, signal, side),
        _kRow(context, 'k_stroke', fg, dim, bg, signal, side),
      ],
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
    final showLabels = bort.labelsSystem;

    final current = bort.themeName;
    final options = <(String, String, IconData)>[
      ('system', 'theme.system', Icons.brightness_auto),
      ('day', 'theme.day', Icons.light_mode),
      ('night', 'theme.night', Icons.dark_mode),
      ('custom', 'theme.custom', Icons.palette_outlined),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
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
                for (final o in options)
                  Pult(
                    spec: PultSpec(
                      id: 'theme_${o.$1}',
                      icon: o.$3,
                      label: showLabels ? i18n.t(o.$2) : null,
                      selected: current == o.$1,
                      onTap: () => onSet('theme', o.$1),
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
                    onCommit: (v) async => onSet(key, v),
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

  Widget _kRow(
    BuildContext context,
    String key,
    Color fg,
    Color dim,
    Color bg,
    Color signal,
    double side,
  ) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    final value = bort.allAsStrings[key] ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(i18n.t('bort.$key'), style: TextStyle(color: fg)),
          ),
          Expanded(
            child: BortField(
              initial: value,
              fg: fg,
              readOnly: false,
              onChanged: (v) => bort.setDraft(key, v),
              onCommit: (v) async => onSet(key, v),
            ),
          ),
        ],
      ),
    );
  }
}
