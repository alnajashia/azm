import 'package:azm/app_controller.dart';
import 'package:azm/data/privileged_channel.dart';
import 'package:azm/l10n/app_localizations.dart';
import 'package:azm/theme.dart';
import 'package:azm/ui/common.dart';
import 'package:azm/ui/config_tab.dart';
import 'package:azm/ui/recovery_ui.dart';
import 'package:azm/ui/scratch_card.dart';
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

  group('Batch B — B1: Settings to Status Tab', () {
    testWidgets('Tapping Setup & Device Owner tile switches to Status tab',
        (tester) async {
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        switch (call.method) {
          case 'isDeviceOwner':
            return {'isDeviceOwner': true, 'isAdminActive': true};
          case 'getPrivateDns':
            return {'mode': 'off', 'spec': ''};
          case 'listUncontrolledResidue':
            return {'packages': <String>[]};
          case 'listUserRestrictions':
            return {'restrictions': <String, dynamic>{}};
          case 'getShizukuState':
            return {'isInstalled': false, 'isAuthorized': false};
          case 'listInstalledApps':
            return {'apps': <Map<String, dynamic>>[]};
          default:
            return null;
        }
      });

      final controller = AppController.test(
        PrivilegedChannel(methodChannel: methodChannel),
      );

      await tester.pumpWidget(
        buildTestApp(child: ConfigTab(controller: controller)),
      );
      await tester.pumpAndSettle();

      // Find Setup & Device Owner tile (setupAndOwner string)
      final setupTile = find.widgetWithText(
        ListTile,
        'Setup & Device Owner',
      );
      expect(setupTile, findsOneWidget);

      await tester.tap(setupTile);
      await tester.pumpAndSettle();

      // Verified: tab switch requested to tabStatus (0)
      expect(controller.requestedTab, equals(AppController.tabStatus));
    });
  });

  group('Batch B — B2: Destructive Confirmation Card', () {
    testWidgets(
        'showDestructiveConfirmDialog renders centered card with red confirm button',
        (tester) async {
      bool? result;

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDestructiveConfirmDialog(
                  context,
                  title: 'Delete Rule',
                  message: 'This rule will be permanently deleted.',
                  confirmText: 'Delete',
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Verify card content
      expect(find.text('Delete Rule'), findsOneWidget);
      expect(
        find.text('This rule will be permanently deleted.'),
        findsOneWidget,
      );
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Verify destructive button styling (red)
      final deleteBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Delete'),
      );
      expect(
        deleteBtn.style?.backgroundColor?.resolve({}),
        equals(AzmColors.red),
      );

      // Tapping Cancel returns false
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);

      // Reopen and tap Delete
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });
  });

  group('Batch B — B3: Remove Device Owner Confirmation Card', () {
    testWidgets(
        'Remove Device Owner requires acknowledgment checkbox before confirm is enabled',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      int removeCalls = 0;
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        switch (call.method) {
          case 'isDeviceOwner':
            return {'isDeviceOwner': true, 'isAdminActive': true};
          case 'getPrivateDns':
            return {'mode': 'off', 'spec': ''};
          case 'listUncontrolledResidue':
            return {'packages': <String>[]};
          case 'listUserRestrictions':
            return {'restrictions': <String, dynamic>{}};
          case 'getShizukuState':
            return {'isInstalled': false, 'isAuthorized': false};
          case 'listInstalledApps':
            return {'apps': <Map<String, dynamic>>[]};
          case 'getSetting':
            return {'value': null};
          case 'removeDeviceOwner':
            removeCalls++;
            return {
              'isDeviceOwner': false,
              'steps': [
                {'id': 'flag', 'ok': true, 'detail': 'ok'}
              ],
            };
          default:
            return null;
        }
      });

      final controller = AppController.test(
        PrivilegedChannel(methodChannel: methodChannel),
      );

      await tester.pumpWidget(
        buildTestApp(child: ConfigTab(controller: controller)),
      );
      await tester.pumpAndSettle();

      // Scroll to Remove Device Owner tile
      final removeTile = find.text('Remove Device Owner now');
      await tester.scrollUntilVisible(
        removeTile,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(removeTile, findsOneWidget);

      await tester.tap(removeTile);
      await tester.pumpAndSettle();

      // Confirmation dialog is shown with exact l10n strings
      expect(
        find.text('Remove Device Owner and end protection?'),
        findsOneWidget,
      );
      expect(
        find.text(
          'All system restrictions, app suspensions, and website blocks will be lifted immediately.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Private DNS settings will be reset.'),
        findsOneWidget,
      );
      expect(
        find.text('Uninstalling the Azm app will be allowed.'),
        findsOneWidget,
      );

      // Confirm button is initially disabled
      final confirmBtnFinder = find.widgetWithText(
        FilledButton,
        'Remove protection',
      );
      expect(confirmBtnFinder, findsOneWidget);
      final confirmBtnBefore = tester.widget<FilledButton>(confirmBtnFinder);
      expect(confirmBtnBefore.onPressed, isNull);

      // Checkbox is present
      final checkboxFinder = find.byType(Checkbox);
      expect(checkboxFinder, findsOneWidget);

      // Tick the acknowledgment checkbox
      await tester.tap(checkboxFinder);
      await tester.pumpAndSettle();

      // Confirm button is now enabled
      final confirmBtnAfter = tester.widget<FilledButton>(confirmBtnFinder);
      expect(confirmBtnAfter.onPressed, isNotNull);

      // Tapping Cancel dismisses without calling removal
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(removeCalls, equals(0));
    });
  });

  group('Batch B — B4: Shared App Picker', () {
    final List<InstalledApp> testApps = [
      const InstalledApp(
        packageName: 'com.example.notes',
        label: 'Notes App',
        isSystem: false,
        isHidden: false,
        isSuspended: false,
        isUninstallBlocked: false,
      ),
      const InstalledApp(
        packageName: 'com.example.camera',
        label: 'Camera Pro',
        isSystem: false,
        isHidden: false,
        isSuspended: false,
        isUninstallBlocked: false,
      ),
      const InstalledApp(
        packageName: 'com.android.settings',
        label: 'System Settings',
        isSystem: true,
        isHidden: false,
        isSuspended: false,
        isUninstallBlocked: false,
      ),
      const InstalledApp(
        packageName: 'com.android.systemui',
        label: 'System UI',
        isSystem: true,
        isHidden: false,
        isSuspended: false,
        isUninstallBlocked: false,
      ),
    ];

    testWidgets('Search filters by label and package, system toggle shows/hides',
        (tester) async {
      Set<String>? picked;

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                picked = await showAppPicker(
                  context: context,
                  channel: PrivilegedChannel(methodChannel: methodChannel),
                  preloadedApps: testApps,
                  title: 'Select Apps',
                );
              },
              child: const Text('Open Picker'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Picker'));
      await tester.pumpAndSettle();

      // Picker is open
      expect(find.text('Select Apps'), findsOneWidget);

      // User apps visible, system apps hidden by default
      expect(find.text('Notes App'), findsOneWidget);
      expect(find.text('Camera Pro'), findsOneWidget);
      expect(find.text('System Settings'), findsNothing);
      expect(find.text('System UI'), findsNothing);

      // Type in search query: "camera"
      await tester.enterText(find.byType(TextField), 'camera');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Only Camera Pro is shown
      expect(find.text('Camera Pro'), findsOneWidget);
      expect(find.text('Notes App'), findsNothing);

      // Clear search
      await tester.enterText(find.byType(TextField), '');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Toggle system apps button (Icons.filter_alt_outlined)
      final filterToggle = find.byIcon(Icons.filter_alt_outlined);
      expect(filterToggle, findsOneWidget);
      await tester.tap(filterToggle);
      await tester.pumpAndSettle();

      // Now system apps are also visible
      expect(find.text('Notes App'), findsOneWidget);
      expect(find.text('Camera Pro'), findsOneWidget);
      expect(find.text('System Settings'), findsOneWidget);
      expect(find.text('System UI'), findsOneWidget);
      expect(find.byIcon(Icons.filter_alt), findsOneWidget);

      // Select Notes App and System Settings
      await tester.tap(find.text('Notes App'));
      await tester.tap(find.text('System Settings'));
      await tester.pumpAndSettle();

      // Tap Save
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(picked, equals({'com.example.notes', 'com.android.settings'}));
    });

    testWidgets('Single select returns immediately upon app tap',
        (tester) async {
      Set<String>? picked;

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                picked = await showAppPicker(
                  context: context,
                  channel: PrivilegedChannel(methodChannel: methodChannel),
                  preloadedApps: testApps,
                  title: 'Select Single App',
                  singleSelect: true,
                );
              },
              child: const Text('Open Single Picker'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Single Picker'));
      await tester.pumpAndSettle();

      // In single select mode, tapping an item immediately returns
      await tester.tap(find.text('Notes App'));
      await tester.pumpAndSettle();

      expect(picked, equals({'com.example.notes'}));
    });
  });

  group('Batch B — B5: Scratch Card and FLAG_SECURE', () {
    testWidgets('ScratchCard reveals via TalkBack button', (tester) async {
      bool revealed = false;

      await tester.pumpWidget(
        buildTestApp(
          child: Center(
            child: SizedBox(
              width: 320,
              height: 240,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return ScratchCard(
                    text: 'ABCD EFGH IJKL MNOP',
                    revealed: revealed,
                    onRevealed: () => setState(() => revealed = true),
                    child: const Text('ABCD EFGH IJKL MNOP'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      // Before reveal: text widget is NOT in the tree
      expect(find.text('ABCD EFGH IJKL MNOP'), findsNothing);
      expect(revealed, isFalse);

      // TalkBack alternative button is present
      final showCodeFinder = find.text('Show code');
      expect(showCodeFinder, findsOneWidget);

      await tester.tap(showCodeFinder);
      await tester.pumpAndSettle();

      // After reveal: text widget is rendered
      expect(revealed, isTrue);
      expect(find.text('ABCD EFGH IJKL MNOP'), findsOneWidget);
    });

    testWidgets('ScratchCard reveals via one quick swipe (threshold 20%)',
        (tester) async {
      bool revealed = false;

      await tester.pumpWidget(
        buildTestApp(
          child: Center(
            child: SizedBox(
              width: 320,
              height: 240,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return ScratchCard(
                    text: 'ABCD EFGH IJKL MNOP',
                    revealed: revealed,
                    onRevealed: () => setState(() => revealed = true),
                    child: const Text('ABCD EFGH IJKL MNOP'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      expect(revealed, isFalse);
      expect(find.text('ABCD EFGH IJKL MNOP'), findsNothing);

      // Batch F, item 2: one horizontal swipe across the middle must
      // reveal — the old 60% threshold forced scrubbing most of the card.
      final cardCenter = tester.getCenter(find.byType(ScratchCard));
      final gesture = await tester.startGesture(
        cardCenter - const Offset(120, 0),
      );
      for (double x = -120; x <= 120; x += 15) {
        await gesture.moveTo(cardCenter + Offset(x, 0));
        await tester.pump(const Duration(milliseconds: 2));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      // Verified: scratch threshold triggered reveal
      expect(revealed, isTrue);
      expect(find.text('ABCD EFGH IJKL MNOP'), findsOneWidget);
    });

    testWidgets('RecoveryWizard sets FLAG_SECURE on Step 2 and clears on dispose',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final List<bool> secureCalls = [];
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        switch (call.method) {
          case 'setWindowSecure':
            final enabled = (call.arguments as Map)['enabled'] as bool;
            secureCalls.add(enabled);
            return {'ok': true};
          case 'generateRecoveryCode':
            return {'code': 'ABCDEFGHIJKLMNOP'};
          case 'setRecoveryCode':
            return {'isSet': true};
          default:
            return null;
        }
      });

      final controller = AppController(
        channel: PrivilegedChannel(methodChannel: methodChannel),
      );

      await tester.pumpWidget(
        buildTestApp(
          child: RecoveryWizard(
            controller: controller,
            onDone: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 1: intro -> FLAG_SECURE is false
      expect(find.text('Step 1 of 4'), findsOneWidget);
      expect(secureCalls.last, isFalse);

      // Tap Next to advance to Step 2 (Write)
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();

      // Step 2: Write -> FLAG_SECURE is true!
      expect(find.text('Step 2 of 4'), findsOneWidget);
      expect(secureCalls.last, isTrue);

      // Code is not yet visible before reveal
      expect(find.text('ABCD EFGH IJKL MNOP'), findsNothing);

      // Checkbox is disabled before reveal
      final checkboxFinder = find.byType(CheckboxListTile);
      expect(checkboxFinder, findsOneWidget);
      final checkboxTile = tester.widget<CheckboxListTile>(checkboxFinder);
      expect(checkboxTile.onChanged, isNull);

      // Tap Show code
      await tester.tap(find.text('Show code'));
      await tester.pumpAndSettle();

      // Code is now visible
      expect(find.text('ABCD EFGH IJKL MNOP'), findsOneWidget);

      // Checkbox is now enabled
      final checkboxTileAfter =
          tester.widget<CheckboxListTile>(checkboxFinder);
      expect(checkboxTileAfter.onChanged, isNotNull);

      // Check the paper box
      await tester.tap(checkboxFinder);
      await tester.pumpAndSettle();

      // Advance to Step 3 (Confirm)
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pumpAndSettle();

      // Step 3: Confirm -> FLAG_SECURE is false!
      expect(find.text('Step 3 of 4'), findsOneWidget);
      expect(secureCalls.last, isFalse);

      // Dispose wizard -> FLAG_SECURE is confirmed false
      await tester.pumpWidget(const SizedBox());
      expect(secureCalls.last, isFalse);
    });
  });
}
