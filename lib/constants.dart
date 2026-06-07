import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF6C63FF);
  static const primaryDark = Color(0xFF3F3D99);
  static const accent = Color(0xFF4FC3F7);
  static const error = Color(0xFFFF5252);
  static const success = Color(0xFF69F0AE);
  static const bubbleGradientStart = Color(0xFF6C63FF);
  static const bubbleGradientEnd = Color(0xFF8B6FFF);

  static const _darkBg = Color(0xFF111118);
  static const _darkSurface = Color(0xFF1A1A2E);
  static const _darkSurfaceLight = Color(0xFF242440);
  static const _darkTextPrimary = Color(0xFFF0F0F5);
  static const _darkTextSecondary = Color(0xFF9898B0);
  static const _darkSidebarBg = Color(0xFF0E0E1A);
  static const _darkInputBg = Color(0xFF1E1E32);
  static const _darkBorder = Color(0xFF2A2A45);

  static const _lightBg = Color(0xFFF5F5FA);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightSurfaceLight = Color(0xFFEEEEF5);
  static const _lightTextPrimary = Color(0xFF1A1A2E);
  static const _lightTextSecondary = Color(0xFF6B6B80);
  static const _lightSidebarBg = Color(0xFFF0F0F5);
  static const _lightInputBg = Color(0xFFE8E8F0);
  static const _lightBorder = Color(0xFFD0D0DC);

  static Color _pick(BuildContext context, Color dark, Color light) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  static Color background(BuildContext context) =>
      _pick(context, _darkBg, _lightBg);
  static Color surface(BuildContext context) =>
      _pick(context, _darkSurface, _lightSurface);
  static Color surfaceLight(BuildContext context) =>
      _pick(context, _darkSurfaceLight, _lightSurfaceLight);
  static Color textPrimary(BuildContext context) =>
      _pick(context, _darkTextPrimary, _lightTextPrimary);
  static Color textSecondary(BuildContext context) =>
      _pick(context, _darkTextSecondary, _lightTextSecondary);
  static Color sidebarBg(BuildContext context) =>
      _pick(context, _darkSidebarBg, _lightSidebarBg);
  static Color inputBg(BuildContext context) =>
      _pick(context, _darkInputBg, _lightInputBg);
  static Color border(BuildContext context) =>
      _pick(context, _darkBorder, _lightBorder);
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors._darkBg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors._darkSurface,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: AppColors._darkTextPrimary,
          letterSpacing: -0.5,
        ),
        displayMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: AppColors._darkTextPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors._darkTextPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: AppColors._darkTextPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: AppColors._darkTextPrimary,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors._darkTextSecondary,
          height: 1.4,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors._darkTextPrimary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors._darkInputBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20, vertical: 16,
        ),
        hintStyle: const TextStyle(
          color: AppColors._darkTextSecondary,
          fontSize: 15,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors._darkBorder,
        thickness: 0.5,
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors._lightBg,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors._lightSurface,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: AppColors._lightTextPrimary,
          letterSpacing: -0.5,
        ),
        displayMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: AppColors._lightTextPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors._lightTextPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: AppColors._lightTextPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: AppColors._lightTextPrimary,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors._lightTextSecondary,
          height: 1.4,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors._lightTextPrimary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors._lightInputBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20, vertical: 16,
        ),
        hintStyle: const TextStyle(
          color: AppColors._lightTextSecondary,
          fontSize: 15,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors._lightBorder,
        thickness: 0.5,
      ),
    );
  }
}
