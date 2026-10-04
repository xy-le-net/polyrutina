// ═══════════════════════════════════════════════════════════════════
// rubka_tab.dart — вкладка рубки.
//
// Три блока: оформление, интерфейс, данные. Свёрнуты по умолчанию,
// разворачиваются по касанию заголовка. На широком экране блоки
// раскладываются бок о бок.
//
// Блок данных: размер журнала, перечитать, очистить (синхронизированные),
// удалить (всё), сброс (борт). Необратимые — с подтверждением.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../data/operational_layer.dart';
import 'app_scope.dart';
import 'bort_field.dart';
import 'pult.dart';

class RubkaTab extends StatefulWidget {
  const RubkaTab({super.key});

  @override
  State<RubkaTab> createState() => _RubkaTabState();
}

class _RubkaTabState extends State<RubkaTab> {
  int _count = 0;
  int _bytes = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSize());
  }

  Future<void> _loadSize() async {
    final app = AppScope.of(context);
    final sz = await app.journal.size();
    if (mounted) {
      setState(() {
        _count = sz.count;
        _bytes = sz.bytes;
      });
    }
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

  // ─── Обработчики данных ───
  Future<void> _reload() async {
    final app = AppScope.of(context);
    await app.bort.reloadFromJournal();
    await app.reloadI18n();
    await _loadSize();
  }

  Future<void> _deleteSynced() async {
    final app = AppScope.of(context);
    await app.journal.deleteSynced();
    await _loadSize();
  }

  Future<void> _deleteAll() async {
    final app = AppScope.of(context);
    await app.journal.clearAll();
    await _loadSize();
  }

  Future<void> _resetCache() async {
    final app = AppScope.of(context);
    await app.bort.resetCache();
    await app.routineLayer.resetAll();
    await app.reloadI18n();
    await _loadSize();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    final brightness = Theme.of(context).brightness;
    final fg = bort.currentFg(brightness);
    final dim = bort.currentDim(brightness);
    final bg = bort.currentBg(brightness);
    final signal = bort.currentSignal(brightness);
    final side = PultScope.of(context).smallSide;

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth > 640;

      final appearance = _block(
        title: i18n.t('block.appearance'),
        isOpen: bort.blockAppearance,
        onToggle: () => bort.setBool('block_appearance', !bort.blockAppearance),
        fg: fg,
        dim: dim,
        children: [
          _themeRow(context, fg, dim, bg, signal, side),
          _settingRow(context, 'bg_day', fg, dim, bg, signal, side),
          _settingRow(context, 'bg_night', fg, dim, bg, signal, side),
          _settingRow(context, 'fg_day', fg, dim, bg, signal, side),
          _settingRow(context, 'fg_night', fg, dim, bg, signal, side),
          _settingRow(context, 'dim_day', fg, dim, bg, signal, side),
          _settingRow(context, 'dim_night', fg, dim, bg, signal, side),
          _settingRow(context, 'signal_day', fg, dim, bg, signal, side),
          _settingRow(context, 'signal_night', fg, dim, bg, signal, side),
        ],
      );

      final interface = _block(
        title: i18n.t('block.interface'),
        isOpen: bort.blockInterface,
        onToggle: () => bort.setBool('block_interface', !bort.blockInterface),
        fg: fg,
        dim: dim,
        children: [
          _settingRow(context, 'scale', fg, dim, bg, signal, side),
          _settingRow(context, 'lang', fg, dim, bg, signal, side),
          _settingRow(context, 'labels_system', fg, dim, bg, signal, side),
          _settingRow(context, 'labels_field', fg, dim, bg, signal, side),
        ],
      );

      final data = _block(
        title: i18n.t('block.data'),
        isOpen: bort.blockData,
        onToggle: () => bort.setBool('block_data', !bort.blockData),
        fg: fg,
        dim: dim,
        children: [
          Row(
            children: [
              SizedBox(
                width: 140,
                child:
                    Text(i18n.t('bort.journal'), style: TextStyle(color: fg)),
              ),
              Expanded(
                child: Text(
                  '${_fmtNum(_count)} ${i18n.t('bort.entries')}   '
                  '${_fmtNum(_bytes)} ${i18n.t('bort.bytes')}',
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
      );

      if (wide) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 80, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Column(children: [appearance, data])),
              const SizedBox(width: 24),
              Expanded(child: Column(children: [interface])),
            ],
          ),
        );
      }

      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 80, 16, 16),
        children: [appearance, interface, data],
      );
    });
  }

  // ─── Блок ───
  Widget _block({
    required String title,
    required bool isOpen,
    required VoidCallback onToggle,
    required List<Widget> children,
    required Color fg,
    required Color dim,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: dim),
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: dim,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      isOpen ? Icons.expand_less : Icons.expand_more,
                      color: dim,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            if (isOpen) ...[
              const SizedBox(height: 8),
              ...children,
            ],
          ],
        ),
      ),
    );
  }

  // ─── Строка пульта с подписью ───
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

  // ─── Строка настройки борта ───
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i18n.t('bort.$key'), style: TextStyle(color: fg)),
                Text(key, style: TextStyle(color: dim, fontSize: 11)),
              ],
            ),
          ),
          Expanded(
            child:
                _settingField(context, key, type, value, fg, bg, signal, side),
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
          child: Pult(
            spec: PultSpec(
              id: 'bool_$key',
              icon: b ? Icons.check : Icons.circle_outlined,
              selected: b,
              onTap: () => bort.setBool(key, !b),
            ),
            fg: fg,
            bg: bg,
            signal: signal,
            overrideSize: side,
          ),
        );
      case 'color':
        final c = _parseColor(value) ?? Colors.transparent;
        return Row(
          children: [
            Expanded(
              child: BortField(
                initial: value,
                fg: fg,
                readOnly: false,
                onChanged: (v) => bort.setDraft(key, v),
                onCommit: (v) => bort.set(key, v),
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
        );
      case 'string':
      default:
        return BortField(
          initial: value,
          fg: fg,
          readOnly: OperationalLayer.readOnlyKeys.contains(key),
          onChanged: (v) => bort.setDraft(key, v),
          onCommit: (v) => bort.set(key, v),
        );
    }
  }

  // ─── Строка выбора темы ───
  Widget _themeRow(BuildContext context, Color fg, Color dim, Color bg,
      Color signal, double side) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;

    const allOptions = ['system', 'dark', 'light'];
    const labelKeys = {
      'system': 'theme.system',
      'dark': 'theme.dark',
      'light': 'theme.light',
    };
    const icons = {
      'system': Icons.brightness_auto,
      'dark': Icons.dark_mode,
      'light': Icons.light_mode,
    };

    final current = bort.theme;
    final showLabels = bort.labelsSystem;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i18n.t('bort.theme'), style: TextStyle(color: fg)),
                Text('theme', style: TextStyle(color: dim, fontSize: 11)),
              ],
            ),
          ),
          Expanded(
            child: Pult(
              spec: PultSpec(
                id: 'theme',
                icon: icons[current] ?? Icons.brightness_auto,
                subsBuilder: () {
                  // Текущая тема не дублируется.
                  return allOptions.where((o) => o != current).map((o) {
                    return PultSpec(
                      id: 'theme_$o',
                      icon: icons[o]!,
                      label: showLabels ? i18n.t(labelKeys[o]!) : null,
                      onTap: () => bort.setSilent('theme', o),
                    );
                  }).toList();
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
