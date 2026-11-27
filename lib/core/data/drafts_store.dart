class DraftsStore {
  final Map<String, String> _drafts = {};

  final Map<String, bool> _sent = {};

  String draft(String key) => _drafts[key] ?? '';

  bool isSent(String key) => _sent[key] == true;

  void setDraft(String key, String text) {
    _drafts[key] = text;
    _sent.remove(key);
  }

  void clearDraft(String key) {
    _drafts.remove(key);
    _sent.remove(key);
  }

  void markSent(String key) {
    _sent[key] = true;
  }

  static String traceKey(int objectId, String slot) =>
      'trace_${objectId}_$slot';

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
