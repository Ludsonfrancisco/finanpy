import 'package:flutter/material.dart';

abstract final class LarTypography {
  static const financial = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w600,
    height: 1.15,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );
}
