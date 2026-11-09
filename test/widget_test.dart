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
            'groups': [],
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
    });
    final controller = AppController.test(client);
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(home: LockScreen(controller: controller)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text("I'm having impulses"), findsOneWidget);
    expect(find.text('Access app'), findsOneWidget);
    expect(find.text('Video App'), findsOneWidget); // read-only usage overview
    expect(controller.startup, StartupState.locked); // still locked

    await tester.pumpWidget(const SizedBox()); // dispose tickers
  });

  testWidgets('First-run wizard shows the generated code grouped for paper (F24)',
      (tester) async {
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

    expect(find.text('ABCD EFGH IJKL MNOP'), findsOneWidget);
    expect(find.textContaining('written this code on paper'), findsOneWidget);
    // Continue is disabled until the paper checkbox is ticked.
    final continueButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'));
    expect(continueButton.onPressed, isNull);
    expect(done, isFalse);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Wizard stores the re-typed code via the channel (F24)', (tester) async {
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

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'ABCDEFGHIJKLMNOP');
    await tester.tap(find.widgetWithText(FilledButton, 'Store recovery code'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(storedCode, 'ABCDEFGHIJKLMNOP');
    expect(done, isTrue);

    await tester.pumpWidget(const SizedBox());
  });
}
