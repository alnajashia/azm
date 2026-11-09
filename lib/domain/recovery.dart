/// Recovery gate + session domain logic (F23), faithfully mirroring the
/// original `security/SecurityManager.kt` session model and
/// `screens/common/PendingChange.kt` loosening semantics:
///
/// * A recovery session lasts 10 minutes and is **in-memory only** — process
///   death ends it (the original ends it in `MainActivity.onDestroy`).
/// * **Tightening** a restriction is always free, with a 5-second undo
///   window. **Loosening** requires an active session.
/// * The 48-hour forced removal is the only code-free escape (F2); its
///   accounting uses elapsed-realtime-style monotonic accumulation so wall
///   clock changes cannot shorten it.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

/// Whether a proposed change loosens or tightens protection.
enum ChangeDirection { tightening, loosening, neutral }

/// Pure loosening computations, ported from the original `PendingChange`
/// `isLooserLimit()/isLooserWindows()/isLooserRestrictions()` semantics.
abstract final class Loosening {
  /// A limit change loosens when the effective cap grows on any day, or a
  /// set limit is removed. (No limit = unbounded = loosest.)
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

  /// Windows loosen when the allowed time on any day grows: a window is
  /// added/widened, or windows are removed entirely.
  /// Window lists are (startMinute, endMinute) pairs, minutes of day,
  /// possibly spanning midnight (end <= start).
  static bool isLooserWindows({
    required List<(int, int)> oldWindows,
    required List<(int, int)> newWindows,
  }) {
    if (oldWindows.isEmpty) return false; // was unrestricted — cannot loosen
    if (newWindows.isEmpty) return true; // removed all windows = loosest
    return _totalMinutes(newWindows) > _totalMinutes(oldWindows);
  }

  static int _totalMinutes(List<(int, int)> windows) => windows.fold(0, (sum, w) {
        final (s, e) = w;
        return sum + (e > s ? e - s : (1440 - s) + e);
      });

  /// A boolean protection toggle: turning a protection OFF (or an app's
  /// suspension/hidden state OFF) loosens; turning it ON tightens.
  static ChangeDirection forProtectionToggle({
    required bool wasOn,
    required bool isOn,
  }) {
    if (wasOn == isOn) return ChangeDirection.neutral;
    return isOn ? ChangeDirection.tightening : ChangeDirection.loosening;
  }

  /// Restrictions map diff: removing a key or weakening a value loosens.
  /// Values compared as strings, except booleans where true->false loosens
  /// and string lists where dropping entries loosens.
  static bool isLooserRestrictions({
    required Map<String, dynamic> oldRestrictions,
    required Map<String, dynamic> newRestrictions,
  }) {
    for (final key in oldRestrictions.keys) {
      if (!newRestrictions.containsKey(key)) return true;
      final oldV = oldRestrictions[key];
      final newV = newRestrictions[key];
      if (oldV is bool && newV is bool && oldV && !newV) return true;
      if (oldV is List && newV is List && newV.length < oldV.length) return true;
      if (oldV is num && newV is num && newV < oldV) return true;
    }
    return false;
  }
}

/// A change that was applied immediately (tightening) and can be undone
/// within [undoWindow] — the original's `PendingChange.schedule()` model.
class PendingChange {
  PendingChange({
    required this.description,
    required this.direction,
    required this.apply,
    required this.revert,
    this.undoWindow = const Duration(seconds: 5),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final String description;
  final ChangeDirection direction;
  final Future<void> Function() apply;
  final Future<void> Function() revert;
  final Duration undoWindow;
  final DateTime Function() _now;

  DateTime? _appliedAt;
  bool _undone = false;

  bool get isApplied => _appliedAt != null && !_undone;
  bool get canUndo =>
      isApplied && _now().difference(_appliedAt!) <= undoWindow;

  Future<void> run() async {
    await apply();
    _appliedAt = _now();
  }

  /// Returns false when the undo window has expired (change stands).
  Future<bool> undo() async {
    if (!canUndo) return false;
    await revert();
    _undone = true;
    return true;
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

  ImpulseLock stop() => const ImpulseLock();

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
