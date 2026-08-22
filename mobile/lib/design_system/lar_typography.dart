import 'package:flutter/material.dart';

import 'lar_tokens.g.dart';

abstract final class LarTypography {
  static const financial = TextStyle(
    fontSize: LarGeneratedTypography.financialFontSize,
    fontWeight: LarGeneratedTypography.financialFontWeight,
    height: LarGeneratedTypography.financialLineHeight,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );
}
