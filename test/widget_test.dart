import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polyrutina/ui/core/control_row.dart';

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
}
