// ═══════════════════════════════════════════════════════════════════
// operational_layer.dart — оперативный слой («борт»).
//
// Назначение: держать всё, что относится к состоянию интерфейса,
// а не к данным рутин и не к журналу. Здесь цвета, размеры, тема,
// язык, якорь корневого пульта, режим смены, черновики полей.
//
// Принцип: прозрачность не применяется нигде — ни в настройках,
// ни в коде. Всякий полутон задаётся отдельным цветом. Сие
// устраняет наложение с альфою и упрощает отрисовку.
//
// Цвета: двенадцать ролей — по шесть на дневную гамму и шесть
// на ночную. Роли:
//   bg      — фон страниц и полей;
//   fg      — основной текст, знаки, ядро пультов;
//   dim     — приглушённый текст, обводки рамок, подписи единиц;
//   signal  — сигнальный цвет: идущий блок, выбранный пульт;
//   bgdim   — фон второстепенного блока (переходы в карточке);
//   bgsel   — фон подсвеченной строки (плашка рутины в списке).
//
// Размеры: все интерфейсные величины — производные от базовой
// величины (малый размер пульта). Коэффициенты хранятся здесь
// и правятся чрез рубку. Сим достигается единый подход: правка
// одного коэффициента меняет согласованно весь вид.
// ═══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'journal_repository.dart';

class OperationalLayer extends ChangeNotifier {
  // ─── Умолчания: цвета ───
  // Сии значения берутся из assets/defaults.json при первом запуске.
  // Коли файла нет либо он повреждён — остаются сии, встроенные.
  Color _defBgDay = const Color(0xFFEFEFEF);
  Color _defBgNight = const Color(0xFF101010);
  Color _defFgDay = const Color(0xFF101010);
  Color _defFgNight = const Color(0xFFEFEFEF);
  Color _defDimDay = const Color(0xFF303030);
  Color _defDimNight = const Color(0xFFCFCFCF);
  Color _defSignalDay = const Color(0xFF000000);
  Color _defSignalNight = const Color(0xFFFFFFFF);
  Color _defBgDimDay = const Color(0xFFE4E4E4);
  Color _defBgDimNight = const Color(0xFF1C1C1C);
  Color _defBgSelDay = const Color(0xFFE8E8E8);
  Color _defBgSelNight = const Color(0xFF181818);

  // ─── Умолчания: прочее ───
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

  // ─── Умолчания: коэффициенты размеров ───
  // Все — доли от базовой величины side (малый размер пульта,
  // вычисляемый в main.dart из системного масштаба и ползунка scale).
  // Правятся в рубке. Нижний предел при применении — один пиксель.
  double _defKPult = 1.0; // размер пульта целиком
  double _defKPultSmall = 0.6667; // малый пульт (две трети)
  double _defKBlockGap = 0.2; // промежуток меж блоками
  double _defKFramePad = 0.375; // отбивка внутри рамки блока
  double _defKTitle = 0.4; // кегль надписи блока
  double _defKNumber = 0.4; // кегль числа (таймера) в карточке
  double _defKNumberSmall = 0.3; // кегль числа в списке
  double _defKName = 0.5; // кегль имени рутины
  double _defKRadius = 0.3; // радиус сглаживания рамок
  double _defKStroke = 0.015; // толщина обводки рамок

  // ─── Текущее: цвета ───
  // Значения из файла, а при первом запуске — из умолчаний выше.
  Color bgDay = const Color(0xFFEFEFEF);
  Color bgNight = const Color(0xFF101010);
  Color fgDay = const Color(0xFF101010);
  Color fgNight = const Color(0xFFEFEFEF);
  Color dimDay = const Color(0xFF303030);
  Color dimNight = const Color(0xFFCFCFCF);
  Color signalDay = const Color(0xFF000000);
  Color signalNight = const Color(0xFFFFFFFF);
  Color bgDimDay = const Color(0xFFE4E4E4);
  Color bgDimNight = const Color(0xFF1C1C1C);
  Color bgSelDay = const Color(0xFFE8E8E8);
  Color bgSelNight = const Color(0xFF181818);

  // ─── Текущее: прочее ───
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

  // ─── Текущее: коэффициенты ───
  double kPult = 1.0;
  double kPultSmall = 0.6667;
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

  // ─── Черновики полей ───
  // Хранят неоконченный ввод, дабы он не пропадал при перерисовке.
  Map<String, String> drafts = {};

  JournalRepository? _journal;
  int _lastAppliedId = 0;
  File? _file;

