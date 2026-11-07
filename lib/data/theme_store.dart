// ═══════════════════════════════════════════════════════════════════
// lib/data/theme_store.dart — colors and themes.
//
// Five roles, in the ladder order used across the app:
//   1 — bgsignal: background of signal elements;
//   2 — bg:       base background;
//   3 — mid:      secondary content and soft strokes;
//   4 — fg:       base content;
//   5 — fgsignal: content of signal elements, the accent color.
//
// Theme selection. Three independent settings:
//   customEnabled — use the «custom» palette;
//   night         — force the night palette (mutually exclusive
//                   with auto);
//   auto          — follow the system brightness (mutually
//                   exclusive with night).
// When both night and auto are false, the day palette is used.
//
// Custom palette — stored as night. The custom entry in the theme
// map is the NIGHT form; the day view is its mirror. When the
// effective mode resolves to night (night on, or auto with a dark
// system), the custom palette is shown as stored; when it resolves
// to day, the mirrored form is shown. The visual appearance of the
// custom palette is unchanged: day looks like the old day, night
// like the old night, only the internal representation is inverted.
// The built-in default custom colours are therefore given in their
// night form: the mirror of the former day values. Saved user data
// is flipped once, in operational_layer._loadFromFile, guarded by
// the state-file schema.
//
// Built-in day and night are unchanged.
//
// Resolving. With customEnabled, the source palette is custom (night
// form); otherwise the built-in day or night. Then:
//   — night on: custom as stored, or built-in night;
//   — auto on and dark system: custom as stored, or built-in night;
//   — otherwise (day): mirrored custom, or built-in day.
//
// Opposite palette. Always the mirror of the current one
// (bg ↔ fg, bgsignal ↔ fgsignal, mid fixed), for running blocks.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

class ThemeStore {
  Map<String, Map<String, Color>> _themes = {};
  Map<String, Map<String, Color>> get themes => _themes;
  set themes(Map<String, Map<String, Color>> v) {
    _themes = v;
    _invalidate();
  }

  // ─── Theme selection ───
  bool _customEnabled = false;
  bool get customEnabled => _customEnabled;
  set customEnabled(bool v) {
    if (_customEnabled == v) return;
    _customEnabled = v;
    _invalidate();
  }

  // Night forces the night palette; auto follows the system. The two
  // are mutually exclusive: turning one on turns the other off.
  bool _night = false;
  bool get night => _night;
  set night(bool v) {
    if (_night == v) return;
    _night = v;
    if (v) _auto = false;
    _invalidate();
  }

  bool _auto = true;
  bool get auto => _auto;
  set auto(bool v) {
    if (_auto == v) return;
    _auto = v;
    if (v) _night = false;
    _invalidate();
  }

  Brightness _systemBrightness = Brightness.light;
  Brightness get systemBrightness => _systemBrightness;
  set systemBrightness(Brightness b) {
    if (_systemBrightness == b) return;
    _systemBrightness = b;
    _invalidate();
  }

  Map<String, Color>? _curCache;
  Map<String, Color>? _oppCache;

  void _invalidate() {
    _curCache = null;
    _oppCache = null;
  }

  Map<String, Color> get _cur => _curCache ??= _computeCurrent();

  Color get bg => _cur['bg']!;
  Color get bgsignal => _cur['bgsignal']!;
  Color get mid => _cur['mid']!;
  Color get fg => _cur['fg']!;
  Color get fgsignal => _cur['fgsignal']!;

  Map<String, Color> get _opp => _oppCache ??= _computeOpposite();

  Map<String, Color>? colorsForOpposite() => Map<String, Color>.from(_opp);

  void resolve() {
    _cur;
  }

  void setSystemBrightness(Brightness b) {
    systemBrightness = b;
  }

  // ─── Resolution ───
  Map<String, Color> _computeCurrent() {
    final source = _customEnabled
        ? Map<String, Color>.from(_themes['custom'] ?? _customColors)
        : null;

    Map<String, Color> builtin(String name) =>
        Map<String, Color>.from(_themes[name] ?? _builtinThemes[name]!);

    final wantNight = _night || (_auto && _systemBrightness == Brightness.dark);

    if (source != null) {
      return wantNight ? source : _invert(source);
    }
    return wantNight ? builtin('night') : builtin('day');
  }

  Map<String, Color> _computeOpposite() => _invert(_cur);

