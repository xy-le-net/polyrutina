import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polyrutina/core/application/ticker.dart';
import 'package:polyrutina/core/data/database.dart';
import 'package:polyrutina/core/data/journal_layer.dart';
import 'package:polyrutina/core/data/journal_repository.dart';

final appDbProvider = Provider<AppDb>((ref) {
  final db = AppDb();
  ref.onDispose(() => unawaited(db.close()));
  return db;
});

final journalRepositoryProvider = Provider<JournalRepository>(
  (ref) => DriftJournalRepository(ref.watch(appDbProvider)),
);

final journalLayerProvider = ChangeNotifierProvider<JournalLayer>(
  (ref) => JournalLayer(ref.watch(journalRepositoryProvider)),
);

final tickerProvider = ChangeNotifierProvider<AppTicker>((ref) => AppTicker());
