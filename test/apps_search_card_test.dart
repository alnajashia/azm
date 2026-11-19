/// User request 2026-11-19 (item 2): while searching the app list,
/// the "App list options" browse card hides — with the keyboard up
/// it covered half the screen and squeezed the results.
library;

import 'package:azm/app_controller.dart';
import 'package:azm/data/privileged_channel.dart';
import 'package:azm/l10n/app_localizations.dart';
import 'package:azm/theme.dart';
import 'package:azm/ui/apps_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'azm/privileged';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methodChannel = MethodChannel(channelName);

  setUp(() {
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        case 'listInstalledApps':
          return [
            {'packageName': 'com.example.alpha', 'label': 'Alpha'},
            {'packageName': 'com.example.beta', 'label': 'Beta'},
          ];
        case 'getUsageToday':
          return {'packages': <String, dynamic>{}};
        case 'getGroups':
          return {'groups': <Map<String, dynamic>>[]};
        case 'getSetting':
          return {'value': null};
        case 'setSetting':
          return <String, dynamic>{};
        default:
          return null;
      }
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  testWidgets('browse card hides while searching, returns after',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AppController.test(
      PrivilegedChannel(methodChannel: methodChannel),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: azmDarkTheme(),
        home: Scaffold(body: AppsTab(controller: controller)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Idle: the browse card and both apps are visible.
    expect(find.text('App list options'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);

    // Focus the search field: the card hides.
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(find.text('App list options'), findsNothing);

    // Typing keeps it hidden and filters the list.
    await tester.enterText(find.byType(TextField), 'alp');
    await tester.pump();
    expect(find.text('App list options'), findsNothing);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);

    // Clear + unfocus: the card returns.
    await tester.enterText(find.byType(TextField), '');
    FocusScope.of(tester.element(find.byType(TextField))).unfocus();
    await tester.pump();
    expect(find.text('App list options'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
