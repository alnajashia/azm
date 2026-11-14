/// Dechainer-parity tests for the 8 screenshots the user sent
/// 2026-11-13 15:18 (item 3 passive blocked-words + item 7 groups):
///
///  Item 3 — the Forbidden words screen works exactly like Dechainer's,
///  after the Batch H merge (one assignment table, two views): a word
///  list can be created for ANY installed app (not only the active
///  targets — Dechainer's Passive section works with "No apps
///  selected" in Active); each word carries its Typed / On-screen
///  mode chips; the per-app edit dialog is titled with the app name
///  alone.
///  Item 7 — the group-edit menu has a time-windows editor (Dechainer's
///  EditGroupDialog has "Group time windows"); the group subtitle
///  shows the window count; the per-app sheet has a "Group" entry
///  (Dechainer's app sheet lists Group first) that assigns the app
///  to a group, with the same gates as editing group members.
library;

import 'package:azm/app_controller.dart';
import 'package:azm/data/privileged_channel.dart';
import 'package:azm/l10n/app_localizations.dart';
import 'package:azm/theme.dart';
import 'package:azm/ui/apps_tab.dart';
import 'package:azm/ui/config_screens.dart';
import 'package:azm/ui/config_tab.dart';
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
  late List<String> fakeWords;
  late List<String> fakeTargets;
  late Map<String, List<String>> fakePassive;
  late List<Map<String, dynamic>> fakeApps;
  late List<Map<String, dynamic>> fakeGroups;
  late String? fakeBlockedGroupsJson;
  late String? fakeDetectorError;
  final createdControllers = <AppController>[];

  Map<String, dynamic> app(String packageName, String label) => {
        'packageName': packageName,
        'label': label,
        'isSystem': false,
        'isHidden': false,
        'isSuspended': false,
        'isUninstallBlocked': false,
      };

  Map<String, dynamic> fakeGroup(
    String id,
    String name,
    List<String> packages, {
    int dailyMinutes = 0,
    List<Map<String, int>> dailyWindows = const [],
  }) => {
        'id': id,
        'name': name,
        'packages': packages,
        'dailyMinutes': dailyMinutes,
        'reopenSeconds': 0,
        'dailyWindows': dailyWindows,
      };

  /// Batch J, item 10: the payload carries the merged assignment
  /// table — one row per word (apps and/or groups + modes) — derived
  /// from the fake legacy state exactly the way the native migration
  /// does (active = words x targets; passive = per-app lists).
  Map<String, dynamic> blockedWordsPayload() {
    final byWord = <String, Map<String, dynamic>>{};
    void add(String w, List<String> pkgs, String mode) {
      if (pkgs.isEmpty) return;
      final row = byWord.putIfAbsent(w, () => {
            'word': w,
            'packageNames': <String>[],
            'groupIds': <String>[],
            'modes': <String>[],
          });
      for (final p in pkgs) {
        if (!(row['packageNames'] as List<String>).contains(p)) {
          (row['packageNames'] as List<String>).add(p);
        }
      }
      if (!(row['modes'] as List<String>).contains(mode)) {
        (row['modes'] as List<String>).add(mode);
      }
    }
    for (final w in fakeWords) {
      add(w, fakeTargets, 'active');
    }
    fakePassive.forEach((pkg, words) {
      for (final w in words) {
        add(w, [pkg], 'passive');
      }
    });
    return {
      'words': fakeWords,
      'targetPackages': fakeTargets,
      'passiveWords': fakePassive,
      'assignments': byWord.values.toList(),
    };
  }

  setUp(() {
    // Tall viewport (the Batch F pattern): the Blocked Words screen
    // and the app sheet are long lists — without it, the passive
    // section and the Group tile sit below the fold and taps miss.
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher
        .implicitView!;
    view.physicalSize = const Size(800, 4000);
    view.devicePixelRatio = 1.0;
    calls = [];
    fakeWords = ['bad', 'worse'];
    fakeTargets = [];
    fakePassive = {
      'com.example.game': ['pussy'],
    };
    fakeApps = [
      app('com.example.game', 'Example Game'),
      app('com.example.social', 'Social App'),
      app('com.example.notes', 'Notes'),
    ];
    fakeGroups = [
      fakeGroup('g1', 'Social', ['com.example.social'], dailyMinutes: 60),
      fakeGroup('g2', 'Work', ['com.example.notes']),
    ];
    fakeBlockedGroupsJson = null;
    fakeDetectorError = null;

    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getBlockedWords':
          return blockedWordsPayload();
        case 'setBlockedWords':
          fakeWords = (call.arguments['words'] as List).cast<String>();
          fakeTargets =
              (call.arguments['targetPackages'] as List).cast<String>();
          return blockedWordsPayload();
        case 'setPassiveWords':
          final pkg = call.arguments['packageName'] as String;
          final words = (call.arguments['words'] as List).cast<String>();
          if (words.isEmpty) {
            fakePassive.remove(pkg);
          } else {
            fakePassive[pkg] = words;
          }
          return blockedWordsPayload();
        case 'setWordAssignments':
          final list = (call.arguments['assignments'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          // Expand group targets through the fake groups, the way
          // the native store does, then derive the fake legacy state.
          Set<String> expanded(Map<String, dynamic> a) {
            final out = <String>{
              ...(a['packageNames'] as List).cast<String>(),
            };
            for (final id
                in (a['groupIds'] as List? ?? const []).cast<String>()) {
              final g = fakeGroups.firstWhere(
                (g) => g['id'] == id,
                orElse: () =>
                    <String, dynamic>{'packages': <String>[]},
              );
              out.addAll((g['packages'] as List).cast<String>());
            }
            return out;
          }
          fakeWords = list
              .where((a) => (a['modes'] as List).contains('active'))
              .map((a) => a['word'] as String)
              .toSet()
              .toList();
          fakeTargets = list
              .where((a) => (a['modes'] as List).contains('active'))
              .expand((a) => expanded(a))
              .toSet()
              .toList();
          fakePassive = {};
          for (final a in list.where(
            (a) => (a['modes'] as List).contains('passive'),
          )) {
            for (final pkg in expanded(a)) {
              (fakePassive[pkg] ??= []).add(a['word'] as String);
            }
          }
          return blockedWordsPayload();
        case 'listInstalledApps':
          return fakeApps;
        case 'getGroups':
          return {'groups': fakeGroups};
        case 'setGroups':
          fakeGroups = (call.arguments['groups'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          return {'groups': fakeGroups};
        case 'getSetting':
          final store = call.arguments['store'] as String?;
          final key = call.arguments['key'] as String?;
          if (store == 'browser_prefs' && key == 'blocked_groups_json') {
            return {'value': fakeBlockedGroupsJson};
          }
          return {'value': null};
        case 'getTimeLimit':
          return {'dailyMinutes': 0};
        case 'getTimeWindows':
          return {'dailyWindows': <Map<String, int>>[]};
        case 'setAppSuspended':
          return {
            'results': (call.arguments['packageNames'] as List)
                .map(
                  (p) => {
                    'packageName': p,
                    'isSuspended': call.arguments['suspended'],
                  },
                )
                .toList(),
          };
        case 'isRecoveryCodeSet':
          return {'isSet': true};
        case 'verifyRecoveryCode':
          return {'matches': true};
        case 'getVisualBlockingConfig':
          return {
            'enabled': false,
            'targetPackages': <String>[],
            'categories': ['hentai', 'porn', 'sexy'],
            'threshold': 0.5,
            'suspendEnabled': false,
            'suspendBlockCount': 5,
            'suspendWindowMinutes': 15,
            'suspendDurationMinutes': 30,
          };
        case 'getVisualDetectorError':
          return {'error': fakeDetectorError};
      }
      throw MissingPluginException('Unhandled ${call.method} in parity test');
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher
        .implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
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
    // The code field lives inside the gate dialog — the screen behind
    // it also has a (read-only) TextField, so scope the finder to the
    // dialog, or the code would land in the wrong field.
    final codeField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(codeField.first, 'AAAAAAAAAAAAAAAA');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();
  }

  List<InstalledApp> installedApps() => fakeApps
      .map((e) => InstalledApp.fromMap(e as Map<dynamic, dynamic>))
      .toList();

  // ---------------------------------------------------------- Item 3

  group('Item 3 — merged blocked-words like Dechainer, one table', () {
    testWidgets('by-app view lists the app with its words and modes; '
        'the app dialog is titled with the app name', (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(child: BlockedWordsScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      // By-app is the default view: one row, word count + mode.
      expect(find.text('Example Game'), findsOneWidget);
      expect(find.text('1 word(s) · On screen'), findsOneWidget);

      // The per-app dialog is titled with the app name alone and
      // shows the word with its Typed / On-screen mode chips.
      await tester.tap(find.text('Example Game'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Example Game'),
        ),
        findsOneWidget,
      );
      expect(find.text('pussy'), findsOneWidget);
      expect(find.text('Typed'), findsOneWidget);
      expect(find.text('On screen'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      // By-word view: the word with its app count.
      await tester.tap(find.text('By word'));
      await tester.pumpAndSettle();
      expect(find.text('pussy'), findsOneWidget);
      expect(find.text('1 target app(s)'), findsOneWidget);
    });

    testWidgets('a word list can be created for an app that is NOT '
        'an active target', (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(child: BlockedWordsScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      // Active has NO targets at all — the old code refused here.
      await tester.tap(find.text('Add app'));
      await tester.pumpAndSettle();

      // The picker offers every installed app, not only targets.
      expect(find.text('Social App'), findsOneWidget);
      await tester.tap(find.text('Social App'));
      await tester.pumpAndSettle();

      // The per-app dialog is titled with the app name alone.
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Social App'),
        ),
        findsOneWidget,
      );
      final wordsField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(wordsField.first, 'secret');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byIcon(Icons.add_outlined),
        ),
      );
      await tester.pump();
      expect(find.text('secret'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Save'),
        ),
      );
      await tester.pumpAndSettle();

      // Creating a list activates blocking: the code gate appears.
      await enterCodeAndConfirm(tester);
      expect(
        calls.any(
          (c) =>
              c.method == 'setWordAssignments' &&
              (c.arguments['assignments'] as List).any(
                (a) =>
                    a['word'] == 'secret' &&
                    (a['packageNames'] as List)
                        .contains('com.example.social'),
              ),
        ),
        isTrue,
      );
      expect(find.text('Social App'), findsOneWidget);
      expect(find.text('1 word(s) · Typed + On screen'), findsOneWidget);
      controller.session.end();
    });

    testWidgets('deleting a word goes through the gate and '
        'removes the assignment', (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(child: BlockedWordsScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Example Game'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byIcon(Icons.delete_outlined),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Save'),
        ),
      );
      await tester.pumpAndSettle();

      // Removing blocking is a loosening: the code gate appears and
      // nothing is cleared yet.
      expect(find.text('Enter recovery code'), findsOneWidget);
      expect(
        calls.any((c) => c.method == 'setWordAssignments'),
        isFalse,
      );

      await enterCodeAndConfirm(tester);
      expect(
        calls.any(
          (c) =>
              c.method == 'setWordAssignments' &&
              !(c.arguments['assignments'] as List).any(
                (a) => (a['packageNames'] as List)
                    .contains('com.example.game'),
              ),
        ),
        isTrue,
      );
      expect(find.text('Example Game'), findsNothing);
      expect(find.text('No apps have word lists yet.'), findsOneWidget);
      controller.session.end();
    });
  });

  // ---------------------------------------------------------- Item 7

  group('Item 7 — group time windows and the app-sheet Group entry', () {
    testWidgets('the group menu has Edit time windows and saving '
        'persists them', (tester) async {
      fakeGroups = [
        fakeGroup('g1', 'Social', ['com.example.social'], dailyMinutes: 60),
      ];
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(
          child: GroupsScreen(
            controller: controller,
            apps: installedApps(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byWidgetPredicate((w) => w is PopupMenuButton<String>),
      );
      await tester.pumpAndSettle();
      expect(find.text('Edit time windows'), findsOneWidget);

      await tester.tap(find.text('Edit time windows'));
      await tester.pumpAndSettle();
      expect(find.byType(TimeWindowsEditor), findsOneWidget);

      // Add one window (07:00–21:00, the editor's defaults).
      await tester.tap(find.text('Add window'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('07:00 – 21:00'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // Adding windows where none existed activates blocking: gated.
      await enterCodeAndConfirm(tester);
      expect(
        calls.any((c) => c.method == 'setGroups'),
        isTrue,
      );
      final saved = fakeGroups.first;
      expect((saved['dailyWindows'] as List).length, 1);
      controller.session.end();
    });

    testWidgets('the group subtitle shows the window count',
        (tester) async {
      fakeGroups = [
        fakeGroup(
          'g1',
          'Social',
          ['com.example.social'],
          dailyMinutes: 60,
          dailyWindows: [
            {'s': 540, 'e': 1020},
          ],
        ),
      ];
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(
          child: GroupsScreen(
            controller: controller,
            apps: installedApps(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('1 window(s)'), findsOneWidget);
    });

    testWidgets('the app sheet has a Group entry that moves the app '
        'to another group', (tester) async {
      final controller = makeController();
      final social = installedApps()[1];
      await tester.pumpWidget(
        buildTestApp(
          child: AppManagementSheet(controller: controller, app: social),
        ),
      );
      await tester.pumpAndSettle();

      // The sheet shows the app's current group.
      expect(find.text('Group'), findsOneWidget);
      expect(find.text('Social'), findsOneWidget);

      await tester.tap(find.text('Group'));
      await tester.pumpAndSettle();
      expect(find.text('Select group'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);

      // Move Social App from Social (restricted: 60 min) to Work
      // (unrestricted): removing from a restricted group loosens.
      await tester.tap(find.text('Work'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();

      await enterCodeAndConfirm(tester);
      expect(
        calls.any((c) => c.method == 'setGroups'),
        isTrue,
      );
      final work = fakeGroups.firstWhere((g) => g['id'] == 'g2');
      final socialGroup = fakeGroups.firstWhere((g) => g['id'] == 'g1');
      expect(
        (work['packages'] as List).contains('com.example.social'),
        isTrue,
      );
      expect(
        (socialGroup['packages'] as List).contains('com.example.social'),
        isFalse,
      );
      controller.session.end();
    });
  });

  // --------------------------------------------- Content check (item 7)

  group('Content check — a detector failure is visible, never silent', () {
    testWidgets('the Visual Blocking screen warns when the detector '
        'failed to load', (tester) async {
      fakeDetectorError = 'models/nsfw_model.tflite not found';
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(
          child: VisualBlockingScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Content inspection is not working'), findsOneWidget);
      expect(
        find.textContaining('models/nsfw_model.tflite not found'),
        findsOneWidget,
      );
      controller.session.end();
    });

    testWidgets('no banner when the detector loaded fine', (tester) async {
      fakeDetectorError = null;
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(
          child: VisualBlockingScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Content inspection is not working'), findsNothing);
      expect(find.text('Content inspection'), findsWidgets);
      controller.session.end();
    });
  });

  // ----------------------- Deadlock item 6 — honest outcome dialog

  group('Removal outcome dialog never claims the owner is gone', () {
    testWidgets('timeout body says the outcome is unverified when the '
        'owner is still active', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showRemovalOutcomeDialog(
                context,
                result: const DeviceOwnerRemovalResult(
                  isDeviceOwner: true,
                  steps: [
                    RemovalStepResult(
                      id: 'clearOwner',
                      ok: false,
                      detail: 'Still Device Owner after clearDeviceOwnerApp',
                    ),
                  ],
                ),
                verification: const RemovalVerificationResult(
                  verified: false,
                  isDeviceOwner: true,
                  isAdminActive: true,
                  restrictionsResidue: [],
                  screenCaptureDisabled: false,
                ),
                isTimeout: true,
              ),
              child: const Text('Show'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      expect(
        find.text('Teardown incomplete — do not uninstall yet'),
        findsOneWidget,
      );
      // The old body claimed "Device Owner was cleared" even when
      // verification said the owner was still active.
      expect(find.textContaining('was cleared'), findsNothing);
      expect(find.textContaining('may still be active'), findsOneWidget);
      expect(find.textContaining('Device Owner is still active'), findsOneWidget);
      expect(find.textContaining('Still Device Owner'), findsOneWidget);
    });

    testWidgets('partial body does not claim the owner is gone either',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showRemovalOutcomeDialog(
                context,
                result: const DeviceOwnerRemovalResult(
                  isDeviceOwner: true,
                  steps: [
                    RemovalStepResult(
                      id: 'clearOwner',
                      ok: false,
                      detail: 'Still Device Owner after clearDeviceOwnerApp',
                    ),
                  ],
                ),
                verification: const RemovalVerificationResult(
                  verified: false,
                  isDeviceOwner: true,
                  isAdminActive: false,
                  restrictionsResidue: [],
                  screenCaptureDisabled: false,
                ),
              ),
              child: const Text('Show'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      expect(find.textContaining('was removed'), findsNothing);
      expect(find.textContaining('may still be active'), findsOneWidget);
    });
  });
}
