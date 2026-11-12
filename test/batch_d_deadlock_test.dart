import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:azm/app_controller.dart';
import 'package:azm/data/privileged_channel.dart';
import 'package:azm/domain/entry_password.dart';
import 'package:azm/ui/lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

class HangingLocalAuth extends LocalAuthentication {
  HangingLocalAuth({
    this.deviceSupported = true,
    Completer<bool>? completer,
  }) : completer = completer ?? Completer<bool>();

  final bool deviceSupported;
  final Completer<bool> completer;
  bool authenticateCalled = false;
  bool lastPersistAcrossBackgrounding = true;

  @override
  Future<bool> isDeviceSupported() async => deviceSupported;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<dynamic> authMessages = const [],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) {
    authenticateCalled = true;
    lastPersistAcrossBackgrounding = persistAcrossBackgrounding;
    return completer.future;
  }
}

AppController controllerWithPassword(String? passwordRecord) {
  final backing = <String, Object?>{
    if (passwordRecord != null) 'security_prefs/entry_password': passwordRecord,
  };
  const methodChannel = MethodChannel('azm/privileged');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  messenger.setMockMethodCallHandler(methodChannel, (call) async {
    switch (call.method) {
      case 'getSetting':
        final args = (call.arguments as Map).cast<String, Object?>();
        return {'value': backing['${args['store']}/${args['key']}']};
      case 'setSetting':
        final args = (call.arguments as Map).cast<String, Object?>();
        backing['${args['store']}/${args['key']}'] = args['value'];
        return <String, Object?>{};
      case 'getUsageToday':
        return {
          'date': '2026-11-10',
          'packages': <Object?>[],
          'groups': <Object?>[],
        };
      case 'listInstalledApps':
        return <Object?>[];
      case 'getGroups':
        return {'groups': <Object?>[]};
      case 'getFocusSession':
        return null;
      case 'isDeviceOwner':
        return {'isDeviceOwner': true, 'isAdminActive': true};
      default:
        throw MissingPluginException('no mock for ${call.method}');
    }
  });

  final controller = AppController.test(
    PrivilegedChannel(methodChannel: methodChannel),
  );
  addTearDown(controller.dispose);
  return controller;
}

