// Gate-coverage tests for the v1.0.4 security directive (see
// docs/CODE_AUDIT_v1.0.4.md): ACTIVATING a restriction is recovery-gated
// exactly like loosening one — the paper code must be entered before any
// activation is applied. Before the audit fix, applying a restriction
// (a pure activation) went through with no gate at all.
import 'package:dominanter/app_controller.dart';
import 'package:dominanter/data/privileged_channel.dart';
import 'package:dominanter/ui/restrictions_tab.dart';
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

  /// One recommended, currently-inactive restriction. Records every
  /// applyUserRestriction call so the tests can prove nothing was
  /// applied before the gate.
  ({PrivilegedChannel client, List<String> applied}) harness() {
    final applied = <String>[];
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        case 'listUserRestrictions':
          return {
            'restrictions': [
              {
                'key': 'disallow_factory_reset',
                'active': false,
                'recommended': true,
              },
            ],
          };
        case 'applyUserRestriction':
          applied.add((call.arguments as Map)['key'] as String);
          return {'active': true};
        case 'clearUserRestriction':
          return {'active': false};
        case 'isRecoveryCodeSet':
          return {'isSet': true};
        case 'verifyRecoveryCode':
          return {'matches': false};
        case 'getSetting':
          return {'value': null};
        default:
          throw MissingPluginException('no mock for ${call.method}');
      }
    });
    return (
      client: PrivilegedChannel(methodChannel: methodChannel),
      applied: applied,
    );
  }

  Future<void> toggleOnAndTapApply(WidgetTester tester) async {
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(find.text('Apply changes'), findsOneWidget);
    await tester.tap(find.text('Apply changes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
      'Activating a restriction opens the recovery gate and applies nothing yet',
      (tester) async {
    final h = harness();
    final controller = AppController.test(h.client);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RestrictionsTab(controller: controller)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(Switch), findsOneWidget);

    await toggleOnAndTapApply(tester);

    // The code-first gate is showing (the code field with its label),
    // and the activation has NOT been applied behind it.
    expect(find.text('Recovery code'), findsOneWidget);
    expect(h.applied, isEmpty);
    expect(controller.session.isActive, isFalse);

    // Cancelling the gate applies nothing either.
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(h.applied, isEmpty);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'With a session already open, the same activation applies directly',
      (tester) async {
    final h = harness();
    final controller = AppController.test(h.client);
    addTearDown(controller.dispose);
    controller.session.start(); // a code-first session is already active

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RestrictionsTab(controller: controller)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await toggleOnAndTapApply(tester);

    // No gate dialog: the active session passes through and the
    // restriction is applied.
    expect(find.text('Recovery code'), findsNothing);
    expect(h.applied, ['disallow_factory_reset']);

    // End the session so its 1-second ticker stops before the test
    // framework's pending-timer check.
    controller.session.end();
    await tester.pumpWidget(const SizedBox());
  });
}
