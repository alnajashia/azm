import 'package:azm/domain/recovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Loosening.isLooserLimit', () {
    test('raising a daily limit loosens', () {
      expect(
        Loosening.isLooserLimit(oldDaily: 60, oldWeekly: null, newDaily: 90, newWeekly: null),
        isTrue,
      );
    });

    test('lowering a daily limit tightens', () {
      expect(
        Loosening.isLooserLimit(oldDaily: 90, oldWeekly: null, newDaily: 60, newWeekly: null),
        isFalse,
      );
    });

    test('removing a limit loosens (no limit = unbounded)', () {
      expect(
        Loosening.isLooserLimit(oldDaily: 60, oldWeekly: null, newDaily: 0, newWeekly: null),
        isTrue,
      );
    });

    test('adding a limit where none existed tightens', () {
      expect(
        Loosening.isLooserLimit(oldDaily: 0, oldWeekly: null, newDaily: 60, newWeekly: null),
        isFalse,
      );
    });

    test('raising any single weekday loosens even if others tighten', () {
      expect(
        Loosening.isLooserLimit(
          oldDaily: null,
          oldWeekly: const [60, 60, 60, 60, 60, 60, 60],
          newDaily: null,
          newWeekly: const [30, 30, 30, 30, 30, 30, 120],
        ),
        isTrue,
      );
    });
  });

  group('Loosening.isLooserWindows', () {
    test('removing all windows loosens', () {
      expect(
        Loosening.isLooserWindows(oldWindows: const [(420, 1260)], newWindows: const []),
        isTrue,
      );
    });

    test('widening a window loosens', () {
      expect(
        Loosening.isLooserWindows(
          oldWindows: const [(540, 1020)],
          newWindows: const [(480, 1080)],
        ),
        isTrue,
      );
    });

    test('narrowing a window tightens', () {
      expect(
        Loosening.isLooserWindows(
          oldWindows: const [(480, 1080)],
          newWindows: const [(540, 1020)],
        ),
        isFalse,
      );
    });

    test('midnight-spanning windows are measured correctly', () {
      // 22:00-02:00 = 240 min; widening to 21:00-03:00 = 360 min loosens.
      expect(
        Loosening.isLooserWindows(
          oldWindows: const [(1320, 120)],
          newWindows: const [(1260, 180)],
        ),
        isTrue,
      );
    });
  });

  group('Loosening.isLooserRestrictions', () {
    test('dropping a key loosens', () {
      expect(
        Loosening.isLooserRestrictions(
          oldRestrictions: const {'URLBlocklist': ['a.com']},
          newRestrictions: const {},
        ),
        isTrue,
      );
    });

    test('boolean true -> false loosens', () {
      expect(
        Loosening.isLooserRestrictions(
          oldRestrictions: const {'ForceGoogleSafeSearch': true},
          newRestrictions: const {'ForceGoogleSafeSearch': false},
        ),
        isTrue,
      );
    });

    test('shrinking a blocklist loosens; growing it does not', () {
      expect(
        Loosening.isLooserRestrictions(
          oldRestrictions: const {
            'URLBlocklist': ['a.com', 'b.com']
          },
          newRestrictions: const {
            'URLBlocklist': ['a.com']
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
            'URLBlocklist': ['a.com', 'b.com']
          },
        ),
        isFalse,
      );
    });
  });

  group('Loosening.forProtectionToggle', () {
    test('turning a protection off loosens, on tightens', () {
      expect(
        Loosening.forProtectionToggle(wasOn: true, isOn: false),
        ChangeDirection.loosening,
      );
      expect(
        Loosening.forProtectionToggle(wasOn: false, isOn: true),
        ChangeDirection.tightening,
      );
      expect(
        Loosening.forProtectionToggle(wasOn: true, isOn: true),
        ChangeDirection.neutral,
      );
    });
  });

  group('PendingChange undo window (original: deferred apply)', () {
    test('run() only schedules: nothing is applied during the window', () async {
      var applied = false;
      var undoCallbacks = 0;
      final change = PendingChange(
        description: 'test',
        direction: ChangeDirection.tightening,
        apply: () async => applied = true,
        onUndo: () async => undoCallbacks++,
      );
      addTearDown(change.dispose);
      await change.run();
      expect(applied, isFalse); // deferred — NOT apply-then-revert
      expect(change.isPending, isTrue);
      expect(change.isApplied, isFalse);
      expect(change.canUndo, isTrue);

      // Undo inside the window: the change is never applied at all.
      expect(await change.undo(), isTrue);
      expect(applied, isFalse);
      expect(change.isUndone, isTrue);
      expect(undoCallbacks, 1);
      await change.done; // settled
      expect(await change.undo(), isFalse); // cannot undo twice
      expect(undoCallbacks, 1);
    });

    test('when the window lapses the change applies exactly once', () async {
      var applyCount = 0;
      final change = PendingChange(
        description: 'test',
        direction: ChangeDirection.tightening,
        apply: () async => applyCount++,
        undoWindow: const Duration(milliseconds: 60),
      );
      await change.run();
      expect(applyCount, 0);
      await change.done; // window lapses -> commit
      expect(applyCount, 1);
      expect(change.isApplied, isTrue);
      expect(change.canUndo, isFalse);
      expect(await change.undo(), isFalse); // too late: the change stands
      expect(applyCount, 1);
    });

    test('undo attempted after the (injected) clock passes the window commits instead', () async {
      var now = DateTime(2026, 1, 1, 12);
      var applied = false;
      final change = PendingChange(
        description: 'test',
        direction: ChangeDirection.tightening,
        apply: () async => applied = true,
        now: () => now,
      );
      await change.run();
      expect(applied, isFalse);
      now = now.add(const Duration(seconds: 6)); // past the 5 s window
      expect(await change.undo(), isFalse);
      expect(applied, isTrue); // lapsed window => the change stands
      expect(change.isApplied, isTrue);
    });

    test('commitNow applies a pending change immediately', () async {
      var applied = false;
      final change = PendingChange(
        description: 'test',
        direction: ChangeDirection.tightening,
        apply: () async => applied = true,
      );
      addTearDown(change.dispose);
      await change.run();
      await change.commitNow();
      expect(applied, isTrue);
      expect(change.isApplied, isTrue);
    });
  });

  group('RecoverySession', () {
    test('10-minute in-memory session: start, expiry by clock, renew, end', () {
      var now = DateTime(2026, 1, 1, 12);
      var mono = Duration.zero;
      final session = RecoverySession(
        now: () => now,
        monotonicNow: () => mono,
      );
      addTearDown(session.dispose);

      expect(session.isActive, isFalse);
      session.start();
      expect(session.isActive, isTrue);
      expect(session.remaining, const Duration(minutes: 10));

      now = now.add(const Duration(minutes: 9));
      mono += const Duration(minutes: 9);
      expect(session.isActive, isTrue);
      expect(session.remaining, const Duration(minutes: 1));

      session.renew();
      expect(session.remaining, const Duration(minutes: 10));

      now = now.add(const Duration(minutes: 11));
      mono += const Duration(minutes: 11);
      expect(session.isActive, isFalse);
      expect(session.remaining, Duration.zero);

      session.start();
      session.end();
      expect(session.isActive, isFalse);
    });

    test('a backward wall-clock jump cannot extend the session (audit B-2)',
        () {
      var now = DateTime(2026, 1, 1, 12);
      var mono = Duration.zero;
      final session = RecoverySession(
        now: () => now,
        monotonicNow: () => mono,
      );
      addTearDown(session.dispose);

      session.start();
      // The wall clock jumps BACK an hour (its deadline is now an hour
      // further away), while 10 real (monotonic) minutes elapse.
      now = now.subtract(const Duration(hours: 1));
      mono += const Duration(minutes: 10);
      expect(session.isActive, isFalse);
      expect(session.remaining, Duration.zero);
    });
  });

  group('ForcedRemoval', () {
    test('24 h total (v1.0.6 user directive); negative deltas never '
        'rewind it', () {
      var fr = const ForcedRemoval().start();
      expect(fr.total, const Duration(hours: 24));
      fr = fr.advance(const Duration(hours: 23));
      expect(fr.isComplete, isFalse);
      fr = fr.advance(const Duration(hours: -5));
      expect(fr.accumulated, const Duration(hours: 23));
      fr = fr.advance(const Duration(hours: 1));
      expect(fr.isComplete, isTrue);
      expect(fr.remaining, Duration.zero);
    });

    test('withTotal rebinds the delay (the native value wins)', () {
      var fr = const ForcedRemoval().start();
      fr = fr.advance(const Duration(hours: 20));
      expect(fr.isComplete, isFalse);
      fr = fr.withTotal(const Duration(hours: 12));
      expect(fr.isComplete, isTrue);
    });

    test('json round-trip', () {
      const fr = ForcedRemoval(active: true, accumulated: Duration(hours: 3));
      final back = ForcedRemoval.fromJson(fr.toJson());
      expect(back.active, isTrue);
      expect(back.accumulated, const Duration(hours: 3));
    });
  });

  group('ImpulseLock', () {
    test('duration is clamped to 15 min – 6 h', () {
      const lock = ImpulseLock();
      expect(lock.start(const Duration(minutes: 5)).total, const Duration(minutes: 15));
      expect(lock.start(const Duration(hours: 9)).total, const Duration(hours: 6));
      expect(lock.start(const Duration(minutes: 60)).total, const Duration(minutes: 60));
    });

    test('ticks down to completion; negative ticks ignored', () {
      var lock = const ImpulseLock().start(const Duration(minutes: 30));
      lock = lock.tick(const Duration(minutes: -10));
      expect(lock.remaining, const Duration(minutes: 30));
      lock = lock.tick(const Duration(minutes: 31));
      expect(lock.isComplete, isTrue);
      expect(lock.remaining, Duration.zero);
    });
  });
}
