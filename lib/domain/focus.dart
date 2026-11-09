/// Focus mode (Pomodoro) timer model (F25) — pure Dart.
///
/// The phase machine mirrors the original `data/FocusMode.kt` and its
/// `FocusCycle` object: 25 min focus / 5 min short break / 15 min long
/// break / 4 cycles before the long break, and a WAITING phase that a
/// break falls into when it runs out without auto-start enabled (nothing
/// is suspended while waiting). Actual suspension of apps and the
/// foreground service are Kotlin effects driven from the UI via the
/// channel; this model only computes phases and remaining time from
/// stored phase anchors, so it survives backgrounding without ticking.
///
/// Timing mirrors the original's dual-clock anchoring as far as pure
/// Dart allows. The original stores the phase start as both wall clock
/// (RTC) and elapsed realtime plus the boot count, and computes the
/// remaining time from elapsed realtime while the boot lasts, so moving
/// the clock cannot shorten a phase. Here every phase stores both a
/// wall-clock start instant ([FocusSession.phaseStartedAt]) and a
/// monotonic anchor ([FocusSession.phaseStartedElapsed], read from a
/// process-wide [Stopwatch] — the closest Dart analogue of
/// `SystemClock.elapsedRealtime()`). Remaining time is computed from
/// the monotonic anchor whenever one is present; a session carrying no
/// monotonic anchor (e.g. one restored after a process restart, like
/// the original's post-reboot wall-clock path) falls back to the wall
/// clock.
library;

enum FocusPhase { idle, focus, breakTime, longBreak, waiting, paused, done }

class FocusConfig {
  const FocusConfig({
    this.focusMinutes = 25,
    this.breakMinutes = 5,
    this.longBreakMinutes = 15,
    this.cyclesBeforeLongBreak = 4,
    this.autoStartFocus = false,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
    this.suspendApps = const [],
    this.suspendGroups = const [],
    this.restrictions = const [],
  });

  // Bounds and defaults from the original `FocusMode.kt` (L31–45,
  // L134–141): focus 25 (5–120), short break 5 (1–30), long break 15
  // (5–60), cycles 4 (2–8), auto-start default off, sound and vibration
  // default on.
  static const int focusMinMinutes = 5;
  static const int focusMaxMinutes = 120;
  static const int shortBreakMinMinutes = 1;
  static const int shortBreakMaxMinutes = 30;
  static const int longBreakMinMinutes = 5;
  static const int longBreakMaxMinutes = 60;
  static const int cyclesMin = 2;
  static const int cyclesMax = 8;

  static int clampFocusMinutes(int v) => v.clamp(focusMinMinutes, focusMaxMinutes);
  static int clampBreakMinutes(int v) =>
      v.clamp(shortBreakMinMinutes, shortBreakMaxMinutes);
  static int clampLongBreakMinutes(int v) =>
      v.clamp(longBreakMinMinutes, longBreakMaxMinutes);
  static int clampCycles(int v) => v.clamp(cyclesMin, cyclesMax);

  final int focusMinutes;

  /// The short break (the original's `short_break_minutes`).
  final int breakMinutes;
  final int longBreakMinutes;
  final int cyclesBeforeLongBreak;

  /// Original `auto_start_focus` (default false): when a break runs out
  /// with this on, the next focus phase starts by itself; with it off
  /// the session parks in [FocusPhase.waiting] instead.
  final bool autoStartFocus;

  /// Original `sound_enabled` (default true).
  final bool soundEnabled;

  /// Original `vibration_enabled` (default true).
  final bool vibrationEnabled;

  final List<String> suspendApps;
  final List<String> suspendGroups;
  final List<String> restrictions;

  /// A copy with every duration/cycle value forced into the original's
  /// bounds — applied on read and on write, like the original's
  /// `coerceIn` in every getter/setter.
  FocusConfig normalized() => FocusConfig(
        focusMinutes: clampFocusMinutes(focusMinutes),
        breakMinutes: clampBreakMinutes(breakMinutes),
        longBreakMinutes: clampLongBreakMinutes(longBreakMinutes),
        cyclesBeforeLongBreak: clampCycles(cyclesBeforeLongBreak),
        autoStartFocus: autoStartFocus,
        soundEnabled: soundEnabled,
        vibrationEnabled: vibrationEnabled,
        suspendApps: suspendApps,
        suspendGroups: suspendGroups,
        restrictions: restrictions,
      );

  Map<String, dynamic> toJson() => {
        'focusMinutes': focusMinutes,
        'breakMinutes': breakMinutes,
        'longBreakMinutes': longBreakMinutes,
        'cyclesBeforeLongBreak': cyclesBeforeLongBreak,
        'autoStartFocus': autoStartFocus,
        'soundEnabled': soundEnabled,
        'vibrationEnabled': vibrationEnabled,
        'suspendApps': suspendApps,
        'suspendGroups': suspendGroups,
        'restrictions': restrictions,
      };

