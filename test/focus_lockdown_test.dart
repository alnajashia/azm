/// Item 4 (2026-11-19): full-phone lockdown during focus. The Dart
/// config gains `lockdownEnabled` + `lockdownStrict`; the focus
/// screen offers the switch and the tier choice (loosening edits go
/// through the recovery gate); the native engine starts a
/// whole-phone lockdown for each focus phase and lifts it during
/// breaks (pinned here by source, like the teardown pins).
library;

import 'dart:convert';
import 'dart:io';

import 'package:azm/app_controller.dart';
import 'package:azm/data/privileged_channel.dart';
import 'package:azm/domain/focus.dart';
import 'package:azm/theme.dart';
import 'package:azm/ui/impulse_focus_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'azm/privileged';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methodChannel = MethodChannel(channelName);

  group('FocusConfig lockdown fields', () {
    test('round-trip keeps lockdownEnabled and lockdownStrict', () {
      const c = FocusConfig(lockdownEnabled: true, lockdownStrict: true);
      final back = FocusConfig.fromJson(c.toJson());
      expect(back.lockdownEnabled, isTrue);
      expect(back.lockdownStrict, isTrue);
      expect(back.copyWith(lockdownStrict: false).lockdownStrict, isFalse);
    });

    test('old JSON without the keys reads as off, Tier 1', () {
      final back = FocusConfig.fromJson(const {
        'focusMinutes': 25,
        'breakMinutes': 5,
        'longBreakMinutes': 15,
        'cyclesBeforeLongBreak': 4,
      });
      expect(back.lockdownEnabled, isFalse);
      expect(back.lockdownStrict, isFalse);
    });
  });

  group('FocusModeScreen lockdown controls', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'getSetting':
            return {'value': null}; // defaults: lockdown off
          case 'listInstalledApps':
            return <Object?>[];
          case 'getGroups':
            return {'groups': <Object?>[]};
          case 'getFocusSession':
            return null;
          case 'setSetting':
            return <String, Object?>{};
          case 'hasNotificationPermission':
            return {'granted': true};
          default:
            throw MissingPluginException('no mock for ${call.method}');
        }
      });
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(methodChannel, null);
    });

    Map<String, dynamic>? lastSavedConfig() {
      for (final call in calls.reversed) {
        if (call.method != 'setSetting') continue;
        final args = call.arguments as Map<dynamic, dynamic>;
        if (args['key'] != 'config') continue;
        return (jsonDecode(args['value'] as String) as Map)
            .cast<String, dynamic>();
      }
      return null;
    }

    testWidgets('enabling the lockdown shows tiers; Tier 2 persists',
        (tester) async {
      final controller = AppController.test(
        PrivilegedChannel(methodChannel: methodChannel),
      );
      addTearDown(controller.dispose);
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: azmDarkTheme(),
          home: FocusModeScreen(controller: controller),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Off by default: the switch shows, the tier radios do not.
      expect(find.text('Full-phone lockdown during focus'), findsWidgets);
      expect(find.text('Level 1 — Suspend everything'), findsNothing);

      // Turn it on (a tightening: no code gate).
      final lockdownSwitch = find.ancestor(
        of: find.text('Lock the whole phone during focus periods; '
            'it lifts during breaks.'),
        matching: find.byType(SwitchListTile),
      );
      await tester.tap(lockdownSwitch);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Level 1 — Suspend everything'), findsOneWidget);
      expect(find.text('Level 2 — Strict kiosk'), findsOneWidget);
      expect(lastSavedConfig()?['lockdownEnabled'], isTrue);
      expect(lastSavedConfig()?['lockdownStrict'], isFalse);

      // Pick Tier 2 (also a tightening).
      await tester.tap(find.text('Level 2 — Strict kiosk'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(lastSavedConfig()?['lockdownStrict'], isTrue);

      await tester.pumpWidget(const SizedBox()); // dispose tickers
    });
  });

  group('Native focus-lockdown wiring (source pins)', () {
    late String src;

    setUpAll(() {
      src = File(
        'android/app/src/main/kotlin/com/alnajashia/azm/focus/'
        'FocusSessionStore.kt',
      ).readAsStringSync();
    });

    test('the Dart config JSON keys are read natively', () {
      expect(src, contains('optBoolean("lockdownEnabled"'));
      expect(src, contains('optBoolean("lockdownStrict"'));
    });

    test('a focus phase starts the lockdown; other phases end it', () {
      final startPhaseAt = src.indexOf('private fun startPhase');
      final nextFunAt = src.indexOf('private fun remainingMillis', startPhaseAt);
      final body = src.substring(startPhaseAt, nextFunAt);
      expect(body, contains('maybeStartFocusLockdown(context)'));
      expect(body, contains('maybeEndFocusLockdown(context)'));
    });

    test('applyState ends it when not enforcing; stop ends it too', () {
      final applyAt = src.indexOf('private fun applyState');
      final applyBody = src.substring(applyAt, applyAt + 700);
      expect(applyBody, contains('if (!isEnforcing()) maybeEndFocusLockdown'));
      final stopAt = src.indexOf('fun stop(context: Context)');
      final stopBody = src.substring(stopAt, stopAt + 900);
      expect(stopBody, contains('maybeEndFocusLockdown(context)'));
    });

    test('the focus lockdown is whole-phone, phase-length, own ID', () {
      final startAt = src.indexOf('private fun maybeStartFocusLockdown');
      final body = src.substring(startAt, startAt + 1600);
      expect(body, contains('LockdownStore.LockdownScope.ALL_APPS'));
      expect(body, contains('id = FOCUS_LOCKDOWN_ID'));
      expect(body, contains('LockdownStore.activeLockdown(context) != null'));
    });
  });
}
