import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:polyrutina/core/localization/i18n.dart';
import 'package:polyrutina/core/localization/providers.dart';
import 'package:polyrutina/features/routines/presentation/pickers/notice_picker.dart';
import 'package:polyrutina/features/settings/application/operational_layer.dart';
import 'package:polyrutina/features/settings/application/providers.dart';
import 'package:polyrutina/shared/presentation/pults/pult_core.dart';

void main() {
  testWidgets('notice picker only offers OK for a nonzero interval', (
    tester,
  ) async {
    final bort = OperationalLayer();
    final pultState = PultState()..baseSide = 32;
    final i18n = await I18n.load('ru');
    addTearDown(pultState.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          operationalLayerProvider.overrideWith((ref) => bort),
          i18nProvider.overrideWith(() => _TestI18nController(i18n)),
        ],
        child: PultScope(
          state: pultState,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Column(
                children: [
                  TextButton(
                    onPressed: () =>
                        showNoticePicker(context, initialSeconds: 0),
                    child: const Text('Zero'),
                  ),
                  TextButton(
                    onPressed: () => showNoticePicker(
                      context,
                      initialSeconds: 60,
                      noticeSet: true,
                    ),
                    child: const Text('Nonzero'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Zero'));
    await tester.pumpAndSettle();
    expect(find.text(i18n.t('common.ok')), findsNothing);
    expect(find.text(':'), findsNothing);
    await tester.tap(find.text(i18n.t('common.cancel')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nonzero'));
    await tester.pumpAndSettle();
    expect(find.text(i18n.t('common.ok')), findsOneWidget);
  });
}

class _TestI18nController extends I18nController {
  final I18n value;

  _TestI18nController(this.value);

  @override
  I18n? build() => value;
}
