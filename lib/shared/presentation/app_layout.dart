import 'package:polyrutina/shared/presentation/bort_metrics.dart';

const double appMaxWidthBaseCharacters = 68;
const double appAverageBaseCharacterWidth = 0.55;

double appScreenMaxWidth(double side) =>
    BortMetrics.fontSizeForSide(side, BortTextRole.base) *
    appAverageBaseCharacterWidth *
    appMaxWidthBaseCharacters;
