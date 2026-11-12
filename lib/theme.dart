/// Azm visual identity — RED & BLACK ONLY (redesign v2,
/// 2026-11-09, superseding the earlier red/blue/black identity at the
/// user's explicit request).
///
/// Taken from the user's two reference images:
/// * Image 1 — glossy deep-red planes and cards floating over a
///   light-grey backdrop, pill-shaped red list rows, circular white/red
///   icon badges, and a chunky 3D red timer ring with big white numerals
///   («05») on a dark-red disc. (The reference's colour washes are NOT
///   reproduced: per the user's v1.0.5 no-gradient directive every
///   surface here is a single flat colour.)
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

abstract final class AzmColors {
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

/// Flat surface colour for hero cards ([HeroCard] in common.dart),
/// per brightness — v1.0.5 (user directive): no colour gradients
/// anywhere in the app; every surface is one flat colour. Dark: the
/// flat deep red of the identity's red scale. Light: flat white.
Color heroSurface(Brightness brightness) => brightness == Brightness.dark
    ? AzmColors.redDeep
    : AzmColors.lightSurface;

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

ThemeData azmLightTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: AzmColors.red,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFFFD9DE),
    onPrimaryContainer: AzmColors.redDeep,
    // Secondary is BLACK in light mode: black chips, black secondary
    // buttons and badges against the light backdrop, as in the black
    // pill-bar variant of the reference.
    secondary: Color(0xFF171717),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFE6E6E6),
    onSecondaryContainer: Color(0xFF171717),
    tertiary: AzmColors.redDark,
    onTertiary: Colors.white,
    error: AzmColors.redDark,
    onError: Colors.white,
    errorContainer: Color(0xFFFFD9DE),
    onErrorContainer: AzmColors.redDeep,
    surface: AzmColors.lightSurface,
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
    inversePrimary: AzmColors.redBright,
  );
  return _baseTheme(scheme, AzmColors.lightBackground);
}

ThemeData azmDarkTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AzmColors.redBright,
    onPrimary: Colors.white,
    primaryContainer: AzmColors.redDeep,
    onPrimaryContainer: Color(0xFFFFD9DE),
    // Secondary is a monochrome light tint of black in dark mode (the
    // capsule and surfaces already carry the black role); tertiary
    // stays inside the red scale.
    secondary: Color(0xFFE9E9E9),
    onSecondary: Color(0xFF0A0A0A),
    secondaryContainer: AzmColors.blackSurfaceHighest,
    onSecondaryContainer: Color(0xFFF5F5F5),
    tertiary: AzmColors.redGlow,
    onTertiary: Colors.white,
    error: Color(0xFFFF6B74),
    onError: Color(0xFF2A0208),
    errorContainer: Color(0xFF4A0A12),
    onErrorContainer: Color(0xFFFFD9DE),
    surface: AzmColors.blackSurface,
    onSurface: Color(0xFFF5F5F5),
    onSurfaceVariant: Color(0xFFBDBDBD),
    surfaceContainerLowest: AzmColors.blackBackground,
    surfaceContainerLow: Color(0xFF101010),
    surfaceContainer: AzmColors.blackSurface,
    surfaceContainerHigh: AzmColors.blackSurfaceHigh,
    surfaceContainerHighest: Color(0xFF2A2A2A),
    outline: Color(0xFF7E7E7E),
    outlineVariant: Color(0xFF363636),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFF5F5F5),
    onInverseSurface: Color(0xFF171717),
    inversePrimary: AzmColors.red,
  );
  return _baseTheme(scheme, AzmColors.blackBackground);
}

/// The single shape language (v1.0.6, user item 10): soft, generous
/// rounded corners everywhere — cards, fields, buttons, dialogs,
/// chips, sheets. Every interactive surface in the app takes its
/// radius from this scale (directly or through the theme); no
/// sharp-cornered interactive surface remains.
///
///  - [small]  (16): inset surfaces, nested cards, menus, snackbars.
///  - [medium] (20): cards, buttons, text/search fields.
///  - [large]  (28): dialogs, bottom sheets, hero surfaces.
///  - [pill]   (999): the Apps search field, chips, badges.
abstract final class AzmRadius {
  static const small = 16.0;
  static const medium = 20.0;
  static const large = 28.0;
  static const pill = 999.0;
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
        backgroundColor: AzmColors.red,
        foregroundColor: Colors.white,
        // Soft generous corners (AzmRadius.medium).
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AzmRadius.medium),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AzmRadius.medium),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AzmRadius.medium),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      // All text/search fields share the soft field shape; the Apps
      // search field goes further and is a full pill (its own
      // decoration, per user item 10).
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AzmRadius.medium),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AzmRadius.medium),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AzmRadius.medium),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AzmRadius.large),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AzmRadius.small),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AzmRadius.small),
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
      // Chips are pills in the shape language.
      shape: const StadiumBorder(),
    ),
    // Cards at AzmRadius.medium, matching the reference's
    // deeply rounded floating cards.
    cardTheme: CardThemeData(
      elevation: scheme.brightness == Brightness.dark ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AzmRadius.medium),
      ),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AzmRadius.large),
      ),
    ),
  );
}
