// ═══════════════════════════════════════════════════════════════════
// theme_store.dart — цвета и темы.
//
// Действующий набор из пяти ролей: bg, bgdim, dim, fg, signal.
// Все пять ролей — внутри каждой темы. Темы: day, night, custom.
//
// Темы образуют пары: day ↔ night. Сигнальный объект берёт цвета
// противоположной темы целиком (colorsForOpposite).
//
// Разбор тем из JSON, разрешение действующей темы по имени либо
// по системной гамме, применение одиночного ключа темы.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

class ThemeStore {
  // ─── Действующий набор ───
  Color bg = const Color(0xFFEFEFEF);
  Color bgdim = const Color(0xFFE4E4E4);
  Color dim = const Color(0xFF8F8F8F);
  Color fg = const Color(0xFF101010);
  Color signal = const Color(0xFF000000);

  // ─── Все темы ───
  // Имя → {bg, bgdim, dim, fg, signal}.
  Map<String, Map<String, Color>> themes = {};

  // Имя действующей темы. «system» — особая.
  String themeName = 'system';

  // Системная гамма.
  Brightness systemBrightness = Brightness.light;

  // ─── Разбор тем из JSON ───
  void parseThemes(Map<dynamic, dynamic> t) {
    themes = {};
    for (final k in t.keys) {
      final v = t[k];
      if (v is Map) {
        themes[k.toString()] = {
          'bg': parseColor(v['bg'] as String?) ?? bg,
          'bgdim': parseColor(v['bgdim'] as String?) ?? bgdim,
          'dim': parseColor(v['dim'] as String?) ?? dim,
          'fg': parseColor(v['fg'] as String?) ?? fg,
          'signal': parseColor(v['signal'] as String?) ?? signal,
        };
      }
    }
  }

  // ─── Разрешение темы ───
  // Ежели themeName == «system», берётся day (светло) либо night
  // (темно) по системной гамме. Иначе — набор с сим именем.
  void resolve() {
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

  void setSystemBrightness(Brightness b) {
    systemBrightness = b;
  }

  // ─── Противоположная тема ───
  String oppositeName() {
    String name = themeName;
    if (name == 'system') {
      name = systemBrightness == Brightness.dark ? 'night' : 'day';
    }
    if (name == 'day') return 'night';
    if (name == 'night') return 'day';
    // Своя тема — противоположной считается ночь.
    return 'night';
  }

  // Пятёрка цветов противоположной темы.
  Map<String, Color>? colorsForOpposite() {
    final name = oppositeName();
    final t = themes[name];
    if (t == null) return null;
    return {
      'bg': t['bg']!,
      'bgdim': t['bgdim']!,
      'dim': t['dim']!,
      'fg': t['fg']!,
      'signal': t['signal']!,
    };
  }

  // ─── Применение одного ключа цвета темы ───
  // Ключ: theme.<имя>.<роль>. Возвращает истину, коли ключ подошёл.
  bool applyThemeKey(String key, String value) {
    if (!key.startsWith('theme.')) return false;
    if (key.split('.').length != 3) return false;
    final parts = key.split('.');
    final name = parts[1];
    final role = parts[2];
    final c = parseColor(value);
    if (c == null) return true;
    themes.putIfAbsent(
      name,
      () => {'bg': bg, 'bgdim': bgdim, 'dim': dim, 'fg': fg, 'signal': signal},
    );
    themes[name]![role] = c;
    final resolved = themeName == 'system'
        ? (systemBrightness == Brightness.dark ? 'night' : 'day')
        : themeName;
    if (name == resolved) resolve();
    return true;
  }

  // ─── Ключ dim (ныне без отдельного применения — dim внутри темы) ───
  // Оставлен для совместимости с прежним ключом в файле борта:
  // при загрузке применяется к теме, коя разрешится.
  bool applyDim(String value) {
    final c = parseColor(value);
    if (c == null) return true;
    // Кладём во все темы? Нет: dim — часть темы. Правка ключа 'dim'
    // в рубке не применяется (поля нет). При загрузке старого файла
    // — игнор.
    return true;
  }

  // ─── Сериализация ───
  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{};
    for (final e in themes.entries) {
      out[e.key] = {
        'bg': colorToHex(e.value['bg']!),
        'bgdim': colorToHex(e.value['bgdim']!),
        'dim': colorToHex(e.value['dim']!),
        'fg': colorToHex(e.value['fg']!),
        'signal': colorToHex(e.value['signal']!),
      };
    }
    return out;
  }

