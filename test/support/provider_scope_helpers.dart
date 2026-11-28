import 'package:polyrutina/core/localization/providers.dart';
import 'package:polyrutina/features/settings/application/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:polyrutina/features/settings/application/operational_layer.dart';
import 'package:polyrutina/core/localization/i18n.dart';

class BortScope extends StatelessWidget {
  final OperationalLayer bort;
  final Widget child;

  const BortScope({super.key, required this.bort, required this.child});

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [operationalLayerProvider.overrideWith((ref) => bort)],
    child: child,
  );
}

class I18nScope extends StatelessWidget {
  final I18n i18n;
  final Widget child;

  const I18nScope({super.key, required this.i18n, required this.child});

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [i18nProvider.overrideWith(() => _TestI18nController(i18n))],
    child: child,
  );
}

class _TestI18nController extends I18nController {
  final I18n value;

  _TestI18nController(this.value);

  @override
  I18n? build() => value;
}
