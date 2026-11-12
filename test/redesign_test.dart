// Redesign (2026-11-09; v2 red & black only) widget tests: floating
// pill navigation, the circular focus timer ring, and the palette
// guard that keeps every scheme/gradient colour inside the red scale
// or the black neutrals. Presentation only — all widgets are driven
// by the same state/handlers as the surfaces they replaced.
import 'package:azm/app_controller.dart';
import 'package:azm/data/privileged_channel.dart';
import 'package:azm/theme.dart';
import 'package:azm/ui/common.dart';
import 'package:azm/ui/impulse_focus_screens.dart';
import 'package:azm/ui/pill_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('azm/privileged');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  testWidgets('Pill nav renders 4 destinations; tapping the 3rd switches tab', (
    tester,
  ) async {
    var index = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: azmLightTheme(),
        home: StatefulBuilder(
          builder: (context, setLocal) => Scaffold(
            body: IndexedStack(
              index: index,
              children: const [
                Center(child: Text('tab body 0')),
                Center(child: Text('tab body 1')),
                Center(child: Text('tab body 2')),
                Center(child: Text('tab body 3')),
              ],
            ),
            // Same widget + wiring the AppShell uses.
            bottomNavigationBar: AzmNavBar(
              selectedIndex: index,
              onSelected: (i) => setLocal(() => index = i),
              destinations: const [
                PillNavDestination(
                  icon: Icons.admin_panel_settings_outlined,
                  selectedIcon: Icons.admin_panel_settings,
                  label: 'Status',
                ),
                PillNavDestination(
                  icon: Icons.shield_outlined,
                  selectedIcon: Icons.shield,
                  label: 'Restrictions',
                ),
                PillNavDestination(
                  icon: Icons.apps_outlined,
                  selectedIcon: Icons.apps,
                  label: 'Apps',
                ),
                PillNavDestination(
                  icon: Icons.settings_outlined,
                  selectedIcon: Icons.settings,
                  label: 'Config',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(AzmNavBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    for (final label in ['Status', 'Restrictions', 'Apps', 'Config']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('tab body 0'), findsOneWidget);

    await tester.tap(find.text('Apps'));
    await tester.pump();

    expect(index, 2);
    expect(find.text('tab body 2'), findsOneWidget);
  });

  testWidgets('Focus timer ring shows the model remaining time', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        case 'getSetting':
          return {'value': null}; // defaults: 25 min focus / 5 min break
        case 'listInstalledApps':
          return <Object?>[];
        case 'getGroups':
          return {'groups': <Object?>[]};
        case 'getFocusSession':
          return null; // no persisted native session: screen loads idle
        case 'startFocusSession':
          // The native store's state map for a just-started 25-minute
          // focus phase (elapsed-realtime clock values, ms).
          return {
            'phase': 'focus',
            'phaseStartedElapsedMs': 1000000,
            'phaseDurationMs': 1500000,
            'completedFocusInCycle': 0,
            'pausedFrom': null,
            'deadlineElapsedMs': 2500000,
          };
        case 'hasNotificationPermission':
          return {'granted': true};
        default:
          throw MissingPluginException('no mock for ${call.method}');
      }
    });
    final controller = AppController.test(
      PrivilegedChannel(methodChannel: methodChannel),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: azmDarkTheme(),
        home: FocusModeScreen(controller: controller),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Idle: the ring shows the configured focus length as mm:ss.
    expect(find.byType(FocusTimerRing), findsOneWidget);
    expect(find.text('Not started'), findsOneWidget);
    expect(find.text('25:00'), findsOneWidget);

    // Start drives the native session (startFocusSession); the ring must
    // track the running session the channel reports back. (The button
    // sits below the taller ring card in the default test viewport, so
    // scroll it into view first.)
    // Note: FilledButton.icon has a private runtime type, so tap by label.
    await tester.ensureVisible(find.text('Start'));
    await tester.pump();
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(FocusTimerRing), findsOneWidget);
    expect(find.text('Focusing'), findsOneWidget);
    final ring = tester.widget<FocusTimerRing>(find.byType(FocusTimerRing));
    expect(ring.remainingText, startsWith('24:5'));
    expect(ring.isBreak, isFalse);
    expect(ring.progress, lessThanOrEqualTo(1.0));
    expect(ring.progress, greaterThan(0.9));

    await tester.pumpWidget(const SizedBox()); // dispose tickers
  });

  // Redesign v2 (red & black only): no colour in either scheme, the
  // hero surfaces or the shared palette may be blue-dominant (or any
  // other non-red hue family). Neutrals — tints/shades of black — pass
  // because their channels stay close together.
  test('Red/black identity: no blue-dominant colour anywhere', () {
    bool isBlueDominant(Color c) => c.b > c.r + 0.08 && c.b > c.g + 0.04;

    final colors = <Color>[
      AzmColors.red,
      AzmColors.redBright,
      AzmColors.redGlow,
      AzmColors.redDark,
      AzmColors.redDeep,
      AzmColors.redDeepest,
      AzmColors.black,
      AzmColors.blackBackground,
      AzmColors.blackBar,
      AzmColors.blackSurface,
      AzmColors.blackSurfaceHigh,
      AzmColors.blackSurfaceHighest,
      for (final scheme in [
        azmLightTheme().colorScheme,
        azmDarkTheme().colorScheme,
      ]) ...[
        scheme.primary,
        scheme.onPrimary,
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        scheme.secondary,
        scheme.onSecondary,
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        scheme.tertiary,
        scheme.onTertiary,
        scheme.error,
        scheme.surface,
        scheme.onSurface,
        scheme.inversePrimary,
      ],
      heroSurface(Brightness.light),
      heroSurface(Brightness.dark),
    ];
    for (final c in colors) {
      expect(isBlueDominant(c), isFalse, reason: '$c is blue-dominant');
    }
    // And the break ring must live in the red scale now, not blue.
    expect(AzmColors.redDark.b, lessThan(AzmColors.redDark.r));
  });

  // v1.0.4 palette law (amendment B): the ONLY hue allowed anywhere is
  // red; every other colour must be true greyscale (R == G == B). This
  // asserts every shared-palette constant, EVERY ColorScheme role of
  // both themes, and both flat hero surfaces.
  test('Strict palette: every theme colour is red-dominant or greyscale', () {
    bool isRedDominant(Color c) => c.r > c.g && c.r > c.b;
    bool isGreyscale(Color c) => c.r == c.g && c.g == c.b;

    final colors = <String, Color>{
      'red': AzmColors.red,
      'redBright': AzmColors.redBright,
      'redGlow': AzmColors.redGlow,
      'redDark': AzmColors.redDark,
      'redDeep': AzmColors.redDeep,
      'redDeepest': AzmColors.redDeepest,
      'black': AzmColors.black,
      'blackBackground': AzmColors.blackBackground,
      'blackBar': AzmColors.blackBar,
      'blackSurface': AzmColors.blackSurface,
      'blackSurfaceHigh': AzmColors.blackSurfaceHigh,
      'blackSurfaceHighest': AzmColors.blackSurfaceHighest,
      'onBlackMuted': AzmColors.onBlackMuted,
      'onBlackFaint': AzmColors.onBlackFaint,
      'lightBackground': AzmColors.lightBackground,
      'lightSurface': AzmColors.lightSurface,
    };
    for (final theme in [azmLightTheme(), azmDarkTheme()]) {
      final s = theme.colorScheme;
      final roles = <String, Color>{
        'primary': s.primary,
        'onPrimary': s.onPrimary,
        'primaryContainer': s.primaryContainer,
        'onPrimaryContainer': s.onPrimaryContainer,
        'primaryFixed': s.primaryFixed,
        'primaryFixedDim': s.primaryFixedDim,
        'onPrimaryFixed': s.onPrimaryFixed,
        'onPrimaryFixedVariant': s.onPrimaryFixedVariant,
        'secondary': s.secondary,
        'onSecondary': s.onSecondary,
        'secondaryContainer': s.secondaryContainer,
        'onSecondaryContainer': s.onSecondaryContainer,
        'secondaryFixed': s.secondaryFixed,
        'secondaryFixedDim': s.secondaryFixedDim,
        'onSecondaryFixed': s.onSecondaryFixed,
        'onSecondaryFixedVariant': s.onSecondaryFixedVariant,
        'tertiary': s.tertiary,
        'onTertiary': s.onTertiary,
        'tertiaryContainer': s.tertiaryContainer,
        'onTertiaryContainer': s.onTertiaryContainer,
        'tertiaryFixed': s.tertiaryFixed,
        'tertiaryFixedDim': s.tertiaryFixedDim,
        'onTertiaryFixed': s.onTertiaryFixed,
        'onTertiaryFixedVariant': s.onTertiaryFixedVariant,
        'error': s.error,
        'onError': s.onError,
        'errorContainer': s.errorContainer,
        'onErrorContainer': s.onErrorContainer,
        'surface': s.surface,
        'onSurface': s.onSurface,
        'surfaceDim': s.surfaceDim,
        'surfaceBright': s.surfaceBright,
        'surfaceContainerLowest': s.surfaceContainerLowest,
        'surfaceContainerLow': s.surfaceContainerLow,
        'surfaceContainer': s.surfaceContainer,
        'surfaceContainerHigh': s.surfaceContainerHigh,
        'surfaceContainerHighest': s.surfaceContainerHighest,
        'onSurfaceVariant': s.onSurfaceVariant,
        'outline': s.outline,
        'outlineVariant': s.outlineVariant,
        'shadow': s.shadow,
        'scrim': s.scrim,
        'inverseSurface': s.inverseSurface,
        'onInverseSurface': s.onInverseSurface,
        'inversePrimary': s.inversePrimary,
        'surfaceTint': s.surfaceTint,
      };
      roles.forEach((name, color) {
        colors['${theme.brightness.name}.$name'] = color;
      });
      colors['scaffold.${theme.brightness.name}'] =
          theme.scaffoldBackgroundColor;
    }
    for (final brightness in Brightness.values) {
      // v1.0.5: hero surfaces are single flat colours now.
      colors['hero.${brightness.name}'] = heroSurface(brightness);
    }

    for (final entry in colors.entries) {
      expect(
        isRedDominant(entry.value) || isGreyscale(entry.value),
        isTrue,
        reason:
            '${entry.key} = ${entry.value} is neither red-dominant '
            'nor true greyscale (R==G==B)',
      );
    }
  });

  // Redesign v2: the pill bar is the reference's BLACK variant in both
  // brightness modes (previously white in light mode).
  testWidgets('Pill nav bar is black even in the light theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: azmLightTheme(),
        home: Scaffold(
          bottomNavigationBar: AzmNavBar(
            selectedIndex: 0,
            onSelected: (_) {},
            destinations: const [
              PillNavDestination(
                icon: Icons.admin_panel_settings_outlined,
                selectedIcon: Icons.admin_panel_settings,
                label: 'Status',
              ),
              PillNavDestination(
                icon: Icons.shield_outlined,
                selectedIcon: Icons.shield,
                label: 'Restrictions',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final containers = tester.widgetList<Container>(
      find.descendant(
        of: find.byType(AzmNavBar),
        matching: find.byType(Container),
      ),
    );
    final barColors = containers
        .map((c) => (c.decoration as BoxDecoration?)?.color)
        .whereType<Color>()
        .toList();
    expect(barColors, contains(AzmColors.blackBar));
  });
}
