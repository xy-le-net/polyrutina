// ═══════════════════════════════════════════════════════════════════
// operational_layer.dart — оперативный слой («борт»).
//
// Состояние интерфейса: цвета действующей темы, коэффициенты размеров,
// язык, вкладка, якорь корневого пульта, черновики полей, признак
// «отправлено», метка первого запуска, смена.
//
// Цвета. Действующий набор — пять полей: bg, bgdim, dim, fg, signal.
// Виджеты читают их напрямую. Все темы (day, night и прочие) лежат
// в themes: имя → пятёрка цветов. Правится действующая тема; наборы
// прочих живут в файле. Имена тем произвольные; имя «system» означает
// выбор по системной гамме (day в светлой, night в тёмной).
//
// Журнал. Борт не ходит в базу сам: при пуске он регистрируется
// в JournalLayer на роды bort (настройки) и actor (смена). Записи
// приходят готовыми, применяются тотчас.
//
// Установка. Метка первого запуска — в install.json, не стирается
// при сбросе кэша.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database.dart';
import 'journal_layer.dart';
import 'journal_types.dart';

class OperationalLayer extends ChangeNotifier {
  // ─── Действующий набор цветов ───
  // Виджеты читают именно сии поля. Наполняются из themes при
  // смене темы либо при разрешении системной.
  Color bg = const Color(0xFFEFEFEF);
  Color bgdim = const Color(0xFFE4E4E4);
  Color dim = const Color(0xFF303030);
  Color fg = const Color(0xFF101010);
  Color signal = const Color(0xFF000000);

  // ─── Все темы ───
  // Имя → {bg, bgdim, dim, fg, signal}. Заполняется из defaults.json
  // при первом пуске и далее из рабочего файла.
  Map<String, Map<String, Color>> themes = {};

  // Имя действующей темы. «system» — особая: разрешается по системной
  // гамме в day либо night.
  String themeName = 'system';

  // Системная гамма, обновляется из main при её смене.
  Brightness systemBrightness = Brightness.light;

  // ─── Прочие настройки ───
  double scale = 1.4;
  String lang = 'ru';
  int tab = 4;
  String anchor = 'tl';
  bool labelsSystem = true;
  bool labelsField = true;
  bool blockAppearance = false;
  bool blockInterface = false;
  bool blockData = false;
  int selectedType = 4;
  int selectedFlags = 0;

  // ─── Коэффициенты размеров ───
  // Доли от базовой величины side.
  double kPult = 1.0;
  double kPultSmall = 0.8889;
  double kBlockGap = 0.2;
  double kFramePad = 0.375;
  double kTitle = 0.4;
  double kNumber = 0.4;
  double kNumberSmall = 0.3;
  double kName = 0.5;
  double kRadius = 0.3;
  double kStroke = 0.015;

  // ─── Смена ───
  bool onShift = false;
  int totalShiftSeconds = 0;
  int? shiftStartedAt;

  // ─── Черновики и признак «отправлено» ───
  // Ключ → текст. Ключи: "console", "trace_<id>_<slot>" и подобные.
  Map<String, String> drafts = {};
  // Ключ тот же: истина — текст в журнале и с тех пор не менялся.
  Map<String, bool> traceSent = {};

  // ─── Метка первого запуска ───
  // Время в секундах от начала эпохи Unix. Хранится в install.json,
  // не стирается при сбросе кэша.
  int firstRunUnixSec = 0;

  // ─── Служебное ───
  File? _file; // operational_layer.json
  File? _installFile; // install.json

  OperationalLayer();

  // ─── Пуск ───
  // Порядок: умолчания из assets, метка установки, рабочий файл,
  // регистрация в JournalLayer. Первое разрешение темы — по
  // сохранённому имени либо системной гамме.
  Future<void> init(JournalLayer journal, Brightness system) async {
    systemBrightness = system;
    final dir = await getApplicationDocumentsDirectory();
    _file = File(p.join(dir.path, 'operational_layer.json'));
    _installFile = File(p.join(dir.path, 'install.json'));
    await _loadDefaults();
    await _loadInstall();
    await _loadFromFile();
    _resolveTheme();

    // Регистрация: борт слушает свои настройки и записи смены.
    journal.register(
      name: 'bort',
      types: [JournalType.bort, JournalType.actor],
      apply: _applyEntry,
      reset: _resetMemory,
    );

    notifyListeners();
  }

