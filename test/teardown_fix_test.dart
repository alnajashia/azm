import 'dart:io';

import 'package:azm/app_controller.dart';
import 'package:azm/data/privileged_channel.dart';
import 'package:azm/l10n/app_localizations.dart';
import 'package:azm/ui/config_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
  });
}
