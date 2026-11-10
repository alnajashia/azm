/// Dominanter visual identity — RED & BLACK ONLY (redesign v2,
/// 2026-11-09, superseding the earlier red/blue/black identity at the
/// user's explicit request).
///
/// Taken from the user's two reference images:
/// * Image 1 — glossy deep-red gradient planes and cards floating over a
///   light-grey backdrop, pill-shaped red list rows, circular white/red
///   icon badges, and a chunky 3D red timer ring with big white numerals
///   («05») on a dark-red disc.
/// * Image 2 — floating pill bottom bars; this design fuses its red-bar
///   and black-bar variants: an ALWAYS-BLACK capsule with a filled red
///   swept active indicator, a white dot under the active label, and
///   muted light-grey inactive items.
///
/// Colour rule (strict): the only chromatic colour is RED, in one scale
/// (#5C0212 → #D90429 → #E5383B → #FF2E4D). Everything else is BLACK and
/// its tints/shades (charcoals, greys, white for text/background
/// legibility). There is no blue, green or any other hue anywhere —
/// secondary/tertiary scheme roles are monochrome or red on purpose,
/// and a widget test guards the palette: every colour must be either
/// red-dominant or true greyscale (R == G == B).
///
/// The [ColorScheme]s are hand-built rather than `ColorScheme.fromSeed`:
/// a seed tints *every* surface toward the seed colour, which would wash
/// the neutral black/white surfaces pink. Hand-building keeps surfaces
/// neutral and reserves red strictly for accents, indicators and CTAs —
/// which is also the contrast rule: red is never long body text. Body
/// text is near-white on near-black (dark) and near-black on white
/// (light); filled CTAs are white text on #D90429 (~5.9:1).
library;

import 'package:flutter/material.dart';

abstract final class DominanterColors {
  /// The red scale — the app's ONLY chromatic colour.
  static const red = Color(0xFFD90429);
  static const redBright = Color(0xFFE5383B);
  static const redGlow = Color(0xFFFF2E4D);
  static const redDark = Color(0xFF9E031E);
  static const redDeep = Color(0xFF5C0212);
  static const redDeepest = Color(0xFF2A0208);

  /// The black scale — surfaces, the navigation capsule, secondary roles.
  static const black = Color(0xFF000000);
  static const blackBackground = Color(0xFF0A0A0A);
  static const blackBar = Color(0xFF101010);
  static const blackSurface = Color(0xFF141414);
  static const blackSurfaceHigh = Color(0xFF1F1F1F);
  static const blackSurfaceHighest = Color(0xFF2A2A2A);

  /// Monochrome neutrals (tints of black) for inactive items on the
  /// always-black pill bar, in either brightness.
  static const onBlackMuted = Color(0xFFBDBDBD);
  static const onBlackFaint = Color(0xFF7E7E7E);

  /// Light-mode surfaces: white and black-tinted greys only.
  static const lightBackground = Color(0xFFF4F4F4);
  static const lightSurface = Color(0xFFFFFFFF);
}

/// Gradient used by [GradientCard] hero surfaces, per brightness.
/// Dark: the reference's glossy red plane — saturated deep red at the
/// top-left, falling through burgundy to near-black at the bottom-right.
/// Light: a white card washed with red at the top and black-tinted grey
/// at the bottom (the reference's light-grey backdrop). Red → black in
/// both modes; no other hue.
LinearGradient heroGradient(Brightness brightness) =>
    brightness == Brightness.dark
    ? const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF9E031E), Color(0xFF5C0212), Color(0xFF12030A)],
        stops: [0.0, 0.55, 1.0],
      )
    : const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFD9DE), Color(0xFFFFFFFF), Color(0xFFECECEC)],
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
    // Secondary is BLACK in light mode: black chips, black secondary
    // buttons and badges against the light backdrop, as in the black
    // pill-bar variant of the reference.
    secondary: Color(0xFF171717),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFE6E6E6),
    onSecondaryContainer: Color(0xFF171717),
    tertiary: DominanterColors.redDark,
    onTertiary: Colors.white,
    error: DominanterColors.redDark,
    onError: Colors.white,
    errorContainer: Color(0xFFFFD9DE),
    onErrorContainer: DominanterColors.redDeep,
    surface: DominanterColors.lightSurface,
    onSurface: Color(0xFF171717),
    onSurfaceVariant: Color(0xFF4D4D4D),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Color(0xFFF2F2F2),
    surfaceContainer: Color(0xFFEDEDED),
    surfaceContainerHigh: Color(0xFFE6E6E6),
    surfaceContainerHighest: Color(0xFFDBDBDB),
    outline: Color(0xFF8E8E8E),
    outlineVariant: Color(0xFFD7D7D7),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF171717),
    onInverseSurface: Color(0xFFF5F5F5),
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
    // Secondary is a monochrome light tint of black in dark mode (the
    // capsule and surfaces already carry the black role); tertiary
    // stays inside the red scale.
    secondary: Color(0xFFE9E9E9),
    onSecondary: Color(0xFF0A0A0A),
    secondaryContainer: DominanterColors.blackSurfaceHighest,
    onSecondaryContainer: Color(0xFFF5F5F5),
    tertiary: DominanterColors.redGlow,
    onTertiary: Colors.white,
    error: Color(0xFFFF6B74),
    onError: Color(0xFF2A0208),
    errorContainer: Color(0xFF4A0A12),
    onErrorContainer: Color(0xFFFFD9DE),
    surface: DominanterColors.blackSurface,
    onSurface: Color(0xFFF5F5F5),
    onSurfaceVariant: Color(0xFFBDBDBD),
    surfaceContainerLowest: DominanterColors.blackBackground,
    surfaceContainerLow: Color(0xFF101010),
    surfaceContainer: DominanterColors.blackSurface,
    surfaceContainerHigh: DominanterColors.blackSurfaceHigh,
    surfaceContainerHighest: Color(0xFF2A2A2A),
    outline: Color(0xFF7E7E7E),
    outlineVariant: Color(0xFF363636),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFF5F5F5),
    onInverseSurface: Color(0xFF171717),
    inversePrimary: DominanterColors.red,
  );
  return _baseTheme(scheme, DominanterColors.blackBackground);
}

ThemeData _baseTheme(ColorScheme scheme, Color scaffoldBackground) {
  // Cairo app-wide (v1.0.4 typography directive): one bundled family
  // for both locales — Arabic and Latin — so the bilingual UI speaks
  // with a single voice. Bundled TTF assets only (assets/fonts/); no
  // runtime font fetching. Headings take the theme's SemiBold/Bold
  // weights, body text Regular.
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Cairo',
  );
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
        // Pill-leaning buttons, echoing the reference's pill rows.
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
    // Larger corner radius, matching the reference's deeply rounded
    // floating cards (was 16 in the previous identity).
    cardTheme: CardThemeData(
      elevation: scheme.brightness == Brightness.dark ? 0 : 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
  );
}
