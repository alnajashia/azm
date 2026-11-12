// v1.0.5 fix #6: the removal teardown report contract.
//
// Since fix #6, `removeDeviceOwner` is an ordered native teardown
// (disarm the lockdown → stop focus → unsuspend → clear restrictions →
// unhide → lift uninstall blocks → clear per-app bundles → clear the
// owner → clear the flag) and the channel returns a per-step report.
// These tests pin the Dart parsing of that report: step order is the
// teardown order, failures are attributable to their step, and a
// missing owner flag reads conservatively as "still owner".
import 'package:azm/data/privileged_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'azm/privileged';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final methodChannel = const MethodChannel(channelName);

  PrivilegedChannel clientWith(Map<String, Object?> reply) {
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      expect(call.method, 'removeDeviceOwner');
      return reply;
    });
    return PrivilegedChannel(methodChannel: methodChannel);
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  Map<String, Object?> step(String id, bool ok, [String detail = 'done']) => {
    'id': id,
    'ok': ok,
    'detail': detail,
  };

  test(
    'Clean removal: owner gone, all steps ok, teardown order preserved',
    () async {
      final client = clientWith({
        'isDeviceOwner': false,
        'steps': [
          step('flag', true),
          step('focus', true),
          step('unsuspend', true),
          step('restrictions', true),
          step('unhide', true),
          step('uninstallBlocks', true),
          step('appRestrictions', true),
          step('clearOwner', true),
          step('flagClear', true),
        ],
      });
      final result = await client.removeDeviceOwner();
      expect(result.removed, isTrue);
      expect(result.clean, isTrue);
      expect(result.failedSteps, isEmpty);
      // The flag is set FIRST and cleared LAST; the owner clears only
      // after every dismantling step — the order is the fix.
      expect(result.steps.map((s) => s.id).toList(), [
        'flag',
        'focus',
        'unsuspend',
        'restrictions',
        'unhide',
        'uninstallBlocks',
        'appRestrictions',
        'clearOwner',
        'flagClear',
      ]);
    },
  );

  test(
    'Partial removal: owner gone but failed steps are reported honestly',
    () async {
      final client = clientWith({
        'isDeviceOwner': false,
        'steps': [
          step('flag', true),
          step('focus', true),
          step('unsuspend', false, '2 package(s) could not be unsuspended'),
          step('restrictions', true),
          step('unhide', true),
          step('uninstallBlocks', true),
          step('appRestrictions', true),
          step('clearOwner', true),
          step('flagClear', true),
        ],
      });
      final result = await client.removeDeviceOwner();
      expect(result.removed, isTrue);
      expect(result.clean, isFalse);
      expect(result.failedSteps.map((s) => s.id), ['unsuspend']);
      expect(
        result.failedSteps.single.detail,
        contains('could not be unsuspended'),
      );
    },
  );

  test('Failed removal: still owner is never read as removed', () async {
    final client = clientWith({
      'isDeviceOwner': true,
      'steps': [
        step('flag', true),
        step(
          'clearOwner',
          false,
          'Still Device Owner after clearDeviceOwnerApp',
        ),
        step('flagClear', true),
      ],
    });
    final result = await client.removeDeviceOwner();
    expect(result.removed, isFalse);
    expect(result.clean, isFalse);
  });

  test(
    'Missing owner flag in the reply reads conservatively as still owner',
    () async {
      final client = clientWith({'steps': <Object?>[]});
      final result = await client.removeDeviceOwner();
      expect(result.isDeviceOwner, isTrue);
      expect(result.removed, isFalse);
      expect(result.steps, isEmpty);
    },
  );
}
