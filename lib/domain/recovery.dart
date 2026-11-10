/// Recovery gate + session domain logic (F23), faithfully mirroring the
/// original `security/SecurityManager.kt` session model and
/// `screens/common/PendingChange.kt` loosening semantics:
///
/// * A recovery session lasts 10 minutes and is **in-memory only** — process
///   death ends it (the original ends it in `MainActivity.onDestroy`).
/// * **Tightening** a restriction is free, but only takes effect after a
///   5-second undo window; undoing inside the window means the change is
///   never applied at all (the original's `PendingChange.schedule()`).
///   **Loosening** requires an active session.
/// * The 48-hour forced removal is the only code-free escape (F2); its
///   accounting uses elapsed-realtime-style monotonic accumulation so wall
///   clock changes cannot shorten it.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

/// Whether a proposed change loosens or tightens protection.
enum ChangeDirection { tightening, loosening, neutral }

/// Pure loosening computations, ported line-by-line from the original
/// `PendingChange.kt` top-level functions
/// (`isLooserLimit()/isLooserWindows()/isLooserRestrictions()/isLooserSet()`).
abstract final class Loosening {
  /// A limit change loosens when the effective cap grows on any day, or a
  /// set limit is removed. (No limit = unbounded = loosest.)
  /// Mirrors `PendingChange.kt`: `cap(minutes) = if (minutes == 0) MAX else
  /// minutes`, compared per `DayOfWeek`.
  static bool isLooserLimit({
    required int? oldDaily,
    required List<int>? oldWeekly,
    required int? newDaily,
    required List<int>? newWeekly,
  }) {
    int eff(int? daily, List<int>? weekly, int day) {
      final v = weekly != null ? weekly[day] : (daily ?? 0);
      return v == 0 ? _unbounded : v;
    }

    for (var day = 0; day < 7; day++) {
      if (eff(newDaily, newWeekly, day) > eff(oldDaily, oldWeekly, day)) {
        return true;
      }
    }
    return false;
  }

  static const _unbounded = 1 << 30;

  /// Whether minute-of-day [minute] lies inside the window ([start], [end]),
  /// mirroring the original `TimeWindow.contains()`: a non-wrapping window
  /// covers `[start, end)`; a wrapping one (end <= start) covers
  /// `[start, 1440) ∪ [0, end)`.
  static bool _windowContains((int, int) window, int minute) {
    final (start, end) = window;
    if (start <= end) return minute >= start && minute < end;
    return minute >= start || minute < end;
  }

  /// Windows are the *allowed* periods and an empty list means always
  /// allowed: loosening is allowing a minute that wasn't.
  /// Line-by-line port of `PendingChange.kt`'s `isLooserWindows(List,
  /// List)`: for every minute of the day, if the new windows allow it and
  /// the old ones did not, the change loosens — regardless of total length.
  static bool isLooserWindows({
    required List<(int, int)> oldWindows,
    required List<(int, int)> newWindows,
  }) {
    bool allowed(List<(int, int)> windows, int minute) =>
        windows.isEmpty || windows.any((w) => _windowContains(w, minute));
    for (var minute = 0; minute < 1440; minute++) {
      if (allowed(newWindows, minute) && !allowed(oldWindows, minute)) {
        return true;
      }
    }
    return false;
  }

  /// Per-weekday overload, mirroring `PendingChange.kt`'s
  /// `isLooserWindows(TimeWindows, TimeWindows)`: each day uses its weekly
  /// windows when set, otherwise the daily windows (the original's
  /// `TimeWindows.windowsFor(day)`), and the change loosens if it loosens
  /// on any day. Day indexes follow the Kotlin `DayOfWeek` order
  /// (Monday = 0 … Sunday = 6).
  static bool isLooserWindowsForWeek({
    required List<(int, int)> oldDaily,
    required List<List<(int, int)>>? oldWeekly,
    required List<(int, int)> newDaily,
    required List<List<(int, int)>>? newWeekly,
  }) {
    List<(int, int)> forDay(
      List<(int, int)> daily,
      List<List<(int, int)>>? weekly,
      int day,
    ) =>
        (weekly != null && day < weekly.length) ? weekly[day] : daily;

    for (var day = 0; day < 7; day++) {
      if (isLooserWindows(
        oldWindows: forDay(oldDaily, oldWeekly, day),
        newWindows: forDay(newDaily, newWeekly, day),
      )) {
        return true;
      }
    }
    return false;
  }

  /// A boolean protection toggle: turning a protection OFF (or an app's
  /// suspension/hidden state OFF) loosens; turning it ON tightens.
  static ChangeDirection forProtectionToggle({
    required bool wasOn,
    required bool isOn,
  }) {
    if (wasOn == isOn) return ChangeDirection.neutral;
    return isOn ? ChangeDirection.tightening : ChangeDirection.loosening;
  }

