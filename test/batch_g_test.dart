/// Batch G regression tests (fake channel — the established pattern
/// from batch_f_features_test.dart):
///
///  Item 11 — the Impulse Lock app picker is available ONLY in
///  "timer + suspend" mode: in "timer only" the tile is disabled
///  (tapping opens nothing); in "timer + suspend" it opens the
///  picker. Enforcement already ignored the list in timer-only mode
///  (AppController.startImpulseLock records it only for
///  timerAndSuspend) — the UI used to offer a picker whose picks
///  were silently dropped.
///  Item 9 — the shared app picker has Select all / Deselect all:
///  from the content-check screen, Select all checks every visible
///  app and Save returns them all; Deselect all clears them.
///  Item 4 — extra dim, honest verification: the status carries the
///  failed keys, the screen shows the warning banner naming the
///  failed mode, and the "Use Azm's own dimming" switch persists
///  the overlay flag. (The native enforce/overlay behaviour itself
///  is Kotlin; the debug build proves it compiles — see
///  BATCH_G_REPORT.md.)
///  Item 6 — the torrent card lives in the Config tab now (not in
///  the browser-restrictions screen): the browser screen has no
///  torrent card at all.
///  Item 5 — logo 40%: verified by measuring the rendered PNGs
///  (symbol 40.2% tall, margins 29.9% + 29.9%), not by a widget
///  test — see BATCH_G_REPORT.md.
library;

import 'dart:convert';

