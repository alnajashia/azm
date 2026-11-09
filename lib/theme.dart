/// Dominanter visual identity (redesign 2026-11-09).
///
/// Identity, taken from the user's reference images:
/// * deep-red glossy surfaces and a chunky red timer ring;
/// * floating capsule (pill) bottom navigation with a red swept indicator;
/// * secondary deep-blue accents; near-black surfaces in dark mode.
///
/// The [ColorScheme]s are hand-built rather than `ColorScheme.fromSeed`:
/// a seed tints *every* surface toward the seed colour, which would wash
/// the dark theme's neutral near-black surfaces and the light theme's
/// clean whites pink. Hand-building keeps surfaces neutral and reserves
/// red/blue strictly for accents, indicators and CTAs — which is also the
/// contrast rule: red is never long body text. Body text is near-white on
/// near-black (dark) and near-black on white (light), both far above WCAG
/// AA; filled CTAs are white text on #D90429 (~5.9:1) or #E5383B.
library;

import 'package:flutter/material.dart';

abstract final class DominanterColors {
  /// Primary red scale (references cluster around #D90429 / #E5383B).
  static const red = Color(0xFFD90429);
  static const redBright = Color(0xFFE5383B);
  static const redDark = Color(0xFF9E031E);
  static const redDeep = Color(0xFF5C0212);

  /// Secondary deep-blue scale (#1D3557 family, #2563EB accent).
  static const blueDeep = Color(0xFF1D3557);
  static const blue = Color(0xFF2563EB);
  static const blueBright = Color(0xFF5B8DEF);

  /// Dark-mode surfaces: neutral near-black, never red-tinted.
  static const blackBackground = Color(0xFF0A0A0C);
  static const blackSurface = Color(0xFF141417);
  static const blackSurfaceHigh = Color(0xFF1E1E23);

  /// Light-mode surfaces.
  static const lightBackground = Color(0xFFF7F7F9);
  static const lightSurface = Color(0xFFFFFFFF);
}

/// Gradient used by [GradientCard] hero surfaces, per brightness.
LinearGradient heroGradient(Brightness brightness) =>
    brightness == Brightness.dark
    ? const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF7A0C1D),
          Color(0xFF2A0A14),
          DominanterColors.blueDeep,
        ],
        stops: [0.0, 0.55, 1.0],
      )
    : const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFE9EC), Color(0xFFFFFFFF), Color(0xFFE8EEF9)],
        stops: [0.0, 0.55, 1.0],
      );

TextTheme _textTheme(TextTheme base) => base.copyWith(
  // Stronger hero/timer numerals, per the reference's big ring digits.
  displayLarge: base.displayLarge?.copyWith(fontWeight: FontWeight.w800),
  displayMedium: base.displayMedium?.copyWith(fontWeight: FontWeight.w800),
  displaySmall: base.displaySmall?.copyWith(fontWeight: FontWeight.w800),
  headlineLarge: base.headlineLarge?.copyWith(fontWeight: FontWeight.w800),
  headlineMedium: base.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
  headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
  titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w700),
);

ThemeData dominanterLightTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: DominanterColors.red,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFFFD9DE),
    onPrimaryContainer: DominanterColors.redDeep,
    secondary: DominanterColors.blueDeep,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFDCE7F7),
    onSecondaryContainer: DominanterColors.blueDeep,
    tertiary: DominanterColors.blue,
    onTertiary: Colors.white,
    error: DominanterColors.redDark,
    onError: Colors.white,
    errorContainer: Color(0xFFFFD9DE),
    onErrorContainer: DominanterColors.redDeep,
    surface: DominanterColors.lightSurface,
    onSurface: Color(0xFF17171A),
    onSurfaceVariant: Color(0xFF4A4A52),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Color(0xFFF1F1F4),
    surfaceContainer: Color(0xFFECECF0),
    surfaceContainerHigh: Color(0xFFE4E4EA),
    surfaceContainerHighest: Color(0xFFD9D9E0),
    outline: Color(0xFF8A8A94),
    outlineVariant: Color(0xFFD5D5DC),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF17171A),
    onInverseSurface: Color(0xFFF5F5F7),
    inversePrimary: DominanterColors.redBright,
  );
  return _baseTheme(scheme, DominanterColors.lightBackground);
}

ThemeData dominanterDarkTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: DominanterColors.redBright,
    onPrimary: Colors.white,
    primaryContainer: DominanterColors.redDeep,
    onPrimaryContainer: Color(0xFFFFD9DE),
    secondary: DominanterColors.blueBright,
    onSecondary: Color(0xFF0A0A0C),
    secondaryContainer: DominanterColors.blueDeep,
    onSecondaryContainer: Color(0xFFDCE7F7),
    tertiary: DominanterColors.blueBright,
    onTertiary: Color(0xFF0A0A0C),
    error: Color(0xFFFF6B74),
    onError: Color(0xFF2A0208),
    errorContainer: Color(0xFF4A0A12),
    onErrorContainer: Color(0xFFFFD9DE),
    surface: DominanterColors.blackSurface,
    onSurface: Color(0xFFF5F5F7),
    onSurfaceVariant: Color(0xFFB9B9C2),
    surfaceContainerLowest: DominanterColors.blackBackground,
    surfaceContainerLow: Color(0xFF101013),
    surfaceContainer: DominanterColors.blackSurface,
    surfaceContainerHigh: DominanterColors.blackSurfaceHigh,
    surfaceContainerHighest: Color(0xFF2A2A31),
    outline: Color(0xFF7A7A85),
    outlineVariant: Color(0xFF33333B),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFF5F5F7),
    onInverseSurface: Color(0xFF17171A),
    inversePrimary: DominanterColors.red,
  );
  return _baseTheme(scheme, DominanterColors.blackBackground);
}

ThemeData _baseTheme(ColorScheme scheme, Color scaffoldBackground) {
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: scaffoldBackground,
    textTheme: _textTheme(base.textTheme),
    appBarTheme: AppBarTheme(
      backgroundColor: scaffoldBackground,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: DominanterColors.red,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? scheme.primary : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? scheme.primary.withValues(alpha: 0.35)
            : null,
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    cardTheme: CardThemeData(
      elevation: scheme.brightness == Brightness.dark ? 0 : 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
