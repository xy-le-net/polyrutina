import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polyrutina/core/application/operational_layer.dart';
import 'package:polyrutina/core/application/ticker.dart';
import 'package:polyrutina/core/data/database.dart';
import 'package:polyrutina/core/data/field_layer.dart';
import 'package:polyrutina/core/data/geo_repository.dart';
import 'package:polyrutina/core/data/journal_layer.dart';
import 'package:polyrutina/core/data/journal_repository.dart';
import 'package:polyrutina/core/data/trace_layer.dart';
import 'package:polyrutina/core/localization/i18n.dart';

final selectedTabProvider = NotifierProvider<SelectedTabController, int>(
  SelectedTabController.new,
);

final i18nProvider = NotifierProvider<I18nController, I18n?>(
  I18nController.new,
);

class I18nController extends Notifier<I18n?> {
  @override
  I18n? build() => null;

  void update(I18n value) {
    state = value;
  }
}

class SelectedTabController extends Notifier<int> {
  @override
  int build() => 0;

  void select(int tab) {
    state = tab;
  }
}

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

final operationalLayerProvider = ChangeNotifierProvider<OperationalLayer>(
  (ref) => OperationalLayer(),
);

final traceLayerProvider = ChangeNotifierProvider<TraceLayer>(
  (ref) => TraceLayer(),
);

final fieldLayerProvider = ChangeNotifierProvider<FieldLayer>(
  (ref) => FieldLayer(),
);

final tickerProvider = ChangeNotifierProvider<AppTicker>((ref) => AppTicker());

final geoRepositoryProvider = Provider<GeoRepository>((ref) {
  final repository = GeolocatorGeoRepository();
  ref.onDispose(repository.close);
  return repository;
});
