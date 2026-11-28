import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:polyrutina/core/localization/i18n.dart';
import 'package:polyrutina/features/settings/application/operational_layer.dart';
import 'package:polyrutina/shared/presentation/widgets/dialog_frame.dart';
import 'package:polyrutina/shared/presentation/widgets/wheel_picker.dart';
import 'package:polyrutina/shared/presentation/pults/pult_core.dart';

import '../../support/provider_scope_helpers.dart';

void main() {
  testWidgets('duration picker keeps the seconds wheel editable', (
    tester,
  ) async {
    final bort = OperationalLayer();
    final pultState = PultState()..baseSide = 32;
    final i18n = await I18n.load('ru');

    int? edited;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => BortScope(
          bort: bort,
          child: I18nScope(
            i18n: i18n,
            child: PultScope(state: pultState, child: child!),
          ),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                edited = await WheelValuePicker.showDurationWheelPicker(
                  context,
                  initialSeconds: 3661,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final secondsPicker = find.byType(CupertinoPicker).at(2);
    final secondsRect = tester.getRect(secondsPicker);
    final dialogRect = tester.getRect(find.byType(DialogFrame));
    expect(secondsRect.left, greaterThanOrEqualTo(dialogRect.left));
    expect(secondsRect.right, lessThanOrEqualTo(dialogRect.right));

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(secondsPicker),
        scrollDelta: const Offset(0, 120),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pump();
    await tester.tap(find.text(i18n.t('common.ok')));
    await tester.pumpAndSettle();

    expect(edited, isNot(3661));
  });
}
