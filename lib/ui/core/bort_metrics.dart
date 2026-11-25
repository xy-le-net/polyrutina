import 'package:flutter/material.dart';

import '../../data/operational_layer.dart';
import '../pults/pult_core.dart';
import 'app_scope.dart';

class BortMetrics {
  static const double baseSide = 32;
  static const double minSide = 16;
  static const double maxSide = 64;
  static const double wheelLabelHeightFactor = 0.5;
  static const double wheelLabelGapFactor = 0.1;
  static const double wheelViewportHeightFactor = 2.2;
  static const double wheelHeightFactor =
      wheelLabelHeightFactor + wheelLabelGapFactor + wheelViewportHeightFactor;

  final OperationalLayer bort;
  final double side;

  const BortMetrics({required this.bort, required this.side});

  factory BortMetrics.of(BuildContext context, {bool compact = false}) {
    final pult = PultScope.of(context);
    return BortMetrics(
      bort: BortScope.of(context),
      side: compact ? pult.smallSide : pult.side,
    );
  }

  static double calculateSide({
    required double platformScale,
    required double appScale,
  }) {
    final scaled = baseSide * platformScale * appScale;
    if (!scaled.isFinite) return baseSide;
    return scaled.clamp(minSide, maxSide).toDouble();
  }

  static double textScaleForSide(double side) => side / baseSide;

  double unit(double factor) => side * factor;

  double get framePadding => unit(bort.kFramePad);
  double get radius => unit(bort.kRadius);
  double get stroke => unit(bort.kStroke);
  double get titleFontSize => unit(bort.kTitle);
  double get numberFontSize => unit(bort.kNumber);
  double get smallFontSize => unit(bort.kNumberSmall);
  double get fieldFontSize => numberFontSize * 1.2;
  double get wheelPickerHeight => unit(wheelHeightFactor);
  double get actionFontSize => unit(bort.kName) / 1.6;
  double get fieldPadding => unit(0.18);
  double get actionGap => unit(0.3);
  EdgeInsets get actionPadding =>
      EdgeInsets.symmetric(horizontal: unit(0.3), vertical: unit(0.1));
  double get fieldBorderWidth =>
      (stroke * 4).clamp(1.0, double.infinity).toDouble();
}
