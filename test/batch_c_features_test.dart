/// Batch C regression tests (fake channel — the established pattern
/// from batch_b_ux_test.dart):
///
///  C1 — all-browser restrictions: the screen lists every installed
///       browser with icon + allow switch; unsupported browsers carry
///       the warning; suspending is direct, unsuspending goes through
///       the recovery gate; Apply pushes the blocklist to supporting
///       browsers only.
///  C2 — Activity Blocker: blocked + recently-accessed lists render;
///       a protected manual add is rejected client-side; removing a
///       block goes through confirm + gate.
///  C3 — Colour Modes: config fromJson/toJson round-trip (incl. a
///       midnight-spanning window); the Dart isLoosening mirror;
///       the screen renders all four modes, disables extra dim when
///       unavailable, shows the lock banner, and offers the recovery
///       gate on a locked reply — then retries.
///  C4 — seal-break priority: filing forced removal never consults a
///       seal; the code path runs removal; a SEALED refusal still
///       surfaces as PrivilegedException.isSealed; the forced-removal
///       start button is never gated on focus state.
library;

import 'dart:convert';

import 'package:azm/app_controller.dart';
import 'package:azm/data/privileged_channel.dart';
import 'package:azm/domain/colour_modes.dart';
import 'package:azm/domain/recovery.dart';
import 'package:azm/l10n/app_localizations.dart';
import 'package:azm/theme.dart';
import 'package:azm/ui/activity_blocker_screen.dart';
import 'package:azm/ui/colour_modes_screen.dart';
import 'package:azm/ui/common.dart';
import 'package:azm/ui/config_screens.dart';
import 'package:azm/ui/config_tab.dart';
import 'package:azm/ui/recovery_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'azm/privileged';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methodChannel = MethodChannel(channelName);

  // ---- Fake channel state (reset before every test) ----------------
  late List<MethodCall> calls;
  late List<Map<String, dynamic>> fakeBrowsers;
  late List<String> fakeBlockedActivities;
  late List<Map<String, dynamic>> fakeAccessedActivities;
  late Map<String, dynamic> fakeColourConfig;
  late Map<String, dynamic> fakeColourStatus;
  late Set<String> fakeLockedModes;
  late bool fakeVerifyCodeMatches;
  late bool fakeRemoveOwnerThrowsSealed;
  late String? fakeBlocklistsJson;

  /// Controllers created in a test: their recovery sessions arm a
  /// 1-second ticker, which must be ended in tearDown or the binding
  /// fails the test with a pending-timer assertion.
  final createdControllers = <AppController>[];

  Map<String, dynamic> defaultColourConfig() => {
    'enabled': true,
    'modes': ['GRAYSCALE'],
    'windows': <String, dynamic>{},
    'scopes': <String, dynamic>{},
    'excludedApps': <String, dynamic>{},
    'onlyApps': <String, dynamic>{},
    'nightLightTemperature': 3200,
    'nightLightIntensity': 5,
    'extraDimLevel': 50,
    'applyDuringFocus': false,
  };

  Map<String, dynamic> defaultColourStatus() => {
    'enabled': true,
    'appliedModes': ['GRAYSCALE'],
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
  };

  setUp(() {
    // A tall viewport: ListView children below the fold are built
    // eagerly, so finders and taps work without scrolling.
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher
        .implicitView!;
    view.physicalSize = const Size(800, 4000);
    view.devicePixelRatio = 1.0;
    calls = [];
    fakeBrowsers = [
      {
        'packageName': 'com.android.chrome',
        'label': 'Chrome',
        'supportsRestrictions': true,
        'isSuspended': false,
        'icon': null,
      },
      {
        'packageName': 'com.example.browser',
        'label': 'Example Browser',
        'supportsRestrictions': false,
        'isSuspended': false,
        'icon': null,
      },
    ];
    fakeBlockedActivities = ['com.example.app.BadActivity'];
    fakeAccessedActivities = [
      {
        'packageName': 'com.example.app',
        'className': 'com.example.app.MainActivity',
        'appName': 'Example',
        'timestamp': DateTime(2026, 11, 12, 20, 0).millisecondsSinceEpoch,
      },
    ];
    fakeColourConfig = defaultColourConfig();
    fakeColourStatus = defaultColourStatus();
    fakeLockedModes = {};
    fakeVerifyCodeMatches = true;
    fakeRemoveOwnerThrowsSealed = false;
    fakeBlocklistsJson = null;

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
          return {'mode': 'off', 'spec': ''};
        case 'getUserRestrictionResidue':
          return {'keys': <String>[]};
        case 'listUserRestrictions':
          return {'restrictions': <String, dynamic>{}};
        case 'getShizukuState':
          return {'isInstalled': false, 'isAuthorized': false};
        case 'getSetting':
          final store = call.arguments['store'] as String?;
          final key = call.arguments['key'] as String?;
          if (store == 'browser_prefs' && key == 'blocked_lists_json') {
            return {'value': fakeBlocklistsJson};
          }
          return {'value': null};
        case 'setSetting':
          return {'value': call.arguments['value']};
        case 'isRecoveryCodeSet':
          return {'isSet': true};
        case 'verifyRecoveryCode':
          return {'matches': fakeVerifyCodeMatches};
        case 'removeDeviceOwner':
          if (fakeRemoveOwnerThrowsSealed) {
            throw PlatformException(
              code: 'SEALED',
              message: 'Removal refused by an active seal',
              details: {
                'seal': {'type': 'FOCUS_RUNNING'},
              },
            );
          }
          return {
            'isDeviceOwner': false,
            'steps': <Map<String, dynamic>>[],
          };
        case 'listInstalledApps':
          return [
            {
              'packageName': 'com.example.app',
              'label': 'Example',
              'isSystem': false,
              'isHidden': false,
              'isSuspended': false,
              'isUninstallBlocked': false,
            },
          ];
        case 'listInstalledBrowsers':
          return fakeBrowsers;
        case 'setAppSuspended':
          final packages =
              (call.arguments['packageNames'] as List).cast<String>();
          final suspended = call.arguments['suspended'] as bool;
          for (final b in fakeBrowsers) {
            if (packages.contains(b['packageName'])) {
              b['isSuspended'] = suspended;
            }
          }
          return {
            'results': packages
                .map(
                  (p) => {'packageName': p, 'isSuspended': suspended},
                )
                .toList(),
          };
        case 'setApplicationRestrictions':
          return {
            'restrictions': {'URLBlocklist': ['example.com']},
          };
        case 'getColourModesConfig':
          return fakeColourConfig;
        case 'setColourModesConfig':
          if (fakeLockedModes.isNotEmpty) {
            return {
              'ok': false,
              'locked': true,
              'lockedModes': fakeLockedModes.toList(),
            };
          }
          fakeColourConfig = Map<String, dynamic>.from(
            (call.arguments as Map).cast<String, dynamic>(),
          );
          return {'ok': true, 'locked': false, 'lockedModes': <String>[]};
        case 'getColourModesStatus':
          return fakeColourStatus;
        case 'syncColourModes':
          return {'ok': true};
        case 'grantWriteSecureSettings':
          return {'granted': true};
        case 'setAccessibilityEnabled':
          return {'isEnabled': true};
        case 'getBlockedActivities':
          return {'activities': fakeBlockedActivities};
        case 'setBlockedActivities':
          fakeBlockedActivities =
              (call.arguments['activities'] as List).cast<String>();
          return {'activities': fakeBlockedActivities};
        case 'getAccessedActivities':
          return {'activities': fakeAccessedActivities};
        default:
          return null;
      }
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
    for (final c in createdControllers) {
      c.session.end();
    }
    createdControllers.clear();
    TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!
        .reset();
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

  /// Drives the recovery-gate dialog: types a 16-letter code and
  /// confirms. The fake verifies it as correct.
  Future<void> enterCodeAndConfirm(WidgetTester tester) async {
    await tester.pumpAndSettle();
    expect(find.text('Enter recovery code'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'AAAAAAAAAAAAAAAA');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();
  }

  // ------------------------------------------------------------ C1: browsers

  group('Batch C — C1: all-browser restrictions', () {
    testWidgets('lists every installed browser with its allow switch',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: BrowserRestrictionsScreen(controller: makeController()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chrome'), findsOneWidget);
      expect(find.text('Example Browser'), findsOneWidget);
      expect(find.text('com.android.chrome'), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(2));
      // Chrome is allowed (not suspended); Example is allowed too.
      expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
    });

    testWidgets('unsupported browser carries the red warning',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: BrowserRestrictionsScreen(controller: makeController()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Restrictions do not work in this browser, it is recommended to disable it.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('suspending a browser is direct — no gate appears',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: BrowserRestrictionsScreen(controller: makeController()),
        ),
      );
      await tester.pumpAndSettle();

      // Chrome's switch is ON (allowed); tapping it suspends.
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      final suspendCalls = calls.where(
        (c) => c.method == 'setAppSuspended',
      );
      expect(suspendCalls, hasLength(1));
      expect(
        suspendCalls.first.arguments['packageNames'],
        ['com.android.chrome'],
      );
      expect(suspendCalls.first.arguments['suspended'], isTrue);
      // The switch now reads suspended (off), from the verified reply.
      expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
    });

    testWidgets('unsuspending a browser goes through the recovery gate',
        (tester) async {
      fakeBrowsers[0]['isSuspended'] = true;
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(
          child: BrowserRestrictionsScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
      await tester.tap(find.byType(Switch).first);
      await enterCodeAndConfirm(tester);

      final suspendCalls = calls.where(
        (c) => c.method == 'setAppSuspended',
      );
      expect(suspendCalls, hasLength(1));
      expect(suspendCalls.first.arguments['suspended'], isFalse);
      expect(
        calls.any((c) => c.method == 'verifyRecoveryCode'),
        isTrue,
        reason: 'the gate must verify the code before unsuspending',
      );
      expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
      controller.session.end();
    });

    testWidgets('Apply pushes the blocklist to supporting browsers only',
        (tester) async {
      fakeBlocklistsJson = jsonEncode([
        {'id': '1', 'title': 'Test', 'sites': ['example.com']},
      ]);
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(child: BrowserRestrictionsScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      // FilledButton.icon builds a private _FilledButtonWithIcon,
      // not a FilledButton widget — match by its unique label text.
      await tester.tap(find.text('Apply blocklists to browsers'));
      await enterCodeAndConfirm(tester);

      final applyCalls = calls.where(
        (c) => c.method == 'setApplicationRestrictions',
      );
      expect(applyCalls, hasLength(1));
      expect(
        applyCalls.first.arguments['packageName'],
        'com.android.chrome',
      );
      expect(
        (applyCalls.first.arguments['restrictions'] as Map)['URLBlocklist'],
        ['example.com'],
      );
      controller.session.end();
    });
  });

  // ------------------------------------------------------- C2: activity blocker

  group('Batch C — C2: Activity Blocker', () {
    testWidgets('renders blocked and recently-accessed lists',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: ActivityBlockerScreen(controller: makeController()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('com.example.app.BadActivity'), findsOneWidget);
      // The accessed list is grouped by app and collapsed: expand it.
      // (find.text('Example') is ambiguous: the blocked tile's subtitle
      // shows the same label.)
      await tester.tap(find.byType(ExpansionTile).first);
      await tester.pumpAndSettle();
      expect(find.text('com.example.app.MainActivity'), findsOneWidget);
      expect(find.text('Example'), findsWidgets);
    });

    testWidgets('protected manual add is rejected client-side',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: ActivityBlockerScreen(controller: makeController()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'com.android.systemui.StatusBarActivity',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(
        find.text('This activity is protected and can never be blocked.'),
        findsOneWidget,
      );
      // The dialog stays open and nothing was written.
      expect(find.text('Block an activity'), findsOneWidget);
      expect(
        calls.where((c) => c.method == 'setBlockedActivities'),
        isEmpty,
      );
    });

    testWidgets('removing a block goes through confirm + gate',
        (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(
          child: ActivityBlockerScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      expect(find.text('Unblock this activity?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Unblock'));
      await enterCodeAndConfirm(tester);

      final saveCalls = calls.where(
        (c) => c.method == 'setBlockedActivities',
      );
      expect(saveCalls, hasLength(1));
      expect(saveCalls.first.arguments['activities'], isEmpty);
      expect(find.text('com.example.app.BadActivity'), findsNothing);
      controller.session.end();
    });

    testWidgets('blocking a seen activity saves directly, no gate',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: ActivityBlockerScreen(controller: makeController()),
        ),
      );
      await tester.pumpAndSettle();

      // Expand the app group, then tap its Block button.
      await tester.tap(find.byType(ExpansionTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Block'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      final saveCalls = calls.where(
        (c) => c.method == 'setBlockedActivities',
      );
      expect(saveCalls, hasLength(1));
      expect(
        (saveCalls.first.arguments['activities'] as List),
        contains('com.example.app.MainActivity'),
      );
    });
  });

  // ------------------------------------------------------- C3: colour modes

  group('Batch C — C3: Colour Modes model', () {
    test('config round-trips, including a midnight-spanning window', () {
      const config = ColourModesConfig(
        enabled: true,
        modes: {ColourMode.grayscale, ColourMode.nightLight},
        windows: {
          ColourMode.grayscale: [TimeWindowModel(1380, 60)],
        },
        scopes: {ColourMode.grayscale: ColourScope.exceptApps},
        excludedApps: {
          ColourMode.grayscale: {'com.example.app'},
        },
        nightLightTemperature: 2700,
        nightLightIntensity: 12,
        extraDimLevel: 70,
        applyDuringFocus: true,
      );
      final back = ColourModesConfig.fromMap(config.toMap());
      expect(back.enabled, isTrue);
      expect(back.modes, config.modes);
      expect(back.windowsFor(ColourMode.grayscale), [
        const TimeWindowModel(1380, 60),
      ]);
      expect(back.scopeFor(ColourMode.grayscale), ColourScope.exceptApps);
      expect(
        back.excludedApps[ColourMode.grayscale],
        {'com.example.app'},
      );
      expect(back.nightLightTemperature, 2700);
      expect(back.nightLightIntensity, 12);
      expect(back.extraDimLevel, 70);
      expect(back.applyDuringFocus, isTrue);
    });

    test('Dart isLoosening mirror matches the native rule', () {
      const device = ColourCoverage(scope: ColourScope.device);
      const exceptEmpty = ColourCoverage(
        scope: ColourScope.exceptApps,
        excludedApps: {},
      );
      const exceptOne = ColourCoverage(
        scope: ColourScope.exceptApps,
        excludedApps: {'com.example.app'},
      );
      const onlyAB = ColourCoverage(
        scope: ColourScope.onlyApps,
        onlyApps: {'a', 'b'},
      );
      const onlyA = ColourCoverage(
        scope: ColourScope.onlyApps,
        onlyApps: {'a'},
      );
      // Widening the scope to the whole device is never a loosening.
      expect(ColourScope.isLoosening(onlyAB, device), isFalse);
      // Device -> only-apps always loosens.
      expect(ColourScope.isLoosening(device, onlyAB), isTrue);
      // Device -> except with an empty list changes nothing.
      expect(ColourScope.isLoosening(device, exceptEmpty), isFalse);
      // Device -> except with an app listed loosens (that app escapes).
      expect(ColourScope.isLoosening(device, exceptOne), isTrue);
      // Shrinking the only-apps list loosens (b escapes).
      expect(ColourScope.isLoosening(onlyAB, onlyA), isTrue);
      // Growing the only-apps list tightens.
      expect(ColourScope.isLoosening(onlyA, onlyAB), isFalse);
    });
  });

  group('Batch C — C3: Colour Modes screen', () {
    testWidgets('renders all four modes, grayscale first', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: ColourModesScreen(controller: makeController()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Grayscale'), findsOneWidget);
      expect(find.text('Night light'), findsOneWidget);
      expect(find.text('Extra dim'), findsOneWidget);
      expect(find.text('Colour inversion'), findsOneWidget);
    });

    testWidgets('extra dim disabled with a reason when unavailable',
        (tester) async {
      fakeColourStatus['extraDimAvailable'] = false;
      await tester.pumpWidget(
        buildTestApp(
          child: ColourModesScreen(controller: makeController()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Extra dim is not available on this device.'),
        findsOneWidget,
      );
    });

    testWidgets('lock banner shows for a locked mode', (tester) async {
      fakeColourStatus['locked'] = {
        'GRAYSCALE': true,
        'NIGHT_LIGHT': false,
        'EXTRA_DIM': false,
        'INVERSION': false,
      };
      fakeColourStatus['activeWindows'] = [
        {'mode': 'GRAYSCALE', 's': 0, 'e': 1440},
      ];
      await tester.pumpWidget(
        buildTestApp(
          child: ColourModesScreen(controller: makeController()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Locked until 24:00 — the recovery code opens it.'),
        findsOneWidget,
      );
    });

    testWidgets('locked reply offers the recovery gate, then retries',
        (tester) async {
      fakeLockedModes = {'GRAYSCALE'};
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(
          child: ColourModesScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      // The grayscale switch is the second Switch (after the master).
      final grayscaleSwitch = find.byType(Switch).at(1);
      expect(tester.widget<Switch>(grayscaleSwitch).value, isTrue);
      await tester.tap(grayscaleSwitch);
      await tester.pumpAndSettle();

      expect(find.text('Locked right now'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Open recovery gate'));
      await tester.pumpAndSettle();
      // The gate is open; from here the session opens the lock.
      fakeLockedModes = {};
      await enterCodeAndConfirm(tester);

      final saveCalls = calls.where(
        (c) => c.method == 'setColourModesConfig',
      );
      expect(saveCalls, hasLength(2));
      expect(
        (saveCalls.last.arguments['modes'] as List),
        isNot(contains('GRAYSCALE')),
      );
      expect(tester.widget<Switch>(find.byType(Switch).at(1)).value, isFalse);
      controller.session.end();
    });
  });

  group('Batch C — config tiles', () {
    testWidgets('Colour modes and Activity blocker are real tiles',
        (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(child: ConfigTab(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'Colour modes'), findsOneWidget);
      expect(
        find.widgetWithText(ListTile, 'Activity blocker'),
        findsOneWidget,
      );
      expect(find.byType(UnavailableTile), findsNothing);
    });

    testWidgets('Colour modes tile opens the Colour Modes screen',
        (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(child: ConfigTab(controller: controller)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ListTile, 'Colour modes'));
      await tester.pumpAndSettle();
      expect(find.text('Grayscale'), findsOneWidget);
    });

    testWidgets('Activity blocker tile opens the Activity Blocker screen',
        (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(child: ConfigTab(controller: controller)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ListTile, 'Activity blocker'));
      await tester.pumpAndSettle();
      expect(find.text('Blocked activities'), findsOneWidget);
    });
  });

  // ------------------------------------------------------- C4: seal-break priority

  group('Batch C — C4: seal-break priority', () {
    test('filing forced removal never consults a seal', () async {
      final controller = makeController();
      await controller.config.setForcedRemoval(
        const ForcedRemoval(active: true),
      );

      expect(
        calls.where((c) => c.method == 'getActiveSeals'),
        isEmpty,
        reason: 'filing must not evaluate seals at all',
      );
      final setCall = calls.firstWhere((c) => c.method == 'setSetting');
      expect(setCall.arguments['store'], 'recovery_prefs');
      expect(setCall.arguments['key'], 'forced_removal');
      expect(setCall.arguments['value'] as String, contains('"active":true'));
    });

    testWidgets('the code path runs removal without re-prompting',
        (tester) async {
      final controller = makeController();
      var ran = false;
      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                ran = await runLoosening(context, controller, () async {
                  await controller.channel.removeDeviceOwner();
                });
              },
              child: const Text('Remove'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Remove'));
      await enterCodeAndConfirm(tester);

      expect(ran, isTrue);
      expect(
        calls.any((c) => c.method == 'verifyRecoveryCode'),
        isTrue,
      );
      expect(
        calls.any((c) => c.method == 'removeDeviceOwner'),
        isTrue,
        reason: 'a verified code must reach the removal call',
      );
      controller.session.end();
    });

    test('a SEALED refusal still surfaces as PrivilegedException.isSealed',
        () async {
      fakeRemoveOwnerThrowsSealed = true;
      final channel = PrivilegedChannel(methodChannel: methodChannel);
      PrivilegedException? caught;
      try {
        await channel.removeDeviceOwner();
      } on PrivilegedException catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      expect(caught!.isSealed, isTrue);
      expect(caught.sealDetails, isNotNull);
    });

    testWidgets('forced-removal start is never gated on focus state',
        (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(child: ConfigTab(controller: controller)),
      );
      await tester.pumpAndSettle();

      // Gated only on a removal already in flight — nothing here
      // reads focus state, by design (C4: the escape path stays
      // visible and enabled during a focus session).
      final buttonFinder = find.widgetWithText(
        OutlinedButton,
        'Start forced removal',
      );
      final button = buttonFinder;
      expect(button, findsOneWidget);
      expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Start forced removal?'), findsOneWidget);
    });
  });
}