  factory FocusConfig.fromJson(Map<String, dynamic> j) => FocusConfig(
        focusMinutes: clampFocusMinutes((j['focusMinutes'] as num?)?.toInt() ?? 25),
        breakMinutes: clampBreakMinutes((j['breakMinutes'] as num?)?.toInt() ?? 5),
        longBreakMinutes:
            clampLongBreakMinutes((j['longBreakMinutes'] as num?)?.toInt() ?? 15),
        cyclesBeforeLongBreak:
            clampCycles((j['cyclesBeforeLongBreak'] as num?)?.toInt() ?? 4),
        autoStartFocus: j['autoStartFocus'] as bool? ?? false,
        soundEnabled: j['soundEnabled'] as bool? ?? true,
        vibrationEnabled: j['vibrationEnabled'] as bool? ?? true,
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
    bool? autoStartFocus,
    bool? soundEnabled,
    bool? vibrationEnabled,
    List<String>? suspendApps,
    List<String>? suspendGroups,
    List<String>? restrictions,
  }) =>
      FocusConfig(
        focusMinutes: clampFocusMinutes(focusMinutes ?? this.focusMinutes),
        breakMinutes: clampBreakMinutes(breakMinutes ?? this.breakMinutes),
        longBreakMinutes:
            clampLongBreakMinutes(longBreakMinutes ?? this.longBreakMinutes),
        cyclesBeforeLongBreak:
            clampCycles(cyclesBeforeLongBreak ?? this.cyclesBeforeLongBreak),
        autoStartFocus: autoStartFocus ?? this.autoStartFocus,
        soundEnabled: soundEnabled ?? this.soundEnabled,
        vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
        suspendApps: suspendApps ?? this.suspendApps,
        suspendGroups: suspendGroups ?? this.suspendGroups,
        restrictions: restrictions ?? this.restrictions,
      );
}

/// A running (or paused) focus session. Immutable; transitions return new
/// values. Time is always derived from stored anchors, never accumulated
/// by a timer, so process backgrounding cannot drift it.
class FocusSession {
  const FocusSession({
    required this.config,
    this.phase = FocusPhase.idle,
    this.phaseStartedAt,
    this.phaseStartedElapsed,
    this.phaseDuration = Duration.zero,
    this.completedFocusPeriods = 0,
    this.pausedFrom,
    this.pausedRemaining,
  });

  /// Process-wide monotonic clock; the Dart analogue of the original's
  /// `SystemClock.elapsedRealtime()` anchor.
  static final Stopwatch _monotonic = Stopwatch()..start();

  /// Current reading of the monotonic clock.
  static Duration get monotonicNow => _monotonic.elapsed;

  final FocusConfig config;
  final FocusPhase phase;

  /// Wall-clock instant the current phase started (the original's
  /// `phase_start_rtc`).
  final DateTime? phaseStartedAt;

  /// Monotonic reading taken when the current phase started (the
  /// original's `phase_start_elapsed`). Null for sessions that were not
  /// anchored in this process (e.g. restored state); those compute
  /// remaining time from the wall clock, like the original does after a
  /// reboot.
  final Duration? phaseStartedElapsed;

  final Duration phaseDuration;
  final int completedFocusPeriods;

  /// The phase [pause] was taken from, so [resume] can re-enter the
  /// *same* phase — mirroring the original, whose `resume()` re-anchors
  /// the current phase instead of forcing FOCUS (`FocusMode.kt`
  /// L246–260).
  final FocusPhase? pausedFrom;
  final Duration? pausedRemaining;

  bool get isRunning =>
      phase == FocusPhase.focus || phase == FocusPhase.breakTime || phase == FocusPhase.longBreak;
  bool get isPaused => phase == FocusPhase.paused;

  /// WAITING: a break ran out without auto-start. Nothing is suspended
  /// and no time accrues until the next focus is started.
  bool get isWaiting => phase == FocusPhase.waiting;

  Duration durationFor(FocusPhase p) => switch (p) {
        FocusPhase.focus => Duration(minutes: config.focusMinutes),
        FocusPhase.breakTime => Duration(minutes: config.breakMinutes),
        FocusPhase.longBreak => Duration(minutes: config.longBreakMinutes),
        _ => Duration.zero,
      };

  Duration remainingAt(DateTime now) {
    if (isPaused) return pausedRemaining ?? Duration.zero;
    if (!isRunning || phaseStartedAt == null) return Duration.zero;
    // Elapsed-realtime first (clock changes cannot shorten the phase);
    // wall clock only when this session has no monotonic anchor.
    final elapsed = phaseStartedElapsed != null
        ? monotonicNow - phaseStartedElapsed!
        : now.difference(phaseStartedAt!);
    final r = phaseDuration - elapsed;
    return r.isNegative ? Duration.zero : r;
  }