  /// Restrictions bundle diff, ported line-by-line from `PendingChange.kt`'s
  /// `isLooserRestrictions(Bundle, Bundle)`. Only keys present in the old
  /// bundle are examined; per old-value type:
  ///
  /// * **bool** — loosens when it was `true` and the new value is not `true`
  ///   (false or removed);
  /// * **String** — loosens when it was non-empty and the new value is
  ///   missing, not a string, or empty;
  /// * **num** — loosens when it was non-zero and the new value is missing
  ///   or numerically zero (a smaller non-zero value does **not** loosen);
  /// * **List** — loosens when the new list (missing/non-list counts as
  ///   empty) does not contain every old entry — containment, not length;
  /// * **Map** (nested bundle) — loosens when the new value is not a map,
  ///   or the recursion into the pair loosens.
  static bool isLooserRestrictions({
    required Map<String, dynamic> oldRestrictions,
    required Map<String, dynamic> newRestrictions,
  }) =>
      _isLooserBundle(oldRestrictions, newRestrictions);

  static bool _isLooserBundle(Map<dynamic, dynamic> current, Map<dynamic, dynamic> next) {
    for (final key in current.keys) {
      final oldVal = current[key];
      final newVal = next.containsKey(key) ? next[key] : null;
      switch (oldVal) {
        case bool():
          if (oldVal && newVal != true) return true;
        case String():
          if (oldVal.isNotEmpty && (newVal is! String || newVal.isEmpty)) {
            return true;
          }
        case num():
          if (oldVal.toInt() != 0 &&
              (newVal == null || (newVal is num && newVal.toInt() == 0))) {
            return true;
          }
        case List():
          final newSet = newVal is List ? newVal.toSet() : const <dynamic>{};
          if (!newSet.containsAll(oldVal.toSet())) return true;
        case Map():
          if (newVal is! Map || _isLooserBundle(oldVal, newVal)) return true;
      }
    }
    return false;
  }

  /// A set change loosens when any old entry is gone from the new set.
  /// Port of `PendingChange.kt`'s `isLooserSet`: `!new.containsAll(old)`.
  static bool isLooserSet({
    required Set<String> oldSet,
    required Set<String> newSet,
  }) =>
      !newSet.containsAll(oldSet);
}

enum _PendingState { idle, pending, committed, undone }

