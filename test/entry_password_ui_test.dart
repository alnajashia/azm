// Entry password UI (v1.0.4): the lock screen offers "Use password
// instead" only when a password record exists; a correct password
// unlocks app entry WITHOUT opening a recovery session; a wrong
// password shows an error and stays locked.
import 'dart:convert';

import 'package:dominanter/app_controller.dart';
import 'package:dominanter/data/privileged_channel.dart';
import 'package:dominanter/domain/entry_password.dart';
import 'package:dominanter/ui/lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('dominanter/privileged');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  /// Channel mock: the settings store is a backing map (same shape as
  /// entry_password_test); the lock screen's other reads return empty
  /// defaults. [passwordRecord] is the stored JSON for the password
  /// 'open sesame' (fast 1000-iteration test record), or null.
  AppController controllerWithPassword(String? passwordRecord) {
    final backing = <String, Object?>{
      if (passwordRecord != null)
        'security_prefs/entry_password': passwordRecord,
    };
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

  testWidgets('No password set: no password action on the lock screen',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final controller = controllerWithPassword(null);
    await tester.pumpWidget(
      MaterialApp(home: LockScreen(controller: controller)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Access app'), findsOneWidget);
    expect(find.text('Use password instead'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Password set: wrong password errors and stays locked',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final controller = controllerWithPassword(recordFor('open sesame'));
    await tester.pumpWidget(
      MaterialApp(home: LockScreen(controller: controller)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Use password instead'), findsOneWidget);
    await tester.tap(find.text('Use password instead'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Enter app password'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'wrong password');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Visible error, dialog still open, app still locked, no session.
    expect(find.text('That password is not correct.'), findsOneWidget);
    expect(find.text('Enter app password'), findsOneWidget);
    expect(controller.startup, StartupState.locked);
    expect(controller.session.isActive, isFalse);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Password set: correct password unlocks entry, '
      'but NOT a recovery session', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final controller = controllerWithPassword(recordFor('open sesame'));
    await tester.pumpWidget(
      MaterialApp(home: LockScreen(controller: controller)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Use password instead'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(find.byType(TextField), 'open sesame');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Enter app password'), findsNothing); // dialog closed
    expect(controller.startup, StartupState.unlocked); // entry unlocked
    expect(controller.session.isActive, isFalse); // session NOT opened

    await tester.pumpWidget(const SizedBox());
  });
}
