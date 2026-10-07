// ═══════════════════════════════════════════════════════════════════
// rubka_tab.dart — вкладка рубки.
//
// Четыре блока: артель, оформление, интерфейс, данные.
//
// Блоки строятся единым Block (ui/block.dart): те же рамки,
// заголовок, значок свёртки в левом верхнем углу.
//
// Артель. Поле «полночь» (чч:мм).
//
// Оформление. Пульт выбора темы; обе темы разом; мягкий текст (dim)
// единый; десять коэффициентов размеров.
//
// Интерфейс. Масштаб, язык, подписи.
//
// Данные. Первою строкою — время борта (приглушённо). Далее счёт
// записей и объём. Пульты: перечитать, очистить, удалить, сброс.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../data/journal_types.dart';
import '../data/operational_layer.dart';
import 'app_scope.dart';
import 'block.dart';
import 'bort_field.dart';
import 'pult_core.dart';
import 'pult_tick.dart';

class RubkaTab extends StatefulWidget {
  const RubkaTab({super.key});

  @override
  State<RubkaTab> createState() => _RubkaTabState();
}

class _RubkaTabState extends State<RubkaTab> {
  @override
  void initState() {
    super.initState();
    // Данные берутся из слоёв при построении — перечитывать надобно
    // при открытии вкладки. Сие делается в didChangeDependencies.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Лёгкое уведомление: пересборка при входе на вкладку.
    // Счёт и объём берутся из полей journal — они всегда свежие.
  }

  String _fmtNum(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  // Время борта — «9ч 03м», «3д 5ч», «03м».
  String _fmtBortTime(int sec) {
    if (sec <= 0) return '0м';
    final days = sec ~/ 86400;
    final hours = (sec % 86400) ~/ 3600;
    final minutes = (sec % 3600) ~/ 60;
    String two(int n) => n.toString().padLeft(2, '0');
    if (days > 0) return '$daysд $hoursч';
    if (hours > 0) return '$hoursч ${two(minutes)}м';
    return '${two(minutes)}м';
  }

  Future<void> _reload() async {
    final app = AppScope.of(context);
    await app.journal.reread();
    await app.reloadI18n();
    if (mounted) setState(() {});
  }

  Future<void> _deleteSynced() async {
    final app = AppScope.of(context);
    await app.journal.deleteSynced();
    if (mounted) setState(() {});
  }

  Future<void> _deleteAll() async {
    final app = AppScope.of(context);
    await app.journal.clearAll();
    if (mounted) setState(() {});
  }

  Future<void> _resetCache() async {
    final app = AppScope.of(context);
    await app.bort.resetCache();
    await app.routineLayer.resetAll();
    await app.traceLayer.resetAll();
    await app.reloadI18n();
    if (mounted) setState(() {});
  }

  Future<void> _logBort(String key, String value) async {
    final app = AppScope.of(context);
    await app.journal.log(
      type: JournalType.bort,
      body: '{"key":"$key","value":"$value"}',
    );
  }

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

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 640;

        final artel = Block(
          title: i18n.t('block.artel'),
          collapsed: !bort.blockArtel,
          onToggleCollapsed: () =>
              _logBort('block_artel', (!bort.blockArtel).toString()),
          bg: bg,
          dim: dim,
          fg: fg,
          signal: signal,
          titleSize: titleSize,
          pad: pad,
          gap: gap,
          strokeW: strokeW,
          radiusW: radiusW,
          child: _midnightRow(context, fg, dim, bg, signal, side),
        );

        final appearance = Block(
          title: i18n.t('block.appearance'),
          collapsed: !bort.blockAppearance,
          onToggleCollapsed: () =>
              _logBort('block_appearance', (!bort.blockAppearance).toString()),
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
              _sectionTitle(i18n.t('theme.day'), dim, side),
              _colorRow(context, 'day', 'bg', fg, dim, bg, signal, side),
              _colorRow(context, 'day', 'bgdim', fg, dim, bg, signal, side),
              _colorRow(context, 'day', 'fg', fg, dim, bg, signal, side),
              _colorRow(context, 'day', 'signal', fg, dim, bg, signal, side),
              _sectionTitle(i18n.t('theme.night'), dim, side),
              _colorRow(context, 'night', 'bg', fg, dim, bg, signal, side),
              _colorRow(context, 'night', 'bgdim', fg, dim, bg, signal, side),
              _colorRow(context, 'night', 'fg', fg, dim, bg, signal, side),
              _colorRow(context, 'night', 'signal', fg, dim, bg, signal, side),
              _sectionTitle(i18n.t('bort.dim'), dim, side),
              _dimRow(context, fg, dim, bg, signal, side),
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
          ),
        );

