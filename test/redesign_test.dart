// Redesign (2026-11-09; v2 red & black only) widget tests: floating
// pill navigation, the circular focus timer ring, and the palette
// guard that keeps every scheme/gradient colour inside the red scale
// or the black neutrals. Presentation only — all widgets are driven
// by the same state/handlers as the surfaces they replaced.
import 'package:dominanter/app_controller.dart';
import 'package:dominanter/data/privileged_channel.dart';
import 'package:dominanter/theme.dart';
import 'package:dominanter/ui/common.dart';
import 'package:dominanter/ui/impulse_focus_screens.dart';
import 'package:dominanter/ui/pill_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('dominanter/privileged');
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
        theme: dominanterLightTheme(),
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
            bottomNavigationBar: DominanterNavBar(
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

    expect(find.byType(DominanterNavBar), findsOneWidget);
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
        theme: dominanterDarkTheme(),
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
  // hero gradients or the shared palette may be blue-dominant (or any
  // other non-red hue family). Neutrals — tints/shades of black — pass
  // because their channels stay close together.
  test('Red/black identity: no blue-dominant colour anywhere', () {
    bool isBlueDominant(Color c) => c.b > c.r + 0.08 && c.b > c.g + 0.04;

    final colors = <Color>[
      DominanterColors.red,
      DominanterColors.redBright,
      DominanterColors.redGlow,
      DominanterColors.redDark,
      DominanterColors.redDeep,
      DominanterColors.redDeepest,
      DominanterColors.black,
      DominanterColors.blackBackground,
      DominanterColors.blackBar,
      DominanterColors.blackSurface,
      DominanterColors.blackSurfaceHigh,
      DominanterColors.blackSurfaceHighest,
      for (final scheme in [
        dominanterLightTheme().colorScheme,
        dominanterDarkTheme().colorScheme,
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
      ...heroGradient(Brightness.light).colors,
      ...heroGradient(Brightness.dark).colors,
    ];
    for (final c in colors) {
      expect(isBlueDominant(c), isFalse, reason: '$c is blue-dominant');
    }
    // And the break ring must live in the red scale now, not blue.
    expect(DominanterColors.redDark.b, lessThan(DominanterColors.redDark.r));
  });

  // Redesign v2: the pill bar is the reference's BLACK variant in both
  // brightness modes (previously white in light mode).
  testWidgets('Pill nav bar is black even in the light theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: dominanterLightTheme(),
        home: Scaffold(
          bottomNavigationBar: DominanterNavBar(
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
        of: find.byType(DominanterNavBar),
        matching: find.byType(Container),
      ),
    );
    final barColors = containers
        .map((c) => (c.decoration as BoxDecoration?)?.color)
        .whereType<Color>()
        .toList();
    expect(barColors, contains(DominanterColors.blackBar));
  });
}
