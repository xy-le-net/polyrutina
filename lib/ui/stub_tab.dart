// ═══════════════════════════════════════════════════════════════════
// stub_tab.dart — заглушка для неготовых вкладок.
//
// Показывает две строки: название раздела и обещание. Ничего более.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import 'app_scope.dart';

class StubTab extends StatelessWidget {
  const StubTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final i18n = app.i18n;
    final brightness = Theme.of(context).brightness;
    final fg = app.bort.currentFg(brightness);
    final dim = app.bort.currentDim(brightness);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            i18n.t('stub.title'),
            style: TextStyle(color: fg, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            i18n.t('stub.text'),
            style: TextStyle(color: dim),
          ),
        ],
      ),
    );
  }
}
