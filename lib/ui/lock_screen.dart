/// Lock screen (F21/F25/F32): the pre-authentication surface.
///
/// Mirrors the original's `LockScreen.kt` composition and posture:
/// authentication is deliberately *not* triggered on open — the panic
/// button has to stay one tap away — so the biometric prompt only runs
/// when the user actually asks to get in. Contents, top to bottom:
///
/// * the impulse ("panic") button, reachable **before** any
///   authentication; while an impulse block is running it is replaced by
///   the countdown card and "Access app" is hidden, exactly as in the
///   original;
/// * the focus session card (`FocusSessionCard` in the original,
///   compact form), also pre-auth: phase label, live countdown ring and
///   completed-cycle count from the persisted native session, with the
///   same actions the original offers pre-auth — start / resume / plain
///   pause are free; ending the session and the long-press
///   pause-that-releases-apps go through the recovery gate; ending is
///   free while the session is WAITING;
/// * "Access app" (biometric / device credential — and if neither is
///   enrolled on the device, entry is allowed: the original's explicit
///   fallback, surfaced here with a notice, never silently);
/// * a quiet "View limits" button opening the read-only, limit-scoped
///   usage overview (`UsageLimitsOverview` in the original): only apps
///   and groups that *have* a time limit are listed, with today's usage
///   against that limit.
///
/// A 1-second ticker drives both countdowns and re-reads the native
/// focus state — the native side advances an expired phase before
/// replying, which is the analogue of the original's `syncIfDue` poll.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../app_controller.dart';
import '../data/config_store.dart';
import '../data/privileged_channel.dart';
import '../domain/focus.dart';
import '../l10n/l10n.dart';
import 'common.dart';
import 'entry_password_ui.dart';
import 'recovery_ui.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.controller, this.auth});
  final AppController controller;
  final LocalAuthentication? auth;
  @override
  State<LockScreen> createState() => _LockScreenState();
}

/// One action of the focus card, mirroring `FocusAction` in the
/// original's `FocusSessionCard.kt`: a tap, plus an optional long-press
/// (only the focus-phase pause has one — the gated pause that also
/// releases the suspended apps).
class _FocusCardAction {
  const _FocusCardAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.onLongPress,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
}

/// One row of the usage-limits overview, mirroring `LimitEntry` in the
/// original's `UsageLimitsOverview.kt`.
class _LimitEntry {
  const _LimitEntry({
    required this.name,
    required this.limitMinutes,
    required this.usedMinutes,
    required this.isGroup,
    this.detail,
    this.groupName,
  });
  final String name;
  final String? detail;

  /// For app entries: the name of the group the app belongs to, shown
  /// as a localized "Group: X" detail at render time (formatting it in
  /// _loadLimits would need the localizations during initState).
  final String? groupName;
  final int limitMinutes;
  final int usedMinutes;
  final bool isGroup;

  double get fraction => limitMinutes > 0
      ? math.min(1, math.max(0, usedMinutes / limitMinutes))
      : 0;
  bool get reached => usedMinutes >= limitMinutes;
}

class _LimitsData {
  const _LimitsData(this.groups, this.apps);
  final List<_LimitEntry> groups;
  final List<_LimitEntry> apps;
  bool get isEmpty => groups.isEmpty && apps.isEmpty;
}

class _LockScreenState extends State<LockScreen> {
  late final _auth = widget.auth ?? LocalAuthentication();
  bool _authBusy = false;
  bool _passwordBusy = false;

  /// Whether an app entry password is set (v1.0.4): when true, the lock
  /// screen offers "Use password instead" next to the biometric action.
  bool _passwordSet = false;

  Timer? _ticker;

  // ---- Impulse countdown anchor -------------------------------------
  // The displayed remaining time is derived from the controller's lock
  // state anchored on the process monotonic clock (the Dart analogue of
  // elapsedRealtime), re-anchored whenever the controller's value moves
  // (its own ticker, start/stop) — so the 1-second display neither
  // drifts nor freezes between the controller's coarser updates.
  bool _impulseWasActive = false;
  Duration _lastControllerRemaining = Duration.zero;
  Duration _lastControllerTotal = Duration.zero;
  Duration _impulseAnchorRemaining = Duration.zero;
  Duration _impulseAnchorMonotonic = Duration.zero;