String recordFor(String password) => jsonEncode(
      EntryPasswordHash.create(password, iterations: 1000).toJson(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Batch D Regression Pins — Teardown & Lock Screen Hardening', () {
    // ------------------------------------------------------------------------
    // (a) Teardown calls removeActiveAdmin AFTER clearDeviceOwnerApp
    // ------------------------------------------------------------------------
    group('(a) Teardown calls removeActiveAdmin after clearDeviceOwnerApp', () {
      test('DeviceOwnerManager.kt source-level pin: clearOwner precedes removeAdmin with exact logcat line', () {
        final src = File(
          'android/app/src/main/kotlin/io/github/alnajashia/azm/deviceowner/DeviceOwnerManager.kt',
        ).readAsStringSync();

        // 1. clearDeviceOwnerApp must be invoked
        final clearOwnerIdx = src.indexOf('dpm.clearDeviceOwnerApp(context.packageName)');
        expect(clearOwnerIdx, isNonNegative, reason: 'clearDeviceOwnerApp missing');

        // 2. removeActiveAdmin must be invoked
        final removeAdminIdx = src.indexOf('dpm.removeActiveAdmin(admin)');
        expect(removeAdminIdx, isNonNegative, reason: 'removeActiveAdmin missing');

        // 3. removeActiveAdmin must follow clearDeviceOwnerApp
        expect(
          removeAdminIdx,
          greaterThan(clearOwnerIdx),
          reason: 'removeActiveAdmin must be called AFTER clearDeviceOwnerApp',
        );

        // 4. Must log "removeActiveAdmin ok" exactly as required by device-proof step
        expect(
          src.contains('removeActiveAdmin ok'),
          isTrue,
          reason: 'Log message "removeActiveAdmin ok" missing in DeviceOwnerManager.kt',
        );

        // 5. Steps order in teardown: clearOwner -> removeAdmin -> tornDown -> stopAccessibility
        final stepClearOwner = src.indexOf('step("clearOwner")');
        final stepRemoveAdmin = src.indexOf('step("removeAdmin")');
        final stepTornDown = src.indexOf('step("tornDown")');
        final stepStopA11y = src.indexOf('step("stopAccessibility")');

        expect(stepClearOwner, isNonNegative);
        expect(stepRemoveAdmin, greaterThan(stepClearOwner));
        expect(stepTornDown, greaterThan(stepRemoveAdmin));
        expect(stepStopA11y, greaterThan(stepTornDown));
      });

      test('RemovalReport mock DPM test: step sequence and report verification', () async {
        const channelName = 'azm/privileged';
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final methodChannel = const MethodChannel(channelName);

        messenger.setMockMethodCallHandler(methodChannel, (call) async {
          expect(call.method, 'removeDeviceOwner');
          return {
            'isDeviceOwner': false,
            'steps': [
              {'id': 'flag', 'ok': true, 'detail': 'lockdown disarmed'},
              {'id': 'focus', 'ok': true, 'detail': 'focus stopped'},
              {'id': 'restrictions', 'ok': true, 'detail': 'restrictions cleared'},
              {'id': 'clearOwner', 'ok': true, 'detail': 'owner cleared'},
              {'id': 'removeAdmin', 'ok': true, 'detail': 'admin removed'},
              {'id': 'tornDown', 'ok': true, 'detail': 'torn down flag set'},
              {'id': 'stopAccessibility', 'ok': true, 'detail': 'a11y stopped'},
              {'id': 'verify', 'ok': true, 'detail': 'clean'},
              {'id': 'flagClear', 'ok': true, 'detail': 'disarm preserved'},
            ],
          };
        });

        final client = PrivilegedChannel(methodChannel: methodChannel);
        final report = await client.removeDeviceOwner();

        expect(report.isDeviceOwner, isFalse);
        expect(report.clean, isTrue);
        expect(report.steps.map((s) => s.id).toList(), containsAllInOrder([
          'clearOwner',
          'removeAdmin',
          'tornDown',
          'stopAccessibility',
        ]));

        messenger.setMockMethodCallHandler(methodChannel, null);
      });
    });

    // ------------------------------------------------------------------------
    // (b) onUnbind lockdown guard does not fire when torn-down flag is set
    // ------------------------------------------------------------------------
    group('(b) onUnbind lockdown guard does not fire when torn-down flag is set', () {
      test('Simulation of onUnbind lockdown decision logic', () {
        bool evaluateLockdown({
          required bool isProtectionTornDown,
          required bool isRemovalInProgress,
          required bool intentionalDisable,
          required bool isAdminActive,
        }) {
          if (!isProtectionTornDown &&
              !isRemovalInProgress &&
              !intentionalDisable &&
              isAdminActive) {
            return true;
          }
          return false;
        }

        // When protection is torn down: lockdown NEVER fires, even if admin is active
        expect(
          evaluateLockdown(
            isProtectionTornDown: true,
            isRemovalInProgress: false,
            intentionalDisable: false,
            isAdminActive: true,
          ),
          isFalse,
          reason: 'Lockdown must NOT fire when isProtectionTornDown is true',
        );

        // When protection is torn down and removalInProgress is true: still false
        expect(
          evaluateLockdown(
            isProtectionTornDown: true,
            isRemovalInProgress: true,
            intentionalDisable: false,
            isAdminActive: true,
          ),
          isFalse,
        );

        // Normal operating state before teardown: lockdown fires if accessibility unexpectedly lost
        expect(
          evaluateLockdown(
            isProtectionTornDown: false,
            isRemovalInProgress: false,
            intentionalDisable: false,
            isAdminActive: true,
          ),
          isTrue,
        );

        // Intentional disable suppresses lockdown
        expect(
          evaluateLockdown(
            isProtectionTornDown: false,
            isRemovalInProgress: false,
            intentionalDisable: true,
            isAdminActive: true,
          ),
          isFalse,
        );
      });

      test('AzmAccessibilityService.kt source-level pin: all enforcement gated by isProtectionTornDown', () {
        final src = File(
          'android/app/src/main/kotlin/io/github/alnajashia/azm/accessibility/AzmAccessibilityService.kt',
        ).readAsStringSync();

        // 1. onUnbind lockdown guard checks !SettingsStore.isProtectionTornDown()
        expect(
          src.contains('!SettingsStore.isProtectionTornDown()'),
          isTrue,
          reason: 'onUnbind must check !SettingsStore.isProtectionTornDown()',
        );

        // 2. onServiceConnected stops if torn down
        expect(
          src.contains('if (SettingsStore.isProtectionTornDown())'),
          isTrue,
          reason: 'onServiceConnected must check isProtectionTornDown() and disableSelf()',
        );

        // 3. onAccessibilityEvent ignores events if torn down
        expect(
          src.contains('if (SettingsStore.isProtectionTornDown() || SettingsStore.isRemovalInProgress()) return'),
          isTrue,
          reason: 'onAccessibilityEvent must bail out when torn down',
        );

        // 4. suspendPackages refuses to suspend when torn down
        expect(
          src.contains('if (suspend && (SettingsStore.isProtectionTornDown() || SettingsStore.isRemovalInProgress())) return'),
          isTrue,
          reason: 'suspendPackages must refuse when torn down',
        );

        // 5. Companion object has disableService
        expect(
          src.contains('fun disableService()'),
          isTrue,
          reason: 'Companion object must provide disableService()',
        );
      });

      test('SettingsStore.kt source-level pin: isProtectionTornDown and isRemovalInProgress coupling', () {
        final src = File(
          'android/app/src/main/kotlin/io/github/alnajashia/azm/data/SettingsStore.kt',
        ).readAsStringSync();

        expect(src.contains('KEY_PROTECTION_TORN_DOWN'), isTrue);
        expect(src.contains('fun setProtectionTornDown(tornDown: Boolean)'), isTrue);
        expect(src.contains('fun isProtectionTornDown(): Boolean'), isTrue);
        // When torn down, isRemovalInProgress() also returns true
        expect(src.contains('if (isProtectionTornDown()) return true'), isTrue);
      });
    });

    // ------------------------------------------------------------------------
    // (c) Lock-screen password button is enabled while biometric auth is in flight
    // ------------------------------------------------------------------------
    group('(c) Lock-screen password button decoupling & timeout hardening', () {
      testWidgets(
        'Password button remains ENABLED while biometric auth is in flight, and opens password prompt',
        (tester) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          final hangingAuth = HangingLocalAuth();
          final passwordJson = recordFor('open sesame');
          final controller = controllerWithPassword(passwordJson);

          await tester.pumpWidget(
            MaterialApp(
              home: LockScreen(controller: controller, auth: hangingAuth),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          // Both buttons initially present
          expect(find.text('Access app'), findsOneWidget);
          expect(find.text('Use password instead'), findsOneWidget);

          final biometricFinder = find.ancestor(
            of: find.text('Access app'),
            matching: find.bySubtype<FilledButton>(),
          );
          final passwordFinder = find.ancestor(
            of: find.text('Use password instead'),
            matching: find.bySubtype<TextButton>(),
          );

          expect(biometricFinder, findsOneWidget);
          expect(passwordFinder, findsOneWidget);

          expect(tester.widget<FilledButton>(biometricFinder).onPressed, isNotNull);
          expect(tester.widget<TextButton>(passwordFinder).onPressed, isNotNull);

          // Tap biometric button: auth begins and is left in flight (hanging)
          await tester.tap(biometricFinder);
          await tester.pump();

          expect(hangingAuth.authenticateCalled, isTrue);
          expect(
            hangingAuth.lastPersistAcrossBackgrounding,
            isFalse,
            reason: 'persistAcrossBackgrounding must be false (requirement 7)',
          );

          // Biometric button is now busy/disabled
          expect(
            tester.widget<FilledButton>(biometricFinder).onPressed,
            isNull,
            reason: 'Biometric button must be disabled while auth is in flight',
          );

          // CRITICAL REQUIREMENT 9: Password button must NEVER be disabled by biometric busy state!
          expect(
            tester.widget<TextButton>(passwordFinder).onPressed,
            isNotNull,
            reason: 'Password button MUST remain enabled while biometric auth is in flight',
          );

          // Tap password button while biometric is still hanging
          await tester.tap(passwordFinder);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          // Password dialog opens immediately
          expect(find.text('Enter app password'), findsOneWidget);

          // Enter correct password and unlock
          await tester.enterText(find.byType(TextField), 'open sesame');
          await tester.pump();
          await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          expect(controller.startup, StartupState.unlocked);

          // Complete the in-flight auth to settle the pending 15s timeout timer
          hangingAuth.completer.complete(false);
          await tester.pump();

          await tester.pumpWidget(const SizedBox());
        },
      );

      testWidgets(
        'Biometric 15-second timeout resets _authBusy and re-enables button if platform hangs',
        (tester) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          final hangingAuth = HangingLocalAuth();
          final controller = controllerWithPassword(null);

          await tester.pumpWidget(
            MaterialApp(
              home: LockScreen(controller: controller, auth: hangingAuth),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          final biometricFinder = find.ancestor(
            of: find.text('Access app'),
            matching: find.bySubtype<FilledButton>(),
          );

          // Tap biometric button
          await tester.tap(biometricFinder);
          await tester.pump();

          // Button is disabled while auth is in flight
          expect(tester.widget<FilledButton>(biometricFinder).onPressed, isNull);

          // Advance virtual clock by 15 seconds to trigger timeout
          await tester.pump(const Duration(seconds: 15));
          await tester.pump();

          // After timeout, _authBusy is reset in finally block and button is re-enabled!
          expect(tester.widget<FilledButton>(biometricFinder).onPressed, isNotNull);

          // Settle the completer and clean up
          hangingAuth.completer.complete(false);
          await tester.pump();

          await tester.pumpWidget(const SizedBox());
        },
      );

      test('LockScreen source-level pin: 15s timeout, persistAcrossBackgrounding: false, decoupled _passwordBusy', () {
        final src = File('lib/ui/lock_screen.dart').readAsStringSync();

        // Requirement 7: persistAcrossBackgrounding: false
        expect(
          src.contains('persistAcrossBackgrounding: false'),
          isTrue,
          reason: 'persistAcrossBackgrounding must be false',
        );

        // Requirement 8: 15-second timeout on authenticate
        expect(
          src.contains('.timeout('),
          isTrue,
          reason: 'authenticate call must have a timeout',
        );
        expect(
          src.contains('const Duration(seconds: 15)'),
          isTrue,
          reason: 'timeout must be 15 seconds',
        );
        expect(
          src.contains('onTimeout: () => false'),
          isTrue,
          reason: 'onTimeout must return false',
        );

        // Requirement 9: _passwordBusy decouples password button from _authBusy
        expect(
          src.contains('bool _passwordBusy = false;'),
          isTrue,
          reason: '_passwordBusy state variable must exist',
        );
        expect(
          src.contains('onPressed: _passwordBusy ? null : _accessWithPassword'),
          isTrue,
          reason: 'Password button must be guarded by _passwordBusy, NOT _authBusy',
        );
      });
    });

    // ------------------------------------------------------------------------
    // (d) Teardown entry is never seal-refused
    // ------------------------------------------------------------------------
    group('(d) Teardown entry is never seal-refused', () {
      test('DeviceOwnerManager.removeDeviceOwner does not evaluate seals and disarms existing seals', () {
        final src = File(
          'android/app/src/main/kotlin/io/github/alnajashia/azm/deviceowner/DeviceOwnerManager.kt',
        ).readAsStringSync();

        // 1. removeDeviceOwner must NOT contain any call to SealRules.firstActiveSeal
        // or check activeSeals
        final methodIdx = src.indexOf('fun removeDeviceOwner(context: Context)');
        expect(methodIdx, isNonNegative);
        final methodBody = src.substring(methodIdx, src.indexOf('return RemovalReport', methodIdx));

        expect(
          methodBody.contains('firstActiveSeal'),
          isFalse,
          reason: 'DeviceOwnerManager.removeDeviceOwner must NOT check seals',
        );
        expect(
          methodBody.contains('PrivException.sealed'),
          isFalse,
          reason: 'removeDeviceOwner must never throw SEALED',
        );

        // 2. Teardown clears seal deadlines and stops focus session
        expect(
          methodBody.contains('SealRules.clearEventDeadlines()'),
          isTrue,
          reason: 'Teardown must clear event seal deadlines',
        );
        expect(
          methodBody.contains('FocusSessionStore.stop(context)'),
          isTrue,
          reason: 'Teardown must stop focus session (clearing condition seals)',
        );
        expect(
          methodBody.contains('genericSet(SettingsStore.PREFS_SECURITY, "impulse_lock", null)'),
          isTrue,
          reason: 'Teardown must clear impulse lock',
        );
      });
    });
  });
}