  bool isPhaseCompleteAt(DateTime now) => isRunning && remainingAt(now) <= Duration.zero;

  /// Starts a fresh session in the focus phase (the original's
  /// `startFocus` with no active session: the completed count resets).
  FocusSession start(DateTime now) => FocusSession(
        config: config,
        phase: FocusPhase.focus,
        phaseStartedAt: now,
        phaseStartedElapsed: monotonicNow,
        phaseDuration: durationFor(FocusPhase.focus),
        completedFocusPeriods: 0,
      );

  /// Enters the focus phase while a session is already active — e.g.
  /// leaving WAITING — keeping the completed-focus count, like the
  /// original's `startFocus` during an active session.
  FocusSession beginFocus(DateTime now) => FocusSession(
        config: config,
        phase: FocusPhase.focus,
        phaseStartedAt: now,
        phaseStartedElapsed: monotonicNow,
        phaseDuration: durationFor(FocusPhase.focus),
        completedFocusPeriods: completedFocusPeriods,
      );

  /// The phase that follows the current one, without applying it.
  /// Mirrors `FocusCycle.next`: a finished focus goes to the long break
  /// once the completed count reaches the cycle length, else to the
  /// short break; a finished break goes back to focus only when
  /// auto-start is on, and parks in WAITING otherwise.
  FocusPhase get nextPhase {
    switch (phase) {
      case FocusPhase.focus:
        final completed = completedFocusPeriods + 1;
        return completed >= config.cyclesBeforeLongBreak
            ? FocusPhase.longBreak
            : FocusPhase.breakTime;
      case FocusPhase.breakTime:
      case FocusPhase.longBreak:
        return config.autoStartFocus ? FocusPhase.focus : FocusPhase.waiting;
      case FocusPhase.waiting:
        return FocusPhase.waiting;
      default:
        return FocusPhase.idle;
    }
  }

  /// Advances to [nextPhase] because the phase timer elapsed. The
  /// completed-focus bookkeeping mirrors `FocusCycle.next`: finishing a
  /// focus increments the count; finishing the long break resets it.
  FocusSession advance(DateTime now) {
    final next = nextPhase;
    return FocusSession(
      config: config,
      phase: next,
      phaseStartedAt: now,
      phaseStartedElapsed: monotonicNow,
      phaseDuration: durationFor(next),
      completedFocusPeriods: switch (phase) {
        FocusPhase.focus => completedFocusPeriods + 1,
        FocusPhase.longBreak => 0,
        _ => completedFocusPeriods,
      },
    );
  }

  /// Skips the current break and starts focusing again — the original's
  /// `skipBreak`: only valid from a break phase, and skipping the long
  /// break also resets the completed-focus count.
  FocusSession skipBreak(DateTime now) {
    if (phase != FocusPhase.breakTime && phase != FocusPhase.longBreak) return this;
    return FocusSession(
      config: config,
      phase: FocusPhase.focus,
      phaseStartedAt: now,
      phaseStartedElapsed: monotonicNow,
      phaseDuration: durationFor(FocusPhase.focus),
      completedFocusPeriods: phase == FocusPhase.longBreak ? 0 : completedFocusPeriods,
    );
  }

  FocusSession pause(DateTime now) {
    if (!isRunning) return this;
    return FocusSession(
      config: config,
      phase: FocusPhase.paused,
      phaseStartedAt: phaseStartedAt,
      phaseStartedElapsed: phaseStartedElapsed,
      phaseDuration: phaseDuration,
      completedFocusPeriods: completedFocusPeriods,
      pausedFrom: phase,
      pausedRemaining: remainingAt(now),
    );
  }

  /// Resumes into the phase the session was paused from, re-anchoring
  /// both clocks so the phase ends [pausedRemaining] from now and the
  /// elapsed portion is preserved — the original's `resume()`
  /// (`FocusMode.kt` L246–260).
  FocusSession resume(DateTime now) {
    if (!isPaused || pausedFrom == null) return this;
    final remaining = pausedRemaining ?? Duration.zero;
    var elapsedSoFar = phaseDuration - remaining;
    if (elapsedSoFar.isNegative) elapsedSoFar = Duration.zero;
    return FocusSession(
      config: config,
      phase: pausedFrom!,
      phaseStartedAt: now.subtract(elapsedSoFar),
      phaseStartedElapsed: monotonicNow - elapsedSoFar,
      phaseDuration: phaseDuration,
      completedFocusPeriods: completedFocusPeriods,
    );
  }

  FocusSession end() => FocusSession(config: config);
}