  // ---- Focus card state ----------------------------------------------
  NativeFocusSessionState? _focusState;
  FocusSession? _focusSession;
  FocusConfig? _focusConfig;
  bool _focusBusy = false;
  bool _focusPollInFlight = false;

  // ---- Usage-limits overview ------------------------------------------
  _LimitsData? _limits;
  bool _showingLimits = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _syncImpulseAnchor();
    _loadLimits();
    _refreshFocus();
    _loadPasswordState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onSecond());
  }

  Future<void> _loadPasswordState() async {
    try {
      final isSet = await widget.controller.config.isEntryPasswordSet();
      if (mounted) setState(() => _passwordSet = isSet);
    } catch (_) {
      // Best-effort, like the focus card: without the flag the screen
      // simply offers the biometric path only.
    }
  }

  /// Password entry (v1.0.4): a verified password unlocks app entry —
  /// the same effect as biometric success. It must NOT open a recovery
  /// session, and it doesn't (see entry_password_ui.dart).
  Future<void> _accessWithPassword() async {
    if (_passwordBusy) return;
    setState(() => _passwordBusy = true);
    try {
      final ok = await showEntryPasswordPrompt(context, widget.controller);
      if (ok) widget.controller.unlock();
    } finally {
      if (mounted) setState(() => _passwordBusy = false);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _ticker?.cancel();
    super.dispose();
  }

  void _onControllerChanged() {
    _syncImpulseAnchor();
    if (mounted) setState(() {});
  }

  void _onSecond() {
    _syncImpulseAnchor();
    // The native side advances an expired focus phase before replying —
    // the analogue of the original lock screen's 1 s `syncIfDue` poll.
    _refreshFocus();
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------- Impulse

  void _syncImpulseAnchor() {
    final lock = widget.controller.impulseLock;
    if (lock.active == _impulseWasActive &&
        lock.remaining == _lastControllerRemaining &&
        lock.total == _lastControllerTotal) {
      return;
    }
    _impulseWasActive = lock.active;
    _lastControllerRemaining = lock.remaining;
    _lastControllerTotal = lock.total;
    _impulseAnchorRemaining = lock.remaining;
    _impulseAnchorMonotonic = FocusSession.monotonicNow;
  }

  /// Remaining impulse-block time, counted down from the anchor on the
  /// monotonic clock.
  Duration get _impulseRemaining {
    if (!widget.controller.impulseLock.active) return Duration.zero;
    final elapsed = FocusSession.monotonicNow - _impulseAnchorMonotonic;
    final r = _impulseAnchorRemaining - elapsed;
    return r.isNegative ? Duration.zero : r;
  }

  bool get _impulseRunning {
    final lock = widget.controller.impulseLock;
    return lock.active && !lock.isComplete && _impulseRemaining > Duration.zero;
  }

  Future<void> _panic() async {
    final l10n = context.l10n;
    final config = await widget.controller.config.getImpulseConfig();
    await widget.controller.startImpulseLock(
      Duration(minutes: config.durationMinutes),
    );
    if (config.action == ImpulseAction.timerAndSuspend &&
        config.suspendApps.isNotEmpty) {
      try {
        await widget.controller.channel.setAppSuspended(
          config.suspendApps,
          true,
          reason: 'IMPULSE_LOCK',
        );
        if (mounted) {
          showInfoSnackBar(
            context,
            l10n.impulseStartedSuspended(config.durationMinutes),
          );
        }
      } catch (e) {
        if (mounted) await showErrorCard(context, e);
      }
    } else if (mounted) {
      showInfoSnackBar(context, l10n.impulseStarted(config.durationMinutes));
    }
    if (mounted) setState(() {});
  }

  /// The original's impulse countdown format: whole seconds (truncated),
  /// hours only when there are any (`h:mm:ss`, else `mm:ss`).
  String _formatImpulseCountdown(Duration d) {
    final totalSeconds = (d.isNegative ? Duration.zero : d).inSeconds;
    final h = totalSeconds ~/ 3600;
    final m = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Widget _impulseCountdownCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.timer_outlined,
              size: 48,
              color: scheme.onErrorContainer,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.impulseBlockActive,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _formatImpulseCountdown(_impulseRemaining),
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: scheme.onErrorContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ Focus

  Future<void> _refreshFocus() async {
    if (_focusPollInFlight) return;
    _focusPollInFlight = true;
    try {
      final channel = widget.controller.channel;
      final state = await channel.getFocusSession();
      var config = _focusConfig;
      config ??= await widget.controller.config.getFocusConfig();
      if (!mounted) return;
      setState(() {
        _focusConfig = config;
        _setFocusState(state, config!);
      });
    } catch (_) {
      // Best-effort: the card keeps its last known state. Channel errors
      // are surfaced on the Setup screen; the lock screen must stay
      // usable (panic button first).
    } finally {
      _focusPollInFlight = false;
    }
  }

  /// Stores the latest native snapshot and rebuilds the display session
  /// only when the snapshot actually changed — re-converting an
  /// unchanged restored session every second would keep re-anchoring
  /// its countdown at the full phase duration.
  void _setFocusState(NativeFocusSessionState? state, FocusConfig config) {
    final prev = _focusState;
    _focusState = state;
    if (state == null) {
      _focusSession = null;
      return;
    }
    final unchanged =
        prev != null &&
        prev.phase == state.phase &&
        prev.phaseStartedElapsedMs == state.phaseStartedElapsedMs &&
        prev.phaseDurationMs == state.phaseDurationMs &&
        prev.completedFocusInCycle == state.completedFocusInCycle &&
        prev.pausedFrom == state.pausedFrom &&
        prev.deadlineElapsedMs == state.deadlineElapsedMs;
    if (!unchanged || _focusSession == null) {
      _focusSession = state.toFocusSession(
        config,
        elapsedRealtimeOffsetMs:
            widget.controller.channel.focusElapsedRealtimeOffsetMs,
      );
    }
  }

  /// The original's focus countdown format: rounded *up*, so the
  /// display reads 00:00 only once the phase is actually over.
  String _formatFocusCountdown(Duration d) {
    final totalSeconds = ((d.isNegative ? 0 : d.inMilliseconds) + 999) ~/ 1000;
    final h = totalSeconds ~/ 3600;
    final m = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  /// Phase title, mirroring `phaseTitle` in `FocusSessionCard.kt`.
  String _focusPhaseTitle(FocusSession session) {
    final l10n = context.l10n;
    final cycles = session.config.cyclesBeforeLongBreak;
    final phase = session.isPaused ? session.pausedFrom : session.phase;
    final title = switch (phase) {
      FocusPhase.focus => l10n.focusCycleTitle(
        math.min(session.completedFocusPeriods + 1, cycles),
        cycles,
      ),
      FocusPhase.breakTime => l10n.focusShortBreak,
      FocusPhase.longBreak => l10n.focusLongBreak,
      FocusPhase.waiting => l10n.focusBreakOver,
      _ => l10n.focusMode,
    };
    return session.isPaused ? '$title${l10n.focusPausedSuffix}' : title;
  }

  Future<void> _runFocusAction(Future<void> Function() action) async {
    if (_focusBusy) return;
    setState(() => _focusBusy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) await showErrorCard(context, e);
    } finally {
      if (mounted) setState(() => _focusBusy = false);
    }
    await _refreshFocus();
  }

  void _focusStart() {
    _runFocusAction(() async {
      final config =
          _focusConfig ?? await widget.controller.config.getFocusConfig();
      final channel = widget.controller.channel;
      await channel.startFocusSession(
        focusMinutes: config.focusMinutes,
        breakMinutes: config.breakMinutes,
        longBreakMinutes: config.longBreakMinutes,
        cycles: config.cyclesBeforeLongBreak,
        autoStartFocus: config.autoStartFocus,
        soundEnabled: config.soundEnabled,
        vibrationEnabled: config.vibrationEnabled,
      );
      // The original's starter asks for the notification permission
      // after starting when it is missing (the native side grants it
      // via the device-owner policy where it can).
      try {
        if (!await channel.hasNotificationPermission()) {
          await channel.requestNotificationPermission();
        }
      } catch (_) {
        // The session is already running; a failed permission ask must
        // not report the start itself as failed.
      }
    });
  }

  void _focusResume() {
    _runFocusAction(() => widget.controller.channel.resumeFocusSession());
  }

  void _focusSkipBreak() {
    _runFocusAction(() => widget.controller.channel.skipFocusSession());
  }

  void _focusPausePlain() {
    _runFocusAction(
      () => widget.controller.channel.pauseFocusSession(releaseApps: false),
    );
  }

  /// Long-press pause: releases the suspended apps too — a loosening,
  /// so it goes through the recovery gate, as in the original.
  void _focusPauseReleasing() {
    runLoosening(context, widget.controller, () async {
      await widget.controller.channel.pauseFocusSession(releaseApps: true);
      await _refreshFocus();
    });
  }

  /// Ending the session is gated — except while WAITING, where the
  /// original ends it freely.
  void _focusEndGated() {
    runLoosening(context, widget.controller, () async {
      await widget.controller.channel.stopFocusSession();
      await _refreshFocus();
    });
  }

  void _focusEndFree() {
    _runFocusAction(() => widget.controller.channel.stopFocusSession());
  }

  /// The card's actions, in the original's order and gating
  /// (`FocusSessionCard.kt`): start/resume/skip-break/plain-pause are
  /// free, the releasing pause (long-press, focus phase only) and end
  /// are gated. Skip break appears during the break phases only.
  List<_FocusCardAction> _focusActions(FocusSession? session) {
    final l10n = context.l10n;
    final start = _FocusCardAction(
      icon: Icons.play_arrow_outlined,
      label: l10n.startFocusAction,
      onTap: _focusStart,
    );
    if (session == null || session.phase == FocusPhase.idle) {
      return [start];
    }
    final actions = <_FocusCardAction>[];
    final phase = session.isPaused ? session.pausedFrom : session.phase;
    if (session.isWaiting) actions.add(start);
    if (session.isPaused) {
      actions.add(
        _FocusCardAction(
          icon: Icons.play_arrow_outlined,
          label: l10n.resumeAction,
          onTap: _focusResume,
        ),
      );
    }
    if (phase == FocusPhase.breakTime || phase == FocusPhase.longBreak) {
      actions.add(
        _FocusCardAction(
          icon: Icons.skip_next_outlined,
          label: l10n.skipBreakAction,
          onTap: _focusSkipBreak,
        ),
      );
    }
    if (!session.isWaiting && !session.isPaused) {
      actions.add(
        _FocusCardAction(
          icon: Icons.pause_outlined,
          label: l10n.pauseAction,
          onTap: _focusPausePlain,
          onLongPress: phase == FocusPhase.focus ? _focusPauseReleasing : null,
        ),
      );
    }
    actions.add(
      _FocusCardAction(
        icon: Icons.stop_outlined,
        label: l10n.endSession,
        onTap: session.isWaiting ? _focusEndFree : _focusEndGated,
      ),
    );
    return actions;
  }

  Widget _focusCard(BuildContext context) {
    final theme = Theme.of(context);
    final session =
        (_focusSession != null && _focusSession!.phase != FocusPhase.idle)
        ? _focusSession
        : null;
    final actions = _focusActions(session);
    final showRing = session != null && !session.isWaiting;
    final remaining = session?.remainingAt(DateTime.now()) ?? Duration.zero;
    final fraction = session != null && session.phaseDuration > Duration.zero
        ? math
              .min(
                1,
                math.max(
                  0,
                  remaining.inMilliseconds /
                      session.phaseDuration.inMilliseconds,
                ),
              )
              .toDouble()
        : 0.0;
    final cycles =
        session?.config.cyclesBeforeLongBreak ??
        _focusConfig?.cyclesBeforeLongBreak ??
        0;
    final l10n = context.l10n;
    final title = session == null ? l10n.focusMode : _focusPhaseTitle(session);
    final subtitle = session == null
        ? (_focusConfig == null
              ? null
              : l10n.focusSuspendingSummary(_focusConfig!.focusMinutes))
        : l10n.focusPeriodsCompleted(
            math.min(session.completedFocusPeriods, cycles),
            cycles,
          );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (showRing)
              SizedBox(
                width: 76,
                height: 76,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 76,
                      height: 76,
                      child: CircularProgressIndicator(
                        value: fraction,
                        strokeWidth: 5,
                        color: theme.colorScheme.primary,
                        backgroundColor: theme.colorScheme.primary.withValues(
                          alpha: 0.15,
                        ),
                      ),
                    ),
                    Text(
                      _formatFocusCountdown(remaining),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )
            else
              Icon(
                Icons.timer_outlined,
                size: 40,
                color: theme.colorScheme.primary,
              ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (subtitle != null)
                    Text(subtitle, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            for (var i = 0; i < actions.length; i++)
              if (i == 0)
                IconButton.filled(
                  onPressed: _focusBusy ? null : actions[i].onTap,
                  onLongPress: _focusBusy ? null : actions[i].onLongPress,
                  tooltip: actions[i].label,
                  icon: Icon(actions[i].icon),
                )
              else
                IconButton.filledTonal(
                  onPressed: _focusBusy ? null : actions[i].onTap,
                  onLongPress: _focusBusy ? null : actions[i].onLongPress,
                  tooltip: actions[i].label,
                  icon: Icon(actions[i].icon),
                ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------- Usage limits

  /// Today's limit for a daily/weekly pair, mirroring the original's
  /// `TimeLimit.todayMinutes()` (days without a limit report 0 and are
  /// skipped by the overview).
  int _todayLimitMinutes(List<int>? weekly, int daily) {
    if (weekly != null) {
      final idx = DateTime.now().weekday - 1; // Mon=1..Sun=7 -> Mon=0..Sun=6
      if (idx >= 0 && idx < weekly.length) return weekly[idx];
    }
    return daily;
  }

  Future<void> _loadLimits() async {
    try {
      final channel = widget.controller.channel;
      final usage = await channel.getUsageToday();
      final groups = await channel.getGroups();
      var labels = <String, String>{};
      try {
        final apps = await channel.listInstalledApps();
        labels = {for (final a in apps) a.packageName: a.label};
      } catch (_) {
        labels = const {};
      }

      // Groups first (the original's section order): only groups whose
      // TODAY limit is > 0; member labels sorted case-insensitively.
      final groupEntries = <_LimitEntry>[];
      for (final g in groups) {
        final limit = _todayLimitMinutes(g.weeklyMinutes, g.dailyMinutes);
        if (limit <= 0) continue;
        final memberLabels = [
          for (final p in g.packages)
            if (labels[p] != null) labels[p]!,
        ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        groupEntries.add(
          _LimitEntry(
            name: g.name,
            detail: memberLabels.isEmpty ? null : memberLabels.join(', '),
            limitMinutes: limit,
            // The original converts with TimeUnit.MILLISECONDS.toMinutes.
            usedMinutes: (usage.groups[g.id] ?? 0) ~/ 60000,
            isGroup: true,
          ),
        );
      }
      groupEntries.sort((a, b) => b.fraction.compareTo(a.fraction));

      // Apps: only apps that HAVE a limit (today > 0). The channel has
      // no batch "all limits" call, so enforcement is fetched per
      // candidate package — the candidates are today's used packages
      // plus every group member. An app with a limit that was neither
      // used today nor grouped is therefore missed here (the original
      // reads the whole limits map at once).
      final candidates = <String>{
        ...usage.packages.keys,
        for (final g in groups) ...g.packages,
      };
      final appEntries = <_LimitEntry>[];
      for (final pkg in candidates) {
        AppEnforcement enf;
        try {
          enf = await channel.getAppEnforcement(pkg);
        } catch (_) {
          continue;
        }
        final limit = enf.todayLimitMinutes;
        if (limit <= 0) continue;
        AppGroupModel? group;
        for (final g in groups) {
          if (g.packages.contains(pkg)) {
            group = g;
            break;
          }
        }
        appEntries.add(
          _LimitEntry(
            name: labels[pkg] ?? pkg,
            groupName: group?.name,
            limitMinutes: limit,
            usedMinutes: (usage.packages[pkg] ?? 0) ~/ 60000,
            isGroup: false,
          ),
        );
      }
      appEntries.sort((a, b) => b.fraction.compareTo(a.fraction));

      if (mounted) {
        setState(() => _limits = _LimitsData(groupEntries, appEntries));
      }
    } catch (_) {
      // Best-effort, like the focus card: never a blocked lock screen —
      // but a total load failure must not render as an EMPTY overview
      // (which would read as "no limits are set"). _limits stays null,
      // the overview's loading state, until a load actually succeeds
      // (v1.0.5 audit C-L6).
      if (mounted) setState(() => _limits = null);
    }
  }

  /// The original's minute format for the overview: `Xh Ymin`, `Xh`,
  /// or `Ymin` (localized).
  String _formatOverviewMinutes(int minutes) {
    final l10n = context.l10n;
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) return l10n.overviewHoursMinutes(h, m);
    if (h > 0) return l10n.overviewHours(h);
    return l10n.overviewMinutes(m);
  }

  Widget _limitCard(BuildContext context, _LimitEntry entry) {
    final theme = Theme.of(context);
    final accent = entry.reached
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    return Card(
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.secondaryContainer,
                  ),
                  child: Icon(
                    entry.isGroup ? Icons.group_outlined : Icons.apps_outlined,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (entry.detail != null || entry.groupName != null)
                        Text(
                          entry.detail ??
                              context.l10n.groupPrefix(entry.groupName!),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: entry.fraction,
                color: accent,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.usageOf(
                      _formatOverviewMinutes(entry.usedMinutes),
                      _formatOverviewMinutes(entry.limitMinutes),
                    ),
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                Text(
                  entry.reached
                      ? context.l10n.limitReached
                      : context.l10n.timeLeft(
                          _formatOverviewMinutes(
                            entry.limitMinutes - entry.usedMinutes,
                          ),
                        ),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _limitsView(BuildContext context) {
    final theme = Theme.of(context);
    final data = _limits;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_outlined),
          onPressed: () => setState(() => _showingLimits = false),
        ),
        title: Text(context.l10n.todaysUsage),
      ),
      body: data == null
          ? LoadingView(message: context.l10n.loadingUsageLimits)
          : data.isEmpty
          ? EmptyView(
              icon: Icons.hourglass_bottom_outlined,
              message: context.l10n.noLimitsSet,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                if (data.groups.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: Text(
                      context.l10n.groupsSection,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  for (final e in data.groups) ...[
                    _limitCard(context, e),
                    const SizedBox(height: 8),
                  ],
                ],
                if (data.apps.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: Text(
                      context.l10n.appsSection,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  for (final e in data.apps) ...[
                    _limitCard(context, e),
                    const SizedBox(height: 8),
                  ],
                ],
              ],
            ),
    );
  }

  // --------------------------------------------------------- Access

  /// The original's F32 no-credential fallback, shared by every path
  /// that reaches it (v1.0.5 audit C-M1): when the device has NO
  /// biometric and NO device credential enrolled, entry is allowed —
  /// and it is always surfaced with the same explanatory dialog first,
  /// never silent. (Previously the PlatformException codes below
  /// unlocked silently while the unsupported-device path showed the
  /// dialog.)
  Future<void> _unlockWithoutDeviceCredential() async {
    final l10n = context.l10n;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.noDeviceLockTitle),
        content: Text(l10n.noDeviceLockBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.continueAction),
          ),
        ],
      ),
    );
    widget.controller.unlock();
  }

  Future<void> _access() async {
    final l10n = context.l10n;
    setState(() => _authBusy = true);
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) {
        await _unlockWithoutDeviceCredential();
        return;
      }
      final ok = await _auth.authenticate(
        localizedReason: l10n.unlockReason,
        biometricOnly: false, // device credential is an allowed fallback
        persistAcrossBackgrounding: false,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () => false,
      );
      if (ok) {
        widget.controller.unlock();
      } else if (mounted) {
        showInfoSnackBar(context, l10n.authNotCompleted);
      }
    } on PlatformException catch (e) {
      // Not enrolled / no passcode set: the same documented, surfaced
      // fallback as the unsupported-device path (shared helper above).
      if (e.code == 'NotEnrolled' ||
          e.code == 'NotAvailable' ||
          e.code == 'PasscodeNotSet') {
        await _unlockWithoutDeviceCredential();
      } else if (mounted) {
        await showErrorCard(
          context,
          PrivilegedException(
            'PERMISSION_DENIED',
            l10n.authFailed(e.message ?? ''),
          ),
        );
      }
    } catch (e) {
      // Never fail silently: any other error (missing plugin host, cast
      // failure inside the biometric bridge, …) must be visible to the
      // user. Reported by the user 2026-11-09: tapping "Access app"
      // previously showed nothing at all when the prompt could not start.
      if (mounted) {
        await showErrorCard(
          context,
          PrivilegedException(
            'PERMISSION_DENIED',
            l10n.authCouldNotStart,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  // ---------------------------------------------------------- Build

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_showingLimits,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _showingLimits) {
          setState(() => _showingLimits = false);
        }
      },
      child: _showingLimits
          ? _limitsView(context)
          : Scaffold(
              appBar: AppBar(title: Text(l10n.appTitle)),
              body: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  // Brand header: the official Broken D mark, the app
                  // name in Cairo Bold, and the brand tagline — centred.
                  // v1.0.6 (user item 8): the mark is HALF its v1.0.5
                  // size (80 → 40 dp) with more empty space around the
                  // block, so the header breathes instead of crowding
                  // the entry controls. (The launcher/adaptive icon is
                  // a system asset and is not affected.)
                  const SizedBox(height: 64),
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        'assets/branding/azm_logo.png',
                        width: 40,
                        height: 40,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    l10n.appTitle,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.brandTagline,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.lockedTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  if (_impulseRunning) ...[
                    // While the impulse block runs, the original hides
                    // "Access app": countdown + focus card + quiet
                    // buttons only.
                    _impulseCountdownCard(context),
                    const SizedBox(height: 16),
                    _focusCard(context),
                    const SizedBox(height: 16),
                    _viewLimitsButton(context),
                  ] else ...[
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.errorContainer,
                        foregroundColor: theme.colorScheme.onErrorContainer,
                        minimumSize: const Size.fromHeight(56),
                      ),
                      onPressed: _panic,
                      icon: const Icon(Icons.emergency_outlined),
                      label: Text(l10n.panicButton),
                    ),
                    const SizedBox(height: 16),
                    _focusCard(context),
                    const SizedBox(height: 24),
                    Text(
                      _passwordSet
                          ? l10n.lockHelperWithPassword
                          : l10n.lockHelperBiometric,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                      onPressed: _authBusy ? null : _access,
                      icon: const Icon(Icons.fingerprint_outlined),
                      label: Text(l10n.accessApp),
                    ),
                    if (_passwordSet) ...[
                      const SizedBox(height: 4),
                      TextButton.icon(
                        onPressed: _passwordBusy ? null : _accessWithPassword,
                        icon: const Icon(Icons.password_outlined, size: 20),
                        label: Text(l10n.usePasswordInstead),
                      ),
                    ],
                    const SizedBox(height: 8),
                    _viewLimitsButton(context),
                  ],
                  const SizedBox(height: 32),
                  Text(
                    l10n.versionFooter(kAppVersion),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _viewLimitsButton(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () {
        setState(() => _showingLimits = true);
        _loadLimits(); // refresh on open, like the original's produceState
      },
      icon: const Icon(Icons.hourglass_bottom_outlined, size: 20),
      label: Text(context.l10n.viewLimits),
    );
  }
}
