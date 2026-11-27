import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polyrutina/core/application/operational_layer.dart';
import 'package:polyrutina/core/data/trace_layer.dart';
import 'package:polyrutina/core/localization/i18n.dart';
import 'package:polyrutina/shared/presentation/app_scope.dart';
import 'package:polyrutina/shared/presentation/pults/pult_core.dart';
import 'package:polyrutina/shared/presentation/screens/media_viewer.dart';

void main() {
  testWidgets('media list opens a single file without navigation controls', (
    tester,
  ) async {
    final bort = OperationalLayer();
    final pultState = PultState();
    final i18n = await I18n.load('en');
    addTearDown(bort.dispose);
    addTearDown(pultState.dispose);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => BortScope(
          bort: bort,
          child: PultScope(
            state: pultState,
            child: I18nScope(i18n: i18n, child: child!),
          ),
        ),
        home: MediaViewer(
          traceId: 1,
          objectId: 1,
          slot: 'note',
          files: [
            TraceFile(kind: MediaKind.file, path: '', name: 'first.txt'),
            TraceFile(kind: MediaKind.file, path: '', name: 'selected.txt'),
            TraceFile(kind: MediaKind.file, path: '', name: 'third.txt'),
          ],
          startIndex: 1,
          blockTitle: 'note',
          routineTitle: 'routine',
          singleFile: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('selected.txt'), findsOneWidget);
    expect(find.text('1/3'), findsNothing);
    expect(find.byType(Pult), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
