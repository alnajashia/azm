// Parity contracts: unit tests pinning the ORIGINAL DeChainer behaviour
// that the full parity audit (docs/PARITY_AUDIT_FULL.md) found untested or
// encoded wrongly in the old suite. Each group names the original source
// of the contract. Production code is the re-port; these tests exist so
// the behaviours cannot silently drift again.
import 'dart:math';

import 'package:dominanter/data/config_store.dart';
import 'package:dominanter/data/privileged_channel.dart';
import 'package:dominanter/domain/challenges.dart';
import 'package:dominanter/domain/focus.dart';
import 'package:dominanter/domain/recovery.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isLooserWindows is per-minute coverage (PendingChange.kt)', () {
    test('an equal-length time SHIFT loosens (new minutes become allowed)', () {
      // 09:00-17:00 -> 10:00-18:00: same 480 minutes, different minutes.
      // Total-length comparison (the old bug) calls this neutral.
      expect(
        Loosening.isLooserWindows(
          oldWindows: const [(540, 1020)],
          newWindows: const [(600, 1080)],
        ),
        isTrue,
      );
    });

    test('identical windows do not loosen; strict narrowing does not loosen', () {
      expect(
        Loosening.isLooserWindows(
          oldWindows: const [(540, 1020)],
          newWindows: const [(540, 1020)],
        ),
        isFalse,
      );
      expect(
        Loosening.isLooserWindows(
          oldWindows: const [(480, 1080)],
          newWindows: const [(540, 1020)],
        ),
        isFalse,
      );
    });

    test('empty old list means always allowed: adding windows tightens', () {
      expect(
        Loosening.isLooserWindows(
          oldWindows: const [],
          newWindows: const [(540, 1020)],
        ),
        isFalse,
      );
      expect(
        Loosening.isLooserWindows(
          oldWindows: const [(540, 1020)],
          newWindows: const [],
        ),
        isTrue,
      );
    });

    test('weekly overload: a shift on ONE weekday loosens', () {
      const daily = [(540, 1020)];
      expect(
        Loosening.isLooserWindowsForWeek(
          oldDaily: daily,
          oldWeekly: null,
          newDaily: daily,
          newWeekly: const [
            [(540, 1020)],
            [(540, 1020)],
            [(600, 1080)], // Wednesday shifted, same length
            [(540, 1020)],
            [(540, 1020)],
            [(540, 1020)],
            [(540, 1020)],
          ],
        ),
        isTrue,
      );
      expect(
        Loosening.isLooserWindowsForWeek(
          oldDaily: daily,
          oldWeekly: null,
          newDaily: daily,
          newWeekly: null,
        ),
        isFalse,
      );
    });
  });

  group('isLooserRestrictions is containment + typed (PendingChange.kt)', () {
    test('String case: emptying or removing a non-empty string loosens', () {
      expect(
        Loosening.isLooserRestrictions(
          oldRestrictions: const {'k': 'abc'},
          newRestrictions: const {'k': ''},
        ),
        isTrue,
      );
      expect(
        Loosening.isLooserRestrictions(
          oldRestrictions: const {'k': 'abc'},
          newRestrictions: const {},
        ),
        isTrue,
      );
      expect(
        Loosening.isLooserRestrictions(
          oldRestrictions: const {'k': 'abc'},
          newRestrictions: const {'k': 'xyz'}, // different but non-empty
        ),
        isFalse,
      );
      expect(
        Loosening.isLooserRestrictions(
          oldRestrictions: const {'k': ''}, // was empty: nothing to loosen
          newRestrictions: const {},
        ),
        isFalse,
      );
    });

    test('list case is containment, not length', () {
      // Same length, one entry swapped out: the old length comparison
      // missed this entirely.
      expect(
        Loosening.isLooserRestrictions(
          oldRestrictions: const {
            'URLBlocklist': ['a.com', 'b.com']
          },
          newRestrictions: const {
            'URLBlocklist': ['a.com', 'c.com']
          },
        ),
        isTrue,
      );
      expect(
        Loosening.isLooserRestrictions(
          oldRestrictions: const {
            'URLBlocklist': ['a.com']
          },
          newRestrictions: const {
            'URLBlocklist': ['b.com', 'a.com'] // superset, reordered
          },
        ),
        isFalse,
      );
    });

    test('num case: zeroing/removing loosens; a smaller non-zero does not', () {
      expect(
        Loosening.isLooserRestrictions(
          oldRestrictions: const {'n': 5},
          newRestrictions: const {'n': 0},
        ),
        isTrue,
      );
      expect(
        Loosening.isLooserRestrictions(
          oldRestrictions: const {'n': 5},
          newRestrictions: const {},
        ),
        isTrue,
      );
      expect(
        Loosening.isLooserRestrictions(
          oldRestrictions: const {'n': 5},
          newRestrictions: const {'n': 3},
        ),
        isFalse,
      );
    });

    test('nested bundles recurse', () {
      expect(
        Loosening.isLooserRestrictions(
          oldRestrictions: const {
            'bundle': {'flag': true}
          },
          newRestrictions: const {
            'bundle': {'flag': false}
          },
        ),
        isTrue,
      );
      expect(
        Loosening.isLooserRestrictions(
          oldRestrictions: const {
            'bundle': {'flag': true}
          },
          newRestrictions: const {'bundle': 'not-a-bundle'},
        ),
        isTrue,
      );
    });
  });

  group('PendingChange deferral timing (PendingChange.kt schedule())', () {
    test('not applied mid-window; undo inside means NEVER applied', () async {
      var applyCount = 0;
      var undoCount = 0;
      final change = PendingChange(
        description: 'contract',
        direction: ChangeDirection.tightening,
        apply: () async => applyCount++,
        onUndo: () async => undoCount++,
        undoWindow: const Duration(milliseconds: 120),
      );
      await change.run();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(applyCount, 0); // still inside the window: nothing applied
      expect(change.isPending, isTrue);

      expect(await change.undo(), isTrue);
      expect(undoCount, 1);
      // Long after the window would have lapsed, the apply must not fire.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(applyCount, 0);
      expect(change.isUndone, isTrue);
    });

    test('an un-undone change applies exactly once when the window lapses', () async {
      var applyCount = 0;
      final change = PendingChange(
        description: 'contract',
        direction: ChangeDirection.tightening,
        apply: () async => applyCount++,
        undoWindow: const Duration(milliseconds: 60),
      );
      await change.run();
      expect(applyCount, 0);
      await change.done;
      expect(applyCount, 1);
      expect(change.isApplied, isTrue);
    });
  });

  group('Math contract (ChallengeScreens.kt MathChallenge)', () {
    test('wrong answer resets solved count to zero', () {
      final c = MathChallenge(random: Random(11))..start();
      c.submit(c.current.answer);
      c.submit(c.current.answer);
      c.submit(c.current.answer);
      expect(c.solved, 3);
      expect(c.submit(c.current.answer + 7), isFalse);
      expect(c.solved, 0);
    });

    test('operands stay in 10..98 and prompts are pure addition', () {
      final pattern = RegExp(r'^(\d+) \+ (\d+)$');
      var seen = 0;
      for (var seed = 100; seed < 124; seed++) {
        final c = MathChallenge(random: Random(seed))..start();
        while (!c.isComplete) {
          final m = pattern.firstMatch(c.current.prompt);
          expect(m, isNotNull, reason: c.current.prompt);
          final a = int.parse(m!.group(1)!);
          final b = int.parse(m.group(2)!);
          expect(a, inInclusiveRange(10, 98), reason: c.current.prompt);
          expect(b, inInclusiveRange(10, 98), reason: c.current.prompt);
          seen++;
          c.submit(c.current.answer);
        }
      }
      expect(seen, 24 * 5);
    });
  });

  group('Words contract (ChallengeScreens.kt WordChallenge)', () {
    test('advance is per-keystroke; mistakes never reset anything', () {
      final c = WordsChallenge(
        random: Random(2),
        wordPool: const ['crane', 'slate'],
        requiredWords: 2,
      )..start();

      // Scribble wrong letters first: index/input state only reflects
      // what is typed; there is no failure state to fall into.
      final target = c.currentWord;
      c.typeInput('zzzzz');
      expect(c.index, 0);
      expect(c.input, 'zzzzz');
      expect(c.charStates.every((s) => s == WordCharState.wrong), isTrue);

      // Erase and type it correctly, one keystroke at a time.
      c.typeInput('');
      expect(c.input, '');
      for (var i = 1; i < target.length; i++) {
        c.typeInput(target.substring(0, i));
        expect(c.index, 0, reason: 'advanced early at $i chars');
      }
      c.typeInput(target);
      expect(c.index, 1);
      expect(c.input, '');

      c.typeInput(c.currentWord);
      expect(c.isComplete, isTrue);
      expect(WordsChallenge.defaultRequiredWords, 32);
    });
  });

  group('Reading timing formula (ReadingChallenge.kt timeWords)', () {
    test('hand-computed: short pause after a comma', () {
      // 'Wait,' = 4 letters -> 300 + 4*45 = 480 -> [600, 1080]; ',' adds
      // a 250 ms short pause -> next starts 1330.
      // 'go' = 2 letters -> 300 + 2*45 = 390 -> [1330, 1720]; no pause.
      final r = ReadingTiming.timeWords('Wait, go');
      expect(r.words, hasLength(2));
      expect(r.words[0].startTime, const Duration(milliseconds: 600));
      expect(r.words[0].endTime, const Duration(milliseconds: 1080));
      expect(r.words[1].startTime, const Duration(milliseconds: 1330));
      expect(r.words[1].endTime, const Duration(milliseconds: 1720));
      expect(r.total, const Duration(milliseconds: 1720));
    });

    test('hand-computed: long pause after a full stop; digits count as letters', () {
      // 'abc123' = 6 letters/digits -> 300 + 6*45 = 570 -> [600, 1170];
      // last char '3' -> no pause. 'End.' = 3 letters -> 435 ->
      // [1170, 1605]; '.' adds 500 -> total 2105.
      final r = ReadingTiming.timeWords('abc123 End.');
      expect(r.words[0].endTime, const Duration(milliseconds: 1170));
      expect(r.words[1].startTime, const Duration(milliseconds: 1170));
      expect(r.words[1].endTime, const Duration(milliseconds: 1605));
      expect(r.total, const Duration(milliseconds: 2105));
    });

    test('constants are the original pace values', () {
      expect(ReadingTiming.wordBaseMs, 300);
      expect(ReadingTiming.letterMs, 45);
      expect(ReadingTiming.shortPauseMs, 250);
      expect(ReadingTiming.longPauseMs, 500);
      expect(ReadingTiming.leadInMs, 600);
    });
  });

  group('Focus contracts (FocusMode.kt / FocusCycle)', () {
    test('resume re-enters the paused BREAK, not focus', () {
      final start = DateTime(2026, 3, 1, 10);
      var s = FocusSession(
        config: const FocusConfig(),
        phase: FocusPhase.longBreak,
        phaseStartedAt: start,
        phaseDuration: const Duration(minutes: 15),
        completedFocusPeriods: 4,
      );
      s = s.pause(start.add(const Duration(minutes: 6)));
      expect(s.pausedFrom, FocusPhase.longBreak);
      s = s.resume(start.add(const Duration(hours: 2)));
      expect(s.phase, FocusPhase.longBreak);
      expect(
        s.remainingAt(start.add(const Duration(hours: 2))).inMilliseconds,
        closeTo(const Duration(minutes: 9).inMilliseconds, 1000),
      );
    });

    test('break end parks in WAITING when autoStartFocus is false', () {
      final start = DateTime(2026, 3, 1, 10);
      const cfg = FocusConfig(autoStartFocus: false);
      final s = FocusSession(
        config: cfg,
        phase: FocusPhase.breakTime,
        phaseStartedAt: start,
        phaseDuration: const Duration(minutes: 5),
        completedFocusPeriods: 1,
      );
      final next = s.advance(start.add(const Duration(minutes: 5)));
      expect(next.phase, FocusPhase.waiting);
      expect(next.isWaiting, isTrue);
    });

    test('break end goes straight to FOCUS when autoStartFocus is true', () {
      final start = DateTime(2026, 3, 1, 10);
      const cfg = FocusConfig(autoStartFocus: true);
      final s = FocusSession(
        config: cfg,
        phase: FocusPhase.breakTime,
        phaseStartedAt: start,
        phaseDuration: const Duration(minutes: 5),
        completedFocusPeriods: 1,
      );
      final next = s.advance(start.add(const Duration(minutes: 5)));
      expect(next.phase, FocusPhase.focus);
    });

    test('clamp edges are the original bounds 5-120 / 1-30 / 5-60 / 2-8', () {
      expect(FocusConfig.clampFocusMinutes(4), 5);
      expect(FocusConfig.clampFocusMinutes(5), 5);
      expect(FocusConfig.clampFocusMinutes(120), 120);
      expect(FocusConfig.clampFocusMinutes(121), 120);
      expect(FocusConfig.clampBreakMinutes(0), 1);
      expect(FocusConfig.clampBreakMinutes(30), 30);
      expect(FocusConfig.clampBreakMinutes(31), 30);
      expect(FocusConfig.clampLongBreakMinutes(4), 5);
      expect(FocusConfig.clampLongBreakMinutes(60), 60);
      expect(FocusConfig.clampLongBreakMinutes(61), 60);
      expect(FocusConfig.clampCycles(1), 2);
      expect(FocusConfig.clampCycles(8), 8);
      expect(FocusConfig.clampCycles(9), 8);
      // copyWith clamps too (the original coerces in every setter).
      const c = FocusConfig();
      expect(c.copyWith(focusMinutes: 500).focusMinutes, 120);
      expect(c.copyWith(cyclesBeforeLongBreak: 0).cyclesBeforeLongBreak, 2);
    });
  });

  group('Usage warnings default (UsageWarningSettings DEFAULT_ENABLED)', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const methodChannel = MethodChannel('dominanter/privileged');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() {
      messenger.setMockMethodCallHandler(methodChannel, null);
    });

    ConfigStore storeReturning(Map<String, Object?> values) {
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        if (call.method == 'getSetting') {
          final key = (call.arguments as Map)['key'] as String;
          return {'value': values[key]};
        }
        throw MissingPluginException('no mock for ${call.method}');
      });
      return ConfigStore(PrivilegedChannel(methodChannel: methodChannel));
    }

    test('unset enabled reads as TRUE (the original default)', () async {
      final store = storeReturning(const {});
      final result = await store.getUsageWarnings();
      expect(result.enabled, isTrue);
      // The original's default stages (ids are assigned on read, so
      // compare the behavioural fields, not object identity).
      expect(
        result.stages.map((s) => (s.minutesBefore, s.type, s.vibrationCount)),
        defaultUsageWarningStages
            .map((s) => (s.minutesBefore, s.type, s.vibrationCount)),
      );
    });

    test('an explicitly stored false is respected', () async {
      final store = storeReturning(const {'enabled': false});
      final result = await store.getUsageWarnings();
      expect(result.enabled, isFalse);
    });
  });
}
