// ═══════════════════════════════════════════════════════════════════
// operational_layer.dart — оперативный слой («борт»).
//
// Держит всё состояние интерфейса: цвета, масштаб, язык, вкладку,
// якорь, тумблеры подписей, тему, блоки рубки, выбор рода и флагов,
// черновики полей, сигнальные цвета.
//
// Умолчания — в assets/defaults.json.
// Рабочие настройки — в operational_layer.json.
// Сохранение — при сворачивании или закрытии приложения (saveNow).
// ═══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'journal_repository.dart';

class OperationalLayer extends ChangeNotifier {
  // ─── Умолчания ───
  Color _defBgDay = const Color(0xFFEFEFEF);
  Color _defBgNight = const Color(0xFF101010);
  Color _defFgDay = const Color(0xFF101010);
  Color _defFgNight = const Color(0xFFEFEFEF);
  Color _defDimDay = const Color(0xFF303030);
  Color _defDimNight = const Color(0xFFCFCFCF);
  Color _defSignalDay = const Color(0xFF000000);
  Color _defSignalNight = const Color(0xFFFFFFFF);
  String _defTheme = 'system';
  double _defScale = 1.4;
  String _defLang = 'ru';
  int _defTab = 4;
  String _defAnchor = 'tl';
  bool _defLabelsSystem = true;
  bool _defLabelsField = true;
  bool _defBlockAppearance = false;
  bool _defBlockInterface = false;
  bool _defBlockData = false;
  int _defSelectedType = 4;
  int _defSelectedFlags = 0;

  // ─── Текущие значения ───
  Color bgDay = const Color(0xFFEFEFEF);
  Color bgNight = const Color(0xFF101010);
  Color fgDay = const Color(0xFF101010);
  Color fgNight = const Color(0xFFEFEFEF);
  Color dimDay = const Color(0xFF303030);
  Color dimNight = const Color(0xFFCFCFCF);
  Color signalDay = const Color(0xFF000000);
  Color signalNight = const Color(0xFFFFFFFF);
  String theme = 'system';
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

  // Черновики: ключ настройки → текст, ещё не поданный.
  Map<String, String> drafts = {};

  JournalRepository? _journal;
  int _lastAppliedId = 0;
  File? _file;

  OperationalLayer();

  Future<void> init(JournalRepository journal) async {
    _journal = journal;
    await _loadDefaults();
    final dir = await getApplicationDocumentsDirectory();
    _file = File(p.join(dir.path, 'operational_layer.json'));
    await _loadFromFile();
    await applyJournalDeltas();
    notifyListeners();
  }