  OperationalLayer();

  // ─── Пуск ───
  // Порядок важен: сперва умолчания (из assets), затем файл (перебивает),
  // затем журнал (перебивает и файл — ибо журнал есть источник правды),
  // затем пересчёт смены.
  Future<void> init(JournalRepository journal) async {
    _journal = journal;
    await _loadDefaults();
    final dir = await getApplicationDocumentsDirectory();
    _file = File(p.join(dir.path, 'operational_layer.json'));
    await _loadFromFile();
    await _recomputeShiftFromJournal();
    await applyJournalDeltas();
    notifyListeners();
  }

  // ─── Загрузка умолчаний из assets/defaults.json ───
  // Всякое поле разбирается с проверкою: коли ключа нет либо тип
  // не тот — остаётся встроенное значение. Сим старые файлы
  // умолчаний не ломают загрузку.
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
      _defBgDimDay = _parseColor(data['bgdim_day'] as String?) ?? _defBgDimDay;
      _defBgDimNight =
          _parseColor(data['bgdim_night'] as String?) ?? _defBgDimNight;
      _defBgSelDay = _parseColor(data['bgsel_day'] as String?) ?? _defBgSelDay;
      _defBgSelNight =
          _parseColor(data['bgsel_night'] as String?) ?? _defBgSelNight;

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