import 'package:azm/app_controller.dart';
import 'package:azm/data/privileged_channel.dart';
import 'package:azm/domain/colour_modes.dart';
import 'package:azm/l10n/app_localizations.dart';
import 'package:azm/theme.dart';
import 'package:azm/ui/colour_modes_screen.dart';
import 'package:azm/ui/config_screens.dart';
import 'package:azm/ui/impulse_focus_screens.dart';
import 'package:azm/ui/visual_blocking_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'azm/privileged';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methodChannel = MethodChannel(channelName);

  late List<MethodCall> calls;
  late List<Map<String, dynamic>> fakeApps;
  late List<Map<String, dynamic>> fakeBrowsers;
  late List<Map<String, dynamic>> fakeTorrentApps;
  late bool fakeBlockTorrents;
  late String? fakeTorrentBlockedJson;
  late String? fakeBlocklistsJson;
  late String? fakeDnsJson;
  late String? fakeImpulseConfigJson;
  late Map<String, dynamic> fakeColourConfig;
  late Map<String, dynamic> fakeColourStatus;
  late Map<String, dynamic> fakeVisualConfig;
  final createdControllers = <AppController>[];

  Map<String, dynamic> app(String packageName, String label) => {
    'packageName': packageName,
    'label': label,
    'isSystem': false,
    'isHidden': false,
    'isSuspended': false,
    'isUninstallBlocked': false,
  };

  Map<String, dynamic> defaultColourConfig() => {
    'enabled': true,
    'modes': ['EXTRA_DIM'],
    'windows': <String, dynamic>{},
    'scopes': <String, dynamic>{},
    'excludedApps': <String, dynamic>{},
    'onlyApps': <String, dynamic>{},
    'nightLightTemperature': 3200,
    'nightLightIntensity': 5,
    'extraDimLevel': 63,
    'extraDimUseOverlay': false,
    'applyDuringFocus': false,
  };

  Map<String, dynamic> defaultColourStatus() => {
    'enabled': true,
    'appliedModes': ['EXTRA_DIM'],
    'writeSecureSettingsGranted': true,
    'accessibilityServiceEnabled': true,
    'locked': {
      'GRAYSCALE': false,
      'NIGHT_LIGHT': false,
      'EXTRA_DIM': false,
      'INVERSION': false,
    },
    'activeWindows': <Map<String, dynamic>>[],
    'platformNightLight': true,
    'extraDimAvailable': true,
    'grayscaleSupported': true,
    'failedKeys': <String>[],
  };

  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher
        .implicitView!;
    view.physicalSize = const Size(800, 4000);
    view.devicePixelRatio = 1.0;
    calls = [];
    fakeApps = [
      app('com.example.app', 'Example'),
      app('com.example.social', 'Social App'),
      app('com.example.notes', 'Notes'),
    ];
    fakeBrowsers = [
      {
        'packageName': 'com.android.chrome',
        'label': 'Chrome',
        'supportsRestrictions': true,
        'isSuspended': false,
        'icon': null,
      },
    ];
    fakeTorrentApps = [
      {'packageName': 'com.example.torrent', 'label': 'Torrent Client'},
    ];
    fakeBlockTorrents = false;
    fakeTorrentBlockedJson = null;
    fakeBlocklistsJson = null;
    fakeDnsJson = null;
    fakeImpulseConfigJson = jsonEncode({
      'action': 'timerOnly',
      'durationMinutes': 60,
      'suspendApps': ['com.example.app'],
    });
    fakeColourConfig = defaultColourConfig();
    fakeColourStatus = defaultColourStatus();
    fakeVisualConfig = {
      'enabled': true,
      'targetPackages': ['com.example.app'],
      'categories': ['hentai', 'porn', 'sexy'],
      'threshold': 0.5,
      'suspendEnabled': false,
      'suspendBlockCount': 5,
      'suspendWindowMinutes': 15,
      'suspendDurationMinutes': 30,
    };

    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'isDeviceOwner':
          return {
            'isDeviceOwner': true,
            'isAdminActive': true,
            'forcedRemovalDelayHours': 24,
          };
        case 'getPrivateDns':
          return {'mode': 'PRIVATE_DNS_MODE_OPPORTUNISTIC', 'hostname': null};
        case 'listInstalledApps':
          return fakeApps;
        case 'listInstalledBrowsers':
          return fakeBrowsers;
        case 'getTorrentApps':
          return fakeTorrentApps;
        case 'isBlockTorrentsEnabled':
          return fakeBlockTorrents;
        case 'setBlockTorrents':
          fakeBlockTorrents = call.arguments['enabled'] as bool;
          return fakeBlockTorrents;
        case 'isAutoBlockUninstallSuspended':
          return true;
        case 'setAppSuspended':
          final packages =
              (call.arguments['packageNames'] as List).cast<String>();
          final suspended = call.arguments['suspended'] as bool;
          return {
            'results': packages
                .map(
                  (p) => {'packageName': p, 'isSuspended': suspended},
                )
                .toList(),
          };
        case 'getSetting':
          final store = call.arguments['store'] as String?;
          final key = call.arguments['key'] as String?;
          if (store == 'security_prefs' && key == 'impulse_config') {
            return {'value': fakeImpulseConfigJson};
          }
          if (store == 'browser_prefs' && key == 'blocked_lists_json') {
            return {'value': fakeBlocklistsJson};
          }
          if (store == 'browser_prefs' && key == 'dns_protection_json') {
            return {'value': fakeDnsJson};
          }
          if (store == 'browser_prefs' && key == 'torrent_blocked_json') {
            return {'value': fakeTorrentBlockedJson};
          }
          return {'value': null};
        case 'setSetting':
          final store = call.arguments['store'] as String?;
          final key = call.arguments['key'] as String?;
          final value = call.arguments['value'] as String?;
          if (store == 'browser_prefs' && key == 'torrent_blocked_json') {
            fakeTorrentBlockedJson = value;
          }
          return {'value': value};
        case 'getColourModesConfig':
          return fakeColourConfig;
        case 'setColourModesConfig':
          fakeColourConfig = Map<String, dynamic>.from(
            (call.arguments as Map).cast<String, dynamic>(),
          );
          return {'ok': true, 'locked': false, 'lockedModes': <String>[]};
        case 'getColourModesStatus':
          return fakeColourStatus;
        case 'syncColourModes':
          return {'ok': fakeColourStatus['accessibilityServiceEnabled']};
        case 'getVisualBlockingConfig':
          return fakeVisualConfig;
        case 'setVisualBlockingConfig':
          fakeVisualConfig = Map<String, dynamic>.from(
            (call.arguments as Map).cast<String, dynamic>(),
          );
          return fakeVisualConfig;
        case 'getVisualDetectorError':
          return {'error': null};
        case 'isRecoveryCodeSet':
          return {'isSet': true};
        case 'verifyRecoveryCode':
          return {'matches': true};
        case 'getUserRestrictionResidue':
          return {'keys': <String>[]};
        case 'getShizukuState':
          return {'isInstalled': false, 'isAuthorized': false};
      }
      throw MissingPluginException('Unhandled ${call.method} in Batch G test');
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
    for (final c in createdControllers) {
      c.session.end();
    }
    createdControllers.clear();
  });

  Widget buildTestApp({required Widget child}) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: azmLightTheme(),
      darkTheme: azmDarkTheme(),
      home: Scaffold(body: child),
    );
  }

  AppController makeController() {
    final c = AppController.test(PrivilegedChannel(methodChannel: methodChannel));
    createdControllers.add(c);
    return c;
  }

  Future<void> enterCodeAndConfirm(WidgetTester tester) async {
    await tester.pumpAndSettle();
    expect(find.text('Enter recovery code'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'AAAAAAAAAAAAAAAA');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();
  }

  // ------------------------------------------------------------ Item 11

  group('Batch G — impulse lock picker (item 11)', () {
    testWidgets('timer-only mode: the app tile does nothing', (tester) async {
      final controller = makeController();
      controller.session.start();
      await tester.pumpWidget(
        buildTestApp(child: ImpulseLockScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      // The tile shows the saved list but must not open the picker.
      expect(find.text('1 app(s) to suspend'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, '1 app(s) to suspend'));
      await tester.pumpAndSettle();
      expect(find.text('Apps suspended during impulse lock'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      // End the session inside the body: its 1s ticker must not
      // outlive the widget tree (the framework flags pending timers).
      controller.session.end();
    });

    testWidgets('timer + suspend mode: the app tile opens the picker',
        (tester) async {
      fakeImpulseConfigJson = jsonEncode({
        'action': 'timerAndSuspend',
        'durationMinutes': 60,
        'suspendApps': ['com.example.app'],
      });
      final controller = makeController();
      controller.session.start();
      await tester.pumpWidget(
        buildTestApp(child: ImpulseLockScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ListTile, '1 app(s) to suspend'));
      await tester.pumpAndSettle();
      expect(
        find.text('Apps suspended during impulse lock'),
        findsOneWidget,
      );
      controller.session.end();
    });
  });

  // ------------------------------------------------------------ Item 9

  group('Batch G — app picker select-all (item 9)', () {
    testWidgets('Select all checks every visible app and Save returns them',
        (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(child: VisualBlockingScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      // The tile's title is the chosen-count, not the card title.
      await tester.tap(find.widgetWithText(ListTile, '1 app(s) chosen'));
      await tester.pumpAndSettle();
      expect(find.text('Select all'), findsOneWidget);

      await tester.tap(find.text('Select all'));
      await tester.pump();
      expect(find.text('Deselect all'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final saved = calls.where((c) => c.method == 'setVisualBlockingConfig');
      expect(saved, hasLength(1));
      expect(
        (saved.first.arguments['targetPackages'] as List).toSet(),
        {'com.example.app', 'com.example.social', 'com.example.notes'},
      );
    });

    testWidgets('Deselect all clears the visible set', (tester) async {
      fakeVisualConfig['targetPackages'] = [
        'com.example.app',
        'com.example.social',
        'com.example.notes',
      ];
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(child: VisualBlockingScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ListTile, '3 app(s) chosen'));
      await tester.pumpAndSettle();
      // All three start selected, so the button is already Deselect.
      expect(find.text('Deselect all'), findsOneWidget);

      await tester.tap(find.text('Deselect all'));
      await tester.pump();
      expect(find.text('Select all'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      // Removing inspected apps is a loosening: the recovery gate
      // opens before the save runs.
      await enterCodeAndConfirm(tester);

      final saved = calls.where((c) => c.method == 'setVisualBlockingConfig');
      expect(saved, hasLength(1));
      expect(saved.first.arguments['targetPackages'], isEmpty);
      // The gate started a recovery session: end it inside the body
      // so its 1s ticker does not outlive the widget tree.
      controller.session.end();
    });
  });

  // ------------------------------------------------------------ Item 4

  group('Batch G — extra dim honest verification (item 4)', () {
    test('ColourModesStatus maps failed keys to modes', () {
      final status = ColourModesStatus.fromMap({
        'enabled': true,
        'appliedModes': <String>[],
        'writeSecureSettingsGranted': true,
        'accessibilityServiceEnabled': true,
        'locked': <String, dynamic>{},
        'activeWindows': <Map<String, dynamic>>[],
        'platformNightLight': true,
        'extraDimAvailable': true,
        'grayscaleSupported': true,
        'failedKeys': [
          'reduce_bright_colors_activated',
          'reduce_bright_colors_level',
        ],
      });
      expect(status.failedModes, {ColourMode.extraDim});
      expect(status.failedKeys, hasLength(2));
    });

    testWidgets('the screen shows the failed-mode warning banner',
        (tester) async {
      fakeColourStatus['failedKeys'] = [
        'reduce_bright_colors_activated',
        'reduce_bright_colors_level',
      ];
      fakeColourStatus['appliedModes'] = <String>[];
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(child: ColourModesScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('The system did not apply'),
        findsOneWidget,
      );
      expect(find.textContaining('Extra dim'), findsWidgets);
    });

    testWidgets('the overlay switch persists the flag', (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(child: ColourModesScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      final tile = find.widgetWithText(
        SwitchListTile,
        "Use Azm's own dimming",
      );
      expect(tile, findsOneWidget);
      await tester.tap(
        find.descendant(of: tile, matching: find.byType(Switch)),
      );
      await tester.pumpAndSettle();

      expect(fakeColourConfig['extraDimUseOverlay'], isTrue);
      final saved = calls.where((c) => c.method == 'setColourModesConfig');
      expect(saved, isNotEmpty);
    });
  });

  // ------------------------------------------------------------ Item 6

  group('Batch G — torrent card in Settings (item 6)', () {
    testWidgets('the browser-restrictions screen has no torrent card',
        (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(
          child: BrowserRestrictionsScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Block torrent apps'), findsNothing);
      expect(find.text('Torrent Client'), findsNothing);
    });
  });
}
