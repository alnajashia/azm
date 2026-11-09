import 'dart:math';

import 'package:dominanter/domain/challenges.dart';
import 'package:dominanter/domain/focus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MathChallenge', () {
    test('requires 5 correct answers; wrong answers do not advance', () {
      final challenge = MathChallenge(random: Random(42))..start();
      expect(challenge.problems.length, MathChallenge.requiredProblems);
      expect(challenge.isComplete, isFalse);

      final wrong = challenge.current.answer + 1;
      expect(challenge.submit(wrong), isFalse);
      expect(challenge.solved, 0);

      for (var i = 0; i < MathChallenge.requiredProblems; i++) {
        expect(challenge.submit(challenge.current.answer), isTrue);
      }
      expect(challenge.isComplete, isTrue);
      expect(challenge.submit(0), isFalse); // already complete
    });

    test('all four operations produce self-consistent problems', () {
      final challenge = MathChallenge(random: Random(7))..start();
      for (final p in challenge.problems) {
        expect(p.check(p.answer), isTrue);
        expect(p.check(p.answer + 1000), isFalse);
      }
    });
  });

  group('WordsChallenge', () {
    test('a mistake restarts the streak', () {
      final challenge = WordsChallenge(
        random: Random(1),
        wordPool: const ['alpha', 'beta'],
        requiredWords: 3,
      )..start();

      expect(challenge.submit(challenge.currentWord), isTrue);
      expect(challenge.index, 1);
      expect(challenge.submit('definitely-wrong'), isFalse);
      expect(challenge.index, 0); // streak reset — the friction is the point

      for (var i = 0; i < 3; i++) {
        expect(challenge.submit(challenge.currentWord), isTrue);
      }
      expect(challenge.isComplete, isTrue);
    });
  });

  group('ReadingChallenge', () {
    test('words reveal one tick at a time; passages advance; completes', () {
      final challenge = ReadingChallenge(
        passages: const [ReadingPassage('t', 'one two three')],
        requiredPassages: 2,
      );
      expect(challenge.revealedWords, isEmpty);
      challenge.tick();
      expect(challenge.revealedWords, ['one']);
      challenge.tick();
      challenge.tick();
      expect(challenge.revealedWords, ['one', 'two', 'three']);
      expect(challenge.isComplete, isFalse);
      challenge.tick(); // end of passage 1
      expect(challenge.passageIndex, 1);
      expect(challenge.revealedWords, isEmpty);
      challenge.tick();
      challenge.tick();
      challenge.tick();
      challenge.tick(); // end of passage 2
      expect(challenge.isComplete, isTrue);
      expect(challenge.tick(), isFalse);
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
    );

    test('phase cycle: focus -> break -> focus -> long break (cycle 2)', () {
      final t0 = DateTime(2026, 1, 1, 9);
      var s = const FocusSession(config: config).start(t0);
      expect(s.phase, FocusPhase.focus);
      expect(s.remainingAt(t0), const Duration(minutes: 25));
      expect(s.remainingAt(t0.add(const Duration(minutes: 10))),
          const Duration(minutes: 15));
      expect(s.isPhaseCompleteAt(t0.add(const Duration(minutes: 26))), isTrue);

      s = s.advance(t0.add(const Duration(minutes: 25)));
      expect(s.phase, FocusPhase.breakTime);
      expect(s.completedFocusPeriods, 1);

      s = s.advance(t0.add(const Duration(minutes: 30)));
      expect(s.phase, FocusPhase.focus);

      s = s.advance(t0.add(const Duration(minutes: 55)));
      expect(s.phase, FocusPhase.longBreak); // 2nd completed focus period
      expect(s.completedFocusPeriods, 2);
    });

    test('pause stores remaining; resume re-enters focus with it', () {
      final t0 = DateTime(2026, 1, 1, 9);
      var s = const FocusSession(config: config).start(t0);
      s = s.pause(t0.add(const Duration(minutes: 10)));
      expect(s.isPaused, isTrue);
      expect(s.remainingAt(t0.add(const Duration(hours: 5))),
          const Duration(minutes: 15)); // frozen while paused
      s = s.resume(t0.add(const Duration(hours: 5)));
      expect(s.phase, FocusPhase.focus);
      expect(s.remainingAt(t0.add(const Duration(hours: 5))),
          const Duration(minutes: 15));
    });

    test('config json round-trip preserves v1 defaults and values', () {
      const c = FocusConfig(focusMinutes: 50, suspendApps: ['a.b']);
      final back = FocusConfig.fromJson(c.toJson());
      expect(back.focusMinutes, 50);
      expect(back.breakMinutes, 5);
      expect(back.suspendApps, ['a.b']);
      expect(const FocusConfig().cyclesBeforeLongBreak, 4);
    });
  });
}
