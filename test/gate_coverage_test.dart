// Gate-coverage tests for the user rule of 2026-11-22: ACTIVATING a
// restriction is free (no recovery code); only DEACTIVATING one
// (clearing it) opens the recovery gate. (This supersedes the old
// v1.0.4 directive that gated activations too.)
//
// v1.0.5 (user directive): the code ALONE opens the session — the gate
// has no challenges stage any more. The third test below is the
// regression pin: a correct code completes a loosening with zero
// challenge involvement.
import 'package:azm/app_controller.dart';
import 'package:azm/data/privileged_channel.dart';
import 'package:azm/ui/restrictions_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('azm/privileged');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  /// One recommended restriction, inactive or active per
  /// [activeInitially]. Records every apply/clear call so the tests
  /// can prove nothing was applied before the gate. [codeMatches]
  /// controls what the native code check answers.
  ({PrivilegedChannel client, List<String> applied, List<String> cleared})
      harness({
    bool codeMatches = false,
    bool activeInitially = false,
  }) {
    final applied = <String>[];
    final cleared = <String>[];
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        case 'listUserRestrictions':
          return {
            'restrictions': [
              {
                'key': 'disallow_factory_reset',
                'active': activeInitially,
                'recommended': true,
              },
            ],
          };
        case 'applyUserRestriction':
          applied.add((call.arguments as Map)['key'] as String);
          return {'active': true};
        case 'clearUserRestriction':
          cleared.add((call.arguments as Map)['key'] as String);
          return {'active': false};
        case 'isRecoveryCodeSet':
          return {'isSet': true};
        case 'verifyRecoveryCode':
          return {'matches': codeMatches};
        case 'getSetting':
          return {'value': null};
        default:
          throw MissingPluginException('no mock for ${call.method}');
      }
    });
    return (
      client: PrivilegedChannel(methodChannel: methodChannel),
      applied: applied,
      cleared: cleared,
    );
  }

  Future<void> toggleAndTapApply(WidgetTester tester) async {
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(find.text('Apply changes'), findsOneWidget);
    await tester.tap(find.text('Apply changes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'Activating a restriction applies directly — no gate (2026-11-22)',
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

      await toggleAndTapApply(tester);

      // No gate dialog, no session needed: the activation went through.
      expect(find.text('Recovery code'), findsNothing);
      expect(h.applied, ['disallow_factory_reset']);
      expect(controller.session.isActive, isFalse);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Clearing a restriction opens the gate and clears nothing yet',
    (tester) async {
      final h = harness(activeInitially: true);
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

      await toggleAndTapApply(tester);

      // The code-first gate is showing, and nothing was cleared yet.
      expect(find.text('Recovery code'), findsOneWidget);
      expect(h.cleared, isEmpty);
      expect(controller.session.isActive, isFalse);

      // Cancelling the gate clears nothing either.
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(h.cleared, isEmpty);

      await tester.pumpWidget(const SizedBox());
    },
  );

  // v1.0.5 regression pin (user directive): entering the correct code
  // completes the loosening immediately — no math/typing/reading
  // challenge is presented anywhere in the gate path. Before this fix,
  // a correct code advanced the dialog to a challenges stage ("solve 5
  // math problems") and the session started only after them.
  testWidgets(
    'Correct code opens the session and clears — no challenges anywhere',
    (tester) async {
      final h = harness(codeMatches: true, activeInitially: true);
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

      await toggleAndTapApply(tester);

      // The gate is at its code stage; nothing cleared yet.
      expect(find.text('Recovery code'), findsOneWidget);
      expect(h.cleared, isEmpty);
      expect(controller.session.isActive, isFalse);

      // Type the 16-letter code and confirm.
      await tester.enterText(find.byType(TextField).last, 'ABCDEFGHIJKLMNOP');
      await tester.pump();
      await tester.tap(find.text('Confirm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The session opened from the code alone and the clear was
      // applied. The dialog is gone and no challenge UI ever appeared:
      // no challenges title, no extra text field, no dialog at all.
      expect(controller.session.isActive, isTrue);
      expect(h.cleared, ['disallow_factory_reset']);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Access challenges'), findsNothing);

      controller.session.end();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
