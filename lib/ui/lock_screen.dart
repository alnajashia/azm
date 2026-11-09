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
import 'common.dart';
import 'recovery_ui.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.controller});
  final AppController controller;
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
  });
  final String name;
  final String? detail;
  final int limitMinutes;
  final int usedMinutes;
  final bool isGroup;

  double get fraction =>
      limitMinutes > 0 ? math.min(1, math.max(0, usedMinutes / limitMinutes)) : 0;
  bool get reached => usedMinutes >= limitMinutes;
}

class _LimitsData {
  const _LimitsData(this.groups, this.apps);
  final List<_LimitEntry> groups;
  final List<_LimitEntry> apps;
  bool get isEmpty => groups.isEmpty && apps.isEmpty;
}

class _LockScreenState extends State<LockScreen> {
  final _auth = LocalAuthentication();
  bool _authBusy = false;

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
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onSecond());
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
            'Impulse lock started; chosen apps suspended for ${config.durationMinutes} min.',
          );
        }
      } catch (e) {
        if (mounted) await showErrorSnackBar(context, e);
      }
    } else if (mounted) {
      showInfoSnackBar(
        context,
        'Impulse lock started for ${config.durationMinutes} min.',
      );
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
            Icon(Icons.timer_outlined, size: 48, color: scheme.onErrorContainer),
            const SizedBox(height: 16),
            Text(
              'Impulse block active',
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
    final unchanged = prev != null &&
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
    final cycles = session.config.cyclesBeforeLongBreak;
    final phase = session.isPaused ? session.pausedFrom : session.phase;
    final title = switch (phase) {
      FocusPhase.focus =>
        'Focus ${math.min(session.completedFocusPeriods + 1, cycles)}/$cycles',
      FocusPhase.breakTime => 'Short break',
      FocusPhase.longBreak => 'Long break',
      FocusPhase.waiting => 'Break over',
      _ => 'Focus mode',
    };
    return session.isPaused ? '$title · paused' : title;
  }

  Future<void> _runFocusAction(Future<void> Function() action) async {
    if (_focusBusy) return;
    setState(() => _focusBusy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) await showErrorSnackBar(context, e);
    } finally {
      if (mounted) setState(() => _focusBusy = false);
    }
    await _refreshFocus();
  }

  void _focusStart() {
    _runFocusAction(() async {
      final config = _focusConfig ??
          await widget.controller.config.getFocusConfig();
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
    final start = _FocusCardAction(
      icon: Icons.play_arrow_outlined,
      label: 'Start focus',
      onTap: _focusStart,
    );
    if (session == null || session.phase == FocusPhase.idle) {
      return [start];
    }
    final actions = <_FocusCardAction>[];
    final phase = session.isPaused ? session.pausedFrom : session.phase;
    if (session.isWaiting) actions.add(start);
    if (session.isPaused) {
      actions.add(_FocusCardAction(
        icon: Icons.play_arrow_outlined,
        label: 'Resume',
        onTap: _focusResume,
      ));
    }
    if (phase == FocusPhase.breakTime || phase == FocusPhase.longBreak) {
      actions.add(_FocusCardAction(
        icon: Icons.skip_next_outlined,
        label: 'Skip break',
        onTap: _focusSkipBreak,
      ));
    }
    if (!session.isWaiting && !session.isPaused) {
      actions.add(_FocusCardAction(
        icon: Icons.pause_outlined,
        label: 'Pause',
        onTap: _focusPausePlain,
        onLongPress:
            phase == FocusPhase.focus ? _focusPauseReleasing : null,
      ));
    }
    actions.add(_FocusCardAction(
      icon: Icons.stop_outlined,
      label: 'End session',
      onTap: session.isWaiting ? _focusEndFree : _focusEndGated,
    ));
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
    final remaining =
        session?.remainingAt(DateTime.now()) ?? Duration.zero;
    final fraction = session != null && session.phaseDuration > Duration.zero
        ? math.min(
            1,
            math.max(
                0, remaining.inMilliseconds / session.phaseDuration.inMilliseconds),
          ).toDouble()
        : 0.0;
    final cycles = session?.config.cyclesBeforeLongBreak ??
        _focusConfig?.cyclesBeforeLongBreak ??
        0;
    final title = session == null ? 'Focus mode' : _focusPhaseTitle(session);
    final subtitle = session == null
        ? (_focusConfig == null
            ? null
            : '${_focusConfig!.focusMinutes} min of focus, suspending the selected apps')
        : 'Focus periods completed: '
            '${math.min(session.completedFocusPeriods, cycles)}/$cycles';
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
                        backgroundColor:
                            theme.colorScheme.primary.withValues(alpha: 0.15),
                      ),
                    ),
                    Text(
                      _formatFocusCountdown(remaining),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
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
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
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
        groupEntries.add(_LimitEntry(
          name: g.name,
          detail: memberLabels.isEmpty ? null : memberLabels.join(', '),
          limitMinutes: limit,
          // The original converts with TimeUnit.MILLISECONDS.toMinutes.
          usedMinutes: (usage.groups[g.id] ?? 0) ~/ 60000,
          isGroup: true,
        ));
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
        appEntries.add(_LimitEntry(
          name: labels[pkg] ?? pkg,
          detail: group == null ? null : 'Group: ${group.name}',
          limitMinutes: limit,
          usedMinutes: (usage.packages[pkg] ?? 0) ~/ 60000,
          isGroup: false,
        ));
      }
      appEntries.sort((a, b) => b.fraction.compareTo(a.fraction));

      if (mounted) {
        setState(() => _limits = _LimitsData(groupEntries, appEntries));
      }
    } catch (_) {
      // Best-effort, like the focus card: an empty overview, never a
      // blocked lock screen.
      if (mounted) setState(() => _limits = const _LimitsData([], []));
    }
  }

  /// The original's minute format for the overview: `Xh Ymin`, `Xh`,
  /// or `Ymin`.
  String _formatOverviewMinutes(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) return '${h}h ${m}min';
    if (h > 0) return '${h}h';
    return '${m}min';
  }

  Widget _limitCard(BuildContext context, _LimitEntry entry) {
    final theme = Theme.of(context);
    final accent =
        entry.reached ? theme.colorScheme.error : theme.colorScheme.primary;
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
                    entry.isGroup ? Icons.group : Icons.apps,
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
                      if (entry.detail != null)
                        Text(
                          entry.detail!,
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
              borderRadius: BorderRadius.circular(4),
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
                    '${_formatOverviewMinutes(entry.usedMinutes)} of '
                    '${_formatOverviewMinutes(entry.limitMinutes)}',
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                Text(
                  entry.reached
                      ? 'Limit reached'
                      : '${_formatOverviewMinutes(entry.limitMinutes - entry.usedMinutes)} left',
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
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _showingLimits = false),
        ),
        title: const Text("Today's usage"),
      ),
      body: data == null
          ? const LoadingView(message: 'Loading usage limits…')
          : data.isEmpty
              ? const EmptyView(
                  icon: Icons.hourglass_bottom_outlined,
                  message: 'No time limit set for apps or groups.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    if (data.groups.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 4),
                        child: Text(
                          'Groups',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(color: theme.colorScheme.primary),
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
                          'Apps',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(color: theme.colorScheme.primary),
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

  Future<void> _access() async {
    setState(() => _authBusy = true);
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) {
        // Original F32 fallback: no biometric and no device credential
        // enrolled => entry is allowed. Surfaced, not silent.
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('No device lock is set up'),
              content: const Text(
                'This device has no biometric or screen credential enrolled, '
                'so there is nothing to authenticate against. Entry is '
                'allowed — exactly as the original app behaves in this '
                'case. Consider setting a device PIN.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Continue'),
                ),
              ],
            ),
          );
          widget.controller.unlock();
        }
        return;
      }
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock Dominanter',
        biometricOnly: false, // device credential is an allowed fallback
        persistAcrossBackgrounding: true,
      );
      if (ok) {
        widget.controller.unlock();
      } else if (mounted) {
        showInfoSnackBar(context, 'Authentication was not completed.');
      }
    } on PlatformException catch (e) {
      // Not enrolled / no passcode set: same documented fallback as above.
      if (e.code == 'NotEnrolled' ||
          e.code == 'NotAvailable' ||
          e.code == 'PasscodeNotSet') {
        widget.controller.unlock();
      } else if (mounted) {
        await showErrorSnackBar(
          context,
          PrivilegedException(
            'PERMISSION_DENIED',
            'Authentication failed: ${e.message}',
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
    final strings = AppStrings(widget.controller.language);
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
              appBar: AppBar(title: Text(strings.appTitle)),
              body: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const Icon(Icons.lock_outline, size: 56),
                  const SizedBox(height: 12),
                  Text(
                    'Dominanter is locked',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
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
                        backgroundColor:
                            Theme.of(context).colorScheme.errorContainer,
                        foregroundColor:
                            Theme.of(context).colorScheme.onErrorContainer,
                        minimumSize: const Size.fromHeight(56),
                      ),
                      onPressed: _panic,
                      icon: const Icon(Icons.emergency_outlined),
                      label: Text(strings.panicButton),
                    ),
                    const SizedBox(height: 16),
                    _focusCard(context),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _authBusy ? null : _access,
                      icon: const Icon(Icons.fingerprint),
                      label: Text(strings.accessApp),
                    ),
                    const SizedBox(height: 12),
                    _viewLimitsButton(context),
                  ],
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
      label: const Text('View limits'),
    );
  }
}
