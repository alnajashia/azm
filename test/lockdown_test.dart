/// Batch I-B, item 14 — full-phone lockdown: the model round-trips
/// and the screen lists windows; starting a one-shot lockdown saves
/// directly (tightening); ending early and adding/deleting/enabling a
/// recurring window go through the paper-code session; editing a
/// window's time saves directly; the exact-alarm banner shows when
/// the permission is off.
///
/// NOTE: the screen runs a 1-second ticker, so these tests use
/// explicit `tester.pump()` calls instead of `pumpAndSettle` (which
/// would time out on the periodic timer).
library;

import 'package:azm/app_controller.dart';
import 'package:azm/data/privileged_channel.dart';
import 'package:azm/domain/lockdown.dart';
import 'package:azm/l10n/app_localizations.dart';
import 'package:azm/theme.dart';
import 'package:azm/ui/lockdown_screen.dart';
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
  late List<Map<String, dynamic>> fakeLockdowns;
  late Map<String, dynamic>? fakeActive;
  late bool fakeCanScheduleExactAlarms;
  final createdControllers = <AppController>[];

  Map<String, dynamic> window(
    String id,
    Set<int> days,
    int startHour,
    int startMinute,
    int endHour,
    int endMinute, {
    bool enabled = true,
    bool strict = false,
    String scope = 'ALL_APPS',
    String label = '',
  }) =>
      {
        'id': id,
        'kind': 'RECURRING',
        'durationMinutes': 180,
        'startHour': startHour,
        'startMinute': startMinute,
        'endHour': endHour,
        'endMinute': endMinute,
        'days': days.toList(),
        'scope': scope,
        'targetApps': <String>[],
        'targetGroups': <String>[],
        'strict': strict,
        'enabled': enabled,
        'label': label,
      };

  Map<String, dynamic> activeLockdown() => {
        'id': 'a1',
        'label': '',
        'strict': false,
        'scope': 'ALL_APPS',
        'endWallClockMs':
            DateTime.now().millisecondsSinceEpoch + 600000,
        'remainingMs': 600000,
        'claimedCount': 3,
      };

  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher
        .implicitView!;
    view.physicalSize = const Size(800, 4000);
    view.devicePixelRatio = 1.0;
    calls = [];
    fakeCanScheduleExactAlarms = true;
    fakeLockdowns = [
      window('w1', {1, 2, 3, 4, 5}, 6, 0, 10, 0, label: 'Morning'),
    ];
    fakeActive = null;

    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getSetting':
          return {'value': null};
        case 'setSetting':
          return <String, dynamic>{};
        case 'getFocusSession':
          return null;
        case 'listInstalledApps':
          return <Map<String, dynamic>>[];
        case 'getGroups':
          return {'groups': <Map<String, dynamic>>[]};
        case 'getLockdownState':
          return {
            'lockdowns': fakeLockdowns,
            'active': fakeActive,
            'canScheduleExactAlarms': fakeCanScheduleExactAlarms,
          };
        case 'setLockdowns':
          fakeLockdowns = (call.arguments['lockdowns'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          return {
            'lockdowns': fakeLockdowns,
            'active': fakeActive,
            'canScheduleExactAlarms': fakeCanScheduleExactAlarms,
          };
        case 'startLockdown':
          final lockdown =
              Map<String, dynamic>.from(call.arguments['lockdown'] as Map);
          fakeActive = {
            'id': lockdown['id'],
            'label': lockdown['label'],
            'strict': lockdown['strict'],
            'scope': lockdown['scope'],
            'endWallClockMs':
                DateTime.now().millisecondsSinceEpoch + 600000,
            'remainingMs': 600000,
            'claimedCount': 2,
          };
          return {
            'lockdowns': fakeLockdowns,
            'active': fakeActive,
            'canScheduleExactAlarms': fakeCanScheduleExactAlarms,
          };
        case 'endLockdown':
          fakeActive = null;
          return {
            'lockdowns': fakeLockdowns,
            'active': fakeActive,
            'canScheduleExactAlarms': fakeCanScheduleExactAlarms,
          };
        case 'openExactAlarmSettings':
          return null;
        case 'isRecoveryCodeSet':
          return {'isSet': true};
        case 'verifyRecoveryCode':
          return {'matches': true};
      }
      throw MissingPluginException('Unhandled ${call.method} in lockdown test');
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

  Future<AppController> pumpScreen(WidgetTester tester) async {
    final controller = makeController();
    await tester.pumpWidget(
      buildTestApp(child: LockdownScreen(controller: controller)),
    );
    // Flush the async loads (state, groups, apps).
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    return controller;
  }

  Future<void> enterCodeAndConfirm(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    expect(find.text('Enter recovery code'), findsOneWidget);
    final codeField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(codeField.first, 'AAAAAAAAAAAAAAAA');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    // End the recovery session here: its 1-second ticker is not owned
    // by the widget tree, so the binding's post-test invariant check
    // would flag it as pending (tearDown's end() runs too late).
    for (final c in createdControllers) {
      c.session.end();
    }
  }

  /// The enable switch inside a window row (scoped by the row's label).
  Finder windowSwitch(String labelText) => find.descendant(
        of: find.ancestor(
          of: find.textContaining(labelText),
          matching: find.byType(ListTile),
        ),
        matching: find.byType(Switch),
      );

  bool methodCalled(String method) =>
      calls.any((c) => c.method == method);

  // ------------------------------------------------------------ model

  group('Lockdown model', () {
    test('round-trip keeps kind, window, scope, tier', () {
      const l = Lockdown(
        id: 'w1',
        kind: LockdownKind.recurring,
        startHour: 22,
        startMinute: 30,
        endHour: 6,
        endMinute: 0,
        daysOfWeek: {1, 2, 3, 4, 5},
        scope: LockdownScope.groups,
        targetGroups: {'g1'},
        strict: true,
        label: 'Night',
      );
      final back = Lockdown.fromMap(l.toMap());
      expect(back, l);
      expect(back?.kind, LockdownKind.recurring);
      expect(back?.strict, true);
    });

    test('fromMap clamps bad values and filters bad days', () {
      final l = Lockdown.fromMap({
        'id': 'x',
        'kind': 'NOPE',
        'durationMinutes': 9999,
        'startHour': 99,
        'days': [1, 8, 0, 5],
        'scope': 'NOPE',
      });
      expect(l, isNotNull);
      expect(l!.kind, LockdownKind.oneShot);
      expect(l.durationMinutes, 1440);
      expect(l.durationSeconds, 86400);
      expect(l.startHour, 23);
      expect(l.daysOfWeek, {1, 5});
      expect(l.scope, LockdownScope.allApps);
    });

    test('duration is seconds: round-trip, clamp, legacy minutes', () {
      // Seconds round-trip (toMap carries both keys).
      const l = Lockdown(id: 's', durationSeconds: 5400);
      final back = Lockdown.fromMap(l.toMap());
      expect(back, l);
      expect(back?.durationSeconds, 5400);
      expect(back?.durationMinutes, 90);
      // Seconds clamp to 60..86400 (1 min..24 h).
      expect(
        Lockdown.fromMap({'id': 'a', 'durationSeconds': 30})
            ?.durationSeconds,
        60,
      );
      expect(
        Lockdown.fromMap({'id': 'b', 'durationSeconds': 90000})
            ?.durationSeconds,
        86400,
      );
      // Legacy minutes-only JSON falls back to minutes.
      expect(
        Lockdown.fromMap({'id': 'c', 'durationMinutes': 90})
            ?.durationSeconds,
        5400,
      );
      // Seconds win when both keys are present.
      expect(
        Lockdown.fromMap({
          'id': 'd',
          'durationSeconds': 120,
          'durationMinutes': 90,
        })?.durationSeconds,
        120,
      );
    });

    test('daysSummary variants', () {
      const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      const every = Lockdown(id: 'e', daysOfWeek: {1, 2, 3, 4, 5, 6, 7});
      expect(
        every.daysSummary(
          everyDay: 'Every day',
          weekdays: 'Weekdays',
          weekend: 'Weekend',
          dayNames: names,
        ),
        'Every day',
      );
      const weekend = Lockdown(id: 'w', daysOfWeek: {6, 7});
      expect(
        weekend.daysSummary(
          everyDay: 'Every day',
          weekdays: 'Weekdays',
          weekend: 'Weekend',
          dayNames: names,
        ),
        'Weekend',
      );
      const some = Lockdown(id: 's', daysOfWeek: {1, 3, 5});
      expect(
        some.daysSummary(
          everyDay: 'Every day',
          weekdays: 'Weekdays',
          weekend: 'Weekend',
          dayNames: names,
        ),
        'Mon · Wed · Fri',
      );
    });
  });

  // ------------------------------------------------------------ widget

  /// The durationSeconds the last startLockdown call carried.
  int startedDurationSeconds() {
    final lockdown = Map<String, dynamic>.from(
      calls.lastWhere((c) => c.method == 'startLockdown').arguments['lockdown']
          as Map,
    );
    return (lockdown['durationSeconds'] as num).toInt();
  }

  group('LockdownScreen', () {
    testWidgets('lists the window and the start card when idle',
        (tester) async {
      await pumpScreen(tester);
      expect(find.text('Start a lockdown'), findsOneWidget);
      expect(find.textContaining('Morning'), findsOneWidget);
      expect(find.text('Level 1 — Suspend everything'), findsOneWidget);
      expect(find.text('Level 2 — Strict kiosk'), findsOneWidget);
      expect(find.text('Start lockdown'), findsOneWidget);
    });

    testWidgets('exact-alarm banner opens settings', (tester) async {
      fakeCanScheduleExactAlarms = false;
      await pumpScreen(tester);
      expect(
        find.text('Exact alarms are off — windows may start late.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Open settings'));
      await tester.pump();
      expect(methodCalled('openExactAlarmSettings'), isTrue);
    });

    testWidgets('starting a one-shot lockdown saves directly',
        (tester) async {
      await pumpScreen(tester);
      // FilledButton.icon builds a _FilledButtonWithIcon, not a
      // FilledButton — tap the label text instead (Batch v1.0.1
      // lesson, repeated here).
      await tester.tap(find.text('Start lockdown'));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(methodCalled('startLockdown'), isTrue);
      expect(find.text('Enter recovery code'), findsNothing);
      expect(find.text('Lockdown active'), findsOneWidget);
      expect(find.text('End lockdown early'), findsOneWidget);
    });

    testWidgets('duration slider sets the lockdown length',
        (tester) async {
      await pumpScreen(tester);
      // Drive the slider's callback directly: dragging by pixels
      // cannot hit an exact minute.
      tester.widget<Slider>(find.byType(Slider)).onChanged!(90);
      await tester.pump();
      expect(find.text('1:30:00'), findsOneWidget);
      await tester.tap(find.text('Start lockdown'));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(startedDurationSeconds(), 5400);
    });

    testWidgets('typed total minutes apply at once', (tester) async {
      await pumpScreen(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Total minutes'),
        '30',
      );
      await tester.pump();
      expect(find.text('30:00'), findsOneWidget);
      await tester.tap(find.text('Start lockdown'));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(startedDurationSeconds(), 1800);
    });

    testWidgets('typed minutes clamp to 24 hours on submit',
        (tester) async {
      await pumpScreen(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Total minutes'),
        '9999',
      );
      await tester.pump();
      // Out of range: nothing applied yet, the slider stays at 3:00:00.
      expect(find.text('3:00:00'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('24:00:00'), findsOneWidget);
      await tester.tap(find.text('Start lockdown'));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(startedDurationSeconds(), 86400);
    });

    testWidgets('hours-minutes-seconds entry composes the duration',
        (tester) async {
      await pumpScreen(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Hours'),
        '2',
      );
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Minutes'),
        '30',
      );
      await tester.pump();
      expect(find.text('2:30:00'), findsOneWidget);
      await tester.tap(find.text('Start lockdown'));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(startedDurationSeconds(), 9000);
    });

    testWidgets('hours-minutes-seconds below one minute clamp on submit',
        (tester) async {
      await pumpScreen(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Hours'),
        '0',
      );
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Minutes'),
        '0',
      );
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Seconds'),
        '30',
      );
      await tester.pump();
      // 30 seconds is below the 1-minute floor: nothing applied yet.
      expect(find.text('3:00:00'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('01:00'), findsOneWidget);
      await tester.tap(find.text('Start lockdown'));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(startedDurationSeconds(), 60);
    });

    testWidgets('the active countdown ticks down', (tester) async {
      fakeActive = activeLockdown();
      await pumpScreen(tester);
      expect(find.text('00:10:00'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('00:09:58'), findsOneWidget);
    });

    testWidgets('ending early goes through the code gate', (tester) async {
      fakeActive = activeLockdown();
      await pumpScreen(tester);
      await tester.tap(find.text('End lockdown early'));
      await enterCodeAndConfirm(tester);
      expect(methodCalled('endLockdown'), isTrue);
      expect(find.text('Start a lockdown'), findsOneWidget);
    });

    testWidgets(
      'ending early still asks for the code with an active session',
      (tester) async {
        // Tier 1 end-early demands FRESH code entry (user request
        // 2026-11-14), like the Tier 2 kiosk activity's native check:
        // an already-active recovery session must NOT let the
        // lockdown end without the code.
        fakeActive = activeLockdown();
        final controller = await pumpScreen(tester);
        controller.session.start();
        await tester.pump();
        await tester.tap(find.text('End lockdown early'));
        for (var i = 0; i < 4; i++) {
          await tester.pump();
        }
        expect(find.text('Enter recovery code'), findsOneWidget);
        expect(methodCalled('endLockdown'), isFalse);
        await enterCodeAndConfirm(tester);
        expect(methodCalled('endLockdown'), isTrue);
        expect(find.text('Start a lockdown'), findsOneWidget);
      },
    );

    testWidgets('adding a window goes through the code gate',
        (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.text('Add window'));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(find.text('Add window'), findsWidgets);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await enterCodeAndConfirm(tester);
      expect(methodCalled('setLockdowns'), isTrue);
      expect(fakeLockdowns.length, 2);
    });

    testWidgets('disabling a window goes through the code gate',
        (tester) async {
      await pumpScreen(tester);
      await tester.tap(windowSwitch('Morning'));
      await enterCodeAndConfirm(tester);
      expect(methodCalled('setLockdowns'), isTrue);
      expect(fakeLockdowns.first['enabled'], isFalse);
    });

    testWidgets('editing a window label saves directly', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.textContaining('Morning'));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      final labelField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(labelField, 'Evening');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(methodCalled('setLockdowns'), isTrue);
      expect(find.text('Enter recovery code'), findsNothing);
      expect(fakeLockdowns.first['label'], 'Evening');
    });

    testWidgets('window editor offers both tiers and saves Tier 2',
        (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.textContaining('Morning'));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      final dialog = find.byType(AlertDialog);
      // Both tiers are offered explicitly (item 3, 2026-11-19): the
      // editor used to show a single Tier 2 switch, hiding Tier 1.
      expect(
        find.descendant(
          of: dialog,
          matching: find.text('Level 1 — Suspend everything'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.text('Level 2 — Strict kiosk'),
        ),
        findsOneWidget,
      );
      // The existing window is Tier 1; choosing Tier 2 saves strict.
      await tester.tap(
        find.descendant(
          of: dialog,
          matching: find.text('Level 2 — Strict kiosk'),
        ),
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(methodCalled('setLockdowns'), isTrue);
      // A tier edit is free — no code gate.
      expect(find.text('Enter recovery code'), findsNothing);
      expect(fakeLockdowns.first['strict'], isTrue);
    });

    testWidgets('reopening a Tier 2 window shows it selected; Tier 1 saves',
        (tester) async {
      fakeLockdowns = [
        window('w2', {1, 2, 3, 4, 5}, 22, 0, 6, 0,
            strict: true, label: 'Night'),
      ];
      await pumpScreen(tester);
      await tester.tap(find.textContaining('Night'));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      final dialog = find.byType(AlertDialog);
      final group = tester.widget<RadioGroup<bool>>(
        find.descendant(of: dialog, matching: find.byType(RadioGroup<bool>)),
      );
      expect(group.groupValue, isTrue);
      await tester.tap(
        find.descendant(
          of: dialog,
          matching: find.text('Level 1 — Suspend everything'),
        ),
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(fakeLockdowns.first['strict'], isFalse);
    });
  });
}
