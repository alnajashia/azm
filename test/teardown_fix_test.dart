import 'dart:io';

import 'package:azm/app_controller.dart';
import 'package:azm/data/privileged_channel.dart';
import 'package:azm/l10n/app_localizations.dart';
import 'package:azm/ui/config_tab.dart';
import 'package:azm/ui/lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

Widget buildTestApp({
  required AppController controller,
  required Widget child,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: child),
  );
}

/// A fake `LocalAuthentication` whose prompt always throws the biometric
/// lockout code (T8): the sensor locked after repeated failed attempts.
class ThrowingLocalAuth extends LocalAuthentication {
  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<dynamic> authMessages = const [],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) {
    throw PlatformException(code: 'LockedOut');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Teardown Fix Regression Pins — Root Causes & Half-Torn-Down Admin State', () {
    // ------------------------------------------------------------------------
    // 1. Source Pins: DeviceOwnerManager.kt
    // ------------------------------------------------------------------------
    group('1. DeviceOwnerManager.kt Source Level Pins', () {
      final src = File(
        'android/app/src/main/kotlin/com/alnajashia/azm/deviceowner/DeviceOwnerManager.kt',
      ).readAsStringSync();

      test('StatusBar disable check is guarded by UPSIDE_DOWN_CAKE (API 34)', () {
        // dpm.isStatusBarDisabled() was added in API 34. Calling it on API < 34 throws
        // NoSuchMethodError, which previously caused getOrDefault(true) to falsely fail step 3.
        expect(
          src.contains('Build.VERSION_CODES.UPSIDE_DOWN_CAKE'),
          isTrue,
          reason: 'StatusBar check must be guarded by UPSIDE_DOWN_CAKE',
        );
        expect(
          src.contains('dpm.isStatusBarDisabled()'),
          isTrue,
        );
        final uIndex = src.indexOf('Build.VERSION_CODES.UPSIDE_DOWN_CAKE');
        final sbIndex = src.indexOf('dpm.isStatusBarDisabled()');
        expect(
          sbIndex,
          greaterThan(uIndex),
          reason: 'isStatusBarDisabled call must appear inside UPSIDE_DOWN_CAKE version check',
        );
      });

      test('removeDeviceOwner permits execution in half-torn-down state (!isOwner && isAdmin)', () {
        // In half-torn-down state, requireOwner(context) throws DPM_NOT_OWNER.
        // removeDeviceOwner must allow proceeding if either owner or admin is active.
        expect(
          src.contains('if (!isDeviceOwner(context) && !isAdminActive(context))'),
          isTrue,
          reason: 'removeDeviceOwner must permit execution if isAdminActive is true',
        );
      });

      test('Teardown polls for admin removal to settle', () {
        // removeActiveAdmin is asynchronous in Android OS. Teardown must poll
        // isAdminActive(context) with sleep before Step 15 verify.
        final removeAdminStep = src.indexOf('step("removeAdmin")');
        final verifyStep = src.indexOf('step("verify")');
        expect(removeAdminStep, isNonNegative);
        expect(verifyStep, greaterThan(removeAdminStep));

        final adminPollSubstr = src.substring(removeAdminStep, verifyStep);
        expect(
          adminPollSubstr.contains('isAdminActive(context)'),
          isTrue,
          reason: 'step removeAdmin must poll isAdminActive',
        );
        expect(
          adminPollSubstr.contains('Thread.sleep'),
          isTrue,
          reason: 'step removeAdmin must wait for admin drop to settle',
        );
      });

      test('verifyRemovalComplete opportunistically cleans up residue admin when owner is cleared', () {
        final verifyFn = src.indexOf('fun verifyRemovalComplete(context: Context)');
        expect(verifyFn, isNonNegative);
        final verifyEnd = src.indexOf('fun getUserRestrictionResidue', verifyFn);
        final verifySubstr = src.substring(verifyFn, verifyEnd > 0 ? verifyEnd : verifyFn + 1000);

        expect(
          verifySubstr.contains('!isOwner && isAdmin'),
          isTrue,
          reason: 'verifyRemovalComplete must check for !isOwner && isAdmin',
        );
        expect(
          verifySubstr.contains('removeActiveAdmin'),
          isTrue,
          reason: 'verifyRemovalComplete must attempt removeActiveAdmin on residue admin',
        );
      });
    });

    // ------------------------------------------------------------------------
    // 2. Source Pins: ColourModesController.kt
    // ------------------------------------------------------------------------
    group('2. ColourModesController.kt Source Level Pins', () {
      final src = File(
        'android/app/src/main/kotlin/com/alnajashia/azm/data/ColourModesController.kt',
      ).readAsStringSync();

      test('ColourModesController.release only removes successfully restored keys', () {
        // Flaw: release previously ran state.edit().remove(KEY_SAVED_KEYS).apply() unconditionally,
        // clobbering keys even if restoreKey failed.
        final releaseIdx = src.indexOf('fun release(context: Context)');
        expect(releaseIdx, isNonNegative);
        final releaseSubstr = src.substring(releaseIdx, releaseIdx + 1200);

        expect(
          releaseSubstr.contains('if (saved.isEmpty())'),
          isTrue,
          reason: 'KEY_SAVED_KEYS must only be removed if all saved keys were restored',
        );
        expect(
          releaseSubstr.contains('state.edit().putStringSet(KEY_SAVED_KEYS, saved)'),
          isTrue,
          reason: 'Un-restored keys must remain in KEY_SAVED_KEYS',
        );
      });

      test('restoreKey returns Boolean indicating success', () {
        final restoreIdx = src.indexOf('private fun restoreKey(');
        expect(restoreIdx, isNonNegative);
        final restoreSubstr = src.substring(restoreIdx, restoreIdx + 500);

        expect(
          restoreSubstr.contains('): Boolean'),
          isTrue,
          reason: 'restoreKey must return a Boolean indicating success',
        );
      });
    });

    // ------------------------------------------------------------------------
    // 3. UI / Controller Layer Verification
    // ------------------------------------------------------------------------
    group('3. UI / Channel Verification in Half-Torn-Down State', () {
      testWidgets('ConfigTab enables removal button when !isOwner && isAdminActive', (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        const channelName = 'azm/privileged';
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final methodChannel = const MethodChannel(channelName);

        messenger.setMockMethodCallHandler(methodChannel, (call) async {
          switch (call.method) {
            case 'isDeviceOwner':
              return {
                'isDeviceOwner': false,
                'isAdminActive': true,
                'forcedRemovalDelayHours': 48,
              };
            case 'getPrivateDns':
              return {'mode': 'OFF', 'hostname': null};
            case 'getUserRestrictionResidue':
              return {'keys': <String>[]};
            case 'getColourModesStatus':
              return {'supported': true, 'active': false};
            case 'listUserRestrictions':
              return {'restrictions': <String, bool>{}};
            case 'listInstalledApps':
              return <Map<String, dynamic>>[];
            case 'getForcedRemovalState':
              return {'active': false, 'dueTimestampMs': 0};
            case 'getSetting':
              return {'value': null};
            case 'setSetting':
              return {};
            default:
              return null;
          }
        });

        final controller = AppController.test(
          PrivilegedChannel(methodChannel: methodChannel),
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          buildTestApp(
            controller: controller,
            child: ConfigTab(controller: controller),
          ),
        );
        await tester.pumpAndSettle();

        // The "Remove Device Owner now" tile should be visible and have an active onTap handler
        final tileFinder = find.widgetWithText(ListTile, 'Remove Device Owner now');
        expect(tileFinder, findsOneWidget);
        final listTile = tester.widget<ListTile>(tileFinder);
        expect(listTile.onTap, isNotNull, reason: 'Tile should be tappable when admin is still active');
      });

      testWidgets('removal tile reads as a tappable action (chevron)', (tester) async {
        // User request 2026-11-19: the tile looked like a label.
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        const channelName = 'azm/privileged';
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final methodChannel = const MethodChannel(channelName);

        messenger.setMockMethodCallHandler(methodChannel, (call) async {
          switch (call.method) {
            case 'isDeviceOwner':
              return {
                'isDeviceOwner': true,
                'isAdminActive': true,
                'forcedRemovalDelayHours': 48,
              };
            case 'getPrivateDns':
              return {'mode': 'OFF', 'hostname': null};
            case 'getUserRestrictionResidue':
              return {'keys': <String>[]};
            case 'getColourModesStatus':
              return {'supported': true, 'active': false};
            case 'listUserRestrictions':
              return {'restrictions': <String, bool>{}};
            case 'listInstalledApps':
              return <Map<String, dynamic>>[];
            case 'getForcedRemovalState':
              return {'active': false, 'dueTimestampMs': 0};
            case 'getSetting':
              return {'value': null};
            case 'setSetting':
              return {};
            default:
              return null;
          }
        });

        final controller = AppController.test(
          PrivilegedChannel(methodChannel: methodChannel),
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          buildTestApp(
            controller: controller,
            child: ConfigTab(controller: controller),
          ),
        );
        await tester.pumpAndSettle();

        final tileFinder = find.widgetWithText(ListTile, 'Remove Device Owner now');
        expect(tileFinder, findsOneWidget);
        final listTile = tester.widget<ListTile>(tileFinder);
        expect(listTile.trailing, isA<Icon>());
        expect((listTile.trailing! as Icon).icon, Icons.navigate_next_outlined);
      });

      test('removal always asks for a fresh recovery code', () {
        // User request 2026-11-19: the most destructive action never
        // rides on an earlier code entry.
        final src = File('lib/ui/config_tab.dart').readAsStringSync();
        final at = src.indexOf('Future<void> _onRemoveOwnerTapped()');
        final body = src.substring(at, at + 900);
        expect(body, contains('forceFreshCode: true'));
      });

      testWidgets('executeDeviceOwnerRemovalFlow performs final verification check before timeout', (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        const channelName = 'azm/privileged';
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final methodChannel = const MethodChannel(channelName);

        var verifyCalls = 0;
        messenger.setMockMethodCallHandler(methodChannel, (call) async {
          switch (call.method) {
            case 'removeDeviceOwner':
              return {
                'isDeviceOwner': false,
                'steps': [
                  {'id': 'flag', 'ok': true, 'detail': 'ok'},
                  {'id': 'clearOwner', 'ok': true, 'detail': 'ok'},
                  {'id': 'removeAdmin', 'ok': true, 'detail': 'ok'},
                  {'id': 'verify', 'ok': true, 'detail': 'clean'},
                ],
              };
            case 'verifyRemovalComplete':
              verifyCalls++;
              // Polling returns unverified initially, but on the final check it returns verified
              if (verifyCalls >= 3) {
                return {
                  'verified': true,
                  'isDeviceOwner': false,
                  'isAdminActive': false,
                  'restrictionsResidue': <String>[],
                  'screenCaptureDisabled': false,
                };
              }
              return {
                'verified': false,
                'isDeviceOwner': false,
                'isAdminActive': true,
                'restrictionsResidue': <String>[],
                'screenCaptureDisabled': false,
              };
            default:
              return null;
          }
        });

        final controller = AppController.test(
          PrivilegedChannel(methodChannel: methodChannel),
        );
        addTearDown(controller.dispose);

        BuildContext? testContext;
        await tester.pumpWidget(
          buildTestApp(
            controller: controller,
            child: Builder(
              builder: (ctx) {
                testContext = ctx;
                return const Text('Root');
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        bool removalSuccessCalled = false;
        final removalFuture = executeDeviceOwnerRemovalFlow(
          context: testContext!,
          controller: controller,
          minDisplayDuration: const Duration(milliseconds: 300),
          maxDisplayDuration: const Duration(milliseconds: 600),
          pollInterval: const Duration(milliseconds: 100),
          onRemovalSuccess: () => removalSuccessCalled = true,
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
        await removalFuture;
        await tester.pumpAndSettle();

        expect(removalSuccessCalled, isTrue, reason: 'Final verification check should confirm success');
        expect(find.text('Protection fully removed'), findsOneWidget);
      });
    });

    // ------------------------------------------------------------------------
    // 4. Deadlock Re-Audit Final Fix Pins (2026-11-14)
    // ------------------------------------------------------------------------
    group('4. Deadlock Re-Audit Final Fix Pins', () {
      final managerSrc = File(
        'android/app/src/main/kotlin/com/alnajashia/azm/deviceowner/DeviceOwnerManager.kt',
      ).readAsStringSync();
      final receiverSrc = File(
        'android/app/src/main/kotlin/com/alnajashia/azm/deviceowner/AdminReceiver.kt',
      ).readAsStringSync();
      final configTabSrc = File('lib/ui/config_tab.dart').readAsStringSync();

      test('T1 — removeAdmin throws after the 13 s ladder when the admin never clears', () {
        final stepStart = managerSrc.indexOf('step("removeAdmin")');
        final stepEnd = managerSrc.indexOf('step("tornDown")', stepStart);
        expect(stepStart, isNonNegative);
        expect(stepEnd, greaterThan(stepStart));
        final body = managerSrc.substring(stepStart, stepEnd);
        expect(
          body.contains('val rungs = listOf(30, 50, 50)'),
          isTrue,
          reason: 'The ladder must be 3 s + 5 s + 5 s = 13 s of polling',
        );
        expect(
          body.contains('throw PrivException.dpmFailed'),
          isTrue,
          reason: 'A stuck admin must fail loudly with the waited time',
        );
        expect(
          body.contains('admin still active after'),
          isTrue,
          reason: 'The failure must carry the waited milliseconds',
        );
        expect(
          body.contains('"active admin removed"'),
          isFalse,
          reason: 'The unconditional false-success return must be gone',
        );
      });

      test('T2 — removeAdmin succeeds after a slow settle (the ladder absorbs it)', () {
        final stepStart = managerSrc.indexOf('step("removeAdmin")');
        final stepEnd = managerSrc.indexOf('step("tornDown")', stepStart);
        final body = managerSrc.substring(stepStart, stepEnd);
        expect(body.contains('listOf(30, 50, 50)'), isTrue);
        // 30 + 50 + 50 ticks of 100 ms = 13 000 ms of budget.
        expect(body.contains('Thread.sleep(100)'), isTrue);
        expect(
          body.contains('if (!isAdminActive(context)) break'),
          isTrue,
          reason: 'The ladder must exit early once the admin settles',
        );
        expect(
          body.contains('active admin removed after'),
          isTrue,
          reason: 'The success detail must report the waited time',
        );
      });

      test('T3 — half-torn-down re-run marks owner-only steps skipped, not passed', () {
        expect(
          managerSrc.contains('val skipped: Boolean = false'),
          isTrue,
          reason: 'TeardownStep must carry a skipped flag',
        );
        expect(
          managerSrc.contains('"skipped" to skipped'),
          isTrue,
          reason: 'The skipped flag must reach the Dart side',
        );
        for (final id in [
          'policies',
          'unsuspend',
          'unhide',
          'uninstallBlocks',
          'appRestrictions',
        ]) {
          expect(
            RegExp('stepSkipped\\(\\s*"$id"').hasMatch(managerSrc),
            isTrue,
            reason: 'Step $id must be recorded as skipped when not owner',
          );
        }
      });

      test('T4 — re-run verify uses the user effective restrictions as residue', () {
        final stepStart = managerSrc.indexOf('step("restrictions")');
        final stepEnd = managerSrc.indexOf('step("unhide")', stepStart);
        expect(stepStart, isNonNegative);
        expect(stepEnd, greaterThan(stepStart));
        final body = managerSrc.substring(stepStart, stepEnd);
        expect(
          body.contains('getUserRestrictionResidue(context)'),
          isTrue,
          reason:
              'The non-owner branch must read the user effective restrictions, not emptyList()',
        );
      });

      test('T5 — active lockdown is ended by the teardown', () {
        final stepStart = managerSrc.indexOf('step("lockdown")');
        final flagStart = managerSrc.indexOf('step("flag")');
        final focusStart = managerSrc.indexOf('step("focus")');
        expect(stepStart, isNonNegative);
        expect(
          stepStart,
          greaterThan(flagStart),
          reason: 'The lockdown step must run after the disarm flag',
        );
        expect(
          stepStart,
          lessThan(focusStart),
          reason: 'The lockdown step must run while still owner (before step 2)',
        );
        final body = managerSrc.substring(
          stepStart,
          managerSrc.indexOf('step("focus")', stepStart),
        );
        expect(body.contains('LockdownStore.end(context)'), isTrue);
        expect(body.contains('LockdownManager.cancelAllWindows(context)'), isTrue);
        expect(body.contains('FocusScheduleManager.cancelAllAlarms(context)'), isTrue);
        expect(
          body.contains('LockdownStore.activeLockdown(context) != null'),
          isTrue,
          reason: 'The step must verify no lockdown record survives',
        );
        final verifyStart = managerSrc.indexOf('step("verify")');
        final verifyEnd = managerSrc.indexOf('step("flagClear")', verifyStart);
        final verifyBody = managerSrc.substring(verifyStart, verifyEnd);
        expect(
          verifyBody.contains('active lockdown record still present'),
          isTrue,
          reason: 'The final verification must fail on a surviving lockdown record',
        );
      });

      test('T7 — AdminReceiver.onEnabled does not reset the flags mid-removal', () {
        final guard = receiverSrc.indexOf('if (!SettingsStore.isRemovalInProgress())');
        expect(guard, isNonNegative);
        final resetTornDown = receiverSrc.indexOf(
          'SettingsStore.setProtectionTornDown(false)',
          guard,
        );
        final resetInProgress = receiverSrc.indexOf(
          'SettingsStore.setRemovalInProgress(false)',
          guard,
        );
        expect(resetTornDown, greaterThan(guard));
        expect(resetInProgress, greaterThan(guard));
      });

      test('T9 — Dart probe polls the admin for 5 s, not 1 s', () {
        final verifyFn = managerSrc.indexOf('fun verifyRemovalComplete(context: Context)');
        expect(verifyFn, isNonNegative);
        final verifyEnd = managerSrc.indexOf(
          'fun getUserRestrictionResidue',
          verifyFn,
        );
        final body = managerSrc.substring(
          verifyFn,
          verifyEnd > 0 ? verifyEnd : verifyFn + 1500,
        );
        expect(
          body.contains('var retries = 50'),
          isTrue,
          reason: 'The opportunistic admin poll must be 50 x 100 ms = 5 s',
        );
      });

      test('Colour pre-flight (D) warns before tearing down', () {
        expect(
          configTabSrc.contains('hasEnforcedColourModes()'),
          isTrue,
          reason: 'The flow must probe whether colour modes are enforced',
        );
        expect(
          configTabSrc.contains('isWriteSecureSettingsGranted()'),
          isTrue,
          reason: 'The flow must probe the WRITE_SECURE_SETTINGS grant',
        );
        expect(
          configTabSrc.contains('removalColourPreflightTitle'),
          isTrue,
          reason: 'The warning dialog must be shown before the teardown starts',
        );
      });

      test('Build stamp (J) exists and is shown on the Status tab', () {
        final buildInfo = File('lib/build_info.dart').readAsStringSync();
        expect(buildInfo.contains('buildGitHead'), isTrue);
        expect(buildInfo.contains('buildDate'), isTrue);
        final setupSrc = File('lib/ui/setup_screen.dart').readAsStringSync();
        expect(
          setupSrc.contains('buildGitHead'),
          isTrue,
          reason: 'The Status tab must show the build stamp',
        );
      });

      testWidgets('T6 — isClean is false when verify is the only failed step', (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final controller = AppController.test(
          PrivilegedChannel(methodChannel: const MethodChannel('azm/privileged')),
        );
        addTearDown(controller.dispose);

        BuildContext? testContext;
        await tester.pumpWidget(
          buildTestApp(
            controller: controller,
            child: Builder(
              builder: (ctx) {
                testContext = ctx;
                return const Text('Root');
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The native report says verify failed, while the Dart probe
        // says verified: the old isClean fudge showed a clean success
        // and hid the failed step. The dialog must show the partial
        // title and list the failed step instead.
        final dialogFuture = showRemovalOutcomeDialog(
          testContext!,
          result: const DeviceOwnerRemovalResult(
            isDeviceOwner: false,
            steps: [
              RemovalStepResult(
                id: 'verify',
                ok: false,
                detail: 'Post-removal residue: admin still active',
              ),
            ],
          ),
          verification: const RemovalVerificationResult(
            verified: true,
            isDeviceOwner: false,
            isAdminActive: false,
            restrictionsResidue: [],
            screenCaptureDisabled: false,
          ),
          isTimeout: false,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Protection removed, with warnings'), findsOneWidget);
        expect(find.text('Protection fully removed'), findsNothing);
        expect(
          find.textContaining('Post-removal verification'),
          findsOneWidget,
          reason: 'The failed verify step must be listed, not hidden',
        );

        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        await dialogFuture;
      });

      testWidgets('T8 — lock-screen auth maps LockedOut to the biometric-lockout message', (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        const channelName = 'azm/privileged';
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final methodChannel = const MethodChannel(channelName);
        messenger.setMockMethodCallHandler(methodChannel, (call) async {
          switch (call.method) {
            case 'getSetting':
              return {'value': null};
            case 'setSetting':
              return <String, Object?>{};
            case 'getUsageToday':
              return {
                'date': '',
                'packages': <String, int>{},
                'groups': <String, int>{},
              };
            default:
              return null;
          }
        });

        final controller = AppController.test(
          PrivilegedChannel(methodChannel: methodChannel),
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          buildTestApp(
            controller: controller,
            child: LockScreen(controller: controller, auth: ThrowingLocalAuth()),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final accessFinder = find.ancestor(
          of: find.text('Access app'),
          matching: find.bySubtype<FilledButton>(),
        );
        expect(accessFinder, findsOneWidget);
        await tester.tap(accessFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          find.text(
            'Biometrics are locked out after failed attempts — use your device PIN, pattern or password to unlock.',
          ),
          findsOneWidget,
          reason: 'LockedOut must show the biometric-lockout message',
        );
        expect(
          find.text('A required permission is not granted.'),
          findsNothing,
          reason: 'A biometric lockout is not a missing permission',
        );
      });
    });

    group('5. Manual-Uninstall Wedge Fix — Deferred F28 + In-App Self-Uninstall', () {
      test('F28 no longer runs the lockdown synchronously inside onUnbind', () {
        final src = File(
          'android/app/src/main/kotlin/com/alnajashia/azm/accessibility/AzmAccessibilityService.kt',
        ).readAsStringSync();

        // The unbind handler must only POST the work now. (The
        // deferred runner lives between onUnbind and onDestroy, so
        // the unbind body is measured up to it, not to onDestroy.)
        final unbindFn = src.indexOf('override fun onUnbind');
        final deferredFn =
            src.indexOf('private fun runDeferredAccessibilityLockdown()');
        final unbindBody = src.substring(unbindFn, deferredFn);
        expect(
          unbindBody.contains('handler.postDelayed('),
          isTrue,
          reason: 'onUnbind must defer the lockdown instead of running it inline',
        );
        expect(
          unbindBody.contains('deferredAccessibilityLockdownRunnable'),
          isTrue,
          reason: 'onUnbind must post the deferred lockdown runnable',
        );
        expect(
          unbindBody.contains('suspendPackages('),
          isFalse,
          reason: 'No suspension may run synchronously inside onUnbind anymore',
        );
        expect(
          unbindBody.contains('addUserRestriction('),
          isFalse,
          reason: 'No restriction write may run synchronously inside onUnbind anymore',
        );
        expect(
          unbindBody.contains('startActivity('),
          isFalse,
          reason: 'No activity may launch synchronously inside onUnbind anymore',
        );

        // The deferred runner re-checks every guard at fire time.
        final deferredBody = src.substring(deferredFn, deferredFn + 2200);
        expect(
          deferredBody.contains('AzmState.accessibilityServiceRunning'),
          isTrue,
          reason: 'The deferred runner must skip if the service is running again',
        );
        expect(deferredBody.contains('isProtectionTornDown()'), isTrue);
        expect(deferredBody.contains('isRemovalInProgress()'), isTrue);
        expect(
          deferredBody.contains('consumeIntentionalAccessibilityDisable()'),
          isTrue,
        );
        expect(deferredBody.contains('isAdminActive(admin)'), isTrue);
        expect(deferredBody.contains('suspendPackages('), isTrue);
        expect(
          unbindBody.contains('ACCESSIBILITY_LOCKDOWN_DEFER_MS'),
          isTrue,
          reason: 'The defer delay must be a named constant, not a literal',
        );

        // A reconnect cancels the pending lockdown.
        final connectedFn = src.indexOf('override fun onServiceConnected');
        final connectedBody = src.substring(connectedFn, connectedFn + 600);
        expect(
          connectedBody.contains(
            'removeCallbacks(deferredAccessibilityLockdownRunnable)',
          ),
          isTrue,
          reason: 'A service reconnect must cancel the pending lockdown',
        );
      });

      test('requestSelfUninstall opens the system uninstaller for the own package', () {
        final handlerSrc = File(
          'android/app/src/main/kotlin/com/alnajashia/azm/channel/PrivilegedChannelHandler.kt',
        ).readAsStringSync();
        expect(handlerSrc.contains('"requestSelfUninstall"'), isTrue);
        expect(
          handlerSrc.contains('Intent.ACTION_UNINSTALL_PACKAGE'),
          isTrue,
          reason: 'Self-uninstall must use the modern system uninstall intent',
        );
        expect(
          handlerSrc.contains('"stillOwner"'),
          isTrue,
          reason: 'The pre-flight owner check must report stillOwner',
        );
        final manifestSrc =
            File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
        expect(
          manifestSrc.contains('android.permission.REQUEST_DELETE_PACKAGES'),
          isTrue,
          reason: 'Android 9+ requires REQUEST_DELETE_PACKAGES for the uninstall intent',
        );
        expect(
          handlerSrc.contains(
            'Uri.parse("package:\${appContext.packageName}")',
          ),
          isTrue,
          reason: 'The uninstall intent must target this app\'s own package',
        );
        expect(handlerSrc.contains('Intent.FLAG_ACTIVITY_NEW_TASK'), isTrue);
        final dartSrc =
            File('lib/data/privileged_channel.dart').readAsStringSync();
        expect(dartSrc.contains('requestSelfUninstall()'), isTrue);
        final configSrc = File('lib/ui/config_tab.dart').readAsStringSync();
        expect(
          configSrc.contains(
            'onUninstall: () async { await controller.channel.requestSelfUninstall(); }',
          ),
          isTrue,
          reason: 'Every outcome-dialog call site must wire the uninstall action',
        );
        expect(
          configSrc.contains('if (_isOwner == false)'),
          isTrue,
          reason: 'The danger-zone uninstall tile must only show when not owner',
        );
      });

      testWidgets('T10 — clean removal outcome offers in-app self-uninstall', (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        const channelName = 'azm/privileged';
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final methodChannel = const MethodChannel(channelName);
        var uninstallCalls = 0;
        messenger.setMockMethodCallHandler(methodChannel, (call) async {
          if (call.method == 'requestSelfUninstall') {
            uninstallCalls++;
            return {'started': true};
          }
          return null;
        });
        addTearDown(() {
          messenger.setMockMethodCallHandler(methodChannel, null);
        });

        final controller = AppController.test(
          PrivilegedChannel(methodChannel: methodChannel),
        );
        addTearDown(controller.dispose);

        BuildContext? testContext;
        await tester.pumpWidget(
          buildTestApp(
            controller: controller,
            child: Builder(
              builder: (ctx) {
                testContext = ctx;
                return const Text('Root');
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        final dialogFuture = showRemovalOutcomeDialog(
          testContext!,
          result: const DeviceOwnerRemovalResult(
            isDeviceOwner: false,
            steps: [],
          ),
          verification: const RemovalVerificationResult(
            verified: true,
            isDeviceOwner: false,
            isAdminActive: false,
            restrictionsResidue: [],
            screenCaptureDisabled: false,
          ),
          isTimeout: false,
          onUninstall: () async {
            await controller.channel.requestSelfUninstall();
          },
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Protection fully removed'), findsOneWidget);
        expect(find.text('Uninstall Azm'), findsOneWidget);
        await tester.tap(find.text('Uninstall Azm'));
        await tester.pump();
        // The dialog's exit animation needs a full pump (the
        // DNS-dialog lesson): 100 ms leaves the title in the tree.
        await tester.pump(const Duration(seconds: 1));
        expect(uninstallCalls, 1);
        expect(find.text('Protection fully removed'), findsNothing);
        await dialogFuture;
      });

      testWidgets('T11 — danger-zone uninstall tile asks first, then calls the channel', (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        const channelName = 'azm/privileged';
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final methodChannel = const MethodChannel(channelName);
        var uninstallCalls = 0;
        messenger.setMockMethodCallHandler(methodChannel, (call) async {
          switch (call.method) {
            case 'isDeviceOwner':
              return {
                'isDeviceOwner': false,
                'isAdminActive': false,
                'forcedRemovalDelayHours': 24,
              };
            case 'getPrivateDns':
              return {'mode': 'off', 'hostname': null};
            case 'requestSelfUninstall':
              uninstallCalls++;
              return {'started': true};
            default:
              return null;
          }
        });
        addTearDown(() {
          messenger.setMockMethodCallHandler(methodChannel, null);
        });

        final controller = AppController.test(
          PrivilegedChannel(methodChannel: methodChannel),
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          buildTestApp(
            controller: controller,
            child: ConfigTab(controller: controller),
          ),
        );
        await tester.pumpAndSettle();

        final tileFinder = find.widgetWithText(ListTile, 'Uninstall Azm');
        expect(tileFinder, findsOneWidget);
        await tester.tap(tileFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // The confirmation card appears, and the channel is NOT
        // called until the user confirms.
        expect(find.text('Uninstall Azm?'), findsOneWidget);
        expect(uninstallCalls, 0);

        await tester.tap(find.widgetWithText(FilledButton, 'Uninstall Azm'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(uninstallCalls, 1);
      });

      testWidgets('T12 — still-owner refusal shows the remove-owner-first message', (tester) async {
        // User request 2026-11-19: the native pre-flight reports
        // stillOwner; the UI must say so plainly, not fail silently.
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        const channelName = 'azm/privileged';
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final methodChannel = const MethodChannel(channelName);
        messenger.setMockMethodCallHandler(methodChannel, (call) async {
          switch (call.method) {
            case 'isDeviceOwner':
              return {
                'isDeviceOwner': false,
                'isAdminActive': false,
                'forcedRemovalDelayHours': 24,
              };
            case 'getPrivateDns':
              return {'mode': 'off', 'hostname': null};
            case 'requestSelfUninstall':
              return {'started': false, 'reason': 'stillOwner'};
            default:
              return null;
          }
        });
        addTearDown(() {
          messenger.setMockMethodCallHandler(methodChannel, null);
        });

        final controller = AppController.test(
          PrivilegedChannel(methodChannel: methodChannel),
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          buildTestApp(
            controller: controller,
            child: ConfigTab(controller: controller),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(ListTile, 'Uninstall Azm'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.widgetWithText(FilledButton, 'Uninstall Azm'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          find.text('Remove Device Owner first — Android refuses to '
              'uninstall an active device owner.'),
          findsOneWidget,
        );
      });
    });
  });
}