  Future<void> _loadDefaults() async {
    try {
      final raw = await rootBundle.loadString('assets/defaults.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _defBgDay = _parseColor(data['bg_day'] as String?) ?? _defBgDay;
      _defBgNight = _parseColor(data['bg_night'] as String?) ?? _defBgNight;
      _defFgDay = _parseColor(data['fg_day'] as String?) ?? _defFgDay;
      _defFgNight = _parseColor(data['fg_night'] as String?) ?? _defFgNight;
      _defDimDay = _parseColor(data['dim_day'] as String?) ?? _defDimDay;
      _defDimNight = _parseColor(data['dim_night'] as String?) ?? _defDimNight;
      _defSignalDay =
          _parseColor(data['signal_day'] as String?) ?? _defSignalDay;
      _defSignalNight =
          _parseColor(data['signal_night'] as String?) ?? _defSignalNight;
      _defTheme = data['theme'] as String? ?? _defTheme;
      _defScale = (data['scale'] as num?)?.toDouble() ?? _defScale;
      _defLang = data['lang'] as String? ?? _defLang;
      _defTab = (data['tab'] as num?)?.toInt() ?? _defTab;
      _defAnchor = data['anchor'] as String? ?? _defAnchor;
      _defLabelsSystem = data['labels_system'] as bool? ?? _defLabelsSystem;
      _defLabelsField = data['labels_field'] as bool? ?? _defLabelsField;
      _defBlockAppearance =
          data['block_appearance'] as bool? ?? _defBlockAppearance;
      _defBlockInterface =
          data['block_interface'] as bool? ?? _defBlockInterface;
      _defBlockData = data['block_data'] as bool? ?? _defBlockData;
      _defSelectedType =
          (data['selected_type'] as num?)?.toInt() ?? _defSelectedType;
      _defSelectedFlags =
          (data['selected_flags'] as num?)?.toInt() ?? _defSelectedFlags;
    } catch (_) {}
    _resetToDefaultsInMemory();
  }

  void _resetToDefaultsInMemory() {
    bgDay = _defBgDay;
    bgNight = _defBgNight;
    fgDay = _defFgDay;
    fgNight = _defFgNight;
    dimDay = _defDimDay;
    dimNight = _defDimNight;
    signalDay = _defSignalDay;
    signalNight = _defSignalNight;
    theme = _defTheme;
    scale = _defScale;
    lang = _defLang;
    tab = _defTab;
    anchor = _defAnchor;
    labelsSystem = _defLabelsSystem;
    labelsField = _defLabelsField;
    blockAppearance = _defBlockAppearance;
    blockInterface = _defBlockInterface;
    blockData = _defBlockData;
    selectedType = _defSelectedType;
    selectedFlags = _defSelectedFlags;
    drafts = {};
  }

  Future<void> _loadFromFile() async {
    if (_file == null || !await _file!.exists()) return;
    try {
      final raw = await _file!.readAsString();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      bgDay = _parseColor(data['bg_day'] as String?) ?? bgDay;
      bgNight = _parseColor(data['bg_night'] as String?) ?? bgNight;
      fgDay = _parseColor(data['fg_day'] as String?) ?? fgDay;
      fgNight = _parseColor(data['fg_night'] as String?) ?? fgNight;
      dimDay = _parseColor(data['dim_day'] as String?) ?? dimDay;
      dimNight = _parseColor(data['dim_night'] as String?) ?? dimNight;
      signalDay = _parseColor(data['signal_day'] as String?) ?? signalDay;
      signalNight = _parseColor(data['signal_night'] as String?) ?? signalNight;
      theme = data['theme'] as String? ?? theme;
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
      final d = data['drafts'];
      if (d is Map) {
        drafts = d.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
      _lastAppliedId = (data['last_id'] as num?)?.toInt() ?? 0;
    } catch (_) {}
  }

  Future<void> applyJournalDeltas() async {
    if (_journal == null) return;
    final entries = await _journal!.entriesAfter(
      _lastAppliedId,
      type: JournalType.bort,
    );
    if (entries.isEmpty) return;
    for (final e in entries) {
      _applyBody(e.body);
      _lastAppliedId = e.id;
    }
    await saveNow();
    notifyListeners();
  }

  void _applyBody(String body) {
    final key = _extract(body, 'key');
    final value = _extract(body, 'value');
    if (key == null) return;
    _apply(key, value ?? '');
  }

  Future<void> saveNow() async {
    await _saveToFile();
  }

  Future<void> resetToDefaults() async {
    if (_file != null && await _file!.exists()) {
      await _file!.delete();
    }
    _resetToDefaultsInMemory();
    if (_journal != null) {
      final last = await _journal!.recent(limit: 1);
      if (last.isNotEmpty) _lastAppliedId = last.first.id;
    }
    await _saveToFile();
    notifyListeners();
  }

  Future<void> set(String key, String value) async {
    _apply(key, value);
    notifyListeners();
  }

  Future<void> setSilent(String key, String value) async {
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

  void setDraft(String key, String text) {
    drafts[key] = text;
  }

  String draft(String key) => drafts[key] ?? '';

  void clearDraft(String key) {
    drafts.remove(key);
  }

  void _apply(String key, String value) {
    switch (key) {
      case 'bg_day':
        bgDay = _parseColor(value) ?? bgDay;
        break;
      case 'bg_night':
        bgNight = _parseColor(value) ?? bgNight;
        break;
      case 'fg_day':
        fgDay = _parseColor(value) ?? fgDay;
        break;
      case 'fg_night':
        fgNight = _parseColor(value) ?? fgNight;
        break;
      case 'dim_day':
        dimDay = _parseColor(value) ?? dimDay;
        break;
      case 'dim_night':
        dimNight = _parseColor(value) ?? dimNight;
        break;
      case 'signal_day':
        signalDay = _parseColor(value) ?? signalDay;
        break;
      case 'signal_night':
        signalNight = _parseColor(value) ?? signalNight;
        break;
      case 'theme':
        theme = value;
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
    final data = <String, dynamic>{
      'bg_day': colorToHex(bgDay),
      'bg_night': colorToHex(bgNight),
      'fg_day': colorToHex(fgDay),
      'fg_night': colorToHex(fgNight),
      'dim_day': colorToHex(dimDay),
      'dim_night': colorToHex(dimNight),
      'signal_day': colorToHex(signalDay),
      'signal_night': colorToHex(signalNight),
      'theme': theme,
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
      'drafts': drafts,
      'last_id': _lastAppliedId,
    };
    await _file!.writeAsString(jsonEncode(data));
  }

  String? _extract(String body, String field) {
    final re = RegExp('"$field"\\s*:\\s*"([^"]*)"');
    return re.firstMatch(body)?.group(1);
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

  Brightness effectiveBrightness(Brightness system) {
    switch (theme) {
      case 'dark':
        return Brightness.dark;
      case 'light':
        return Brightness.light;
      case 'system':
      default:
        return system;
    }
  }

  Color currentBg(Brightness b) => b == Brightness.dark ? bgNight : bgDay;
  Color currentFg(Brightness b) => b == Brightness.dark ? fgNight : fgDay;
  Color currentDim(Brightness b) => b == Brightness.dark ? dimNight : dimDay;
  Color currentSignal(Brightness b) =>
      b == Brightness.dark ? signalNight : signalDay;

  Map<String, String> get allAsStrings => {
        'bg_day': colorToHex(bgDay),
        'bg_night': colorToHex(bgNight),
        'fg_day': colorToHex(fgDay),
        'fg_night': colorToHex(fgNight),
        'dim_day': colorToHex(dimDay),
        'dim_night': colorToHex(dimNight),
        'signal_day': colorToHex(signalDay),
        'signal_night': colorToHex(signalNight),
        'theme': theme,
        'scale': scale.toStringAsFixed(2),
        'lang': lang,
        'labels_system': labelsSystem.toString(),
        'labels_field': labelsField.toString(),
      };

  static const Map<String, String> settingTypes = {
    'bg_day': 'color',
    'bg_night': 'color',
    'fg_day': 'color',
    'fg_night': 'color',
    'dim_day': 'color',
    'dim_night': 'color',
    'signal_day': 'color',
    'signal_night': 'color',
    'theme': 'theme',
    'scale': 'string',
    'lang': 'string',
    'labels_system': 'bool',
    'labels_field': 'bool',
  };

  static const Set<String> readOnlyKeys = {};
}
