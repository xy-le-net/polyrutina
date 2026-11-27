import 'package:material_ui/material_ui.dart';

import 'package:polyrutina/core/domain/bort_time.dart';
import 'package:polyrutina/shared/presentation/app_scope.dart';
import 'package:polyrutina/shared/presentation/bort_metrics.dart';
import 'package:polyrutina/shared/presentation/widgets/dialog_frame.dart';
import 'package:polyrutina/shared/presentation/widgets/wheel_picker.dart';
import 'package:polyrutina/shared/presentation/pults/pult_core.dart';

Future<DateTime?> showBortDatePicker(
  BuildContext context,
  DateTime initial,
) async {
  final bort = BortScope.of(context);
  final i18n = I18nScope.of(context);
  final metrics = BortMetrics.of(context, compact: true);
  final side = metrics.side;

  DateTime viewing = DateTime(initial.year, initial.month, 1);

  String two(int n) => n.toString().padLeft(2, '0');

  // Seed the wheel: the caller's time when it carries one, technical noon otherwise.
  final hasTime = initial.hour != 0 || initial.minute != 0;
  var selectedDay = initial.day;
  var selectedMonth = initial.month;
  var selectedYear = initial.year;
  var hour = hasTime ? initial.hour : kBortTechNoonHour;
  var minute = hasTime ? initial.minute : kBortTechNoonMinute;

  try {
    final picked = await showDialog<DateTime>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            final firstWeekday = viewing.weekday;
            final daysInMonth = DateTime(
              viewing.year,
              viewing.month + 1,
              0,
            ).day;

            // Six rows fixed. The block never changes height across
            // months and never truncates a 31-day month.
            const int rows = 6;
            const totalCells = rows * 7;

            final grid = <Widget>[];
            for (var i = 0; i < totalCells; i++) {
              final dayNum = i - (firstWeekday - 1) + 1;
              if (dayNum < 1 || dayNum > daysInMonth) {
                grid.add(const SizedBox.shrink());
                continue;
              }
              final isSelected =
                  dayNum == selectedDay &&
                  viewing.month == selectedMonth &&
                  viewing.year == selectedYear;

              grid.add(
                GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedDay = dayNum;
                      selectedMonth = viewing.month;
                      selectedYear = viewing.year;
                    });
                  },
                  child: Center(
                    child: Container(
                      width: side * 0.44,
                      height: side * 0.44,
                      alignment: Alignment.center,
                      decoration: isSelected
                          ? BoxDecoration(
                              color: bort.bgsignal,
                              borderRadius: BorderRadius.circular(side * 0.14),
                            )
                          : null,
                      child: Text(
                        '$dayNum',
                        style: TextStyle(
                          color: isSelected ? bort.fgsignal : bort.fg,
                          fontSize: metrics.textSize(BortTextRole.caption),
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }

            final gridW = side * 3.15;
            final gridH = gridW / 7 * rows;

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
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${viewing.year}.${two(viewing.month)}',
                            style: TextStyle(
                              color: bort.fg,
                              fontSize: metrics.textSize(BortTextRole.header),
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
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
                  SizedBox(height: metrics.unit(0.5)),
                  SizedBox(
                    width: gridW,
                    height: gridH,
                    child: GridView.count(
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 7,
                      childAspectRatio: 1,
                      children: grid,
                    ),
                  ),
                  SizedBox(height: metrics.unit(0.5)),
                  SizedBox(
                    height: metrics.wheelPickerHeight,
                    child: WheelValuePicker(
                      columns: [
                        WheelColumn(
                          label: i18n.t('notice.hours'),
                          separator: ':',
                          value: hour,
                          itemCount: 24,
                          onChanged: (v) => setState(() => hour = v),
                          formatter: two,
                        ),
                        WheelColumn(
                          label: i18n.t('notice.minutes'),
                          separator: ':',
                          value: minute,
                          itemCount: 60,
                          onChanged: (v) => setState(() => minute = v),
                          formatter: two,
                        ),
                      ],
                      side: side,
                    ),
                  ),
                  SizedBox(height: metrics.unit(0.5)),
                  DialogActions(
                    actions: [
                      DialogAction(
                        label: i18n.t('common.cancel'),
                        onTap: () => Navigator.of(ctx).pop(),
                      ),
                      DialogAction(
                        label: i18n.t('common.ok'),
                        onTap: () => Navigator.of(ctx).pop(
                          DateTime(
                            selectedYear,
                            selectedMonth,
                            selectedDay
                                .clamp(
                                  1,
                                  DateTime(
                                    selectedYear,
                                    selectedMonth + 1,
                                    0,
                                  ).day,
                                )
                                .toInt(),
                            hour,
                            minute,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    return picked;
  } catch (_) {
    return null;
  }
}
