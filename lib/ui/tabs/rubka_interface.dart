// ═══════════════════════════════════════════════════════════════════
// rubka_interface.dart — «interface» block in the rubka.
//
// Extracted from rubka_tab.
//
// Scale, language, labels — one per row. Language — a human-readable
// dropdown (русский / english). Labels — the former «system labels»;
// «field labels» are abolished: button labels are unified. Slots —
// a checklist of five kinds: which slots to show permanently in the
// routine card.
//
// Simplifications: the unused `dim` parameter has been removed from
// all private methods (_langRow, _slotTicks, _settingRow,
// _settingField), since it was never used in their bodies.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/operational_layer.dart';
import '../core/app_scope.dart';
import '../core/bort_field.dart';
import '../pults/pult_core.dart';
import '../pults/pult_tick.dart';

class RubkaInterface extends StatelessWidget {
  final void Function(String key, String value) onSet;

  const RubkaInterface({super.key, required this.onSet});

  static const List<String> _slotKinds = [
    'prep',
    'transit',
    'work',
    'idle',
    'closeout',
  ];

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
        _settingRow(context, 'scale', fg, bg, signal, side),
        _langRow(context, fg, bg, signal, side),
        _settingRow(context, 'labels_buttons', fg, bg, signal, side),
        _sectionTitle(i18n.t('bort.default_slots'), dim, side),
        ..._slotTicks(context, fg, bg, signal, side),
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

  // ─── Language: dropdown ───
  Widget _langRow(
    BuildContext context,
    Color fg,
    Color bg,
    Color signal,
    double side,
  ) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;

    const langs = <(String, String)>[('ru', 'lang.ru'), ('en', 'lang.en')];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(i18n.t('bort.lang'), style: TextStyle(color: fg)),
          ),
          Expanded(
            child: Pult(
              spec: PultSpec(
                id: 'lang',
                icon: Icons.translate,
                label: i18n.t('lang.${bort.lang}'),
                subsBuilder: () {
                  final out = <PultSpec>[];
                  for (final l in langs) {
                    if (l.$1 == bort.lang) continue;
                    out.add(
                      PultSpec(
                        id: 'lang_${l.$1}',
                        icon: Icons.language,
                        label: i18n.t(l.$2),
                        onTap: () => onSet('lang', l.$1),
                      ),
                    );
                  }
                  return out;
                },
              ),
              fg: fg,
              bg: bg,
              signal: signal,
              overrideSize: side,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Default slots ───
  List<Widget> _slotTicks(
    BuildContext context,
    Color fg,
    Color bg,
    Color signal,
    double side,
  ) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    final out = <Widget>[];
    for (final k in _slotKinds) {
      final on = bort.defaultSlots.contains(k);
      out.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 140,
                child: Text(
                  i18n.t('routine.block.$k'),
                  style: TextStyle(color: fg),
                ),
              ),
              PultTick(
                id: 'slot_$k',
                value: on,
                binary: true,
                fg: fg,
                bg: bg,
                signal: signal,
                overrideSize: side,
                onTap: () => bort.setDefaultSlot(k, !on),
              ),
            ],
          ),
        ),
      );
    }
    return out;
  }

  Widget _settingRow(
    BuildContext context,
    String key,
    Color fg,
    Color bg,
    Color signal,
    double side,
  ) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    final type = OperationalLayer.settingTypes[key] ?? 'string';
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
            child: _settingField(
              context,
              key,
              type,
              value,
              fg,
              bg,
              signal,
              side,
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingField(
    BuildContext context,
    String key,
    String type,
    String value,
    Color fg,
    Color bg,
    Color signal,
    double side,
  ) {
    final app = AppScope.of(context);
    final bort = app.bort;

    switch (type) {
      case 'bool':
        final b = value == 'true';
        return Align(
          alignment: Alignment.centerLeft,
          child: PultTick(
            id: 'bool_$key',
            value: b,
            binary: true,
            fg: fg,
            bg: bg,
            signal: signal,
            overrideSize: side,
            onTap: () => onSet(key, (!b).toString()),
          ),
        );
      case 'theme':
      case 'string':
      default:
        return BortField(
          initial: value,
          fg: fg,
          readOnly: OperationalLayer.readOnlyKeys.contains(key),
          onChanged: (v) => bort.setDraft(key, v),
          onCommit: (v) async => onSet(key, v),
        );
    }
  }
}
