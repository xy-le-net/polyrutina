import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polyrutina/core/localization/i18n.dart';

final i18nProvider = NotifierProvider<I18nController, I18n?>(
  I18nController.new,
);

class I18nController extends Notifier<I18n?> {
  @override
  I18n? build() => null;

  void update(I18n value) {
    state = value;
  }
}