      _defKPult = (data['k_pult'] as num?)?.toDouble() ?? _defKPult;
      _defKPultSmall =
          (data['k_pult_small'] as num?)?.toDouble() ?? _defKPultSmall;
      _defKBlockGap =
          (data['k_block_gap'] as num?)?.toDouble() ?? _defKBlockGap;
      _defKFramePad =
          (data['k_frame_pad'] as num?)?.toDouble() ?? _defKFramePad;
      _defKTitle = (data['k_title'] as num?)?.toDouble() ?? _defKTitle;
      _defKNumber = (data['k_number'] as num?)?.toDouble() ?? _defKNumber;
      _defKNumberSmall =
          (data['k_number_small'] as num?)?.toDouble() ?? _defKNumberSmall;
      _defKName = (data['k_name'] as num?)?.toDouble() ?? _defKName;
      _defKRadius = (data['k_radius'] as num?)?.toDouble() ?? _defKRadius;
      _defKStroke = (data['k_stroke'] as num?)?.toDouble() ?? _defKStroke;
    } catch (_) {}
    _resetToDefaultsInMemory();
  }

  // ─── Сброс памяти к умолчаниям ───
  // Применяется при пуске (поверх встроенных значений ложатся
  // значения из assets) и при сбросе кэша.
  void _resetToDefaultsInMemory() {
    bgDay = _defBgDay;
    bgNight = _defBgNight;
    fgDay = _defFgDay;
    fgNight = _defFgNight;
    dimDay = _defDimDay;
    dimNight = _defDimNight;
    signalDay = _defSignalDay;
    signalNight = _defSignalNight;
    bgDimDay = _defBgDimDay;
    bgDimNight = _defBgDimNight;
    bgSelDay = _defBgSelDay;
    bgSelNight = _defBgSelNight;

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

    kPult = _defKPult;
    kPultSmall = _defKPultSmall;
    kBlockGap = _defKBlockGap;
    kFramePad = _defKFramePad;
    kTitle = _defKTitle;
    kNumber = _defKNumber;
    kNumberSmall = _defKNumberSmall;
    kName = _defKName;
    kRadius = _defKRadius;
    kStroke = _defKStroke;

    onShift = false;
    totalShiftSeconds = 0;
    shiftStartedAt = null;
    drafts = {};
  }

  // ─── Загрузка рабочего файла ───
  // Файл operational_layer.json лежит в папке документов. Коли его
  // нет — молча выходим, остаются умолчания. Коли есть, но ключа
  // какого-то нет — берётся прежнее значение (сие важно при
  // добавлении новых полей: старые файлы не ломаются).
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
      bgDimDay = _parseColor(data['bgdim_day'] as String?) ?? bgDimDay;
      bgDimNight = _parseColor(data['bgdim_night'] as String?) ?? bgDimNight;
      bgSelDay = _parseColor(data['bgsel_day'] as String?) ?? bgSelDay;
      bgSelNight = _parseColor(data['bgsel_night'] as String?) ?? bgSelNight;

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
      _lastAppliedId = (data['last_id'] as num?)?.toInt() ?? 0;
    } catch (_) {}
  }

  // ─── Пересчёт смены по журналу ───
  // Идём по всем записям рода actor и считаем пары start/stop.
  // Незакрытый start означает идущую смену — сим состоянием
  // и восстанавливается onShift после перезапуска.
  Future<void> _recomputeShiftFromJournal() async {
    if (_journal == null) return;
    final entries = await _journal!.entriesAfter(0, type: JournalType.actor);
    int total = 0;
    int? started;
    for (final e in entries) {
      if (e.body.contains('shift_start')) {
        started = e.time;
      } else if (e.body.contains('shift_stop')) {
        if (started != null) {
          total += e.time - started;
          started = null;
        }
      }
    }
    totalShiftSeconds = total;
    shiftStartedAt = started;
    onShift = (started != null);
  }

  // ─── Применение записей журнала ───
  // Род bort: изменения настроек, положенные в журнал. Применяем
  // всё, что после _lastAppliedId. Сим восстанавливается состояние
  // при перезапуске и принимаются правки, сделанные из консоли.
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

  // Разбор тела записи вида {"key":"...","value":"..."}.
  // Прочее игнорируется: род bort может содержать служебные записи.
  void _applyBody(String body) {
    final key = _extract(body, 'key');
    final value = _extract(body, 'value');
    if (key == null) return;
    _apply(key, value ?? '');
  }

  // ─── Полный пересбор из журнала ───
  // Сбрасывает память к умолчаниям и воспроизводит все записи рода
  // bort. Применяется по кнопке «перечитать» в рубке.
  Future<void> reloadFromJournal() async {
    if (_journal == null) return;
    _resetToDefaultsInMemory();
    _lastAppliedId = 0;

    final entries = await _journal!.entriesAfter(0, type: JournalType.bort);
    for (final e in entries) {
      _applyBody(e.body);
      _lastAppliedId = e.id;
    }
    await _recomputeShiftFromJournal();
    await saveNow();
    notifyListeners();
  }

  // ─── Сброс кэша ───
  // Удаляет рабочий файл и сбрасывает память. Журнал не трогается:
  // после сброса следующее событие рода bort восстановит настройки.
  Future<void> resetCache() async {
    if (_file != null && await _file!.exists()) {
      await _file!.delete();
    }
    _resetToDefaultsInMemory();
    _lastAppliedId = 0;
    await _saveToFile();
    notifyListeners();
  }

  Future<void> saveNow() async {
    await _saveToFile();
  }

  Future<void> resetToDefaults() async {
    await resetCache();
  }

  // ─── Установка значений ───
  // set, setBool, setInt — общие: применяют и уведомляют.
  // setSilent отличается лишь названием: применяет без записи
  // в журнал (запись делается отдельно, коли нужно).
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

  // ─── Смена ───
  // startShift и stopShift не пишут в журнал сами: запись делается
  // вызывающим (вкладка актора), дабы запись и состояние не
  // разъезжались.
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
  // Единая точка разбора: строка ключа из журнала либо из рубки
  // ложится в поле. Всякое новое поле надобно добавить сюда,
  // в _loadFromFile, _saveToFile, allAsStrings и settingTypes.
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
      case 'bgdim_day':
        bgDimDay = _parseColor(value) ?? bgDimDay;
        break;
      case 'bgdim_night':
        bgDimNight = _parseColor(value) ?? bgDimNight;
        break;
      case 'bgsel_day':
        bgSelDay = _parseColor(value) ?? bgSelDay;
        break;
      case 'bgsel_night':
        bgSelNight = _parseColor(value) ?? bgSelNight;
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

  // ─── Сохранение рабочего файла ───
  // Пишем всё, что надобно для восстановления. Коли новое поле
  // завели, но сюда не внесли — оно не сохранится, и после
  // перезапуска вернётся к умолчанию. Сие надлежит помнить.
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
      'bgdim_day': colorToHex(bgDimDay),
      'bgdim_night': colorToHex(bgDimNight),
      'bgsel_day': colorToHex(bgSelDay),
      'bgsel_night': colorToHex(bgSelNight),
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
      'last_id': _lastAppliedId,
    };
    await _file!.writeAsString(jsonEncode(data));
  }

  // Разбор значения из JSON-тела: вынимаем строку чрез простое
  // регулярное выражение. Годится токмо для плоских пар ключ-значение.
  String? _extract(String body, String field) {
    final re = RegExp('"$field"\\s*:\\s*"([^"]*)"');
    return re.firstMatch(body)?.group(1);
  }

  // Цвет в шестнадцатеричном виде "#RRGGBB" (либо "RRGGBB").
  // Восьмой байт (альфа) всегда полон: прозрачности в проекте нет.
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

  // ─── Текущая гамма ───
  // effectiveBrightness берёт системную и, ежели тема задана явно
  // (dark либо light), перебивает её.
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

  // ─── Доступ к цветам по гамме ───
  // Виджеты не знают, какая ныне гамма: они зовут сии геттеры
  // с системною яркостью, а геттеры выбирают нужную роль.
  Color currentBg(Brightness b) => b == Brightness.dark ? bgNight : bgDay;
  Color currentFg(Brightness b) => b == Brightness.dark ? fgNight : fgDay;
  Color currentDim(Brightness b) => b == Brightness.dark ? dimNight : dimDay;
  Color currentSignal(Brightness b) =>
      b == Brightness.dark ? signalNight : signalDay;
  Color currentBgDim(Brightness b) =>
      b == Brightness.dark ? bgDimNight : bgDimDay;
  Color currentBgSel(Brightness b) =>
      b == Brightness.dark ? bgSelNight : bgSelDay;

  // ─── Плоское представление для рубки ───
  // Рубка обходит ключи и берёт значения отсюда. Цвета — строкою,
  // числа — с фиксированною точностью (иначе ползут хвосты).
  Map<String, String> get allAsStrings => {
        'bg_day': colorToHex(bgDay),
        'bg_night': colorToHex(bgNight),
        'fg_day': colorToHex(fgDay),
        'fg_night': colorToHex(fgNight),
        'dim_day': colorToHex(dimDay),
        'dim_night': colorToHex(dimNight),
        'signal_day': colorToHex(signalDay),
        'signal_night': colorToHex(signalNight),
        'bgdim_day': colorToHex(bgDimDay),
        'bgdim_night': colorToHex(bgDimNight),
        'bgsel_day': colorToHex(bgSelDay),
        'bgsel_night': colorToHex(bgSelNight),

        // ─── Прочее, плоскими строками ───
        // Всякое значение приводится к строке: рубка отображает
        // и правит всё единообразно, а разбор ввода делается
        // в _apply. Числа — с фиксированною точностью, дабы
        // после перезаписи не ползли хвосты (0.3000 вместо 0.3).
        'theme': theme,
        'scale': scale.toStringAsFixed(2),
        'lang': lang,
        'labels_system': labelsSystem.toString(),
        'labels_field': labelsField.toString(),

        // ─── Коэффициенты размеров ───
        // Четыре знака после запятой: сего довольно для долей,
        // и вместе с тем строка не разрастается.
        'k_pult': kPult.toStringAsFixed(4),
        'k_pult_small': kPultSmall.toStringAsFixed(4),
        'k_block_gap': kBlockGap.toStringAsFixed(4),
        'k_frame_pad': kFramePad.toStringAsFixed(4),
        'k_title': kTitle.toStringAsFixed(4),
        'k_number': kNumber.toStringAsFixed(4),
        'k_number_small': kNumberSmall.toStringAsFixed(4),
        'k_name': kName.toStringAsFixed(4),
        'k_radius': kRadius.toStringAsFixed(4),
        'k_stroke': kStroke.toStringAsFixed(4),
      };

  // ─── Роды полей для рубки ───
  // По сему словарю рубка решает, как строить строку настройки:
  // как поле цвета (с образчиком), как выбор темы (чрез подпульты),
  // как поле числа либо строки, как переключатель (булев).
  // Всякое новое поле надобно внести и сюда, иначе рубка
  // покажет его простым полем ввода.
  //
  // Заметьте: двенадцать цветов поименованы явно; здесь токмо
  // те, что ныне правятся. Коли понадобится править прочие
  // коэффициенты чрез рубку — допишите их с родом 'string'.
  static const Map<String, String> settingTypes = {
    'bg_day': 'color',
    'bg_night': 'color',
    'fg_day': 'color',
    'fg_night': 'color',
    'dim_day': 'color',
    'dim_night': 'color',
    'signal_day': 'color',
    'signal_night': 'color',
    'bgdim_day': 'color',
    'bgdim_night': 'color',
    'bgsel_day': 'color',
    'bgsel_night': 'color',
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

  // ─── Поля только для чтения ───
  // Ныне пусто: все поля доступны правке. Ключ оставлен
  // на случай, ежели однажды понадобится защитить какое-то
  // значение от случайной правки (скажем, служебное).
  static const Set<String> readOnlyKeys = {};
}
