/// Batch I-A, item 13 — focus schedules: the model round-trips and
/// the card lists schedules; toggling/deleting/adding an auto-start
/// schedule goes through the paper-code session, reminder-only ones
/// save directly; the exact-alarm banner shows when the permission is
/// off and its button opens settings.
///
/// NOTE: the focus screen runs a 1-second ticker, so these tests use
/// explicit `tester.pump()` calls instead of `pumpAndSettle` (which
/// would time out on the periodic timer).
library;

import 'package:azm/app_controller.dart';
import 'package:azm/data/privileged_channel.dart';
import 'package:azm/domain/focus.dart';
import 'package:azm/l10n/app_localizations.dart';
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

  late List<MethodCall> calls;
  late List<Map<String, dynamic>> fakeSchedules;
  late bool fakeCanScheduleExactAlarms;
  final createdControllers = <AppController>[];

  Map<String, dynamic> schedule(
    String id,
    Set<int> days,
    int hour,
    int minute, {
    bool enabled = true,
    bool autoStart = false,
    int remindMinutesBefore = 0,
    String label = '',
  }) => {
        'id': id,
        'days': days.toList(),
        'hour': hour,
        'minute': minute,
        'enabled': enabled,
        'autoStart': autoStart,
        'remindMinutesBefore': remindMinutesBefore,
        'label': label,
      };

  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher
        .implicitView!;
    view.physicalSize = const Size(800, 4000);
    view.devicePixelRatio = 1.0;
    calls = [];
    fakeCanScheduleExactAlarms = true;
    fakeSchedules = [
      schedule(
        's1',
        {1, 2, 3, 4, 5},
        8,
        0,
        remindMinutesBefore: 5,
        label: 'Study',
      ),
      schedule('s2', {6, 7}, 10, 30, autoStart: true),
    ];

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
        case 'getFocusSchedules':
          return {
            'schedules': fakeSchedules,
            'canScheduleExactAlarms': fakeCanScheduleExactAlarms,
          };
        case 'setFocusSchedules':
          fakeSchedules = (call.arguments['schedules'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          return {
            'schedules': fakeSchedules,
            'canScheduleExactAlarms': fakeCanScheduleExactAlarms,
          };
        case 'openExactAlarmSettings':
          return null;
        case 'isRecoveryCodeSet':
          return {'isSet': true};
        case 'verifyRecoveryCode':
          return {'matches': true};
      }
      throw MissingPluginException('Unhandled ${call.method} in schedules test');
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

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      buildTestApp(child: FocusModeScreen(controller: makeController())),
    );
    // Flush the async loads (config, session, groups, schedules).
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
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

  /// The enable switch inside a schedule row (the screen also has
  /// config switches above the card, so scope by the row's title).
  Finder scheduleSwitch(String titleText) => find.descendant(
        of: find.ancestor(
          of: find.text(titleText),
          matching: find.byType(ListTile),
        ),
        matching: find.byType(Switch),
      );

  bool setSchedulesCalled() =>
      calls.any((c) => c.method == 'setFocusSchedules');

  // ------------------------------------------------------------ model

  group('FocusSchedule model', () {
    test('round-trip keeps days, time, extensions', () {
      const s = FocusSchedule(
        id: 's1',
        daysOfWeek: {1, 3, 5},
        hour: 8,
        minute: 30,
        autoStart: true,
        remindMinutesBefore: 10,
        label: 'Study',
      );
      final back = FocusSchedule.fromMap(s.toMap());
      expect(back, s);
      expect(back.formattedTime, '08:30');
    });

    test('daysSummary names every day, weekdays, weekend, and lists', () {
      const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      String summary(Set<int> days) => FocusSchedule(
            id: 'x',
            daysOfWeek: days,
            hour: 8,
            minute: 0,
          ).daysSummary(
            everyDay: 'Every day',
            weekdays: 'Weekdays',
            weekend: 'Weekend',
            dayNames: names,
          );
      expect(summary({1, 2, 3, 4, 5, 6, 7}), 'Every day');
      expect(summary({1, 2, 3, 4, 5}), 'Weekdays');
      expect(summary({6, 7}), 'Weekend');
      expect(summary({1, 3, 5}), 'Mon, Wed, Fri');
    });

    test('fromMap clamps bad values instead of throwing', () {
      final s = FocusSchedule.fromMap({
        'id': 'x',
        'days': [0, 1, 8, 3],
        'hour': 25,
        'minute': -1,
      });
      expect(s.daysOfWeek, {1, 3});
      expect(s.hour, 23);
      expect(s.minute, 0);
      expect(s.enabled, isTrue);
    });
  });

  // ------------------------------------------------------------ screen

  group('FocusModeScreen schedules card', () {
    testWidgets('lists schedules with time, days, and mode', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Focus schedules & reminders'), findsOneWidget);
      expect(find.text('08:00 · Study'), findsOneWidget);
      expect(
        find.textContaining('Weekdays · Reminder · 5 min before'),
        findsOneWidget,
      );
      expect(find.text('10:30'), findsOneWidget);
      expect(find.textContaining('Weekend · Auto-start'), findsOneWidget);
      expect(find.text('Add schedule'), findsOneWidget);
    });

    testWidgets('exact-alarm banner opens settings', (tester) async {
      fakeCanScheduleExactAlarms = false;
      await pumpScreen(tester);
      expect(
        find.text('Exact alarms are off — schedules may start late.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Open settings'));
      await tester.pump();
      expect(
        calls.any((c) => c.method == 'openExactAlarmSettings'),
        isTrue,
      );
    });

    testWidgets('toggling a reminder-only schedule saves directly', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(scheduleSwitch('08:00 · Study'));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(find.text('Enter recovery code'), findsNothing);
      expect(setSchedulesCalled(), isTrue);
      expect(fakeSchedules.first['enabled'], isFalse);
    });

    testWidgets('toggling an auto-start schedule goes through the gate', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(scheduleSwitch('10:30'));
      await enterCodeAndConfirm(tester);
      expect(setSchedulesCalled(), isTrue);
      expect(fakeSchedules.last['enabled'], isFalse);
    });

    testWidgets('deleting an auto-start schedule goes through the gate', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(find.byTooltip('Delete').last);
      await enterCodeAndConfirm(tester);
      expect(setSchedulesCalled(), isTrue);
      expect(fakeSchedules.length, 1);
      expect(fakeSchedules.single['id'], 's1');
    });

    testWidgets('adding a reminder schedule from the editor saves directly', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(find.text('Add schedule'));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(find.text('Add schedule'), findsNWidgets(2)); // card + dialog
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(find.text('Enter recovery code'), findsNothing);
      expect(setSchedulesCalled(), isTrue);
      expect(fakeSchedules.length, 3);
      final added = fakeSchedules.singleWhere(
        (s) => (s['id'] as String).startsWith('schedule-'),
      );
      expect(added['hour'], 8);
      expect(added['minute'], 0);
      expect((added['days'] as List).length, 5);
      expect(added['autoStart'], isFalse);
    });
  });
}
