class JournalEntry {
  final int id;
  final int time;
  final int flags;
  final int type;
  final String body;

  const JournalEntry({
    required this.id,
    required this.time,
    required this.flags,
    required this.type,
    required this.body,
  });
}