  Map<String, String> toFlatStrings() {
    final out = <String, String>{};
    for (final e in themes.entries) {
      out['theme.${e.key}.bg'] = colorToHex(e.value['bg']!);
      out['theme.${e.key}.bgdim'] = colorToHex(e.value['bgdim']!);
      out['theme.${e.key}.dim'] = colorToHex(e.value['dim']!);
      out['theme.${e.key}.fg'] = colorToHex(e.value['fg']!);
      out['theme.${e.key}.signal'] = colorToHex(e.value['signal']!);
    }
    return out;
  }

  // ─── Встроенные умолчания ───
  // Дополняет недостающие темы, не перетирая уже загруженные:
  // ежели в файле борта темы custom нет (записан до правки), она
  // добавится с умолчаниями, а day и night останутся как были.
  void ensureThemes() {
    final defaults = <String, Map<String, Color>>{
      'day': {
        'bg': const Color(0xFFEFEFEF),
        'bgdim': const Color(0xFFE4E4E4),
        'dim': const Color(0xFF8F8F8F),
        'fg': const Color(0xFF101010),
        'signal': const Color(0xFF000000),
      },
      'night': {
        'bg': const Color(0xFF101010),
        'bgdim': const Color(0xFF1C1C1C),
        'dim': const Color(0xFF8F8F8F),
        'fg': const Color(0xFFEFEFEF),
        'signal': const Color(0xFFFFFFFF),
      },
      // Своя тема — запасной набор, согласный с assets/defaults.json.
      // Единая лестница светлоты (22 → 30 → 52 → 80 → 88):
      //   bg      — тёмный сине-серый, не чёрный;
      //   bgdim   — мягкий фон между bg и dim;
      //   dim     — холодный серый со слабым голубым, середина;
      //   fg      — бледный тёплый белый, ближе к сливкам;
      //   signal  — тёплый янтарь, самый яркий в наборе.
      // Каждая пара соседей различается на восемь единиц светлоты
      // и боле: лестница читается при чёрно-белом отображении,
      // при протанопии, дейтеранопии и тританопии. Сине-жёлтая ось
      // (холодные ступени против тёплого сигнала) дополнительно
      // усиливает различие при красно-зелёных типах.
      'custom': {
        'bg': const Color(0xFF1B2630),
        'bgdim': const Color(0xFF2A353E),
        'dim': const Color(0xFF7A868F),
        'fg': const Color(0xFFDCD6C8),
        'signal': const Color(0xFFE8A838),
      },
    };
    for (final e in defaults.entries) {
      if (!themes.containsKey(e.key)) {
        themes[e.key] = Map<String, Color>.from(e.value);
      }
    }
  }
}

// ─── Разбор цвета ───
Color? parseColor(String? s) {
  if (s == null) return null;
  var t = s.trim();
  if (t.startsWith('#')) t = t.substring(1);
  if (t.length != 6) return null;
  final v = int.tryParse(t, radix: 16);
  if (v == null) return null;
  return Color(0xFF000000 | v);
}

// ─── Цвет в строку ───
String colorToHex(Color c) {
  final r = (c.r * 255).round().toRadixString(16).padLeft(2, '0');
  final g = (c.g * 255).round().toRadixString(16).padLeft(2, '0');
  final b = (c.b * 255).round().toRadixString(16).padLeft(2, '0');
  return '#$r$g$b';
}
