// ═══════════════════════════════════════════════════════════════════
// drafts_store.dart — черновики полей и признак «отправлено».
//
// Черновик — неоконченный текст поля ввода (консоль журнала, поле
// следа блока). Живёт в слое и в файле борта, дабы не пропасть при
// перерисовке, переключении вкладок и закрытии приложения.
//
// Признак «отправлено» — булево для того же ключа: истина, коли
// текст уже в журнале и с тех пор не менялся. Пульт отправки
// спрашивает его, дабы решить, бледный он либо активный.
//
// Ключи: «console», «trace_<objectId>_<slot>».
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

class DraftsStore {
  // ─── Черновики ───
  final Map<String, String> _drafts = {};

  // ─── Признак «отправлено» ───
  // Ключ тот же; истина — текст в журнале и не менялся.
  final Map<String, bool> _sent = {};

  // ─── Чтение ───
  String draft(String key) => _drafts[key] ?? '';

  bool isSent(String key) => _sent[key] == true;

  // ─── Запись черновика ───
  // Всякая правка снимает признак «отправлено».
  void setDraft(String key, String text) {
    _drafts[key] = text;
    _sent.remove(key);
  }

  // ─── Очистка ───
  void clearDraft(String key) {
    _drafts.remove(key);
    _sent.remove(key);
  }

  // ─── Пометка отправки ───
  void markSent(String key) {
    _sent[key] = true;
  }

  // ─── Ключи для следов ───
  static String traceKey(int objectId, String slot) =>
      'trace_${objectId}_$slot';

  // ─── Сериализация ───
  Map<String, dynamic> toJson() => {'drafts': _drafts, 'trace_sent': _sent};

  void loadJson(Map<String, dynamic> data) {
    _drafts.clear();
    _sent.clear();
    final d = data['drafts'];
    if (d is Map) {
      for (final k in d.keys) {
        _drafts[k.toString()] = d[k].toString();
      }
    }
    final s = data['trace_sent'];
    if (s is Map) {
      for (final k in s.keys) {
        _sent[k.toString()] = s[k] == true;
      }
    }
  }

  void reset() {
    _drafts.clear();
    _sent.clear();
  }
}
