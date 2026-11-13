import 'package:azm/app_controller.dart';
import 'package:azm/data/privileged_channel.dart';
import 'package:azm/l10n/app_localizations.dart';
import 'package:azm/main.dart';
import 'package:azm/theme.dart';
import 'package:azm/ui/config_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'azm/privileged';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methodChannel = MethodChannel(channelName);

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  Widget buildTestApp({
    required AppController controller,
    required Widget child,
    Locale locale = const Locale('en'),
  }) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: azmLightTheme(),
      darkTheme: azmDarkTheme(),
      home: Scaffold(body: child),
    );
  }

  group('Batch D Addendum — Post-Confirmation Loading for Device Owner Removal', () {
    testWidgets(
      '1. Loading dialog appears after confirmation and cannot be dismissed by back button or tapping outside',
      (tester) async {
        int removeCallCount = 0;
        messenger.setMockMethodCallHandler(methodChannel, (call) async {
          switch (call.method) {
            case 'removeDeviceOwner':
              removeCallCount++;
              return {
                'isDeviceOwner': false,
                'steps': [
                  {'id': 'flag', 'ok': true, 'detail': 'ok'},
                  {'id': 'clearOwner', 'ok': true, 'detail': 'ok'},
                ],
              };
            case 'verifyRemovalComplete':
              return {
                'verified': true,
                'isDeviceOwner': false,
                'isAdminActive': false,
                'restrictionsResidue': <String>[],
                'screenCaptureDisabled': false,
              };
            default:
              return null;
          }
        });

        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final controller = AppController.test(
          PrivilegedChannel(methodChannel: methodChannel),
        );

        BuildContext? testContext;
        await tester.pumpWidget(
          buildTestApp(
            controller: controller,
            child: Builder(
              builder: (ctx) {
                testContext = ctx;
                return const Text('Test Root');
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Run removal flow
        bool removalSuccessCalled = false;
        final removalFuture = executeDeviceOwnerRemovalFlow(
          context: testContext!,
          controller: controller,
          onRemovalSuccess: () => removalSuccessCalled = true,
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Loading dialog is visible
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(
          find.text('Completing Device Owner removal…'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Please wait. Do not close the app or uninstall until teardown completes.',
          ),
          findsOneWidget,
        );
        expect(controller.isRemovingDeviceOwner, isTrue);

        // Attempt 1: back button / gesture via popRoute
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // Attempt 2: tap outside on the modal barrier (top-left corner)
        await tester.tapAt(const Offset(10, 10));
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // Advance fake timer past the 10s minimum
        await tester.pump(const Duration(seconds: 10));
        await tester.pump();
        await removalFuture;
        await tester.pumpAndSettle();

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(removalSuccessCalled, isTrue);
        expect(find.text('Protection fully removed'), findsOneWidget);
        expect(removeCallCount, 1);
      },
    );

    testWidgets(
      '2. Loading stays visible for at least ~10 seconds even if verification is immediately complete',
      (tester) async {
        messenger.setMockMethodCallHandler(methodChannel, (call) async {
          switch (call.method) {
            case 'removeDeviceOwner':
              return {
                'isDeviceOwner': false,
                'steps': [
                  {'id': 'clearOwner', 'ok': true, 'detail': 'ok'},
                ],
              };
            case 'verifyRemovalComplete':
              return {
                'verified': true,
                'isDeviceOwner': false,
                'isAdminActive': false,
                'restrictionsResidue': <String>[],
                'screenCaptureDisabled': false,
              };
            default:
              return null;
          }
        });

        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final controller = AppController.test(
          PrivilegedChannel(methodChannel: methodChannel),
        );

        BuildContext? testContext;
        await tester.pumpWidget(
          buildTestApp(
            controller: controller,
            child: Builder(
              builder: (ctx) {
                testContext = ctx;
                return const Text('Test Root');
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        final removalFuture = executeDeviceOwnerRemovalFlow(
          context: testContext!,
          controller: controller,
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // At 3 seconds: still loading
        await tester.pump(const Duration(seconds: 3));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Protection fully removed'), findsNothing);

        // At 7 seconds: still loading
        await tester.pump(const Duration(seconds: 4));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Protection fully removed'), findsNothing);

        // At 9.9 seconds: still loading
        await tester.pump(const Duration(milliseconds: 2800));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Protection fully removed'), findsNothing);

        // At 10.1 seconds: completed and dismissed
        await tester.pump(const Duration(milliseconds: 300));
        await removalFuture;
        await tester.pumpAndSettle();

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('Protection fully removed'), findsOneWidget);
      },
    );

    testWidgets(
      '3. Loading dismisses early once verification succeeds after the 10s minimum (before 20s max)',
      (tester) async {
        int pollCount = 0;
        messenger.setMockMethodCallHandler(methodChannel, (call) async {
          switch (call.method) {
            case 'removeDeviceOwner':
              return {
                'isDeviceOwner': false,
                'steps': [
                  {'id': 'clearOwner', 'ok': true, 'detail': 'ok'},
                ],
              };
            case 'verifyRemovalComplete':
              pollCount++;
              // Verified false until 13th poll (~13 seconds)
              final isVerified = pollCount >= 13;
              return {
                'verified': isVerified,
                'isDeviceOwner': !isVerified,
                'isAdminActive': false,
                'restrictionsResidue': <String>[],
                'screenCaptureDisabled': false,
              };
            default:
              return null;
          }
        });

        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final controller = AppController.test(
          PrivilegedChannel(methodChannel: methodChannel),
        );

        BuildContext? testContext;
        await tester.pumpWidget(
          buildTestApp(
            controller: controller,
            child: Builder(
              builder: (ctx) {
                testContext = ctx;
                return const Text('Test Root');
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        final removalFuture = executeDeviceOwnerRemovalFlow(
          context: testContext!,
          controller: controller,
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // At 10s: still unverified, still loading
        await tester.pump(const Duration(seconds: 10));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Protection fully removed'), findsNothing);

        // At 12s: still unverified, still loading
        await tester.pump(const Duration(seconds: 2));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Protection fully removed'), findsNothing);

        // At 13s: becomes verified! Dismisses early without waiting for 20s
        await tester.pump(const Duration(seconds: 1));
        await removalFuture;
        await tester.pumpAndSettle();

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('Protection fully removed'), findsOneWidget);
        expect(pollCount, inInclusiveRange(13, 14));
      },
    );

    testWidgets(
      '4. On 20s timeout without verification, dismisses and outcome dialog reports unverified checks honestly with re-check action',
      (tester) async {
        messenger.setMockMethodCallHandler(methodChannel, (call) async {
          switch (call.method) {
            case 'removeDeviceOwner':
              return {
                'isDeviceOwner': false,
                'steps': [
                  {'id': 'clearOwner', 'ok': true, 'detail': 'ok'},
                ],
              };
            case 'verifyRemovalComplete':
              return {
                'verified': false,
                'isDeviceOwner': false,
                'isAdminActive': true,
                'restrictionsResidue': ['no_install_apps'],
                'screenCaptureDisabled': true,
              };
            default:
              return null;
          }
        });

        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final controller = AppController.test(
          PrivilegedChannel(methodChannel: methodChannel),
        );

        BuildContext? testContext;
        await tester.pumpWidget(
          buildTestApp(
            controller: controller,
            child: Builder(
              builder: (ctx) {
                testContext = ctx;
                return const Text('Test Root');
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        final removalFuture = executeDeviceOwnerRemovalFlow(
          context: testContext!,
          controller: controller,
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Advance to 19 seconds: still loading
        await tester.pump(const Duration(seconds: 19));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Teardown incomplete — do not uninstall yet'), findsNothing);

        // Advance past 20 seconds: timeout triggered, loading dismissed
        await tester.pump(const Duration(seconds: 2));
        await removalFuture;
        await tester.pumpAndSettle();

        expect(find.byType(CircularProgressIndicator), findsNothing);

        // Warning outcome dialog is displayed (NEVER blanket success)
        expect(find.text('Protection fully removed'), findsNothing);
        expect(
          find.text('Teardown incomplete — do not uninstall yet'),
          findsOneWidget,
        );
        expect(
          find.text(
            'The teardown did not finish within the time limit, so its outcome is unverified — Device Owner may still be active. Do NOT uninstall yet, or the device may experience issues. The following checks are unverified:',
          ),
          findsOneWidget,
        );
        expect(find.text('• Device Admin is still active'), findsOneWidget);
        expect(
          find.text('• Restrictions still in force: no_install_apps'),
          findsOneWidget,
        );
        expect(find.text('• Screen capture is still blocked'), findsOneWidget);
        expect(find.text('Re-check status'), findsOneWidget);
      },
    );

    testWidgets(
      '5. Backgrounding and returning does not abort, relock, or double-invoke removal',
      (tester) async {
        int removeInvocations = 0;
        messenger.setMockMethodCallHandler(methodChannel, (call) async {
          switch (call.method) {
            case 'removeDeviceOwner':
              removeInvocations++;
              return {
                'isDeviceOwner': false,
                'steps': [
                  {'id': 'clearOwner', 'ok': true, 'detail': 'ok'},
                ],
              };
            case 'verifyRemovalComplete':
              return {
                'verified': true,
                'isDeviceOwner': false,
                'isAdminActive': false,
                'restrictionsResidue': <String>[],
                'screenCaptureDisabled': false,
              };
            default:
              return null;
          }
        });

        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final controller = AppController.test(
          PrivilegedChannel(methodChannel: methodChannel),
        );
        controller.startup = StartupState.unlocked;

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: AppShell(controller: controller),
          ),
        );
        await tester.pumpAndSettle();

        // Start removal
        final navigatorCtx = tester.element(find.byType(AppShell));
        final removalFuture = executeDeviceOwnerRemovalFlow(
          context: navigatorCtx,
          controller: controller,
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(controller.isRemovingDeviceOwner, isTrue);

        // Simulate app backgrounding
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump(const Duration(seconds: 3));

        // Simulate app returning to foreground
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();

        // Must NOT relock while teardown is in flight
        expect(controller.startup, StartupState.unlocked);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // Attempt a concurrent removal trigger (guard against double invocation)
        await executeDeviceOwnerRemovalFlow(
          context: navigatorCtx,
          controller: controller,
        );
        expect(removeInvocations, 1);

        // Advance to 10s completion
        await tester.pump(const Duration(seconds: 6));
        await removalFuture;
        await tester.pumpAndSettle();

        expect(find.text('Protection fully removed'), findsOneWidget);
        expect(removeInvocations, 1);
      },
    );

    testWidgets(
      '6. Danger-zone tile and forced-removal button are disabled while loading is shown',
      (tester) async {
        messenger.setMockMethodCallHandler(methodChannel, (call) async {
          switch (call.method) {
            case 'isDeviceOwner':
              return {
                'isDeviceOwner': true,
                'isAdminActive': true,
                'forcedRemovalDelayHours': 24,
              };
            case 'getPrivateDns':
              return {'mode': 'off', 'hostname': null};
            case 'removeDeviceOwner':
              return {
                'isDeviceOwner': false,
                'steps': [
                  {'id': 'clearOwner', 'ok': true, 'detail': 'ok'},
                ],
              };
            case 'verifyRemovalComplete':
              return {
                'verified': true,
                'isDeviceOwner': false,
                'isAdminActive': false,
                'restrictionsResidue': <String>[],
                'screenCaptureDisabled': false,
              };
            default:
              return null;
          }
        });

        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final controller = AppController.test(
          PrivilegedChannel(methodChannel: methodChannel),
        );

        await tester.pumpWidget(
          buildTestApp(
            controller: controller,
            child: ConfigTab(controller: controller),
          ),
        );
        await tester.pumpAndSettle();

        final tileFinder = find.widgetWithText(
          ListTile,
          'Remove Device Owner now',
        );
        expect(tileFinder, findsOneWidget);

        // Initially enabled
        ListTile tile = tester.widget<ListTile>(tileFinder);
        expect(tile.onTap, isNotNull);

        // Set removing state
        controller.isRemovingDeviceOwner = true;
        await tester.pump();

        // Now disabled while loading is shown
        tile = tester.widget<ListTile>(tileFinder);
        expect(
          tile.onTap,
          isNull,
          reason: 'Remove Device Owner tile must be disabled while isRemovingDeviceOwner is true',
        );

        // Reset
        controller.isRemovingDeviceOwner = false;
        await tester.pump();
        tile = tester.widget<ListTile>(tileFinder);
        expect(tile.onTap, isNotNull);
      },
    );

    testWidgets(
      '7. Re-check action in timeout outcome dialog launches verification and reports clean on success',
      (tester) async {
        bool recheckVerified = false;
        messenger.setMockMethodCallHandler(methodChannel, (call) async {
          switch (call.method) {
            case 'removeDeviceOwner':
              return {
                'isDeviceOwner': false,
                'steps': [
                  {'id': 'clearOwner', 'ok': true, 'detail': 'ok'},
                ],
              };
            case 'verifyRemovalComplete':
              return {
                'verified': recheckVerified,
                'isDeviceOwner': !recheckVerified,
                'isAdminActive': false,
                'restrictionsResidue': <String>[],
                'screenCaptureDisabled': false,
              };
            default:
              return null;
          }
        });

        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final controller = AppController.test(
          PrivilegedChannel(methodChannel: methodChannel),
        );

        BuildContext? testContext;
        await tester.pumpWidget(
          buildTestApp(
            controller: controller,
            child: Builder(
              builder: (ctx) {
                testContext = ctx;
                return const Text('Test Root');
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Initial run times out at 20s
        final removalFuture = executeDeviceOwnerRemovalFlow(
          context: testContext!,
          controller: controller,
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 21));
        await removalFuture;
        await tester.pumpAndSettle();

        expect(
          find.text('Teardown incomplete — do not uninstall yet'),
          findsOneWidget,
        );
        final recheckButton = find.text('Re-check status');
        expect(recheckButton, findsOneWidget);

        // Set re-check probe to now return verified true
        recheckVerified = true;

        // Tap "Re-check status"
        await tester.tap(recheckButton);
        await tester.pump();

        // Loading dialog shows again
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(
          find.text('Completing Device Owner removal…'),
          findsOneWidget,
        );

        // Advance 1 second: verification completes and dismisses
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();

        // Clean outcome dialog is now shown!
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('Protection fully removed'), findsOneWidget);
      },
    );
  });
}
