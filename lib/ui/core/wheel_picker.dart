import 'package:flutter/cupertino.dart';

import 'app_scope.dart';

class WheelValuePicker extends StatelessWidget {
  final List<WheelColumn> columns;
  final double side;
  final VoidCallback onCancel;
  final VoidCallback onOk;
  final String cancelText;
  final String okText;

  const WheelValuePicker({
    super.key,
    required this.columns,
    required this.side,
    required this.onCancel,
    required this.onOk,
    required this.cancelText,
    required this.okText,
  });

  @override
  Widget build(BuildContext context) {
    final bort = BortScope.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < columns.length; i++) ...[
          if (i > 0)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: side * 0.08),
              child: Text(
                columns[i].separator,
                style: TextStyle(
                  color: bort.fg,
                  fontSize: side * 0.45,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          _WheelColumn(column: columns[i], side: side),
        ],
      ],
    );
  }
}

class WheelColumn {
  final String label;
  final String separator;
  final int value;
  final int itemCount;
  final ValueChanged<int> onChanged;
  final String Function(int)? formatter;

  const WheelColumn({
    required this.label,
    this.separator = '',
    required this.value,
    required this.itemCount,
    required this.onChanged,
    this.formatter,
  });
}

class _WheelColumn extends StatelessWidget {
  final WheelColumn column;
  final double side;

  const _WheelColumn({required this.column, required this.side});

  @override
  Widget build(BuildContext context) {
    final bort = BortScope.of(context);
    final controller = FixedExtentScrollController(
      initialItem: column.value.clamp(0, column.itemCount - 1),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          column.label,
          style: TextStyle(
            color: bort.mid,
            fontSize: side * 0.3,
            decoration: TextDecoration.none,
          ),
        ),
        SizedBox(height: side * 0.1),
        SizedBox(
          width: side * (column.itemCount > 24 ? 1.15 : 1.05),
          height: side * 2.2,
          child: CupertinoPicker(
            scrollController: controller,
            itemExtent: side * 0.65,
            useMagnifier: true,
            magnification: 1.1,
            diameterRatio: 1.5,
            squeeze: 1.05,
            onSelectedItemChanged: column.onChanged,
            children: List<Widget>.generate(
              column.itemCount,
              (i) => Center(
                child: Text(
                  column.formatter?.call(i) ?? i.toString(),
                  style: TextStyle(
                    color: bort.fg,
                    fontSize: side * 0.42,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
