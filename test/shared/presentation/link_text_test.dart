import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:polyrutina/features/settings/application/operational_layer.dart';
import 'package:polyrutina/features/settings/application/providers.dart';
import 'package:polyrutina/shared/presentation/control_row.dart';
import 'package:polyrutina/shared/presentation/pults/pult_core.dart';
import 'package:polyrutina/shared/presentation/widgets/dialog_frame.dart';
import 'package:polyrutina/shared/presentation/widgets/link_text.dart';

void main() {
  testWidgets('link backdrop wraps text instead of filling its row', (
    tester,
  ) async {
    final bort = OperationalLayer();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [operationalLayerProvider.overrideWith((ref) => bort)],
        child: const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 280,
                child: LinkText(
                  text: 'open media list',
                  fontSize: 16,
                  onTap: null,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final backdrop = find.descendant(
      of: find.byType(LinkText),
      matching: find.byType(DecoratedBox),
    );
    expect(tester.getSize(backdrop.first).width, lessThan(280));
  });

  testWidgets('dialog frame is laid out below the control row', (tester) async {
    final bort = OperationalLayer();
    final pultState = PultState()..baseSide = 32;
    addTearDown(pultState.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [operationalLayerProvider.overrideWith((ref) => bort)],
        child: PultScope(
          state: pultState,
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (_) => DialogFrame(
                      onDismiss: () => Navigator.of(context).pop(),
                      maxHeight: 900,
                      scrollable: false,
                      child: const SizedBox(
                        height: 900,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Text('Dialog body'),
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final frame = find.ancestor(
      of: find.text('Dialog body'),
      matching: find.byType(DecoratedBox),
    );
    expect(
      tester.getTopLeft(frame.first).dy,
      greaterThanOrEqualTo(ControlRow.reserve(pultState.smallSide)),
    );
  });
}
