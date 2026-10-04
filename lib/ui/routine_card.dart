// ═══════════════════════════════════════════════════════════════════
// routine_card.dart — карточка рутины.
//
// Пока заготовка: номер и надпись «в работе».
// Далее: пять блоков с пульсами, обзорный блок.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import 'app_scope.dart';

class RoutineCard extends StatelessWidget {
  final int routineId;
  const RoutineCard({super.key, required this.routineId});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final brightness = Theme.of(context).brightness;
    final dim = bort.currentDim(brightness);

    final r = bort.findRoutine(routineId);
    if (r == null) {
      return Scaffold(
        body: Center(
          child: Text(app.i18n.t('routine.not_found')),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Text(
            '#${r.id} — ${app.i18n.t(
              r.runningBlock != null ? 'routine.in_work' : 'routine.waiting',
            )}',
            style: TextStyle(color: dim),
          ),
        ),
      ),
    );
  }
}
