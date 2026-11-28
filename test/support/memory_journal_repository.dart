import 'package:polyrutina/core/data/journal_repository.dart';
import 'package:polyrutina/core/domain/journal_entry.dart';
import 'package:polyrutina/core/domain/journal_types.dart';

class MemoryJournalRepository implements JournalRepository {
  final List<JournalEntry> _entries = [];

  @override
  Future<T> transaction<T>(Future<T> Function() action) => action();

  @override
  Future<int> insert({
    required int type,
    required String body,
    int flags = 0,
  }) async {
    final id = _entries.isEmpty ? 1 : _entries.last.id + 1;
    _entries.add(
      JournalEntry(
        id: id,
        time: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        flags: flags,
        type: type,
        body: body,
      ),
    );
    return id;
  }

  @override
  Stream<List<JournalEntry>> watchAll() => Stream.value(List.of(_entries));

  @override
  Future<List<JournalEntry>> entriesAfter(int fromId, {int? type}) async =>
      _entries
          .where(
            (entry) =>
                entry.id > fromId && (type == null || entry.type == type),
          )
          .toList();

  @override
  Future<List<JournalEntry>> all() async => List.of(_entries);

  @override
  Future<void> clearEntries() async {
    _entries.clear();
  }

  @override
  Future<int> deleteSynced() async {
    final before = _entries.length;
    _entries.removeWhere((entry) => (entry.flags & JournalFlag.synced) != 0);
    return before - _entries.length;
  }

  @override
  Future<int> countSynced() async =>
      _entries.where((entry) => (entry.flags & JournalFlag.synced) != 0).length;

  @override
  Future<void> markSynced(int id) async {
    final index = _entries.indexWhere((entry) => entry.id == id);
    if (index < 0) return;
    final entry = _entries[index];
    _entries[index] = JournalEntry(
      id: entry.id,
      time: entry.time,
      flags: entry.flags | JournalFlag.synced,
      type: entry.type,
      body: entry.body,
    );
  }

  @override
  Future<int> countEntries() async => _entries.length;

  @override
  Future<int> lastEntryId() async => _entries.isEmpty ? 0 : _entries.last.id;

  @override
  Future<void> reclaimSpace() async {}
}
