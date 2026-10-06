// ═══════════════════════════════════════════════════════════════════
// stub_tab.dart — заглушка для неготовых вкладок.
//
// Показывает две строки: название раздела и обещание. Ничего более.
// Используется для вкладок Поле (карта) и Артель, кои впереди.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import 'app_scope.dart';

class StubTab extends StatelessWidget {
  const StubTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final i18n = app.i18n;
    final bort = app.bort;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            i18n.t('stub.title'),
            style: TextStyle(color: bort.fg, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            i18n.t('stub.text'),
            style: TextStyle(color: bort.dim),
          ),
        ],
      ),
    );
  }
}
