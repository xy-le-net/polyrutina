import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polyrutina/core/localization/i18n.dart';
import 'package:polyrutina/core/application/operational_layer.dart';
import 'package:polyrutina/shared/presentation/pickers/bort_date_picker.dart';
import 'package:polyrutina/shared/presentation/app_scope.dart';
import 'package:polyrutina/shared/presentation/widgets/bort_field.dart';
import 'package:polyrutina/shared/presentation/bort_metrics.dart';
import 'package:polyrutina/shared/presentation/control_row.dart';
import 'package:polyrutina/shared/presentation/timer_text.dart';
import 'package:polyrutina/shared/presentation/widgets/wheel_picker.dart';
import 'package:polyrutina/shared/presentation/pults/pult_core.dart';

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

  test('text roles share the Rubka base size', () {
    const side = 40.0;
    final base = BortMetrics.fontSizeForSide(side, BortTextRole.base);
    expect(BortMetrics.fontSizeForSide(side, BortTextRole.header) / base, 1.2);
    expect(BortMetrics.fontSizeForSide(side, BortTextRole.caption) / base, 0.8);
    expect(BortMetrics.fontSizeForSide(side, BortTextRole.edit) / base, 1.1);

    final theme = BortMetrics.normalizeTextTheme(ThemeData().textTheme, 18);
    final sizes = [
      theme.displayLarge,
      theme.displayMedium,
      theme.displaySmall,
      theme.headlineLarge,
      theme.headlineMedium,
      theme.headlineSmall,
      theme.titleLarge,
      theme.titleMedium,
      theme.titleSmall,
      theme.bodyLarge,
      theme.bodyMedium,
      theme.bodySmall,
      theme.labelLarge,
      theme.labelMedium,
      theme.labelSmall,
    ];
    expect(sizes.every((style) => style?.fontSize == 18), isTrue);
  });

  testWidgets('compact layouts retain the shared base font size', (
    tester,
  ) async {
    final bort = OperationalLayer();
    final pultState = PultState()..baseSide = 32;
    addTearDown(bort.dispose);
    addTearDown(pultState.dispose);

    double? compactSize;
    double? regularSize;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => BortScope(
          bort: bort,
          child: PultScope(
            state: pultState,
            child: Builder(
              builder: (context) {
                compactSize = BortMetrics.of(
                  context,
                  compact: true,
                ).textSize(BortTextRole.base);
                regularSize = BortMetrics.of(
                  context,
                ).textSize(BortTextRole.base);
                return child!;
              },
            ),
          ),
        ),
        home: const Scaffold(),
      ),
    );

    expect(compactSize, 12.8);
    expect(regularSize, 12.8);
  });

  testWidgets('wheel scroll moves one item and remains draggable', (
    tester,
  ) async {
    final bort = OperationalLayer();
    final pultState = PultState()..baseSide = 32;
    addTearDown(bort.dispose);
    addTearDown(pultState.dispose);

    var value = 4;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => BortScope(
          bort: bort,
          child: PultScope(state: pultState, child: child!),
        ),
        home: Scaffold(
          body: Center(
            child: WheelValuePicker(
              side: 32,
              columns: [
                WheelColumn(
                  label: 'minutes',
                  value: value,
                  itemCount: 60,
                  onChanged: (next) => value = next,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final picker = find.byType(CupertinoPicker);
    final position = tester.getCenter(picker);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: position,
        scrollDelta: const Offset(0, 120),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pumpAndSettle();
    expect(value, 5);

    await tester.drag(picker, const Offset(0, -50));
    await tester.pumpAndSettle();
    expect(value, greaterThan(5));
  });

  testWidgets('BortField Enter commits and triggers its submit action', (
    tester,
  ) async {
    final bort = OperationalLayer();
    final pultState = PultState();
    addTearDown(bort.dispose);
    addTearDown(pultState.dispose);

    final committed = <String>[];
    var submitted = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => BortScope(
          bort: bort,
          child: PultScope(state: pultState, child: child!),
        ),
        home: Scaffold(
          body: BortField(
            initial: 'before',
            fg: Colors.black,
            readOnly: false,
            onCommit: (value) async => committed.add(value),
            onSubmitted: () async {
              submitted++;
            },
          ),
        ),
      ),
    );

    final field = find.byType(TextField);
    expect(tester.widget<TextField>(field).style?.fontSize, 12.8);
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(field).style?.fontSize,
      closeTo(14.08, .01),
    );

    await tester.enterText(field, 'after');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(committed, ['after']);
    expect(submitted, 1);
    expect(tester.widget<TextField>(field).style?.fontSize, 12.8);
  });

  testWidgets('zero-duration ticker has no visible value', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TimerText(
          seconds: 0,
          running: true,
          fg: Colors.black,
          dim: Colors.grey,
          numberSize: 12,
          t: (key) => key,
        ),
      ),
    );

    expect(find.text('0'), findsNothing);
    expect(find.text('s'), findsNothing);
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
    expect(tester.getSize(controlRow).height, 48);
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

  testWidgets('right click does not trigger a pult long-press action', (
    tester,
  ) async {
    final bort = OperationalLayer();
    final pultState = PultState();
    addTearDown(bort.dispose);
    addTearDown(pultState.dispose);

    await tester.pumpWidget(_pultSubmenuApp(bort, pultState));
    await tester.tap(find.byType(Pult), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(find.byType(Pult), findsOneWidget);
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
