import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:polyrutina/core/application/providers.dart';
import 'package:polyrutina/core/data/journal_layer.dart';
import 'package:polyrutina/core/localization/i18n.dart';
import 'package:polyrutina/core/localization/providers.dart';
import 'package:polyrutina/features/settings/application/operational_layer.dart';
import 'package:polyrutina/features/settings/application/providers.dart';
import 'package:polyrutina/features/traces/application/providers.dart';
import 'package:polyrutina/features/traces/application/trace_layer.dart';
import 'package:polyrutina/features/traces/application/trace_repository.dart';
import 'package:polyrutina/features/traces/presentation/trace_field.dart';
import 'package:polyrutina/shared/presentation/pults/pult_core.dart';
import '../../support/memory_journal_repository.dart';

void main() {
  testWidgets('trace text preview and editor respect their height limits', (
    tester,
  ) async {
    final text = List.filled(200, 'line').join('\n');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);

    await _pumpTraceField(tester, text: text);

    final preview = find
        .ancestor(of: find.text(text), matching: find.byType(Container))
        .first;
    expect(tester.getSize(preview).height, closeTo(400, 0.1));
    await tester.tapAt(tester.getTopLeft(preview) + const Offset(8, 8));
    await tester.pump();
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();

    final fieldHeight = tester.getSize(find.byType(TextField)).height;
    expect(fieldHeight, lessThanOrEqualTo(205));
  });
}

Future<void> _pumpTraceField(
  WidgetTester tester, {
  required String text,
}) async {
  const routineId = 42;
  final traceLayer = TraceLayer(_EmptyTraceRepository())
    ..traces[1] = Trace(id: 1, slot: 'prep', text: text, parents: [routineId]);
  final journal = JournalLayer(MemoryJournalRepository());
  final bort = OperationalLayer();
  final pultState = PultState()..baseSide = 32;
  final i18n = await I18n.load('ru');
  addTearDown(pultState.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        operationalLayerProvider.overrideWith((ref) => bort),
        traceLayerProvider.overrideWith((ref) => traceLayer),
        journalLayerProvider.overrideWith((ref) => journal),
        i18nProvider.overrideWith(() => _TestI18nController(i18n)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: PultScope(
            state: pultState,
            child: const SingleChildScrollView(
              child: TraceField(
                objectId: routineId,
                slot: 'prep',
                fg: Colors.black,
                dim: Colors.grey,
                bg: Colors.white,
                signal: Colors.red,
                side: 32,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _TestI18nController extends I18nController {
  final I18n value;

  _TestI18nController(this.value);

  @override
  I18n? build() => value;
}

class _EmptyTraceRepository implements TraceRepository {
  @override
  Future<TraceCache> load() async => const TraceCache.empty();

  @override
  Future<void> save({
    required List<Trace> traces,
    required int lastJournalId,
  }) async {}
}
