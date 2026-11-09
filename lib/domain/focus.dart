/// Focus mode (Pomodoro) timer model (F25) — pure Dart.
///
/// The phase machine mirrors the original `data/FocusMode.kt` defaults
/// (25 min focus / 5 min break / 15 min long break / 4 cycles). Actual
/// suspension of apps and the foreground service are Kotlin effects driven
/// from the UI via the channel; this model only computes phases and
/// remaining time from a stored phase-start instant, so it survives
/// backgrounding without ticking.
library;

enum FocusPhase { idle, focus, breakTime, longBreak, paused, done }

class FocusConfig {
  const FocusConfig({
    this.focusMinutes = 25,
    this.breakMinutes = 5,
    this.longBreakMinutes = 15,
    this.cyclesBeforeLongBreak = 4,
    this.suspendApps = const [],
    this.suspendGroups = const [],
    this.restrictions = const [],
  });

  final int focusMinutes;
  final int breakMinutes;
  final int longBreakMinutes;
  final int cyclesBeforeLongBreak;
  final List<String> suspendApps;
  final List<String> suspendGroups;
  final List<String> restrictions;

  Map<String, dynamic> toJson() => {
        'focusMinutes': focusMinutes,
        'breakMinutes': breakMinutes,
        'longBreakMinutes': longBreakMinutes,
        'cyclesBeforeLongBreak': cyclesBeforeLongBreak,
        'suspendApps': suspendApps,
        'suspendGroups': suspendGroups,
        'restrictions': restrictions,
      };

  factory FocusConfig.fromJson(Map<String, dynamic> j) => FocusConfig(
        focusMinutes: (j['focusMinutes'] as num?)?.toInt() ?? 25,
        breakMinutes: (j['breakMinutes'] as num?)?.toInt() ?? 5,
        longBreakMinutes: (j['longBreakMinutes'] as num?)?.toInt() ?? 15,
        cyclesBeforeLongBreak: (j['cyclesBeforeLongBreak'] as num?)?.toInt() ?? 4,
        suspendApps: (j['suspendApps'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        suspendGroups:
            (j['suspendGroups'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        restrictions:
            (j['restrictions'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );

  FocusConfig copyWith({
    int? focusMinutes,
    int? breakMinutes,
    int? longBreakMinutes,
    int? cyclesBeforeLongBreak,
    List<String>? suspendApps,
    List<String>? suspendGroups,
    List<String>? restrictions,
  }) =>
      FocusConfig(
        focusMinutes: focusMinutes ?? this.focusMinutes,
        breakMinutes: breakMinutes ?? this.breakMinutes,
        longBreakMinutes: longBreakMinutes ?? this.longBreakMinutes,
        cyclesBeforeLongBreak: cyclesBeforeLongBreak ?? this.cyclesBeforeLongBreak,
        suspendApps: suspendApps ?? this.suspendApps,
        suspendGroups: suspendGroups ?? this.suspendGroups,
        restrictions: restrictions ?? this.restrictions,
      );
}

/// A running (or paused) focus session. Immutable; transitions return new
/// values. Time is always derived from stored instants, never accumulated
/// by a timer, so process backgrounding cannot drift it.
class FocusSession {
  const FocusSession({
    required this.config,
    this.phase = FocusPhase.idle,
    this.phaseStartedAt,
    this.phaseDuration = Duration.zero,
    this.completedFocusPeriods = 0,
    this.pausedRemaining,
  });

  final FocusConfig config;
  final FocusPhase phase;
  final DateTime? phaseStartedAt;
  final Duration phaseDuration;
  final int completedFocusPeriods;
  final Duration? pausedRemaining;

  bool get isRunning =>
      phase == FocusPhase.focus || phase == FocusPhase.breakTime || phase == FocusPhase.longBreak;
  bool get isPaused => phase == FocusPhase.paused;

  Duration durationFor(FocusPhase p) => switch (p) {
        FocusPhase.focus => Duration(minutes: config.focusMinutes),
        FocusPhase.breakTime => Duration(minutes: config.breakMinutes),
        FocusPhase.longBreak => Duration(minutes: config.longBreakMinutes),
        _ => Duration.zero,
      };

  Duration remainingAt(DateTime now) {
    if (isPaused) return pausedRemaining ?? Duration.zero;
    if (!isRunning || phaseStartedAt == null) return Duration.zero;
    final r = phaseDuration - now.difference(phaseStartedAt!);
    return r.isNegative ? Duration.zero : r;
  }

  bool isPhaseCompleteAt(DateTime now) => isRunning && remainingAt(now) <= Duration.zero;

  FocusSession start(DateTime now) => FocusSession(
        config: config,
        phase: FocusPhase.focus,
        phaseStartedAt: now,
        phaseDuration: durationFor(FocusPhase.focus),
        completedFocusPeriods: 0,
      );

  /// The phase that follows the current one, without applying it.
  FocusPhase get nextPhase {
    switch (phase) {
      case FocusPhase.focus:
        final completed = completedFocusPeriods + 1;
        return completed % config.cyclesBeforeLongBreak == 0
            ? FocusPhase.longBreak
            : FocusPhase.breakTime;
      case FocusPhase.breakTime:
      case FocusPhase.longBreak:
        return FocusPhase.focus;
      default:
        return FocusPhase.idle;
    }
  }

  /// Advances to [nextPhase] (phase timer elapsed or user skipped a break —
  /// skipping a break and starting/resuming are free actions in the
  /// original; pausing/ending a session are recovery-gated, enforced by
  /// the UI layer, not this model).
  FocusSession advance(DateTime now) {
    final next = nextPhase;
    return FocusSession(
      config: config,
      phase: next,
      phaseStartedAt: now,
      phaseDuration: durationFor(next),
      completedFocusPeriods:
          phase == FocusPhase.focus ? completedFocusPeriods + 1 : completedFocusPeriods,
    );
  }

  FocusSession pause(DateTime now) => FocusSession(
        config: config,
        phase: FocusPhase.paused,
        phaseStartedAt: phaseStartedAt,
        phaseDuration: phaseDuration,
        completedFocusPeriods: completedFocusPeriods,
        pausedRemaining: remainingAt(now),
      );

  FocusSession resume(DateTime now) {
    // Resume re-enters the focus phase with the paused remainder. The
    // paused-from phase is not retained (v1 simplification, matching the
    // original's "pause releases into the current phase" bookkeeping being
    // UI-level); resuming during a break is done via advance() instead.
    return FocusSession(
      config: config,
      phase: FocusPhase.focus,
      phaseStartedAt: now,
      phaseDuration: pausedRemaining ?? durationFor(FocusPhase.focus),
      completedFocusPeriods: completedFocusPeriods,
    );
  }

  FocusSession end() => FocusSession(config: config);
}
