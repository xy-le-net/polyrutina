// ═══════════════════════════════════════════════════════════════════
// i18n.dart — dictionary.
//
// Reads assets/i18n.json, holds the current language, returns strings
// by key. The dictionary file is edited by hand; the code is not
// touched when adding languages.
//
// Resilient load. If the asset is missing, malformed, or (worst case)
// a JSON array instead of an object, the loader falls back to an empty
// dictionary so the app can still start. Previously a single typo in
// i18n.json took down the whole app with a black screen.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class I18n {
  final Map<String, Map<String, String>> _data;
  final String lang;

  I18n._(this._data, this.lang);

  // Load the dictionary. `lang` is «ru» or «en». Other languages are
  // added to the JSON without touching the code.
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

  // String by key. If the key is missing in the current language, the
  // English one is used, then the key itself.
  String t(String key) {
    return _data[lang]?[key] ?? _data['en']?[key] ?? key;
  }
}
