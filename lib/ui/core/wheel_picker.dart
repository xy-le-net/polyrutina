import 'package:flutter/gestures.dart';
import 'package:flutter/cupertino.dart';

import 'app_scope.dart';
import 'bort_metrics.dart';

class WheelValuePicker extends StatelessWidget {
  final List<WheelColumn> columns;
  final double side;

  const WheelValuePicker({
    super.key,
    required this.columns,
    required this.side,
  });

  @override
  Widget build(BuildContext context) {
    final bort = BortScope.of(context);
    final columnHeight = side * BortMetrics.wheelHeightFactor;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < columns.length; i++) ...[
          if (i > 0)
            SizedBox(
              height: columnHeight,
              child: Align(
                alignment: const Alignment(0, 0.22),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: side * 0.08),
                  child: Text(
                    columns[i].separator,
                    style: TextStyle(
                      color: bort.fg,
                      fontSize: BortMetrics.fontSizeForSide(
                        side,
                        BortTextRole.base,
                      ),
                      decoration: TextDecoration.none,
                    ),
                  ),
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

class _WheelColumn extends StatefulWidget {
  final WheelColumn column;
  final double side;

  const _WheelColumn({required this.column, required this.side});

  @override
  State<_WheelColumn> createState() => _WheelColumnState();
}

class _WheelColumnState extends State<_WheelColumn> {
  late final FixedExtentScrollController _controller;
  late int _selectedValue;
  int? _pendingWheelValue;
  bool _wheelUpdateScheduled = false;

  @override
  void initState() {
    super.initState();
    _selectedValue = _boundedValue;
    _controller = FixedExtentScrollController(initialItem: _selectedValue);
  }

  int get _boundedValue =>
      widget.column.value.clamp(0, widget.column.itemCount - 1).toInt();

  @override
  void didUpdateWidget(covariant _WheelColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    final value = _boundedValue;
    if (value != _selectedValue) {
      _selectedValue = value;
      _controller.jumpToItem(value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final delta = event.scrollDelta.dy;
    if (delta == 0) return;
    final current = _pendingWheelValue ?? _selectedValue;
    final next = (current + (delta > 0 ? 1 : -1))
        .clamp(0, widget.column.itemCount - 1)
        .toInt();
    if (next == current) return;
    _pendingWheelValue = next;
    if (_wheelUpdateScheduled) return;
    _wheelUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _wheelUpdateScheduled = false;
      final value = _pendingWheelValue;
      _pendingWheelValue = null;
      if (!mounted || value == null) return;
      setState(() => _selectedValue = value);
      if (_controller.hasClients) _controller.jumpToItem(value);
      widget.column.onChanged(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bort = BortScope.of(context);
    final column = widget.column;
    final side = widget.side;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: side * BortMetrics.wheelLabelHeightFactor,
          child: Center(
            child: Text(
              column.label,
              maxLines: 1,
              style: TextStyle(
                color: bort.mid,
                fontSize: BortMetrics.fontSizeForSide(
                  side,
                  BortTextRole.caption,
                ),
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
        SizedBox(height: side * BortMetrics.wheelLabelGapFactor),
        SizedBox(
          width: side,
          height: side * BortMetrics.wheelViewportHeightFactor,
          child: Listener(
            onPointerSignal: _handlePointerSignal,
            child: CupertinoPicker.builder(
              scrollController: _controller,
              itemExtent: side * 0.65,
              useMagnifier: true,
              magnification: 1.1,
              diameterRatio: 1.5,
              squeeze: 1.05,
              selectionOverlay: const SizedBox.shrink(),
              onSelectedItemChanged: (value) {
                setState(() => _selectedValue = value);
                column.onChanged(value);
              },
              childCount: column.itemCount,
              itemBuilder: (context, i) => Container(
                alignment: Alignment.center,
                decoration: i == _selectedValue
                    ? BoxDecoration(
                        color: bort.fgsignal,
                        borderRadius: BorderRadius.circular(side * 0.08),
                      )
                    : null,
                child: Text(
                  column.formatter?.call(i) ?? i.toString(),
                  style: TextStyle(
                    color: i == _selectedValue ? bort.bgsignal : bort.fg,
                    fontSize: BortMetrics.fontSizeForSide(
                      side,
                      BortTextRole.base,
                    ),
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
