import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polyrutina/core/data/journal_layer.dart';
import 'package:polyrutina/features/fields/application/field_layer.dart';
import 'package:polyrutina/features/fields/application/providers.dart';
import 'package:polyrutina/features/routines/application/providers.dart';
import 'package:polyrutina/features/routines/application/routine_access.dart';
import 'package:polyrutina/features/settings/application/operational_layer.dart';
import 'package:polyrutina/features/settings/application/providers.dart';
import 'package:polyrutina/features/traces/application/providers.dart';
import 'package:polyrutina/features/traces/application/trace_layer.dart';
import 'package:polyrutina/core/application/providers.dart';

class ExportContext {
  final JournalLayer journal;
  final FieldLayer fieldLayer;
  final RoutineAccess routineLayer;
  final OperationalLayer settings;
  final TraceLayer traceLayer;

  const ExportContext({
    required this.journal,
    required this.fieldLayer,
    required this.routineLayer,
    required this.settings,
    required this.traceLayer,
  });
}

final exportContextProvider = Provider<ExportContext>(
  (ref) => ExportContext(
    journal: ref.watch(journalLayerProvider),
    fieldLayer: ref.watch(fieldLayerProvider),
    routineLayer: ref.watch(routineLayerProvider),
    settings: ref.watch(operationalLayerProvider),
    traceLayer: ref.watch(traceLayerProvider),
  ),
);
