// ═══════════════════════════════════════════════════════════════════
// rubka_tab.dart — вкладка рубки.
//
// Четыре блока: артель, оформление, интерфейс, данные.
//
// Артель. Поле «полночь» (чч:мм) для сброса смены.
//
// Оформление. Пульт выбора темы; обе темы разом для правки —
// дневная (четыре роли) и ночная (четыре роли); мягкий текст (dim)
// единый, вне тем; десять коэффициентов размеров.
//
// Интерфейс. Масштаб, язык, подписи.
//
// Данные. Размер журнала, перечитать, очистить, удалить, сброс.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../data/journal_types.dart';
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

  Future<void> _reload() async {
    final app = AppScope.of(context);
    await app.journal.reread();
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
    await app.traceLayer.resetAll();
    await app.reloadI18n();
    await _loadSize();
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

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth > 640;

      final artel = _block(
        title: i18n.t('block.artel'),
        isOpen: bort.blockArtel,
        onToggle: () => _logBort('block_artel', (!bort.blockArtel).toString()),
        fg: fg,
        dim: dim,
        children: [
          _midnightRow(context, fg, dim, bg, signal, side),
        ],
      );

      final appearance = _block(
        title: i18n.t('block.appearance'),
        isOpen: bort.blockAppearance,
        onToggle: () =>
            _logBort('block_appearance', (!bort.blockAppearance).toString()),
        fg: fg,
        dim: dim,
        children: [
          _themeRow(context, fg, dim, bg, signal, side),
          const SizedBox(height: 8),
          _sectionTitle(i18n.t('theme.day'), dim, side),
          _colorRow(context, 'day', 'bg', fg, dim, bg, signal, side),
          _colorRow(context, 'day', 'bgdim', fg, dim, bg, signal, side),
          _colorRow(context, 'day', 'fg', fg, dim, bg, signal, side),
          _colorRow(context, 'day', 'signal', fg, dim, bg, signal, side),
          const SizedBox(height: 8),
          _sectionTitle(i18n.t('theme.night'), dim, side),
          _colorRow(context, 'night', 'bg', fg, dim, bg, signal, side),
          _colorRow(context, 'night', 'bgdim', fg, dim, bg, signal, side),
          _colorRow(context, 'night', 'fg', fg, dim, bg, signal, side),
          _colorRow(context, 'night', 'signal', fg, dim, bg, signal, side),
          const SizedBox(height: 8),
          _sectionTitle(i18n.t('bort.dim'), dim, side),
          _dimRow(context, fg, dim, bg, signal, side),
          const SizedBox(height: 12),
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

      final interface = _block(
        title: i18n.t('block.interface'),
        isOpen: bort.blockInterface,
        onToggle: () =>
            _logBort('block_interface', (!bort.blockInterface).toString()),
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
        onToggle: () => _logBort('block_data', (!bort.blockData).toString()),
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
    });
  }

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

  Widget _midnightRow(BuildContext context, Color fg, Color dim, Color bg,
      Color signal, double side) {
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

  Widget _dimRow(BuildContext context, Color fg, Color dim, Color bg,
      Color signal, double side) {
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

  Widget _themeRow(BuildContext context, Color fg, Color dim, Color bg,
      Color signal, double side) {
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
                    out.add(PultSpec(
                      id: 'theme_system',
                      icon: Icons.brightness_auto,
                      label: showLabels ? i18n.t('theme.system') : null,
                      onTap: () => _logBort('theme', 'system'),
                    ));
                  }
                  for (final name in bort.themes.keys) {
                    if (name == bort.themeName) continue;
                    out.add(PultSpec(
                      id: 'theme_$name',
                      icon: Icons.palette_outlined,
                      label: showLabels ? name : null,
                      onTap: () => _logBort('theme', name),
                    ));
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
