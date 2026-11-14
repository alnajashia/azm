/// Batch H, item 12 — seal rules watch MANY apps and a group: the
/// rule summary names the group and the app count; narrowing the
/// targets goes through the paper-code session; widening saves
/// directly.
library;

import 'package:azm/app_controller.dart';
import 'package:azm/data/privileged_channel.dart';
import 'package:azm/domain/seal_rules.dart';
import 'package:azm/l10n/app_localizations.dart';
import 'package:azm/theme.dart';
import 'package:azm/ui/seal_rules_screen.dart';
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
  late List<Map<String, dynamic>> fakeRules;
  late List<Map<String, dynamic>> fakeGroups;
  late List<Map<String, dynamic>> fakeApps;
  final createdControllers = <AppController>[];

  Map<String, dynamic> app(String packageName, String label) => {
        'packageName': packageName,
        'label': label,
        'isSystem': false,
        'isHidden': false,
        'isSuspended': false,
        'isUninstallBlocked': false,
      };

  Map<String, dynamic> rule(
    String id,
    String trigger,
    List<String> packageNames, {
    String? groupId,
    int? durationMinutes,
  }) => {
        'id': id,
        'trigger': trigger,
        'packageNames': packageNames,
        'groupId': groupId,
        'durationMinutes': durationMinutes,
        'enabled': true,
      };

  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher
        .implicitView!;
    view.physicalSize = const Size(800, 4000);
    view.devicePixelRatio = 1.0;
    calls = [];
    fakeRules = [
      rule(
        'r1',
        'APP_SUSPENDED',
        ['com.example.game', 'com.example.social'],
        groupId: 'g1',
      ),
      rule(
        'r2',
        'BANNED_WORD',
        [],
        groupId: 'g1',
        durationMinutes: 360,
      ),
    ];
    fakeGroups = [
      {
        'id': 'g1',
        'name': 'Social',
        'packages': ['com.example.social', 'com.example.notes'],
        'dailyMinutes': 0,
        'reopenSeconds': 0,
        'dailyWindows': <Map<String, int>>[],
      },
    ];
    fakeApps = [
      app('com.example.game', 'Example Game'),
      app('com.example.social', 'Social App'),
      app('com.example.notes', 'Notes App'),
    ];

    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getSealRules':
          return {
            'rules': fakeRules,
            'activeSeals': <Map<String, dynamic>>[],
            'isDeviceOwner': true,
          };
        case 'setSealRules':
          fakeRules = (call.arguments['rules'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          return {
            'rules': fakeRules,
            'activeSeals': <Map<String, dynamic>>[],
          };
        case 'getGroups':
          return {'groups': fakeGroups};
        case 'listInstalledApps':
          return fakeApps;
        case 'getSetting':
          return {'value': null};
        case 'isRecoveryCodeSet':
          return {'isSet': true};
        case 'verifyRecoveryCode':
          return {'matches': true};
      }
      throw MissingPluginException('Unhandled ${call.method} in seal test');
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

  Finder editDialog() => find.ancestor(
        of: find.text('Edit seal rule'),
        matching: find.byType(AlertDialog),
      );

  Finder pickerDialog() => find.ancestor(
        of: find.text('Choose an app'),
        matching: find.byType(AlertDialog),
      );

  Future<void> openRuleEditor(WidgetTester tester) async {
    await tester.tap(
      find.textContaining('A chosen app is suspended by Azm'),
    );
    await tester.pumpAndSettle();
    expect(editDialog(), findsOneWidget);
  }

  // ------------------------------------------------------------ model

  group('SealRule model', () {
    test('legacy packageName migrates to packageNames', () {
      final r = SealRule.fromMap({
        'id': 'r',
        'trigger': 'APP_SUSPENDED',
        'packageName': 'com.example.app',
        'enabled': true,
      });
      expect(r, isNotNull);
      expect(r!.packageNames, ['com.example.app']);
      expect(r.groupId, isNull);
    });

    test('round-trip keeps apps and group', () {
      const r = SealRule(
        id: 'r',
        trigger: SealTrigger.appBlocked,
        packageNames: ['com.a', 'com.b'],
        groupId: 'g1',
      );
      expect(SealRule.fromMap(r.toMap()), r);
    });

    test('sealChangeLoosens: narrowing loosens, widening is free', () {
      const base = SealRule(
        id: 'r',
        trigger: SealTrigger.appSuspended,
        packageNames: ['com.a', 'com.b'],
        groupId: 'g1',
      );
      expect(
        sealChangeLoosens(
          base,
          base.copyWith(packageNames: ['com.a']),
        ),
        isTrue,
      );
      expect(
        sealChangeLoosens(base, base.copyWith(clearGroupId: true)),
        isTrue,
      );
      expect(
        sealChangeLoosens(base, base.copyWith(groupId: 'g2')),
        isTrue,
      );
      expect(
        sealChangeLoosens(
          base,
          base.copyWith(packageNames: ['com.a', 'com.b', 'com.c']),
        ),
        isFalse,
      );
      expect(sealChangeLoosens(base, base), isFalse);
    });
  });

  // ------------------------------------------------------------ widget

  group('seal rules screen', () {
    testWidgets('summary names the group and the app count', (
      tester,
    ) async {
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(child: SealRulesScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      // Both rules watch group g1, so both summaries name it.
      expect(find.textContaining('Group: Social'), findsNWidgets(2));
      expect(find.textContaining('2 target app(s)'), findsOneWidget);
      controller.session.end();
    });

    testWidgets('narrowing the apps goes through the gate', (
      tester,
    ) async {
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(child: SealRulesScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      await openRuleEditor(tester);
      await tester.tap(find.text('Apps'));
      await tester.pumpAndSettle();
      expect(pickerDialog(), findsOneWidget);
      // Uncheck Social App, keep Example Game.
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Social App'));
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: pickerDialog(),
          matching: find.widgetWithText(FilledButton, 'Save'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: editDialog(),
          matching: find.widgetWithText(FilledButton, 'Save'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Enter recovery code'), findsOneWidget);
      expect(
        calls.any((c) => c.method == 'setSealRules'),
        isFalse,
      );
      await enterCodeAndConfirm(tester);
      final saved = calls.lastWhere((c) => c.method == 'setSealRules');
      final rules = (saved.arguments['rules'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final r1 = rules.firstWhere((r) => r['id'] == 'r1');
      expect(r1['packageNames'], ['com.example.game']);
      expect(r1['groupId'], 'g1');
      controller.session.end();
    });

    testWidgets('adding an app saves directly, no gate', (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(child: SealRulesScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      await openRuleEditor(tester);
      await tester.tap(find.text('Apps'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Notes App'));
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: pickerDialog(),
          matching: find.widgetWithText(FilledButton, 'Save'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: editDialog(),
          matching: find.widgetWithText(FilledButton, 'Save'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Enter recovery code'), findsNothing);
      final saved = calls.lastWhere((c) => c.method == 'setSealRules');
      final rules = (saved.arguments['rules'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final r1 = rules.firstWhere((r) => r['id'] == 'r1');
      expect(
        (r1['packageNames'] as List).toSet(),
        {'com.example.game', 'com.example.social', 'com.example.notes'},
      );
      controller.session.end();
    });
  });
}
