/// Item 2 regression (2026-11-19): the focus timer must not reset to
/// the full phase duration when the app returns after a process
/// restart. The native state carries elapsed-realtime anchors; the
/// channel now captures the native<->Dart clock offset on restore
/// (`getFocusSession`), so a mid-phase snapshot reconstructs its true
/// remaining time instead of 25:00.
library;

import 'package:azm/data/privileged_channel.dart';
import 'package:azm/domain/focus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'azm/privileged';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methodChannel = MethodChannel(channelName);

  // Native elapsed-realtime "now": 300000 ms since boot.
  const nativeNowMs = 300000;
  // The phase started 60 s ago and lasts 25 minutes.
  const phaseStartedMs = nativeNowMs - 60000;
  const phaseDurationMs = 25 * 60 * 1000;
  const deadlineMs = phaseStartedMs + phaseDurationMs;

  setUp(() {
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        case 'getFocusSession':
          return <String, dynamic>{
            'phase': 'focus',
            'phaseStartedElapsedMs': phaseStartedMs,
            'phaseDurationMs': phaseDurationMs,
            'completedFocusInCycle': 1,
            'pausedFrom': null,
            'deadlineElapsedMs': deadlineMs,
          };
        case 'getElapsedRealtimeMs':
          return <String, dynamic>{'elapsedRealtimeMs': nativeNowMs};
        default:
          return null;
      }
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  test(
    'a restored mid-phase session shows its true remaining time',
    () async {
      final channel = PrivilegedChannel();
      final state = await channel.getFocusSession();
      expect(state, isNotNull);
      // The offset must have been captured on restore.
      expect(channel.focusElapsedRealtimeOffsetMs, isNotNull);

      final session = state!.toFocusSession(
        const FocusConfig(),
        elapsedRealtimeOffsetMs: channel.focusElapsedRealtimeOffsetMs,
        now: DateTime.now(),
      );
      final remaining = session.remainingAt(DateTime.now());
      // ~24 minutes remain (25:00 - 1:00 elapsed); allow a few seconds
      // of real time between capture and assertion.
      expect(remaining.inSeconds, greaterThan(23 * 60));
      expect(remaining.inSeconds, lessThan(24 * 60 + 5));
    },
  );

  test('without an offset the display still falls back to full duration', () {
    const state = NativeFocusSessionState(
      phase: 'focus',
      phaseStartedElapsedMs: phaseStartedMs,
      phaseDurationMs: phaseDurationMs,
      completedFocusInCycle: 1,
      pausedFrom: null,
      deadlineElapsedMs: deadlineMs,
    );
    final session = state.toFocusSession(
      const FocusConfig(),
      now: DateTime.now(),
    );
    // Anchored at now with the full duration (minus the milliseconds
    // between anchoring and this read).
    final remaining = session.remainingAt(DateTime.now());
    expect(remaining.inSeconds, greaterThanOrEqualTo(24 * 60 + 55));
    expect(remaining.inSeconds, lessThanOrEqualTo(25 * 60));
  });
}