  static Map<String, Color> _invert(Map<String, Color> cur) => {
    'bg': cur['fg']!,
    'bgsignal': cur['fgsignal']!,
    'mid': cur['mid']!,
    'fg': cur['bg']!,
    'fgsignal': cur['bgsignal']!,
  };

  // Public — used by operational_layer when migrating saved palettes.
  static Map<String, Color> invert(Map<String, Color> c) => _invert(c);

  void parseThemes(Map<dynamic, dynamic> t) {
    final out = <String, Map<String, Color>>{};
    for (final k in t.keys) {
      final name = k.toString();
      final v = t[k];
      if (v is Map) {
        out[name] = {
          'bg': parseColor(v['bg'] as String?) ?? _dayColors['bg']!,
          'bgsignal':
              parseColor(v['bgsignal'] as String?) ?? _dayColors['bgsignal']!,
          'mid': parseColor(v['mid'] as String?) ?? _dayColors['mid']!,
          'fg': parseColor(v['fg'] as String?) ?? _dayColors['fg']!,
          'fgsignal':
              parseColor(v['fgsignal'] as String?) ?? _dayColors['fgsignal']!,
        };
      }
    }
    _themes = out;
    _invalidate();
  }

  static const Set<String> _roleSet = {
    'bg',
    'bgsignal',
    'mid',
    'fg',
    'fgsignal',
  };

  bool applyThemeKey(String key, String value) {
    if (!key.startsWith('theme.')) return false;
    if (key.split('.').length != 3) return false;
    final parts = key.split('.');
    final name = parts[1];
    final role = parts[2];
    if (!_roleSet.contains(role)) return true;
    final c = parseColor(value);
    if (c == null) return true;
    _themes.putIfAbsent(name, () => Map<String, Color>.from(_dayColors));
    _themes[name]![role] = c;
    _invalidate();
    return true;
  }

  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{};
    for (final e in _themes.entries) {
      out[e.key] = {
        'bg': colorToHex(e.value['bg']!),
        'bgsignal': colorToHex(e.value['bgsignal']!),
        'mid': colorToHex(e.value['mid']!),
        'fg': colorToHex(e.value['fg']!),
        'fgsignal': colorToHex(e.value['fgsignal']!),
      };
    }
    return out;
  }

  Map<String, String> toFlatStrings() {
    final out = <String, String>{};
    for (final e in _themes.entries) {
      out['theme.${e.key}.bg'] = colorToHex(e.value['bg']!);
      out['theme.${e.key}.bgsignal'] = colorToHex(e.value['bgsignal']!);
      out['theme.${e.key}.mid'] = colorToHex(e.value['mid']!);
      out['theme.${e.key}.fg'] = colorToHex(e.value['fg']!);
      out['theme.${e.key}.fgsignal'] = colorToHex(e.value['fgsignal']!);
    }
    return out;
  }

  void ensureThemes() {
    var changed = false;
    for (final e in _builtinThemes.entries) {
      if (!_themes.containsKey(e.key)) {
        _themes[e.key] = Map<String, Color>.from(e.value);
        changed = true;
      }
    }
    if (changed) _invalidate();
  }

  static const Map<String, Color> _dayColors = {
    'bg': Color(0xFFD9D3C7),
    'bgsignal': Color(0xFFFBF5E9),
    'mid': Color(0xFF7F8694),
    'fg': Color(0xFF181D27),
    'fgsignal': Color(0xFF060810),
  };

  static const Map<String, Color> _nightColors = {
    'bg': Color(0xFF181D27),
    'bgsignal': Color(0xFF060810),
    'mid': Color(0xFF7F8694),
    'fg': Color(0xFFD9D3C7),
    'fgsignal': Color(0xFFFBF5E9),
  };

  // Default custom palette, in its night form (dark background,
  // light text). This is the original custom palette: under the
  // new convention it already IS night, and the day view is its
  // mirror (light background, dark text). The previous build
  // inverted these defaults by mistake, which showed the light
  // form in night mode.
  static const Map<String, Color> _customColors = {
    'bg': Color(0xFF3F4D5A),
    'bgsignal': Color(0xFF071232),
    'mid': Color(0xFF7A868F),
    'fg': Color(0xFFB9B3A6),
    'fgsignal': Color(0xFFFFCB4F),
  };

  static const Map<String, Map<String, Color>> _builtinThemes = {
    'day': _dayColors,
    'night': _nightColors,
    'custom': _customColors,
  };
}

Color? parseColor(String? s) {
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