        final interface = Block(
          title: i18n.t('block.interface'),
          collapsed: !bort.blockInterface,
          onToggleCollapsed: () =>
              _logBort('block_interface', (!bort.blockInterface).toString()),
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
              _settingRow(context, 'scale', fg, dim, bg, signal, side),
              _settingRow(context, 'lang', fg, dim, bg, signal, side),
              _settingRow(context, 'labels_system', fg, dim, bg, signal, side),
              _settingRow(context, 'labels_field', fg, dim, bg, signal, side),
            ],
          ),
        );

        final data = Block(
          title: i18n.t('block.data'),
          collapsed: !bort.blockData,
          onToggleCollapsed: () =>
              _logBort('block_data', (!bort.blockData).toString()),
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
              // Время борта — первою строкою, приглушённо.
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _fmtBortTime(bort.bortTime),
                  style: TextStyle(color: dim, fontSize: side * 0.35),
                ),
              ),
              // Счёт записей и объём.
              Row(
                children: [
                  SizedBox(
                    width: 140,
                    child: Text(
                      i18n.t('bort.journal'),
                      style: TextStyle(color: fg),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${_fmtNum(app.journal.entryCount)} '
                      '${i18n.t('bort.entries')}   '
                      '${_fmtNum(app.journal.entryBytes)} '
                      '${i18n.t('bort.bytes')}',
                      style: TextStyle(color: fg, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _pultRow(
                label: i18n.t('bort.reload'),
                fg: fg,
                pult: Pult(
                  spec: PultSpec(
                    id: 'reload',
                    icon: Icons.refresh,
                    confirm: true,
                    onTap: _reload,
                  ),
                  fg: fg,
                  bg: bg,
                  signal: signal,
                  overrideSize: side,
                ),
              ),
              const SizedBox(height: 12),
              _pultRow(
                label: i18n.t('bort.cleanup'),
                fg: fg,
                pult: Pult(
                  spec: PultSpec(
                    id: 'cleanup',
                    icon: Icons.cloud_done,
                    confirm: true,
                    onTap: _deleteSynced,
                  ),
                  fg: fg,
                  bg: bg,
                  signal: signal,
                  overrideSize: side,
                ),
              ),
              const SizedBox(height: 12),
              _pultRow(
                label: i18n.t('bort.delete'),
                fg: fg,
                pult: Pult(
                  spec: PultSpec(
                    id: 'delete',
                    icon: Icons.delete_outline,
                    confirm: true,
                    onTap: _deleteAll,
                  ),
                  fg: fg,
                  bg: bg,
                  signal: signal,
                  overrideSize: side,
                ),
              ),
              const SizedBox(height: 12),
              _pultRow(
                label: i18n.t('bort.reset'),
                fg: fg,
                pult: Pult(
                  spec: PultSpec(
                    id: 'reset',
                    icon: Icons.cleaning_services,
                    confirm: true,
                    onTap: _resetCache,
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

        if (wide) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 80, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Column(children: [artel, appearance, data])),
                const SizedBox(width: 24),
                Expanded(child: Column(children: [interface])),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 80, 16, 16),
          children: [artel, appearance, interface, data],
        );
      },
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

  Widget _pultRow({
    required String label,
    required Widget pult,
    required Color fg,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 140,
          child: Text(label, style: TextStyle(color: fg)),
        ),
        pult,
      ],
    );
  }

  Widget _midnightRow(
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
                await _logBort('midnight', v);
              },
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
    final c = _parseColor(value) ?? Colors.transparent;

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
                    onCommit: (v) => _logBort(key, v),
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

  Widget _dimRow(
    BuildContext context,
    Color fg,
    Color dim,
    Color bg,
    Color signal,
    double side,
  ) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final value = bort.allAsStrings['dim'] ?? '';
    final c = _parseColor(value) ?? Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const SizedBox(width: 140),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: BortField(
                    initial: value,
                    fg: fg,
                    readOnly: false,
                    onChanged: (v) => bort.setDraft('dim', v),
                    onCommit: (v) => _logBort('dim', v),
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
              onCommit: (v) => _logBort(key, v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingRow(
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
            onTap: () => _logBort(key, (!b).toString()),
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
          onCommit: (v) => _logBort(key, v),
        );
    }
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(i18n.t('bort.theme'), style: TextStyle(color: fg)),
          ),
          Expanded(
            child: Pult(
              spec: PultSpec(
                id: 'theme',
                icon: Icons.brightness_auto,
                subsBuilder: () {
                  final out = <PultSpec>[];
                  if (bort.themeName != 'system') {
                    out.add(
                      PultSpec(
                        id: 'theme_system',
                        icon: Icons.brightness_auto,
                        label: showLabels ? i18n.t('theme.system') : null,
                        onTap: () => _logBort('theme', 'system'),
                      ),
                    );
                  }
                  for (final name in bort.themes.keys) {
                    if (name == bort.themeName) continue;
                    out.add(
                      PultSpec(
                        id: 'theme_$name',
                        icon: Icons.palette_outlined,
                        label: showLabels ? name : null,
                        onTap: () => _logBort('theme', name),
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

  Color? _parseColor(String s) {
    var t = s.trim();
    if (t.startsWith('#')) t = t.substring(1);
    if (t.length != 6) return null;
    final v = int.tryParse(t, radix: 16);
    if (v == null) return null;
    return Color(0xFF000000 | v);
  }
}
