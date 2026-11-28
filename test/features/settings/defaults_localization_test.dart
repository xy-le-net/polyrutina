import 'package:flutter_test/flutter_test.dart';
import 'package:polyrutina/core/localization/i18n.dart';
import 'package:polyrutina/features/settings/application/operational_layer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('routine mutual exclusion is off by default', () {
    final bort = OperationalLayer();
    expect(bort.mutexRoutines, isFalse);
    expect(bort.shiftEnabled, isTrue);
    expect(bort.mapScale, 64);
    bort.dispose();
  });

  test('wheel register labels stay within three characters', () async {
    final ru = await I18n.load('ru');
    final en = await I18n.load('en');
    const keys = [
      'notice.days',
      'notice.hours',
      'notice.minutes',
      'notice.seconds',
    ];

    expect(keys.every((key) => ru.t(key).length <= 3), isTrue);
    expect(keys.every((key) => en.t(key).length <= 3), isTrue);
    expect(ru.t('lang.ru'), 'Русский');
    expect(ru.t('lang.en'), 'English');
    expect(en.t('lang.ru'), 'Русский');
    expect(en.t('lang.en'), 'English');
    expect(ru.t('bort.default_slots'), 'слоты по умолчанию');
    expect(en.t('bort.default_slots'), 'default slots');
    expect(ru.t('help.bort.reset'), contains('не касается рабочих данных'));
    expect(en.t('help.bort.reset'), contains('does not affect work data'));
  });
}