  // ─── Метка первого запуска ───
  Future<void> _loadInstall() async {
    if (_installFile == null) return;
    try {
      if (await _installFile!.exists()) {
        final raw = await _installFile!.readAsString();
        final data = jsonDecode(raw) as Map<String, dynamic>;
        firstRunUnixSec = (data['first_run_unix_sec'] as num?)?.toInt() ?? 0;
      } else {
        firstRunUnixSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        await _installFile!.writeAsString(jsonEncode({
          'first_run_unix_sec': firstRunUnixSec,
        }));
      }
    } catch (_) {}
  }

  // ─── Умолчания из assets ───
  // Читает themes (map имя → пятёрка) и прочие поля. Ключи цветов
  // внутри темы: bg, bgdim, dim, fg, signal.
  Future<void> _loadDefaults() async {
    try {
      final raw = await rootBundle.loadString('assets/defaults.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final t = data['themes'];
      if (t is Map) {
        themes = {};
        for (final k in t.keys) {
          final v = t[k];
          if (v is Map) {
            themes[k.toString()] = {
              'bg': _parseColor(v['bg'] as String?) ?? bg,
              'bgdim': _parseColor(v['bgdim'] as String?) ?? bgdim,
              'dim': _parseColor(v['dim'] as String?) ?? dim,
              'fg': _parseColor(v['fg'] as String?) ?? fg,
              'signal': _parseColor(v['signal'] as String?) ?? signal,
            };
          }
        }
      }
      themeName = data['theme'] as String? ?? themeName;
      scale = (data['scale'] as num?)?.toDouble() ?? scale;
      lang = data['lang'] as String? ?? lang;
      tab = (data['tab'] as num?)?.toInt() ?? tab;
      anchor = data['anchor'] as String? ?? anchor;
      labelsSystem = data['labels_system'] as bool? ?? labelsSystem;
      labelsField = data['labels_field'] as bool? ?? labelsField;
      blockAppearance = data['block_appearance'] as bool? ?? blockAppearance;
      blockInterface = data['block_interface'] as bool? ?? blockInterface;
      blockData = data['block_data'] as bool? ?? blockData;
      selectedType = (data['selected_type'] as num?)?.toInt() ?? selectedType;
      selectedFlags =
          (data['selected_flags'] as num?)?.toInt() ?? selectedFlags;

      kPult = (data['k_pult'] as num?)?.toDouble() ?? kPult;
      kPultSmall = (data['k_pult_small'] as num?)?.toDouble() ?? kPultSmall;
      kBlockGap = (data['k_block_gap'] as num?)?.toDouble() ?? kBlockGap;
      kFramePad = (data['k_frame_pad'] as num?)?.toDouble() ?? kFramePad;
      kTitle = (data['k_title'] as num?)?.toDouble() ?? kTitle;
      kNumber = (data['k_number'] as num?)?.toDouble() ?? kNumber;
      kNumberSmall =
          (data['k_number_small'] as num?)?.toDouble() ?? kNumberSmall;
      kName = (data['k_name'] as num?)?.toDouble() ?? kName;
      kRadius = (data['k_radius'] as num?)?.toDouble() ?? kRadius;
      kStroke = (data['k_stroke'] as num?)?.toDouble() ?? kStroke;
    } catch (_) {
      // Умолчаний нет — работаем со встроенными.
    }
    if (themes.isEmpty) {
      themes = {
        'day': {
          'bg': const Color(0xFFEFEFEF),
          'bgdim': const Color(0xFFE4E4E4),
          'dim': const Color(0xFF303030),
          'fg': const Color(0xFF101010),
          'signal': const Color(0xFF000000),
        },
        'night': {
          'bg': const Color(0xFF101010),
          'bgdim': const Color(0xFF1C1C1C),
          'dim': const Color(0xFFCFCFCF),
          'fg': const Color(0xFFEFEFEF),
          'signal': const Color(0xFFFFFFFF),
        },
      };
    }
  }

  // ─── Рабочий файл ───
  Future<void> _loadFromFile() async {
    if (_file == null || !await _file!.exists()) return;
    try {
      final raw = await _file!.readAsString();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final t = data['themes'];
      if (t is Map) {
        themes = {};
        for (final k in t.keys) {
          final v = t[k];
          if (v is Map) {
            themes[k.toString()] = {
              'bg': _parseColor(v['bg'] as String?) ?? bg,
              'bgdim': _parseColor(v['bgdim'] as String?) ?? bgdim,
              'dim': _parseColor(v['dim'] as String?) ?? dim,
              'fg': _parseColor(v['fg'] as String?) ?? fg,
              'signal': _parseColor(v['signal'] as String?) ?? signal,
            };
          }
        }
      }
      themeName = data['theme'] as String? ?? themeName;
      scale = (data['scale'] as num?)?.toDouble() ?? scale;
      lang = data['lang'] as String? ?? lang;
      tab = (data['tab'] as num?)?.toInt() ?? tab;
      anchor = data['anchor'] as String? ?? anchor;
      labelsSystem = data['labels_system'] as bool? ?? labelsSystem;
      labelsField = data['labels_field'] as bool? ?? labelsField;
      blockAppearance = data['block_appearance'] as bool? ?? blockAppearance;
      blockInterface = data['block_interface'] as bool? ?? blockInterface;
      blockData = data['block_data'] as bool? ?? blockData;
      selectedType = (data['selected_type'] as num?)?.toInt() ?? selectedType;
      selectedFlags =
          (data['selected_flags'] as num?)?.toInt() ?? selectedFlags;
      onShift = data['on_shift'] as bool? ?? onShift;
      totalShiftSeconds =
          (data['total_shift_seconds'] as num?)?.toInt() ?? totalShiftSeconds;
      shiftStartedAt =
          (data['shift_started_at'] as num?)?.toInt() ?? shiftStartedAt;

      kPult = (data['k_pult'] as num?)?.toDouble() ?? kPult;
      kPultSmall = (data['k_pult_small'] as num?)?.toDouble() ?? kPultSmall;
      kBlockGap = (data['k_block_gap'] as num?)?.toDouble() ?? kBlockGap;
      kFramePad = (data['k_frame_pad'] as num?)?.toDouble() ?? kFramePad;
      kTitle = (data['k_title'] as num?)?.toDouble() ?? kTitle;
      kNumber = (data['k_number'] as num?)?.toDouble() ?? kNumber;
      kNumberSmall =
          (data['k_number_small'] as num?)?.toDouble() ?? kNumberSmall;
      kName = (data['k_name'] as num?)?.toDouble() ?? kName;
      kRadius = (data['k_radius'] as num?)?.toDouble() ?? kRadius;
      kStroke = (data['k_stroke'] as num?)?.toDouble() ?? kStroke;

      final d = data['drafts'];
      if (d is Map) {
        drafts = d.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
      final ts = data['trace_sent'];
      if (ts is Map) {
        traceSent = ts.map((k, v) => MapEntry(k.toString(), v == true));
      }
    } catch (_) {}
  }

  // ─── Разрешение темы ───
  // Ежели themeName == «system», берётся day (светло) либо night
  // (темно) по системной гамме. Иначе — набор с сим именем.
  void _resolveTheme() {
    String name = themeName;
    if (name == 'system') {
      name = systemBrightness == Brightness.dark ? 'night' : 'day';
    }
    final t = themes[name];
    if (t == null) return;
    bg = t['bg']!;
    bgdim = t['bgdim']!;
    dim = t['dim']!;
    fg = t['fg']!;
    signal = t['signal']!;
  }

  // Смена системной гаммы из main. Ежели тема системная, действующий
  // набор пересчитывается.
  void setSystemBrightness(Brightness b) {
    if (systemBrightness == b) return;
    systemBrightness = b;
    if (themeName == 'system') {
      _resolveTheme();
      notifyListeners();
    }
  }

  // ─── Применение записи журнала ───
  // Диспетчер по роду: bort — пары ключ-значение; actor — смена.
  void _applyEntry(JournalData e) {
    try {
      final data = jsonDecode(e.body) as Map<String, dynamic>;
      if (e.type == JournalType.bort) {
        final key = data['key'] as String?;
        if (key == null) return;
        _apply(key, data['value']?.toString() ?? '');
      } else if (e.type == JournalType.actor) {
        final action = data['action'] as String?;
        if (action == 'shift_start') {
          onShift = true;
          shiftStartedAt = e.time;
        } else if (action == 'shift_stop') {
          if (shiftStartedAt != null) {
            totalShiftSeconds += e.time - shiftStartedAt!;
          }
          onShift = false;
          shiftStartedAt = null;
        }
      }
    } catch (_) {}
  }

  // Полный сброс памяти (зовётся из JournalLayer.reread).
  void _resetMemory() {
    themes = {};
    themeName = 'system';
    onShift = false;
    totalShiftSeconds = 0;
    shiftStartedAt = null;
    notifyListeners();
  }

  // ─── Сброс кэша ───
  // Удаляет рабочий файл и сбрасывает память к умолчаниям.
  // Журнал и install.json не трогаются.
  Future<void> resetCache() async {
    if (_file != null && await _file!.exists()) {
      await _file!.delete();
    }
    _resetMemory();
    await _loadDefaults();
    _resolveTheme();
    await _saveToFile();
    notifyListeners();
  }

  Future<void> saveNow() async {
    await _saveToFile();
  }

  // ─── Установка значений ───
  // Ныне — токмо память. Запись в журнал делается вкладкой (рубкой)
  // чрез JournalLayer.log с родом bort. Метод _apply лишь применяет
  // значение к памяти, чтобы интерфейс отозвался тотчас.
  void set(String key, String value) {
    _apply(key, value);
    notifyListeners();
  }

  void setSilent(String key, String value) {
    _apply(key, value);
    notifyListeners();
  }

  void setBool(String key, bool v) {
    _apply(key, v ? 'true' : 'false');
    notifyListeners();
  }

  void setInt(String key, int v) {
    _apply(key, v.toString());
    notifyListeners();
  }

  // ─── Черновики ───
  void setDraft(String key, String text) {
    drafts[key] = text;
    traceSent.remove(key);
  }

  String draft(String key) => drafts[key] ?? '';

  void clearDraft(String key) {
    drafts.remove(key);
    traceSent.remove(key);
  }

  bool isTraceSent(String key) => traceSent[key] == true;

  void markTraceSent(String key) {
    traceSent[key] = true;
    notifyListeners();
  }

  static String traceDraftKey(int objectId, String slot) =>
      'trace_${objectId}_$slot';

  // ─── Смена ───
  void startShift() {
    if (onShift) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    onShift = true;
    shiftStartedAt = now;
    notifyListeners();
  }

  void stopShift() {
    if (!onShift) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (shiftStartedAt != null) {
      totalShiftSeconds += now - shiftStartedAt!;
    }
    onShift = false;
    shiftStartedAt = null;
    notifyListeners();
  }

  int get shiftSecondsNow {
    final base = totalShiftSeconds;
    if (shiftStartedAt == null) return base;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return base + (now - shiftStartedAt!);
  }

  // ─── Применение одного ключа ───
  // Ключи цветов: theme.<имя>.<роль>. Ключ theme — смена действующей
  // темы. Прочее — как было.
  void _apply(String key, String value) {
    // Цвет темы: theme.day.bg и подобные.
    if (key.startsWith('theme.') && key.split('.').length == 3) {
      final parts = key.split('.');
      final name = parts[1];
      final role = parts[2];
      final c = _parseColor(value);
      if (c == null) return;
      themes.putIfAbsent(
          name,
          () => {
                'bg': bg,
                'bgdim': bgdim,
                'dim': dim,
                'fg': fg,
                'signal': signal,
              });
      themes[name]![role] = c;
      // Ежели правится действующая тема — обновить набор.
      final resolved = themeName == 'system'
          ? (systemBrightness == Brightness.dark ? 'night' : 'day')
          : themeName;
      if (name == resolved) _resolveTheme();
      return;
    }

    switch (key) {
      case 'theme':
        themeName = value;
        _resolveTheme();
        break;
      case 'scale':
        scale = double.tryParse(value) ?? scale;
        break;
      case 'lang':
        lang = value;
        break;
      case 'tab':
        tab = int.tryParse(value) ?? tab;
        break;
      case 'anchor':
        anchor = value;
        break;
      case 'labels_system':
        labelsSystem = _parseBool(value) ?? labelsSystem;
        break;
      case 'labels_field':
        labelsField = _parseBool(value) ?? labelsField;
        break;
      case 'block_appearance':
        blockAppearance = _parseBool(value) ?? blockAppearance;
        break;
      case 'block_interface':
        blockInterface = _parseBool(value) ?? blockInterface;
        break;
      case 'block_data':
        blockData = _parseBool(value) ?? blockData;
        break;
      case 'selected_type':
        selectedType = int.tryParse(value) ?? selectedType;
        break;
      case 'selected_flags':
        selectedFlags = int.tryParse(value) ?? selectedFlags;
        break;
      case 'on_shift':
        onShift = _parseBool(value) ?? onShift;
        break;
      case 'k_pult':
        kPult = double.tryParse(value) ?? kPult;
        break;
      case 'k_pult_small':
        kPultSmall = double.tryParse(value) ?? kPultSmall;
        break;
      case 'k_block_gap':
        kBlockGap = double.tryParse(value) ?? kBlockGap;
        break;
      case 'k_frame_pad':
        kFramePad = double.tryParse(value) ?? kFramePad;
        break;
      case 'k_title':
        kTitle = double.tryParse(value) ?? kTitle;
        break;
      case 'k_number':
        kNumber = double.tryParse(value) ?? kNumber;
        break;
      case 'k_number_small':
        kNumberSmall = double.tryParse(value) ?? kNumberSmall;
        break;
      case 'k_name':
        kName = double.tryParse(value) ?? kName;
        break;
      case 'k_radius':
        kRadius = double.tryParse(value) ?? kRadius;
        break;
      case 'k_stroke':
        kStroke = double.tryParse(value) ?? kStroke;
        break;
    }
  }

  bool? _parseBool(String s) {
    final t = s.trim().toLowerCase();
    if (t == 'true' || t == '1' || t == 'yes') return true;
    if (t == 'false' || t == '0' || t == 'no') return false;
    return null;
  }

  Future<void> _saveToFile() async {
    if (_file == null) return;
    final themeOut = <String, dynamic>{};
    for (final e in themes.entries) {
      themeOut[e.key] = {
        'bg': colorToHex(e.value['bg']!),
        'bgdim': colorToHex(e.value['bgdim']!),
        'dim': colorToHex(e.value['dim']!),
        'fg': colorToHex(e.value['fg']!),
        'signal': colorToHex(e.value['signal']!),
      };
    }
    final data = <String, dynamic>{
      'themes': themeOut,
      'theme': themeName,
      'scale': scale,
      'lang': lang,
      'tab': tab,
      'anchor': anchor,
      'labels_system': labelsSystem,
      'labels_field': labelsField,
      'block_appearance': blockAppearance,
      'block_interface': blockInterface,
      'block_data': blockData,
      'selected_type': selectedType,
      'selected_flags': selectedFlags,
      'on_shift': onShift,
      'total_shift_seconds': totalShiftSeconds,
      'shift_started_at': shiftStartedAt,
      'k_pult': kPult,
      'k_pult_small': kPultSmall,
      'k_block_gap': kBlockGap,
      'k_frame_pad': kFramePad,
      'k_title': kTitle,
      'k_number': kNumber,
      'k_number_small': kNumberSmall,
      'k_name': kName,
      'k_radius': kRadius,
      'k_stroke': kStroke,
      'drafts': drafts,
      'trace_sent': traceSent,
    };
    await _file!.writeAsString(jsonEncode(data));
  }

  Color? _parseColor(String? s) {
    if (s == null) return null;
    var t = s.trim();
    if (t.startsWith('#')) t = t.substring(1);
    if (t.length != 6) return null;
    final v = int.tryParse(t, radix: 16);
    if (v == null) return null;
    return Color(0xFF000000 | v);
  }

  String colorToHex(Color c) {
    final r = (c.r * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (c.g * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (c.b * 255).round().toRadixString(16).padLeft(2, '0');
    return '#$r$g$b';
  }

  // ─── Инверсия пяти цветов ───
  // При наложении на сигнальный фон цвета обращаются попарно:
  //   фон (bg) ↔ сигнальный (signal);
  //   мягкий фон (bgdim) ↔ текст (fg);
  //   мягкий текст (dim) — не меняется.
  // Сим сигнальный блок читается: то, что было фоном, стало сигнальным,
  // а текст и мягкий фон поменялись местами, дабы сохранить различие.
  // Единое правило для всех, кто рисуется на сигнальном фоне
  // (плашка рутины, блок карточки, таймер, пульт).
  static Map<String, Color> invertOnSignal({
    required Color bg,
    required Color bgdim,
    required Color dim,
    required Color fg,
    required Color signal,
  }) {
    return {
      'bg': signal,
      'bgdim': fg,
      'dim': dim,
      'fg': bgdim,
      'signal': bg,
    };
  }

  // ─── Плоское представление для рубки ───
  // Цвета каждой темы — ключами вида theme.<имя>.<роль>.
  Map<String, String> get allAsStrings {
    final out = <String, String>{};
    for (final e in themes.entries) {
      out['theme.${e.key}.bg'] = colorToHex(e.value['bg']!);
      out['theme.${e.key}.bgdim'] = colorToHex(e.value['bgdim']!);
      out['theme.${e.key}.dim'] = colorToHex(e.value['dim']!);
      out['theme.${e.key}.fg'] = colorToHex(e.value['fg']!);
      out['theme.${e.key}.signal'] = colorToHex(e.value['signal']!);
    }
    out['theme'] = themeName;
    out['scale'] = scale.toStringAsFixed(2);
    out['lang'] = lang;
    out['labels_system'] = labelsSystem.toString();
    out['labels_field'] = labelsField.toString();
    out['k_pult'] = kPult.toStringAsFixed(4);
    out['k_pult_small'] = kPultSmall.toStringAsFixed(4);
    out['k_block_gap'] = kBlockGap.toStringAsFixed(4);
    out['k_frame_pad'] = kFramePad.toStringAsFixed(4);
    out['k_title'] = kTitle.toStringAsFixed(4);
    out['k_number'] = kNumber.toStringAsFixed(4);
    out['k_number_small'] = kNumberSmall.toStringAsFixed(4);
    out['k_name'] = kName.toStringAsFixed(4);
    out['k_radius'] = kRadius.toStringAsFixed(4);
    out['k_stroke'] = kStroke.toStringAsFixed(4);
    return out;
  }

  // Роды полей для рубки: как отображать (цвет, булево, строка, тема).
  static const Map<String, String> settingTypes = {
    'theme': 'theme',
    'scale': 'string',
    'lang': 'string',
    'labels_system': 'bool',
    'labels_field': 'bool',
    'k_pult': 'string',
    'k_pult_small': 'string',
    'k_block_gap': 'string',
    'k_frame_pad': 'string',
    'k_title': 'string',
    'k_number': 'string',
    'k_number_small': 'string',
    'k_name': 'string',
    'k_radius': 'string',
    'k_stroke': 'string',
  };

  static const Set<String> readOnlyKeys = {};
}