/// A tightening change with the original's 5-second undo window — a direct
/// port of `PendingChange.schedule()` in `PendingChange.kt`:
///
/// * [run] only *schedules* the change. During the undo window the change
///   is **not live**: nothing has been applied yet.
/// * If the window lapses without an undo, [apply] runs exactly once.
/// * [undo] inside the window cancels the schedule, so the change is
///   **never applied** — undo is not a compensating revert; [onUndo] (the
///   original's `onUndo` callback) runs instead, e.g. to roll back an
///   optimistic UI toggle.
/// * [commitNow] applies a pending change immediately. The original commits
///   a showing change as soon as its snackbar is dismissed (which is how a
///   new change supersedes the previous one), so the UI layer calls this
///   when the snackbar goes away for any reason other than Undo.
class PendingChange {
  PendingChange({
    required this.description,
    required this.direction,
    required this.apply,
    this.onUndo,
    this.undoWindow = const Duration(seconds: 5),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final String description;
  final ChangeDirection direction;

  /// The change itself. Runs at most once, and only after the undo window
  /// lapses (or [commitNow] is called).
  final Future<void> Function() apply;

  /// Runs when the user undoes the change inside the window — the change
  /// was never applied, so this only needs to restore any optimistic UI
  /// state, exactly as in the original.
  final Future<void> Function()? onUndo;

  final Duration undoWindow;
  final DateTime Function() _now;

  _PendingState _state = _PendingState.idle;
  Timer? _timer;
  DateTime? _windowEndsAt;
  Object? _commitError;
  final Completer<void> _done = Completer<void>();

  /// The undo window is open and the change is not yet applied.
  bool get isPending => _state == _PendingState.pending;

  /// The change has been applied (the window lapsed or [commitNow] ran).
  bool get isApplied => _state == _PendingState.committed;

  /// The change was undone inside the window and will never be applied.
  bool get isUndone => _state == _PendingState.undone;

  /// Undo is possible exactly while the change is pending.
  bool get canUndo => _state == _PendingState.pending;

  /// The error thrown by [apply] when it ran, if any. Apply runs after
  /// [run] has returned, so its failures surface here (and complete [done]
  /// normally) instead of being thrown into the scheduler.
  Object? get commitError => _commitError;

  /// Completes once the change settles: applied, or undone.
  Future<void> get done => _done.future;

  /// Starts the undo window without applying anything. Returns as soon as
  /// the change is scheduled, mirroring the original's fire-and-forget
  /// `scope.launch { … }`.
  Future<void> run() async {
    if (_state != _PendingState.idle) return;
    _state = _PendingState.pending;
    _windowEndsAt = _now().add(undoWindow);
    _timer = Timer(undoWindow, () => unawaited(commitNow()));
  }

  /// Undoes the change if the window is still open: the scheduled apply is
  /// cancelled and never runs. Returns false when the window has already
  /// lapsed (the change is committed and stands).
  Future<bool> undo() async {
    if (_state != _PendingState.pending) return false;
    if (_now().isAfter(_windowEndsAt!)) {
      await commitNow();
      return false;
    }
    _timer?.cancel();
    _timer = null;
    _state = _PendingState.undone;
    await onUndo?.call();
    if (!_done.isCompleted) _done.complete();
    return true;
  }

  /// Applies the pending change right away (the original commits on
  /// snackbar dismissal). No-op unless the change is pending.
  Future<void> commitNow() async {
    if (_state != _PendingState.pending) return;
    _timer?.cancel();
    _timer = null;
    _state = _PendingState.committed;
    try {
      await apply();
    } catch (e) {
      _commitError = e;
    }
    if (!_done.isCompleted) _done.complete();
  }

  /// Cancels the window timer without settling the change. A pending change
  /// that is disposed is simply never applied.
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

/// The 10-minute recovery session (F23). In-memory only, by design.
class RecoverySession extends ChangeNotifier {
  RecoverySession({DateTime Function()? now, this.duration = const Duration(minutes: 10)})
      : _now = now ?? DateTime.now;

  final Duration duration;
  final DateTime Function() _now;
  DateTime? _endsAt;
  Timer? _ticker;

  bool get isActive => _endsAt != null && _now().isBefore(_endsAt!);

  Duration get remaining {
    if (!isActive) return Duration.zero;
    final r = _endsAt!.difference(_now());
    return r.isNegative ? Duration.zero : r;
  }

  void start() {
    _endsAt = _now().add(duration);
    _armTicker();
    notifyListeners();
  }

  void renew() {
    if (!isActive) return;
    _endsAt = _now().add(duration);
    notifyListeners();
  }

  void end() {
    _endsAt = null;
    _ticker?.cancel();
    _ticker = null;
    notifyListeners();
  }

  void _armTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isActive) {
        _endsAt = null;
        _ticker?.cancel();
        _ticker = null;
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

/// 48-hour forced-removal accounting (F2). The original accumulates elapsed
/// time across reboots using both wall clock and elapsedRealtime; here the
/// persisted state is (accumulated, lastTickEpoch) and progress advances by
/// **monotonic deltas supplied by the caller** — a backwards wall-clock jump
/// never adds negative time and a forwards jump only counts real elapsed
/// deltas the caller measured, mirroring the original's distrust of RTC.
class ForcedRemoval {
  const ForcedRemoval({this.active = false, this.accumulated = Duration.zero});

  static const total = Duration(hours: 48);

  final bool active;
  final Duration accumulated;

  Duration get remaining => total - accumulated;
  bool get isComplete => active && accumulated >= total;
  double get progress => (accumulated.inMilliseconds / total.inMilliseconds).clamp(0, 1);

  ForcedRemoval start() => const ForcedRemoval(active: true);
  ForcedRemoval cancel() => const ForcedRemoval();
  ForcedRemoval advance(Duration delta) {
    if (!active || delta.isNegative) return this;
    return ForcedRemoval(active: true, accumulated: accumulated + delta);
  }

  Map<String, dynamic> toJson() => {
        'active': active,
        'accumulatedMs': accumulated.inMilliseconds,
      };

  factory ForcedRemoval.fromJson(Map<String, dynamic> j) => ForcedRemoval(
        active: j['active'] as bool? ?? false,
        accumulated: Duration(milliseconds: (j['accumulatedMs'] as num?)?.toInt() ?? 0),
      );
}

/// Impulse-lock timer model (F21): 15 min – 6 h, clock-change resistant in
/// the same dual-clock spirit — the deadline is stored as a remaining
/// duration decremented by measured ticks, not as a wall-clock target.
class ImpulseLock {
  const ImpulseLock({this.active = false, this.remaining = Duration.zero, this.total = Duration.zero});

  static const minDuration = Duration(minutes: 15);
  static const maxDuration = Duration(minutes: 360);
  static const defaultDuration = Duration(minutes: 60);

  final bool active;
  final Duration remaining;
  final Duration total;

  bool get isComplete => active && remaining <= Duration.zero;

  ImpulseLock start(Duration duration) {
    final clamped = duration < minDuration
        ? minDuration
        : (duration > maxDuration ? maxDuration : duration);
    return ImpulseLock(active: true, remaining: clamped, total: clamped);
  }

  ImpulseLock tick(Duration delta) {
    if (!active || delta.isNegative) return this;
    final r = remaining - delta;
    return ImpulseLock(active: true, remaining: r.isNegative ? Duration.zero : r, total: total);
  }

  Map<String, dynamic> toJson() => {
        'active': active,
        'remainingMs': remaining.inMilliseconds,
        'totalMs': total.inMilliseconds,
      };

  factory ImpulseLock.fromJson(Map<String, dynamic> j) => ImpulseLock(
        active: j['active'] as bool? ?? false,
        remaining: Duration(milliseconds: (j['remainingMs'] as num?)?.toInt() ?? 0),
        total: Duration(milliseconds: (j['totalMs'] as num?)?.toInt() ?? 0),
      );
}
