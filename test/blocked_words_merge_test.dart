/// Batch J, item 10 redesign — one blocked-word entry is a word +
/// its targets (apps and/or groups) + its modes, behind the same two
/// views (words-per-app, apps-per-word), with the standing gates
/// (removing coverage or activating blocking in a new place goes
/// through the paper-code session; adding words or modes to an
/// already-covered app is free). Group targets expand to their
/// member apps at enforcement time.
library;

import 'package:azm/app_controller.dart';
import 'package:azm/data/privileged_channel.dart';
import 'package:azm/l10n/app_localizations.dart';
import 'package:azm/theme.dart';
import 'package:azm/ui/config_screens.dart';
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
  late List<Map<String, dynamic>> fakeAssignments;
  late List<Map<String, dynamic>> fakeApps;
  late List<Map<String, dynamic>> fakeGroups;
  final createdControllers = <AppController>[];

  Map<String, dynamic> app(String packageName, String label) => {
        'packageName': packageName,
        'label': label,
        'isSystem': false,
        'isHidden': false,
        'isSuspended': false,
        'isUninstallBlocked': false,
      };

  Map<String, dynamic> assignment(
    String w,
    List<String> pkgs,
    List<String> modes, {
    List<String> groups = const [],
  }) => {
    'word': w,
    'packageNames': pkgs,
    'groupIds': groups,
    'modes': modes,
  };

  Map<String, dynamic> makeGroup(String id, String name, List<String> pkgs) => {
    'id': id,
    'name': name,
    'packages': pkgs,
    'dailyMinutes': 0,
    'reopenSeconds': 0,
    'dailyWindows': <Map<String, int>>[],
  };

  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher
        .implicitView!;
    view.physicalSize = const Size(800, 4000);
    view.devicePixelRatio = 1.0;
    calls = [];
    // bad -> [game] both modes; secret -> [social] passive;
    // bet -> group g1 (Social: social + notes) active.
    fakeAssignments = [
      assignment('bad', ['com.example.game'], ['active', 'passive']),
      assignment('secret', ['com.example.social'], ['passive']),
      assignment('bet', [], ['active'], groups: ['g1']),
    ];
    fakeApps = [
      app('com.example.game', 'Example Game'),
      app('com.example.social', 'Social App'),
      app('com.example.notes', 'Notes'),
    ];
    fakeGroups = [
      makeGroup('g1', 'Social', ['com.example.social', 'com.example.notes']),
    ];

    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getBlockedWords':
          return {
            'words': ['bad', 'bet'],
            'targetPackages': ['com.example.game'],
            'passiveWords': {
              'com.example.game': ['bad'],
              'com.example.social': ['secret'],
            },
            'assignments': fakeAssignments,
          };
        case 'setWordAssignments':
          fakeAssignments = (call.arguments['assignments'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          return {
            'words': ['bad', 'bet'],
            'targetPackages': ['com.example.game'],
            'passiveWords': {
              'com.example.game': ['bad'],
              'com.example.social': ['secret'],
            },
            'assignments': fakeAssignments,
          };
        case 'listInstalledApps':
          return fakeApps;
        case 'getGroups':
          return {'groups': fakeGroups};
        case 'getSetting':
          return {'value': null};
        case 'isRecoveryCodeSet':
          return {'isSet': true};
        case 'verifyRecoveryCode':
          return {'matches': true};
      }
      throw MissingPluginException('Unhandled ${call.method} in merge test');
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
    final c = AppController.test(
      PrivilegedChannel(methodChannel: methodChannel),
    );
    createdControllers.add(c);
    return c;
  }

  Future<void> enterCodeAndConfirm(WidgetTester tester) async {
    await tester.pumpAndSettle();
    expect(find.text('Enter recovery code'), findsOneWidget);
    final codeField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(codeField.first, 'AAAAAAAAAAAAAAAA');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();
  }

  List<AppGroupModel> testGroups() => fakeGroups
      .map((e) => AppGroupModel.fromMap(e as Map<dynamic, dynamic>))
      .toList();

  // ------------------------------------------------------------ model

  group('WordAssignment model', () {
    test('round-trips through toMap/fromMap; bad input is dropped', () {
      const a = WordAssignment(
        word: 'bad',
        packageNames: ['com.example.game'],
        groupIds: ['g1'],
        modes: {WordBlockMode.active},
      );
      expect(WordAssignment.fromMap(a.toMap()), a);
      expect(
        WordAssignment.fromMap({
          'word': 'x',
          'packageNames': ['com.y'],
          'groupIds': <String>[],
          'modes': ['nope'],
        }),
        isNull,
      );
      expect(
        WordAssignment.fromMap({
          'word': '  ',
          'packageNames': ['com.y'],
          'groupIds': <String>[],
          'modes': ['active'],
        }),
        isNull,
      );
      expect(
        WordAssignment.fromMap({
          'word': 'x',
          'packageNames': <String>[],
          'groupIds': <String>[],
          'modes': ['active'],
        }),
        isNull,
      );
    });

    test('old Batch H shape still parses (single app + mode)', () {
      final a = WordAssignment.fromMap({
        'word': 'bad',
        'packageName': 'com.example.game',
        'mode': 'active',
      });
      expect(a, isNotNull);
      expect(a!.packageNames, ['com.example.game']);
      expect(a.modes, {WordBlockMode.active});
    });

    test('BlockedWordsState parses assignments; forApp/forWord slice it',
        () {
      final s = BlockedWordsState.fromMap({
        'words': ['bad'],
        'targetPackages': ['com.example.game'],
        'passiveWords': {'com.example.social': ['secret']},
        'assignments': [
          assignment('bad', ['com.example.game'], ['active']),
          assignment('secret', ['com.example.social'], ['passive']),
          assignment('bet', [], ['active'], groups: ['g1']),
        ],
      });
      expect(s.assignments.length, 3);
      // Direct coverage only, without groups.
      expect(s.forApp('com.example.game').length, 1);
      expect(s.forApp('com.example.social').length, 1);
      expect(s.forAppDirect('com.example.social').length, 1);
      expect(s.forAppDirect('com.example.notes'), isEmpty);
      // With groups: bet covers social + notes through g1.
      final groups = testGroups();
      expect(s.forApp('com.example.notes', groups: groups).length, 1);
      expect(s.forApp('com.example.social', groups: groups).length, 2);
      expect(s.forWord('secret').length, 1);
      expect(s.forWord('missing'), isEmpty);
      // Group expansion + group names.
      final bet = s.forWord('bet').first;
      expect(
        bet.expandedPackages(groups),
        {'com.example.social', 'com.example.notes'},
      );
      expect(bet.coveringGroupNames('com.example.notes', groups), ['Social']);
      expect(bet.coveringGroupNames('com.example.game', groups), isEmpty);
    });
  });

  group('gate helpers', () {
    final badGame = WordAssignment(
      word: 'bad',
      packageNames: ['com.example.game'],
      modes: {WordBlockMode.active, WordBlockMode.passive},
    );
    final badGameActive = WordAssignment(
      word: 'bad',
      packageNames: ['com.example.game'],
      modes: {WordBlockMode.active},
    );
    final secretSocial = WordAssignment(
      word: 'secret',
      packageNames: ['com.example.social'],
      modes: {WordBlockMode.passive},
    );
    final betGroup = WordAssignment(
      word: 'bet',
      groupIds: ['g1'],
      modes: {WordBlockMode.active},
    );

    test('appWordCoverage expands groups; appCoverageChangeLoosens', () {
      final groups = testGroups();
      final all = [badGame, secretSocial, betGroup];
      final game = appWordCoverage(all, 'com.example.game', groups);
      expect(game, {
        'bad': {WordBlockMode.active, WordBlockMode.passive},
      });
      final social = appWordCoverage(all, 'com.example.social', groups);
      expect(social, {
        'secret': {WordBlockMode.passive},
        'bet': {WordBlockMode.active},
      });
      // Removing a word or dropping a mode loosens.
      expect(
        appCoverageChangeLoosens(social, {
          'bet': {WordBlockMode.active},
        }),
        isTrue,
      );
      expect(
        appCoverageChangeLoosens(social, {
          'secret': {WordBlockMode.passive},
          'bet': {WordBlockMode.active},
        }),
        isFalse,
      );
      // New coverage (empty -> some) activates: gated.
      expect(
        appCoverageChangeLoosens({}, {'bad': {WordBlockMode.active}}),
        isTrue,
      );
      // Adding words/modes to an already-covered app is free.
      expect(
        appCoverageChangeLoosens({'bad': {WordBlockMode.active}}, game),
        isFalse,
      );
      // Removing group-derived coverage loosens too.
      expect(
        appCoverageChangeLoosens(social, {
          'secret': {WordBlockMode.passive},
        }),
        isTrue,
      );
      // No change is free.
      expect(appCoverageChangeLoosens(social, social), isFalse);
    });

    test('wordAssignmentsChangeLoosens: any change is gated', () {
      expect(
        wordAssignmentsChangeLoosens([badGameActive], [badGameActive]),
        isFalse,
      );
      expect(
        wordAssignmentsChangeLoosens([badGameActive], [badGame]),
        isTrue,
      );
      expect(
        wordAssignmentsChangeLoosens([badGame], [badGameActive]),
        isTrue,
      );
      expect(wordAssignmentsChangeLoosens([badGame], []), isTrue);
      expect(
        wordAssignmentsChangeLoosens(
          [badGameActive],
          [
            WordAssignment(
              word: 'bad',
              packageNames: ['com.example.game', 'com.example.social'],
              modes: {WordBlockMode.active},
            ),
          ],
        ),
        isTrue,
      );
    });
  });

  // ------------------------------------------------------------ widget

  group('merged screen', () {
    testWidgets('adding a mode to an already-covered app saves '
        'directly, no gate', (tester) async {
      // Start with (bad, game, active) only.
      fakeAssignments = [
        assignment('bad', ['com.example.game'], ['active']),
      ];
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(child: BlockedWordsScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Example Game'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'On screen'));
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Save'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Enter recovery code'), findsNothing);
      expect(
        calls.any((c) => c.method == 'setWordAssignments'),
        isTrue,
      );
      expect(
        find.text('1 word(s) · Typed + On screen'),
        findsOneWidget,
      );
      controller.session.end();
    });

    testWidgets('word dialog: removing the only app goes through '
        'the gate', (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(child: BlockedWordsScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('By word'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('secret'));
      await tester.pumpAndSettle();
      expect(find.text('Targets — secret'), findsOneWidget);
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
                (a) => a['word'] == 'secret',
              ),
        ),
        isTrue,
      );
      expect(find.text('secret'), findsNothing);
      controller.session.end();
    });

    testWidgets('word dialog: select-all apps adds every app, '
        'through the gate', (tester) async {
      // bad -> [game] both modes.
      fakeAssignments = [
        assignment('bad', ['com.example.game'], ['active', 'passive']),
      ];
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(child: BlockedWordsScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('By word'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('bad'));
      await tester.pumpAndSettle();
      expect(find.text('Targets — bad'), findsOneWidget);

      // Open the app picker and select all three apps.
      // TextButton.icon builds _TextButtonWithIcon, not TextButton.
      await tester.tap(find.text('Add app'));
      await tester.pumpAndSettle();
      expect(find.text('Add app'), findsNWidgets(2));
      await tester.tap(find.text('Select all'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
      await tester.pumpAndSettle();
      expect(find.text('Social App'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);

      // Saving adds two newly covered apps: gated.
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Save'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Enter recovery code'), findsOneWidget);
      await enterCodeAndConfirm(tester);
      final saved = calls
          .lastWhere((c) => c.method == 'setWordAssignments')
          .arguments['assignments'] as List;
      final bad = saved.firstWhere((a) => a['word'] == 'bad') as Map;
      expect(
        (bad['packageNames'] as List).toSet(),
        {
          'com.example.game',
          'com.example.social',
          'com.example.notes',
        },
      );
      expect(find.text('3 target app(s)'), findsOneWidget);
      controller.session.end();
    });

    testWidgets('word dialog: select-all groups adds the group, '
        'through the gate', (tester) async {
      // secret -> [social] passive only.
      fakeAssignments = [
        assignment('secret', ['com.example.social'], ['passive']),
      ];
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(child: BlockedWordsScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('By word'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('secret'));
      await tester.pumpAndSettle();
      expect(find.text('Targets — secret'), findsOneWidget);

      // TextButton.icon builds _TextButtonWithIcon, not TextButton.
      await tester.tap(find.text('Add group'));
      await tester.pumpAndSettle();
      // The word dialog's Groups section header plus the picker title.
      expect(find.text('Groups'), findsNWidgets(2));
      await tester.tap(find.text('Select all'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
      await tester.pumpAndSettle();
      expect(find.text('Social'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Save'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Enter recovery code'), findsOneWidget);
      await enterCodeAndConfirm(tester);
      final saved = calls
          .lastWhere((c) => c.method == 'setWordAssignments')
          .arguments['assignments'] as List;
      final secret = saved.firstWhere((a) => a['word'] == 'secret') as Map;
      expect(secret['groupIds'], ['g1']);
      expect(find.text('1 target app(s) · 1 group(s)'), findsOneWidget);
      controller.session.end();
    });

    testWidgets('app dialog: a group-only word is read-only and '
        'jumps to the word editor', (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(child: BlockedWordsScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      // Social App is covered by bet through group g1 (and by
      // secret directly): 2 words, both modes.
      expect(find.text('2 word(s) · Typed + On screen'), findsOneWidget);
      await tester.tap(find.text('Social App'));
      await tester.pumpAndSettle();
      expect(find.text('via Social'), findsOneWidget);
      await tester.tap(find.text('bet'));
      await tester.pumpAndSettle();
      expect(find.text('Targets — bet'), findsOneWidget);
      controller.session.end();
    });
  });
}
