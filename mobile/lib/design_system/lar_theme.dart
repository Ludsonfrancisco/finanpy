import 'package:flutter/material.dart';
import 'lar_colors.dart';

abstract final class LarTheme {
  static final light = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: LarColors.lightCanvas,
    colorScheme: const ColorScheme(
      brightness: Brightness.light,
      primary: LarColors.mineral,
      onPrimary: LarColors.lightSurface,
      secondary: LarColors.champagne,
      onSecondary: LarColors.lightText,
      error: LarColors.danger,
      onError: LarColors.lightSurface,
      surface: LarColors.lightSurface,
      onSurface: LarColors.lightText,
      outline: Color(0xFF8B8A80),
      shadow: Color(0x22091311),
    ),
    dividerColor: const Color(0xFFCBC5B9),
    navigationBarTheme: const NavigationBarThemeData(
      height: 72,
      indicatorColor: Color(0x33C7A35A),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      indicatorColor: Color(0x33C7A35A),
      useIndicator: true,
    ),
  );
  static final dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: LarColors.darkCanvas,
    colorScheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: LarColors.champagne,
      onPrimary: LarColors.lightText,
      secondary: LarColors.mineral,
      onSecondary: LarColors.darkText,
      error: LarColors.danger,
      onError: LarColors.lightSurface,
      surface: LarColors.darkSurface,
      onSurface: LarColors.darkText,
      outline: Color(0xFF8D958D),
      shadow: Color(0x55000000),
    ),
    dividerColor: const Color(0xFF31403A),
    navigationBarTheme: const NavigationBarThemeData(
      height: 72,
      indicatorColor: Color(0x33C7A35A),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      indicatorColor: Color(0x33C7A35A),
      useIndicator: true,
    ),
  );
}
