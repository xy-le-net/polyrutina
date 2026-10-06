// ═══════════════════════════════════════════════════════════════════
// rubka_tab.dart — вкладка рубки.
//
// Три блока: оформление, интерфейс, данные. Свёрнуты по умолчанию,
// разворачиваются касанием заголовка. На широком экране блоки
// раскладываются бок о бок.
//
// Оформление. Тема (подпульт выбора), пять цветов действующей темы,
// десять коэффициентов размеров. Ключи не показываются: правка
// поля влечёт запись в журнал рода bort с ключом theme.<имя>.<роль>.
//
// Интерфейс. Масштаб, язык, подписи, предел столбцов мозаики.
//
// Данные. Размер журнала, перечитать, очистить (синхронизированные),
// удалить (всё), сброс (три кэша: борт, рутины, следы).
// Необратимые — с подтверждением.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../data/operational_layer.dart';
import '../data/journal_types.dart';
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

  // Числа с разрядами чрез пробел: 12345 -> "12 345".
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
  // Перечитать: полный пересбор всех слоёв из журнала.
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

  // Сброс: снимаются кэши всех трёх слоёв. Журнал не трогается.
  Future<void> _resetCache() async {
    final app = AppScope.of(context);
    await app.bort.resetCache();
    await app.routineLayer.resetAll();
    await app.traceLayer.resetAll();
    await app.reloadI18n();
    await _loadSize();
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

      final appearance = _block(
        title: i18n.t('block.appearance'),
        isOpen: bort.blockAppearance,
        onToggle: () => bort.setBool('block_appearance', !bort.blockAppearance),
        fg: fg,
        dim: dim,
        children: [
          _themeRow(context, fg, dim, bg, signal, side),
          _colorRow(context, 'bg', fg, dim, bg, signal, side),
          _colorRow(context, 'bgdim', fg, dim, bg, signal, side),
          _colorRow(context, 'dim', fg, dim, bg, signal, side),
          _colorRow(context, 'fg', fg, dim, bg, signal, side),
          _colorRow(context, 'signal', fg, dim, bg, signal, side),
          const SizedBox(height: 8),
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

  // Разрешённое имя действующей темы: ежели «system», берётся day
  // либо night по системной гамме; иначе — сама тема.
  String _resolvedThemeName(BuildContext context) {
    final bort = AppScope.of(context).bort;
    if (bort.themeName == 'system') {
      return bort.systemBrightness == Brightness.dark ? 'night' : 'day';
    }
    return bort.themeName;
  }

  // ─── Строка цвета ───
  // Показывает значение из действующей темы. Правка идёт в ту же тему
  // ключом theme.<имя>.<роль> и записывается в журнал.
  Widget _colorRow(
    BuildContext context,
    String role,
    Color fg,
    Color dim,
    Color bg,
    Color signal,
    double side,
  ) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    final name = _resolvedThemeName(context);
    final key = 'theme.$name.$role';
    final value = bort.allAsStrings[key] ?? '';
    final c = _parseColor(value) ?? Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(i18n.t('bort.$role'), style: TextStyle(color: fg)),
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
                    onCommit: (v) async {
                      await app.journal.log(
                        type: JournalType.bort,
                        body: '{"key":"$key","value":"$v"}',
                      );
                    },
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

  // ─── Строка коэффициента ───
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
              onCommit: (v) async {
                await app.journal.log(
                  type: JournalType.bort,
                  body: '{"key":"$key","value":"$v"}',
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── Строка прочей настройки ───
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

    // Запись значения в журнал рода bort.
    Future<void> commit(String v) async {
      await app.journal.log(
        type: JournalType.bort,
        body: '{"key":"$key","value":"$v"}',
      );
    }

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
              onTap: () => commit(!b ? 'true' : 'false'),
            ),
            fg: fg,
            bg: bg,
            signal: signal,
            overrideSize: side,
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
          onCommit: commit,
        );
    }
  }

  // ─── Строка выбора темы ───
  // Пульт с иконою текущей темы. Касание открывает подпульт со всеми
  // темами, кроме текущей.
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
                  // «system» первым.
                  if (bort.themeName != 'system') {
                    out.add(PultSpec(
                      id: 'theme_system',
                      icon: Icons.brightness_auto,
                      label: showLabels ? i18n.t('theme.system') : null,
                      onTap: () => app.journal.log(
                        type: JournalType.bort,
                        body: '{"key":"theme","value":"system"}',
                      ),
                    ));
                  }
                  for (final name in bort.themes.keys) {
                    if (name == bort.themeName) continue;
                    out.add(PultSpec(
                      id: 'theme_$name',
                      icon: Icons.palette_outlined,
                      label: showLabels ? name : null,
                      onTap: () => app.journal.log(
                        type: JournalType.bort,
                        body: '{"key":"theme","value":"$name"}',
                      ),
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
