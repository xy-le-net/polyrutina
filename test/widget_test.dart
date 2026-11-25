import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polyrutina/data/operational_layer.dart';
import 'package:polyrutina/ui/core/app_scope.dart';
import 'package:polyrutina/ui/core/control_row.dart';
import 'package:polyrutina/ui/pults/pult_core.dart';

void main() {
  testWidgets('transparent app icon asset renders', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Image(image: AssetImage('assets/icon.png'))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('control row stays aligned to the root pult height', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ControlRow(
            rootSide: 32,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [Text('month'), Text('subtitle')],
            ),
          ),
        ),
      ),
    );

    final controlRow = find.descendant(
      of: find.byType(ControlRow),
      matching: find.byType(Row),
    );
    expect(tester.getSize(controlRow).height, 40);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pult with tap submenu displays its secondary-action dot', (
    tester,
  ) async {
    final bort = OperationalLayer();
    final pultState = PultState();
    addTearDown(bort.dispose);
    addTearDown(pultState.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: BortScope(
          bort: bort,
          child: PultScope(
            state: pultState,
            child: const Pult(
              spec: PultSpec(
                id: 'menu',
                icon: Icons.more_horiz,
                subsBuilder: _testSubmenu,
              ),
              fg: Colors.black,
              bg: Colors.white,
              signal: Colors.red,
            ),
          ),
        ),
      ),
    );

    final dot = find.descendant(
      of: find.byType(Pult),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).shape == BoxShape.circle,
      ),
    );
    expect(dot, findsOneWidget);
  });
}

List<PultSpec> _testSubmenu() => const [
  PultSpec(id: 'option', icon: Icons.check),
];
