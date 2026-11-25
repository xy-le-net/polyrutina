import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polyrutina/data/i18n.dart';
import 'package:polyrutina/data/operational_layer.dart';
import 'package:polyrutina/ui/cards/bort_date_picker.dart';
import 'package:polyrutina/ui/core/app_scope.dart';
import 'package:polyrutina/ui/core/bort_metrics.dart';
import 'package:polyrutina/ui/core/control_row.dart';
import 'package:polyrutina/ui/pults/pult_core.dart';

void main() {
  test('layout scale is bounded and shared by text and controls', () {
    final side = BortMetrics.calculateSide(platformScale: 1, appScale: 1.4);
    expect(side, closeTo(44.8, 0.001));
    expect(BortMetrics.textScaleForSide(side), closeTo(1.4, 0.001));
    expect(
      BortMetrics.calculateSide(platformScale: 2, appScale: 2),
      BortMetrics.maxSide,
    );
    expect(
      BortMetrics.calculateSide(platformScale: 0.5, appScale: 0.5),
      BortMetrics.minSide,
    );

    final bort = OperationalLayer();
    addTearDown(bort.dispose);
    bort.scale = 5;
    expect(bort.scale, OperationalLayer.maxScale);
    bort.scale = 0.1;
    expect(bort.scale, OperationalLayer.minScale);
    bort.scale = double.nan;
    expect(bort.scale, OperationalLayer.minScale);
  });

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

  testWidgets('date picker avoids overflow across screen and text scales', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);

    final bort = OperationalLayer();
    final pultState = PultState()..maxSide = 64;
    final i18n = await I18n.load('ru');
    addTearDown(bort.dispose);
    addTearDown(pultState.dispose);

    const samples = [
      (size: Size(360, 640), side: 16.0, textScale: 1.0),
      (size: Size(360, 640), side: 64.0, textScale: 2.0),
      (size: Size(900, 1068), side: 32.0, textScale: 1.4),
    ];

    for (final sample in samples) {
      tester.view.physicalSize = sample.size;
      pultState.baseSide = sample.side;

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(sample.textScale)),
            child: BortScope(
              bort: bort,
              child: PultScope(
                state: pultState,
                child: I18nScope(i18n: i18n, child: child!),
              ),
            ),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  showBortDatePicker(context, DateTime(2026, 12, 8));
                },
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open picker'));
      await tester.pumpAndSettle();
      final exception = tester.takeException();
      expect(exception, isNull, reason: '$sample');

      await tester.tap(find.text(i18n.t('common.cancel')));
      await tester.pumpAndSettle();
    }

    addTearDown(tester.view.resetPhysicalSize);
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

  testWidgets('pult with tap submenu opens from a long press', (tester) async {
    final bort = OperationalLayer();
    final pultState = PultState();
    addTearDown(bort.dispose);
    addTearDown(pultState.dispose);

    await tester.pumpWidget(_pultSubmenuApp(bort, pultState));
    await tester.longPress(find.byType(Pult));
    await tester.pumpAndSettle();

    expect(find.byType(Pult), findsNWidgets(2));
  });

  testWidgets('pult with tap submenu opens from a right click', (tester) async {
    final bort = OperationalLayer();
    final pultState = PultState();
    addTearDown(bort.dispose);
    addTearDown(pultState.dispose);

    await tester.pumpWidget(_pultSubmenuApp(bort, pultState));
    await tester.tap(find.byType(Pult), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(find.byType(Pult), findsNWidgets(2));
  });
}

List<PultSpec> _testSubmenu() => const [
  PultSpec(id: 'option', icon: Icons.check),
];

Widget _pultSubmenuApp(OperationalLayer bort, PultState pultState) =>
    MaterialApp(
      builder: (context, child) => BortScope(
        bort: bort,
        child: PultScope(state: pultState, child: child!),
      ),
      home: const Scaffold(
        body: Pult(
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
    );
