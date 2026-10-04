// ═══════════════════════════════════════════════════════════════════
// i18n.dart — словарь двух языков.
//
// Читает assets/i18n.json, держит текущий язык, отдаёт строки по ключу.
// Файл правится вручную — код при добавлении языков не трогается.
// ═══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:flutter/services.dart';

class I18n {
  final Map<String, Map<String, String>> _data;
  final String lang;

  I18n._(this._data, this.lang);

  // ─── Загрузка словаря ───
  // lang — «ru» либо «en». Прочие языки добавляются в JSON без правки кода.
  static Future<I18n> load(String lang) async {
    final raw = await rootBundle.loadString('assets/i18n.json');
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final data = map.map(
      (k, v) => MapEntry(k, Map<String, String>.from(v as Map)),
    );
    return I18n._(data, lang);
  }

  // ─── Строка по ключу ───
  // Ежели ключа нет в текущем языке — берём английский, затем сам ключ.
  String t(String key) {
    return _data[lang]?[key] ?? _data['en']?[key] ?? key;
  }
}
