/// Regression pins for the v1.0.5 second audit
/// (docs/CODE_AUDIT_v1.0.5.md). Each group names the finding it pins.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dominanter/app_controller.dart';
import 'package:dominanter/data/config_store.dart';
import 'package:dominanter/data/privileged_channel.dart';
import 'package:dominanter/domain/challenges.dart';
import 'package:dominanter/domain/entry_password.dart';
import 'package:dominanter/domain/recovery.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('B-1 MonotonicDelta (clock jumps cannot move the timers)', () {
    test('first take is zero; later takes are exact monotonic deltas', () {
      final tracker = MonotonicDelta();
      tracker.reset(const Duration(minutes: 5));
      expect(
        tracker.take(const Duration(minutes: 5)),
        Duration.zero,
      );
      expect(
        tracker.take(const Duration(minutes: 7)),
        const Duration(minutes: 2),
      );
      expect(
        tracker.take(const Duration(minutes: 7, seconds: 30)),
        const Duration(seconds: 30),
      );
    });

    test('a backwards reading clamps to zero, never negative', () {
      final tracker = MonotonicDelta();
      tracker.reset(const Duration(minutes: 5));
      expect(tracker.take(const Duration(minutes: 1)), Duration.zero);
    });

    test('forced removal fed only monotonic deltas needs the full 24 h '
        'of real elapsed time', () {
      // The wall clock does not appear anywhere in this accounting:
      // the tracker is fed monotonic readings, so even a +24 h wall
      // jump contributes nothing — only real elapsed deltas advance.
      final tracker = MonotonicDelta()..reset(Duration.zero);
      var removal = const ForcedRemoval().start();
      removal = removal.advance(tracker.take(const Duration(hours: 23)));
      expect(removal.isComplete, isFalse);
      removal = removal.advance(tracker.take(const Duration(hours: 24)));
      expect(removal.isComplete, isTrue);
    });
  });

  group('B-13 PendingChange.dispose completes done', () {
    test('a disposed pending change settles done and never applies',
        () async {
      var applied = false;
      final change = PendingChange(
        description: 'pin',
        direction: ChangeDirection.tightening,
        apply: () async => applied = true,
      );
      await change.run();
      expect(change.isPending, isTrue);
      change.dispose();
      // Would hang forever before the fix.
      await change.done.timeout(const Duration(seconds: 2));
      expect(applied, isFalse);
    });
  });

  group('B-14 WordsChallenge getters are safe before start()', () {
    test('currentWord/charStates do not throw on a fresh challenge', () {
      final challenge = WordsChallenge();
      expect(challenge.currentWord, '');
      expect(challenge.charStates, isEmpty);
    });
  });

  group('B-8 EntryPasswordHash.verify honours KDF parameter floors', () {
    test('a truncated-hash record never verifies, even when the '
        'truncated derivation matches', () {
      final salt = List<int>.generate(16, (i) => i);
      final shortHash = pbkdf2HmacSha256(
        password: utf8.encode('hunter2!'),
        salt: salt,
        iterations: 1000,
        keyLength: 1,
      );
      final tampered = EntryPasswordHash(
        saltBase64: base64.encode(salt),
        hashBase64: base64.encode(shortHash),
        iterations: 1000,
      );
      expect(tampered.verify('hunter2!'), isFalse);
    });

    test('a stripped iteration count never verifies and never crashes',
        () {
      final salt = List<int>.generate(16, (i) => i * 3 % 256);
      final weakHash = pbkdf2HmacSha256(
        password: utf8.encode('hunter2!'),
        salt: salt,
        iterations: 1,
        keyLength: 32,
      );
      final tampered = EntryPasswordHash(
        saltBase64: base64.encode(salt),
        hashBase64: base64.encode(weakHash),
        iterations: 1,
      );
      expect(tampered.verify('hunter2!'), isFalse);
      const zero = EntryPasswordHash(
        saltBase64: 'AAAAAAAAAAAAAAAAAAAAAA==',
        hashBase64:
            'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        iterations: 0,
      );
      expect(zero.verify('hunter2!'), isFalse);
    });
  });

  group('B-3 persisted anti-guess throttle', () {
    test('delay schedule: 2 s per failure, capped at 30 s', () {
      expect(entryPasswordDelaySeconds(0), 0);
      expect(entryPasswordDelaySeconds(1), 2);
      expect(entryPasswordDelaySeconds(3), 6);
      expect(entryPasswordDelaySeconds(15), 30);
      expect(entryPasswordDelaySeconds(100), 30);
    });

    const methodChannel = MethodChannel('dominanter/privileged');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final backing = <String, Object?>{};

    ConfigStore statefulStore() {
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        final args = (call.arguments as Map).cast<String, Object?>();
        final slot = '${args['store']}/${args['key']}';
        switch (call.method) {
          case 'getSetting':
            return {'value': backing[slot]};
          case 'setSetting':
            backing[slot] = args['value'];
            return <String, Object?>{};
          default:
            throw MissingPluginException('no mock for ${call.method}');
        }
      });
      return ConfigStore(PrivilegedChannel(methodChannel: methodChannel));
    }

    setUp(backing.clear);
    tearDown(() => messenger.setMockMethodCallHandler(methodChannel, null));

    test('failures persist across store instances and drive the wait; '
        'reset clears them', () async {
      final store = statefulStore();
      expect((await store.getEntryPasswordThrottle()).failures, 0);
      expect(await store.entryPasswordWaitRemaining(), Duration.zero);

      expect(await store.recordEntryPasswordFailure(), 1);
      expect(await store.recordEntryPasswordFailure(), 2);

      // A NEW store instance (a new "process") still sees the count —
      // the throttle is not dialog- or process-local.
      final store2 = statefulStore();
      final throttle = await store2.getEntryPasswordThrottle();
      expect(throttle.failures, 2);
      // Two failures = a 4 s delay; only just recorded, so most of the
      // wait is still owed.
      final wait = await store2.entryPasswordWaitRemaining();
      expect(wait, greaterThan(const Duration(seconds: 3)));
      expect(wait, lessThanOrEqualTo(const Duration(seconds: 4)));

      await store2.resetEntryPasswordThrottle();
      expect((await store.getEntryPasswordThrottle()).failures, 0);
      expect(await store.entryPasswordWaitRemaining(), Duration.zero);
    });

    test('a corrupt entry-password record reports corrupt, not unset '
        '(B-9)', () async {
      final store = statefulStore();
      expect(
        await store.getEntryPasswordRecordState(),
        EntryPasswordRecordState.unset,
      );
      backing['security_prefs/entry_password'] = '{"salt": 42}';
      expect(
        await store.getEntryPasswordRecordState(),
        EntryPasswordRecordState.corrupt,
      );
      // Verification still fails closed, never crashes.
      expect(await store.isEntryPasswordSet(), isFalse);
      expect(await store.verifyEntryPassword('whatever1'), isFalse);
    });
  });

  group('B-5/B-6/B-7 channel verified-state fields are never fabricated',
      () {
    const channelName = 'dominanter/privileged';
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final methodChannel = const MethodChannel(channelName);

    PrivilegedChannel clientWith(
      Future<Object?>? Function(MethodCall call)? handler,
    ) {
      messenger.setMockMethodCallHandler(methodChannel, handler);
      return PrivilegedChannel(methodChannel: methodChannel);
    }

    tearDown(() {
      messenger.setMockMethodCallHandler(methodChannel, null);
    });

    test('setAppHidden with a missing isHidden field throws INTERNAL',
        () async {
      final client = clientWith((_) async => <String, Object?>{});
      await expectLater(
        client.setAppHidden('com.example', true),
        throwsA(
          isA<PrivilegedException>().having((e) => e.code, 'code', 'INTERNAL'),
        ),
      );
    });

    test('setUninstallBlocked with a missing field throws INTERNAL',
        () async {
      final client = clientWith((_) async => <String, Object?>{});
      await expectLater(
        client.setUninstallBlocked('com.example', true),
        throwsA(
          isA<PrivilegedException>().having((e) => e.code, 'code', 'INTERNAL'),
        ),
      );
    });

    test('setAccessibilityEnabled with a missing field throws INTERNAL',
        () async {
      final client = clientWith((_) async => <String, Object?>{});
      await expectLater(
        client.setAccessibilityEnabled(true),
        throwsA(
          isA<PrivilegedException>().having((e) => e.code, 'code', 'INTERNAL'),
        ),
      );
    });

    test('isRecoveryCodeSet with a missing isSet field throws INTERNAL '
        'instead of routing to setup', () async {
      final client = clientWith((_) async => <String, Object?>{});
      await expectLater(
        client.isRecoveryCodeSet(),
        throwsA(
          isA<PrivilegedException>().having((e) => e.code, 'code', 'INTERNAL'),
        ),
      );
    });

    test('well-formed verified replies still pass through', () async {
      final client = clientWith((call) async {
        switch (call.method) {
          case 'setAppHidden':
            return {'isHidden': true};
          case 'isRecoveryCodeSet':
            return {'isSet': false};
          default:
            throw MissingPluginException('no mock for ${call.method}');
        }
      });
      expect(await client.setAppHidden('com.example', true), isTrue);
      expect(await client.isRecoveryCodeSet(), isFalse);
    });

    test('getApplicationRestrictions with a non-Map restrictions value '
        'throws instead of reading as "no restrictions"', () async {
      final client = clientWith((_) async => {'restrictions': 'bogus'});
      await expectLater(
        client.getApplicationRestrictions('com.example'),
        throwsA(
          isA<PrivilegedException>().having((e) => e.code, 'code', 'INTERNAL'),
        ),
      );
    });
  });

  group('H-1 challenge runner reachability (source scan)', () {
    test('ChallengeRunnerView is constructed ONLY in the Impulse Lock '
        'screen — never in the recovery gate or anywhere else', () {
      final libDir = Directory('lib');
      final constructors = <String>[];
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          final source = entity.readAsStringSync();
          // The class definition itself lives in challenges_ui.dart;
          // every CONSTRUCTION outside it is a call site.
          if (entity.path.endsWith('challenges_ui.dart')) continue;
          if (source.contains('ChallengeRunnerView(')) {
            constructors.add(entity.path);
          }
        }
      }
      expect(constructors, ['lib/ui/impulse_focus_screens.dart']);
      // And the gate file must not reference the runner or the views.
      final gate = File('lib/ui/recovery_ui.dart').readAsStringSync();
      expect(gate.contains('ChallengeRunnerView'), isFalse);
      expect(gate.contains('challenges_ui'), isFalse);
    });
  });

  group('H-1 impulse lock challenge early-end', () {
    const methodChannel = MethodChannel('dominanter/privileged');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final backing = <String, Object?>{};
    final suspendedCalls = <({List<String> packages, bool suspended})>[];

    tearDown(() => messenger.setMockMethodCallHandler(methodChannel, null));

    test('completeImpulseLockEarly releases exactly the recorded '
        'suspension and persists the completed lock', () async {
      suspendedCalls.clear();
      backing.clear();
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        final args =
            (call.arguments as Map?)?.cast<String, Object?>() ?? {};
        switch (call.method) {
          case 'getSetting':
            return {'value': backing['${args['store']}/${args['key']}']};
          case 'setSetting':
            backing['${args['store']}/${args['key']}'] = args['value'];
            return <String, Object?>{};
          case 'getImpulseConfig':
            return <String, Object?>{};
          case 'setAppSuspended':
            suspendedCalls.add((
              packages:
                  (args['packageNames'] as List).map((e) => '$e').toList(),
              suspended: args['suspended'] as bool,
            ));
            return {
              'results': [
                for (final p in (args['packageNames'] as List))
                  {'packageName': '$p', 'isSuspended': args['suspended']},
              ],
            };
          default:
            throw MissingPluginException('no mock for ${call.method}');
        }
      });
      final channel = PrivilegedChannel(methodChannel: methodChannel);
      final controller = AppController.test(channel);
      addTearDown(controller.dispose);

      // Configure an impulse lock that suspends two apps, then start it
      // the way both start paths do (record + suspend).
      await controller.config.setImpulseConfig(
        const ImpulseConfig(
          action: ImpulseAction.timerAndSuspend,
          durationMinutes: 60,
          suspendApps: ['com.a', 'com.b'],
        ),
      );
      await controller.startImpulseLock(const Duration(minutes: 60));
      await channel.setAppSuspended(
        ['com.a', 'com.b'],
        true,
        reason: 'IMPULSE_LOCK',
      );
      suspendedCalls.clear();
      expect(controller.impulseLock.active, isTrue);
      expect(controller.impulseLock.isComplete, isFalse);

      await controller.completeImpulseLockEarly();

      expect(controller.impulseLock.isComplete, isTrue);
      // Exactly one release, of exactly the recorded set.
      expect(suspendedCalls, hasLength(1));
      expect(suspendedCalls.single.packages, ['com.a', 'com.b']);
      expect(suspendedCalls.single.suspended, isFalse);
      // And the completed state is what got persisted.
      final persisted = await controller.config.getImpulseLock();
      expect(persisted.isComplete, isTrue);
    });
  });

  group('removal result honesty (field-failure pin)', () {
    Map<String, Object?> stepMap(String id, bool ok) => {
      'id': id,
      'ok': ok,
      'detail': '',
    };

    test('a failed post-removal verify step means NOT clean, even with '
        'the owner gone', () {
      final result = DeviceOwnerRemovalResult.fromMap({
        'isDeviceOwner': false,
        'steps': [
          stepMap('flag', true),
          stepMap('restrictions', true),
          stepMap('clearOwner', true),
          stepMap('verify', false),
        ],
      });
      expect(result.removed, isTrue);
      expect(result.clean, isFalse);
      expect(result.failedSteps.single.id, 'verify');
    });

    test('a failed notifications step also blocks a clean verdict', () {
      final result = DeviceOwnerRemovalResult.fromMap({
        'isDeviceOwner': false,
        'steps': [stepMap('notifications', false), stepMap('verify', true)],
      });
      expect(result.clean, isFalse);
    });

    test('all steps ok and owner gone is the only clean outcome', () {
      final result = DeviceOwnerRemovalResult.fromMap({
        'isDeviceOwner': false,
        'steps': [stepMap('verify', true)],
      });
      expect(result.clean, isTrue);
    });
  });
}
