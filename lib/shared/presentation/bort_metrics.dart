import 'package:material_ui/material_ui.dart';

import 'package:polyrutina/core/application/operational_layer.dart';
import 'package:polyrutina/shared/presentation/pults/pult_core.dart';
import 'package:polyrutina/shared/presentation/app_scope.dart';

enum BortTextRole {
  caption(0.8),
  base(1),
  edit(1.1),
  header(1.2);

  final double factor;

  const BortTextRole(this.factor);
}

class BortMetrics {
  static const double baseSide = 32;
  static const double minSide = 16;
  static const double maxSide = 64;
  static const double baseFontFactor = 0.4;
  static const double wheelLabelHeightFactor = 0.5;
  static const double wheelLabelGapFactor = 0.1;
  static const double wheelViewportHeightFactor = 2.2;
  static const double wheelHeightFactor =
      wheelLabelHeightFactor + wheelLabelGapFactor + wheelViewportHeightFactor;

  final OperationalLayer bort;
  final double side;
  final double fontSide;

  const BortMetrics({required this.bort, required this.side, double? fontSide})
    : fontSide = fontSide ?? side;

  factory BortMetrics.of(BuildContext context, {bool compact = false}) {
    final pult = PultScope.of(context);
    return BortMetrics(
      bort: BortScope.of(context),
      side: compact ? pult.smallSide : pult.side,
      fontSide: pult.side,
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

  double textSize(BortTextRole role) => fontSizeForSide(fontSide, role);

  static double fontSizeForSide(double side, BortTextRole role) =>
      side * baseFontFactor * role.factor;

  static TextTheme normalizeTextTheme(TextTheme theme, double fontSize) {
    TextStyle? sized(TextStyle? style) => style?.copyWith(fontSize: fontSize);

    return theme.copyWith(
      displayLarge: sized(theme.displayLarge),
      displayMedium: sized(theme.displayMedium),
      displaySmall: sized(theme.displaySmall),
      headlineLarge: sized(theme.headlineLarge),
      headlineMedium: sized(theme.headlineMedium),
      headlineSmall: sized(theme.headlineSmall),
      titleLarge: sized(theme.titleLarge),
      titleMedium: sized(theme.titleMedium),
      titleSmall: sized(theme.titleSmall),
      bodyLarge: sized(theme.bodyLarge),
      bodyMedium: sized(theme.bodyMedium),
      bodySmall: sized(theme.bodySmall),
      labelLarge: sized(theme.labelLarge),
      labelMedium: sized(theme.labelMedium),
      labelSmall: sized(theme.labelSmall),
    );
  }

  double get framePadding => unit(bort.kFramePad);
  double get radius => unit(bort.kRadius);
  double get stroke => unit(bort.kStroke);
  double get titleFontSize => textSize(BortTextRole.header);
  double get numberFontSize => textSize(BortTextRole.base);
  double get baseFontSize => textSize(BortTextRole.base);
  double get smallFontSize => textSize(BortTextRole.caption);
  double get fieldFontSize => textSize(BortTextRole.edit);
  double get wheelPickerHeight => unit(wheelHeightFactor);
  double get actionFontSize => textSize(BortTextRole.base);
  double get fieldPadding => unit(0.18);
  double get actionGap => unit(0.3);
  EdgeInsets get actionPadding =>
      EdgeInsets.symmetric(horizontal: unit(0.3), vertical: unit(0.1));
  double get fieldBorderWidth =>
      (stroke * 4).clamp(1.0, double.infinity).toDouble();
}
