import 'dart:math';

import 'package:azm/domain/challenges.dart';
import 'package:azm/domain/focus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MathChallenge (original: addition only, reset on wrong)', () {
    test('requires 5 correct answers to complete', () {
      final challenge = MathChallenge(random: Random(42))..start();
      expect(MathChallenge.requiredProblems, 5);
      expect(challenge.isComplete, isFalse);

      for (var i = 0; i < MathChallenge.requiredProblems; i++) {
        expect(challenge.submit(challenge.current.answer), isTrue);
        expect(challenge.solved, i + 1);
      }
      expect(challenge.isComplete, isTrue);
      expect(challenge.submit(0), isFalse); // already complete
    });

    test('a wrong answer resets progress to zero', () {
      final challenge = MathChallenge(random: Random(3))..start();
      expect(challenge.submit(challenge.current.answer), isTrue);
      expect(challenge.submit(challenge.current.answer), isTrue);
      expect(challenge.solved, 2);

      expect(challenge.submit(challenge.current.answer + 1), isFalse);
      expect(challenge.solved, 0); // the original's reset-to-zero branch

      // An unparseable/empty answer is a wrong answer too.
      expect(challenge.submit(challenge.current.answer), isTrue);
      expect(challenge.submit(null), isFalse);
      expect(challenge.solved, 0);
    });

    test('problems are addition only with both operands in 10..98', () {
      final pattern = RegExp(r'^(\d+) \+ (\d+)$');
      var sampled = 0;
      for (var seed = 0; seed < 40; seed++) {
        final challenge = MathChallenge(random: Random(seed))..start();
        while (!challenge.isComplete) {
          final p = challenge.current;
          final m = pattern.firstMatch(p.prompt);
          expect(m, isNotNull, reason: 'not an addition prompt: ${p.prompt}');
          final a = int.parse(m!.group(1)!);
          final b = int.parse(m.group(2)!);
          expect(a, inInclusiveRange(10, 98));
          expect(b, inInclusiveRange(10, 98));
          expect(p.answer, a + b);
          expect(p.check(p.answer), isTrue);
          expect(p.check(p.answer + 1), isFalse);
          sampled++;
          challenge.submit(p.answer);
        }
      }
      expect(sampled, 40 * MathChallenge.requiredProblems);
    });
  });

  group('WordsChallenge (original: per-keystroke, no failure state)', () {
    test('typing is checked per keystroke and advances on the exact word', () {
      final challenge = WordsChallenge(
        random: Random(1),
        wordPool: const ['apple', 'berry'],
        requiredWords: 2,
      )..start();

      final word = challenge.currentWord;
      challenge.typeInput(word.substring(0, 3));
      expect(challenge.input, word.substring(0, 3));
      expect(challenge.index, 0);
      expect(
        challenge.charStates,
        [
          WordCharState.correct,
          WordCharState.correct,
          WordCharState.correct,
          WordCharState.untyped,
          WordCharState.untyped,
        ],
      );

      // A wrong character is only *shown* wrong — no penalty, no reset.
      final wrongChar = word[3] == 'x' ? 'z' : 'x';
      challenge.typeInput('${word.substring(0, 3)}$wrongChar');
      expect(challenge.charStates[3], WordCharState.wrong);
      expect(challenge.index, 0);
      expect(challenge.input, '${word.substring(0, 3)}$wrongChar');

      // Completing the word (any case) advances and clears the input.
      challenge.typeInput(word.toUpperCase());
      expect(challenge.index, 1);
      expect(challenge.input, '');

      challenge.typeInput(challenge.currentWord);
      expect(challenge.isComplete, isTrue);
    });

    test('input is truncated to the word length', () {
      final challenge = WordsChallenge(
        random: Random(5),
        wordPool: const ['apple'],
        requiredWords: 1,
      )..start();
      // Typing past the end truncates to the target, which equals it.
      challenge.typeInput('applepie');
      expect(challenge.isComplete, isTrue);
    });

    test('defaults mirror the original: 32 words from a 200-word 5-letter pool', () {
      expect(WordsChallenge.defaultRequiredWords, 32);
      expect(WordsChallenge().requiredWords, 32);
      expect(WordsChallenge.defaultWordPool, hasLength(200));
      expect(
        WordsChallenge.defaultWordPool.every((w) => w.length == 5),
        isTrue,
      );
      final challenge = WordsChallenge(random: Random(9))..start();
      expect(challenge.sequence, hasLength(WordsChallenge.selectedWords));
    });
  });

  group('ReadingChallenge (original timing: 300 + 45/letter + pauses)', () {
    test('passage timeline follows the original pace formula', () {
      final challenge = ReadingChallenge(
        passages: const [ReadingPassage('t', 'One two.')],
        requiredPassages: 2,
      );
      // 'One': 600 lead-in, 300 + 3*45 = 435 -> [600, 1035], no pause.
      // 'two.': 3 letters, 435 -> [1035, 1470], '.' pause 500 -> total 1970.
      expect(challenge.totalDuration, const Duration(milliseconds: 1970));
      expect(challenge.timedWords, hasLength(2));
      expect(challenge.timedWords[0].startTime, const Duration(milliseconds: 600));
      expect(challenge.timedWords[0].endTime, const Duration(milliseconds: 1035));
      expect(challenge.timedWords[1].startTime, const Duration(milliseconds: 1035));
      expect(challenge.timedWords[1].endTime, const Duration(milliseconds: 1470));

      expect(challenge.revealedWords, isEmpty); // still in the lead-in
      challenge.advance(const Duration(milliseconds: 600));
      expect(challenge.revealedWords, ['One']);
      expect(challenge.isPassageComplete, isFalse);
      expect(challenge.next(), isFalse); // locked until fully read

      challenge.advance(const Duration(milliseconds: 435));
      expect(challenge.revealedWords, ['One', 'two.']);
      challenge.advance(const Duration(milliseconds: 935));
      expect(challenge.isPassageComplete, isTrue);

      expect(challenge.next(), isTrue);
      expect(challenge.passageIndex, 1);
      expect(challenge.revealedWords, isEmpty);
      expect(challenge.elapsed, Duration.zero);

      challenge.advance(const Duration(seconds: 10)); // clamps at total
      expect(challenge.elapsed, challenge.totalDuration);
      expect(challenge.next(), isTrue);
      expect(challenge.isComplete, isTrue);
      expect(challenge.next(), isFalse);
    });

    test('Tetris is the only challenge unavailable in v1', () {
      expect(ChallengeType.tetris.isAvailableInV1, isFalse);
      expect(ChallengeType.math.isAvailableInV1, isTrue);
      expect(ChallengeType.words.isAvailableInV1, isTrue);
      expect(ChallengeType.reading.isAvailableInV1, isTrue);
    });
  });

  group('FocusSession', () {
    const config = FocusConfig(
      focusMinutes: 25,
      breakMinutes: 5,
      longBreakMinutes: 15,
      cyclesBeforeLongBreak: 2,
      autoStartFocus: true,
    );

    test('phase cycle: focus -> break -> focus -> long break (cycle 2)', () {
      final t0 = DateTime(2026, 1, 1, 9);
      var s = const FocusSession(config: config).start(t0);
      expect(s.phase, FocusPhase.focus);
      expect(s.completedFocusPeriods, 0);

      s = s.advance(t0.add(const Duration(minutes: 25)));
      expect(s.phase, FocusPhase.breakTime);
      expect(s.completedFocusPeriods, 1);

      s = s.advance(t0.add(const Duration(minutes: 30)));
      expect(s.phase, FocusPhase.focus); // auto-start is on

      s = s.advance(t0.add(const Duration(minutes: 55)));
      expect(s.phase, FocusPhase.longBreak); // 2nd completed focus period
      expect(s.completedFocusPeriods, 2);

      s = s.advance(t0.add(const Duration(minutes: 70)));
      expect(s.phase, FocusPhase.focus);
      expect(s.completedFocusPeriods, 0); // long break resets the cycle
    });

    test('without auto-start, a finished break parks in WAITING', () {
      const cfg = FocusConfig(cyclesBeforeLongBreak: 4); // autoStart off
      final t0 = DateTime(2026, 1, 1, 9);
      var s = const FocusSession(config: cfg).start(t0);
      s = s.advance(t0.add(const Duration(minutes: 25)));
      expect(s.phase, FocusPhase.breakTime);
      s = s.advance(t0.add(const Duration(minutes: 30)));
      expect(s.phase, FocusPhase.waiting);
      expect(s.isWaiting, isTrue);
      // Leaving WAITING keeps the completed-focus count.
      s = s.beginFocus(t0.add(const Duration(minutes: 31)));
      expect(s.phase, FocusPhase.focus);
      expect(s.completedFocusPeriods, 1);
    });

    test('remaining time falls back to the wall clock without a monotonic anchor', () {
      final t0 = DateTime(2026, 1, 1, 9);
      final s = FocusSession(
        config: config,
        phase: FocusPhase.focus,
        phaseStartedAt: t0,
        phaseDuration: const Duration(minutes: 25),
      );
      expect(s.remainingAt(t0), const Duration(minutes: 25));
      expect(s.remainingAt(t0.add(const Duration(minutes: 10))),
          const Duration(minutes: 15));
      expect(s.isPhaseCompleteAt(t0.add(const Duration(minutes: 26))), isTrue);
    });

    test('pause freezes remaining; resume re-enters the SAME phase', () {
      final t0 = DateTime(2026, 1, 1, 9);
      // Pause during a BREAK: the original's resume() re-anchors the
      // current phase instead of forcing focus.
      var s = FocusSession(
        config: config,
        phase: FocusPhase.breakTime,
        phaseStartedAt: t0,
        phaseDuration: const Duration(minutes: 5),
      );
      s = s.pause(t0.add(const Duration(minutes: 2)));
      expect(s.isPaused, isTrue);
      expect(s.pausedFrom, FocusPhase.breakTime);
      expect(s.remainingAt(t0.add(const Duration(hours: 5))),
          const Duration(minutes: 3)); // frozen while paused

      final t1 = t0.add(const Duration(hours: 5));
      s = s.resume(t1);
      expect(s.phase, FocusPhase.breakTime); // not focus
      expect(
        s.remainingAt(t1).inMilliseconds,
        closeTo(const Duration(minutes: 3).inMilliseconds, 1000),
      );
    });

    test('config json round-trip preserves values; out-of-range values clamp', () {
      const c = FocusConfig(focusMinutes: 50, suspendApps: ['a.b']);
      final back = FocusConfig.fromJson(c.toJson());
      expect(back.focusMinutes, 50);
      expect(back.breakMinutes, 5);
      expect(back.suspendApps, ['a.b']);
      expect(const FocusConfig().cyclesBeforeLongBreak, 4);
      expect(const FocusConfig().autoStartFocus, isFalse);
      expect(const FocusConfig().soundEnabled, isTrue);
      expect(const FocusConfig().vibrationEnabled, isTrue);

      final clamped = FocusConfig.fromJson(const {
        'focusMinutes': 1000,
        'breakMinutes': 0,
        'longBreakMinutes': 1,
        'cyclesBeforeLongBreak': 99,
      });
      expect(clamped.focusMinutes, 120);
      expect(clamped.breakMinutes, 1);
      expect(clamped.longBreakMinutes, 5);
      expect(clamped.cyclesBeforeLongBreak, 8);
    });
  });
}
