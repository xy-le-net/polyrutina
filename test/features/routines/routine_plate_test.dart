import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:polyrutina/core/application/providers.dart';
import 'package:polyrutina/core/application/ticker.dart';
import 'package:polyrutina/core/localization/i18n.dart';
import 'package:polyrutina/core/localization/providers.dart';
import 'package:polyrutina/features/fields/application/field_layer.dart';
import 'package:polyrutina/features/fields/application/field_repository.dart';
import 'package:polyrutina/features/fields/application/providers.dart';
import 'package:polyrutina/features/routines/application/providers.dart';
import 'package:polyrutina/features/routines/application/routine_layer.dart';
import 'package:polyrutina/features/routines/application/routine_repository.dart';
import 'package:polyrutina/features/routines/domain/routine.dart';
import 'package:polyrutina/features/routines/presentation/routine_plate.dart';
import 'package:polyrutina/features/settings/application/operational_layer.dart';
import 'package:polyrutina/features/settings/application/providers.dart';
import 'package:polyrutina/shared/presentation/widgets/block.dart';
import 'package:polyrutina/shared/presentation/pults/pult_core.dart';
import 'package:polyrutina/shared/presentation/pults/pult_tick.dart';
import 'package:polyrutina/features/routines/presentation/timer_text.dart';

void main() {
  testWidgets('completion pult replaces the routine ticker until a slot runs', (
    tester,
  ) async {
    final routine = Routine.create(1, at: 100);
    final app = await _routinePlateApp(routine);
    addTearDown(app.dispose);

    await tester.pumpWidget(app.widget);
    expect(find.byType(TimerText), findsNothing);
    expect(find.byType(PultTick), findsOneWidget);
    expect(_findPult('list_complete_1'), findsOneWidget);
    expect(_findPult('routine_1'), findsNothing);

    routine.startBlockAt(
      RoutineBlock.work,
      DateTime.now().millisecondsSinceEpoch ~/ 1000 - 5,
    );
    app.notifyListeners();
    await tester.pump();
    expect(find.byType(TimerText), findsOneWidget);
    expect(find.byType(PultTick), findsNothing);
    expect(_findPult('routine_1'), findsOneWidget);
  });

  testWidgets('slot collapse mark is smaller and left padding matches right', (
    tester,
  ) async {
    const pad = 8.0;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Block(
            title: 'Slot',
            bg: Colors.white,
            dim: Colors.grey,
            fg: Colors.black,
            signal: Colors.red,
            titleSize: 20,
            pad: pad,
            gap: 0,
            strokeW: 1,
            radiusW: 4,
          ),
        ),
      ),
    );

    final padding = tester.widget<Padding>(
      find
          .descendant(of: find.byType(Stack), matching: find.byType(Padding))
          .first,
    );
    expect(padding.padding, const EdgeInsets.fromLTRB(pad, pad, pad, pad));
    final icon = tester.widget<Icon>(find.byIcon(Icons.unfold_less));
    expect(icon.size, 20 * 1.2 * 0.35);
  });
}

Finder _findPult(String id) =>
    find.byWidgetPredicate((widget) => widget is Pult && widget.spec.id == id);

Future<_RoutinePlateApp> _routinePlateApp(Routine routine) async {
  final bort = OperationalLayer();
  final ticker = AppTicker()..pause();
  final fieldLayer = FieldLayer(_EmptyFieldRepository());
  final routineLayer = RoutineLayer(
    repository: _EmptyRoutineRepository(),
    fieldContext: () => (activeFieldId: null, rootId: null),
    copyTraces: (journal, sourceId, targetId, slots) async {},
  )..routines.add(routine);
  final state = PultState();
  final i18n = await I18n.load('ru');

  return _RoutinePlateApp(
    widget: ProviderScope(
      overrides: [
        operationalLayerProvider.overrideWith((ref) => bort),
        tickerProvider.overrideWith((ref) => ticker),
        fieldLayerProvider.overrideWith((ref) => fieldLayer),
        routineLayerProvider.overrideWith((ref) => routineLayer),
        i18nProvider.overrideWith(() => _TestI18nController(i18n)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: PultScope(
            state: state,
            child: RoutinePlate(
              routine: routine,
              onTap: () {},
              onLongPress: () {},
              onChanged: () {},
            ),
          ),
        ),
      ),
    ),
    notifyListeners: routineLayer.notifyListeners,
    dispose: state.dispose,
  );
}

class _RoutinePlateApp {
  final Widget widget;
  final VoidCallback notifyListeners;
  final VoidCallback dispose;

  const _RoutinePlateApp({
    required this.widget,
    required this.notifyListeners,
    required this.dispose,
  });
}

class _TestI18nController extends I18nController {
  final I18n value;

  _TestI18nController(this.value);

  @override
  I18n? build() => value;
}

class _EmptyFieldRepository implements FieldRepository {
  @override
  Future<FieldCache> load() async => const FieldCache.empty();

  @override
  Future<void> save({
    required int? activeFieldId,
    required List<FieldNode> nodes,
    required int lastJournalId,
  }) async {}
}

class _EmptyRoutineRepository implements RoutineRepository {
  @override
  Future<RoutineCache> load() async => const RoutineCache.empty();

  @override
  Future<void> save({
    required List<Routine> routines,
    required String? lastActiveBlockKind,
    required int lastJournalId,
  }) async {}
}
