// ═══════════════════════════════════════════════════════════════════
// i18n.dart — словарь.
//
// Читает assets/i18n.json, держит текущий язык, отдаёт строки по ключу.
// Файл словаря правится вручную — код при добавлении языков не трогается.
//
// Resilient load. If the asset is missing, malformed, or (worst case)
// a JSON array instead of an object, the loader falls back to an empty
// dictionary so the app can still start. Previously a single typo in
// i18n.json took down the whole app with a black screen.
// ═══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class I18n {
  final Map<String, Map<String, String>> _data;
  final String lang;

  I18n._(this._data, this.lang);

  static Future<I18n> load(String lang) async {
    try {
      final raw = await rootBundle.loadString('assets/i18n.json');
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final data = decoded.map(
          (k, v) => MapEntry(k, Map<String, String>.from(v as Map)),
        );
        return I18n._(data, lang);
      }
      debugPrint('i18n.json is not a JSON object');
    } catch (e) {
      debugPrint('Failed to load i18n.json: $e');
    }
    return I18n._({'ru': {}, 'en': {}}, lang);
  }

  String t(String key) {
    return _data[lang]?[key] ?? _data['en']?[key] ?? key;
  }
}
