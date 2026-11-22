// Total focus repetitions (user request 2026-11-22): the session
// ends after the configured number of focus phases instead of
// looping forever. Example from the user: total cycles = 2 and
// cycles before long break = 2 → focus, short break, focus, long
// break, then the session stops for good.
import 'dart:io';

import 'package:azm/domain/focus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FocusConfig.totalCycles', () {
    test('round-trips through JSON', () {
      const c = FocusConfig(totalCycles: 2);
      expect(FocusConfig.fromJson(c.toJson()).totalCycles, 2);
    });

    test('old stored configs without the key default to 4', () {
      expect(FocusConfig.fromJson(const {}).totalCycles, 4);
    });

    test('clamps to 1..12', () {
      expect(FocusConfig.fromJson(const {'totalCycles': 0}).totalCycles, 1);
      expect(FocusConfig.fromJson(const {'totalCycles': 99}).totalCycles, 12);
      expect(const FocusConfig(totalCycles: 3).copyWith(totalCycles: 0).totalCycles, 1);
    });
  });

  group('session ends after the total repetitions', () {
    FocusSession run(FocusConfig config, int advances) {
      var s = FocusSession(config: config).start(DateTime(2026, 1, 1));
      for (var i = 0; i < advances; i++) {
        s = s.advance(DateTime(2026, 1, 1).add(Duration(minutes: i + 1)));
      }
      return s;
    }

    test('total 2, before-long 2: focus, short, focus, long, done', () {
      const config = FocusConfig(
        totalCycles: 2,
        cyclesBeforeLongBreak: 2,
        autoStartFocus: true,
      );
      var s = FocusSession(config: config).start(DateTime(2026, 1, 1));
      expect(s.phase, FocusPhase.focus);
      s = s.advance(DateTime(2026, 1, 1, 1));
      expect(s.phase, FocusPhase.breakTime);
      s = s.advance(DateTime(2026, 1, 1, 2));
      expect(s.phase, FocusPhase.focus);
      s = s.advance(DateTime(2026, 1, 1, 3));
      expect(s.phase, FocusPhase.longBreak);
      expect(s.totalCompletedFocusPeriods, 2);
      s = s.advance(DateTime(2026, 1, 1, 4));
      expect(s.phase, FocusPhase.done);
    });

    test('total 3, before-long 2: ends after the third focus break', () {
      const config = FocusConfig(
        totalCycles: 3,
        cyclesBeforeLongBreak: 2,
        autoStartFocus: true,
      );
      final phases = <FocusPhase>[];
      var s = FocusSession(config: config).start(DateTime(2026, 1, 1));
      phases.add(s.phase);
      for (var i = 0; i < 6; i++) {
        s = s.advance(DateTime(2026, 1, 1).add(Duration(hours: i + 1)));
        phases.add(s.phase);
      }
      expect(phases, [
        FocusPhase.focus,
        FocusPhase.breakTime,
        FocusPhase.focus,
        FocusPhase.longBreak,
        FocusPhase.focus,
        FocusPhase.breakTime,
        FocusPhase.done,
      ]);
    });

    test('without auto-start the final break ends instead of WAITING', () {
      const config = FocusConfig(
        totalCycles: 1,
        cyclesBeforeLongBreak: 4,
        autoStartFocus: false,
      );
      final s = run(config, 2);
      expect(s.phase, FocusPhase.done);
    });

    test('skipping the final break ends the session', () {
      const config = FocusConfig(
        totalCycles: 2,
        cyclesBeforeLongBreak: 2,
        autoStartFocus: true,
      );
      final s = run(config, 3); // in the long break, total reached
      expect(s.phase, FocusPhase.longBreak);
      expect(s.skipBreak(DateTime(2026, 1, 1, 5)).phase, FocusPhase.done);
    });

    test('skipping an earlier break still starts the next focus', () {
      const config = FocusConfig(
        totalCycles: 4,
        cyclesBeforeLongBreak: 4,
        autoStartFocus: true,
      );
      final s = run(config, 1); // in the first short break
      expect(s.phase, FocusPhase.breakTime);
      expect(s.skipBreak(DateTime(2026, 1, 1, 5)).phase, FocusPhase.focus);
    });
  });

  group('native wiring pins', () {
    final kt = File(
      'android/app/src/main/kotlin/com/alnajashia/azm/focus/FocusSessionStore.kt',
    ).readAsStringSync();

    test('total cycles config is snapshotted from the Dart JSON', () {
      expect(kt.contains('KEY_TOTAL_CYCLES = "total_cycles"'), isTrue);
      expect(kt.contains('fun dartConfigTotalCycles()'), isTrue);
      expect(kt.contains('putInt(KEY_TOTAL_CYCLES, dartConfigTotalCycles())'), isTrue);
    });

    test('sync ends the session when the total is reached', () {
      expect(kt.contains('total cycles reached, session ends'), isTrue);
      expect(kt.contains('KEY_TOTAL_COMPLETED'), isTrue);
    });

    test('the wire shape carries the session total', () {
      expect(kt.contains('"totalCompletedFocus"'), isTrue);
    });
  });
}
