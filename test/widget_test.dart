import 'package:dominanter/app_controller.dart';
import 'package:dominanter/data/privileged_channel.dart';
import 'package:dominanter/ui/lock_screen.dart';
import 'package:dominanter/ui/recovery_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('dominanter/privileged');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  PrivilegedChannel mockClient(Map<String, Object? Function(MethodCall)> handlers) {
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      final h = handlers[call.method];
      if (h == null) throw MissingPluginException('no mock for ${call.method}');
      return h(call);
    });
    return PrivilegedChannel(methodChannel: methodChannel);
  }

  testWidgets('Lock screen: panic button is visible BEFORE any auth (F21/F32)',
      (tester) async {
    final client = mockClient({
      'getUsageToday': (_) => {
            'date': '2026-11-09',
            'packages': [
              {'packageName': 'com.example.video', 'usedMs': 1800000},
            ],
            'groups': <Object?>[],
          },
      'listInstalledApps': (_) => [
            {
              'packageName': 'com.example.video',
              'label': 'Video App',
              'isSystem': false,
              'isHidden': false,
              'isSuspended': false,
              'isUninstallBlocked': false,
              'hasExplicitContentRating': null,
            },
          ],
      'getGroups': (_) => {'groups': <Object?>[]},
      // The limits overview only lists apps that HAVE a limit: this app
      // has a 60-minute daily limit (30 min used today).
      'getTimeLimit': (_) => {'dailyMinutes': 60, 'reopenSeconds': 0},
      'getTimeWindows': (_) => {'dailyWindows': <Object?>[], 'weeklyWindows': null},
      'getFocusSession': (_) => null, // no native focus session
      'getSetting': (_) => {'value': null},
    });
    final controller = AppController.test(client);
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(home: LockScreen(controller: controller)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text("I'm having impulses"), findsOneWidget);
    expect(find.text('Access app'), findsOneWidget);
    expect(controller.startup, StartupState.locked); // still locked

    // The usage overview is limit-scoped and lives behind 'View limits':
    // nothing about individual apps is shown inline any more.
    expect(find.text('Video App'), findsNothing);
    await tester.ensureVisible(find.text('View limits'));
    await tester.tap(find.text('View limits'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text("Today's usage"), findsOneWidget);
    expect(find.text('Video App'), findsOneWidget);
    expect(find.text('30min of 1h'), findsOneWidget); // 30 min used of 60

    await tester.pumpWidget(const SizedBox()); // dispose tickers
  });

  testWidgets('Wizard step 2 is reveal-gated: no code before "Show code" (F24)',
      (tester) async {
    // Tall viewport: with the default 800x600 surface the wizard's
    // write-step checkbox lands in the bottom button bar's tap shadow.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final client = mockClient({
      'generateRecoveryCode': (_) => {'code': 'ABCDEFGHIJKLMNOP'},
      'setRecoveryCode': (_) => {'isSet': true},
    });
    final controller = AppController.test(client);
    addTearDown(controller.dispose);
    var done = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RecoveryWizard(controller: controller, onDone: () => done = true),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Step 1 of 4: Intro — the code is not generated into view here.
    expect(find.text('Step 1 of 4'), findsOneWidget);
    expect(find.text('ABCD EFGH IJKL MNOP'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pump();

    // Step 2: Write — the code stays hidden until the explicit reveal,
    // and Next is disabled until it has been revealed AND the paper
    // checkbox is ticked.
    expect(find.text('Step 2 of 4'), findsOneWidget);
    expect(find.text('ABCD EFGH IJKL MNOP'), findsNothing);
    final nextButton =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'));
    expect(nextButton.onPressed, isNull);

    await tester.tap(find.text('Show code'));
    await tester.pump();
    expect(find.text('ABCD EFGH IJKL MNOP'), findsOneWidget);
    expect(done, isFalse);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Wizard: full 4-step flow stores the re-typed code (F24)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    String? storedCode;
    final client = mockClient({
      'generateRecoveryCode': (_) => {'code': 'ABCDEFGHIJKLMNOP'},
      'setRecoveryCode': (call) {
        storedCode = (call.arguments as Map)['code'] as String;
        return {'isSet': true};
      },
    });
    final controller = AppController.test(client);
    addTearDown(controller.dispose);
    var done = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RecoveryWizard(controller: controller, onDone: () => done = true),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Intro -> Write.
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pump();
    // Reveal, confirm the paper copy, advance.
    await tester.tap(find.text('Show code'));
    await tester.pump();
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox)); // 'I wrote the code on paper'
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pump();

    // Step 3: Confirm — the code is hidden again; type it from paper.
    expect(find.text('Step 3 of 4'), findsOneWidget);
    expect(find.text('ABCD EFGH IJKL MNOP'), findsNothing);
    await tester.enterText(find.byType(TextField), 'ABCDEFGHIJKLMNOP');
    await tester.pump();
    expect(find.text('The code is correct'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pump();

    // Step 4: Store — Finish stays disabled until the storage checkbox,
    // and only Finish talks to the channel.
    expect(find.text('Step 4 of 4'), findsOneWidget);
    final finishButton =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Finish'));
    expect(finishButton.onPressed, isNull);
    expect(storedCode, isNull);

    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox)); // 'I stored the paper in a safe place'
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Finish'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(storedCode, 'ABCDEFGHIJKLMNOP');
    expect(done, isTrue);

    await tester.pumpWidget(const SizedBox());
  });
}
