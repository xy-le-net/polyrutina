// ═══════════════════════════════════════════════════════════════════
// bort_date_picker.dart — custom date picker in the bort style.
//
// Extracted from routine_card to give the picker its own name and
// contract. The system showDatePicker is not used: the picker keeps
// the app's visual unity (DialogFrame, signal pults, LinkText).
//
// Returns the picked date at midnight (no time component); the
// caller applies the bort's midnight setting on top.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/dialog_frame.dart';
import '../core/link_text.dart';
import '../pults/pult_core.dart';

Future<DateTime?> showBortDatePicker(
  BuildContext context,
  DateTime initial,
) async {
  final bort = BortScope.of(context);
  final i18n = I18nScope.of(context);
  final side = PultScope.of(context).smallSide;

  DateTime viewing = DateTime(initial.year, initial.month, 1);

  return showDialog<DateTime>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setState) {
          final firstWeekday = viewing.weekday;
          final daysInMonth = DateTime(viewing.year, viewing.month + 1, 0).day;
          final totalCells = (((firstWeekday - 1) + daysInMonth + 6) ~/ 7) * 7;

          final grid = <Widget>[];
          for (var i = 0; i < totalCells; i++) {
            final dayNum = i - (firstWeekday - 1) + 1;
            if (dayNum < 1 || dayNum > daysInMonth) {
              grid.add(const SizedBox.shrink());
              continue;
            }
            final isSelected =
                dayNum == initial.day &&
                viewing.month == initial.month &&
                viewing.year == initial.year;

            grid.add(
              GestureDetector(
                onTap: () => Navigator.of(
                  ctx,
                ).pop(DateTime(viewing.year, viewing.month, dayNum)),
                child: Center(
                  child: Container(
                    width: side * 0.9,
                    height: side * 0.9,
                    alignment: Alignment.center,
                    decoration: isSelected
                        ? BoxDecoration(
                            color: bort.bgsignal,
                            borderRadius: BorderRadius.circular(side * 0.1),
                          )
                        : null,
                    child: Text(
                      '$dayNum',
                      style: TextStyle(
                        color: isSelected ? bort.fgsignal : bort.fg,
                        fontSize: side * 0.4,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          return DialogFrame(
            onDismiss: () => Navigator.of(ctx).pop(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Pult(
                      spec: PultSpec(
                        id: 'date_prev',
                        icon: Icons.chevron_left,
                        onTap: () => setState(() {
                          viewing = DateTime(
                            viewing.year,
                            viewing.month - 1,
                            1,
                          );
                        }),
                      ),
                      fg: bort.fg,
                      bg: bort.bg,
                      signal: bort.fgsignal,
                      overrideSize: side,
                    ),
                    Text(
                      '${viewing.year}.${viewing.month.toString().padLeft(2, '0')}',
                      style: TextStyle(color: bort.fg, fontSize: side * 0.5),
                    ),
                    Pult(
                      spec: PultSpec(
                        id: 'date_next',
                        icon: Icons.chevron_right,
                        onTap: () => setState(() {
                          viewing = DateTime(
                            viewing.year,
                            viewing.month + 1,
                            1,
                          );
                        }),
                      ),
                      fg: bort.fg,
                      bg: bort.bg,
                      signal: bort.fgsignal,
                      overrideSize: side,
                    ),
                  ],
                ),
                SizedBox(height: side * 0.5),
                SizedBox(
                  width: side * 6.3,
                  child: GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 7,
                    childAspectRatio: 1,
                    children: grid,
                  ),
                ),
                SizedBox(height: side * 0.5),
                Align(
                  alignment: Alignment.centerRight,
                  child: LinkText(
                    text: i18n.t('common.cancel'),
                    color: bort.mid,
                    fontSize: side * bort.kName / 1.6,
                    padding: EdgeInsets.symmetric(
                      horizontal: side * 0.3,
                      vertical: side * 0.1,
                    ),
                    onTap: () => Navigator.of(ctx).pop(),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
