/// Impulse lock (F21) + challenge configuration (F22), and Focus mode
/// (F25) screens.
///
/// Impulse settings mirror the original `ImpulseLockScreen`: every
/// settings control is enabled only while a recovery session is active
/// (starting the lock itself is not a setting and stays free), and —
/// exactly as in the original — an active impulse lock has **no early
/// stop**: it ends when its timer runs out, and natural expiry releases
/// the apps it suspended (see `AppController`).
///
/// Focus mode is driven by the native focus runtime: this screen
/// starts, pauses, resumes and stops the persisted native session
/// through the channel and mirrors its state (refreshed on
/// `focusPhaseChanged` events); the domain [FocusSession] is only the
/// display view over the native snapshot. The native side takes its
/// suspension targets (apps / groups / restrictions) from the persisted
/// focus config that the pickers below write through [ConfigStore].
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/config_store.dart';
import '../data/privileged_channel.dart';
import '../domain/challenges.dart';
import '../domain/focus.dart';
import '../domain/recovery.dart';
import 'common.dart';
import 'recovery_ui.dart';

// ------------------------------------------------------------------ Impulse

class ImpulseLockScreen extends StatefulWidget {
  const ImpulseLockScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<ImpulseLockScreen> createState() => _ImpulseLockScreenState();
}

class _ImpulseLockScreenState extends State<ImpulseLockScreen> {
  ImpulseConfig? _config;
  List<ChallengeType> _challenges = const [];
  List<String> _customPhrases = const [];
  bool _shuffle = false;
  List<InstalledApp>? _apps;
  Object? _error;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final config = await widget.controller.config.getImpulseConfig();
      final challenges = await widget.controller.config.getChallengeSelection();
      final phrases = await widget.controller.config.getCustomReadingPhrases();
      final shuffle = await widget.controller.config.getShuffleKeyboard();
      final apps = await widget.controller.channel.listInstalledApps();
      if (mounted) {
        setState(() {
          _config = config;
          _challenges = challenges;
          _customPhrases = phrases;
          _shuffle = shuffle;
          _apps = apps;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String _labelFor(String pkg) =>
      _apps?.where((a) => a.packageName == pkg).firstOrNull?.label ?? pkg;

  Future<void> _saveConfig(ImpulseConfig c) async {
    await widget.controller.config.setImpulseConfig(c);
    if (mounted) setState(() => _config = c);
  }

  Future<void> _startLock() async {
    final config = _config!;
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
      } catch (e) {
        await showErrorSnackBar(context, e);
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _pickSuspendApps() async {
    final selected = {..._config!.suspendApps};
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Apps suspended during impulse lock'),
          content: SizedBox(
            width: 360,
            height: 400,
            child: ListView(
              children: [
                for (final app in _apps!)
                  CheckboxListTile(
                    title: Text(app.label),
                    value: selected.contains(app.packageName),
                    onChanged: (v) => setLocal(() {
                      if (v == true) {
                        selected.add(app.packageName);
                      } else {
                        selected.remove(app.packageName);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected.toList()),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      await _saveConfig(_config!.copyWith(suspendApps: result));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Impulse lock')),
        body: ErrorView(error: _error!, onRetry: _load),
      );
    }
    final config = _config;
    if (config == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Impulse lock')),
        body: const LoadingView(message: 'Loading impulse lock…'),
      );
    }
    final lock = widget.controller.impulseLock;
    return Scaffold(
      appBar: AppBar(title: const Text('Impulse lock')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (lock.active && !lock.isComplete)
            GradientCard(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ListTile(
                leading: const Icon(Icons.lock_clock),
                title: Text(
                  'Impulse lock active — ${formatDuration(lock.remaining)} left',
                ),
                subtitle: const Text(
                  'Like the original, the lock has no early stop: it ends '
                  'on its own when the timer runs out, and the apps it '
                  'suspended are released then.',
                ),
              ),
            )
          else
            FilledButton.icon(
              onPressed: _startLock,
              icon: const Icon(Icons.emergency_outlined),
              label: Text('Start impulse lock (${config.durationMinutes} min)'),
            ),
          const SizedBox(height: 16),
          // All settings below are session-gated, as in the original:
          // the controls are disabled unless a recovery session is
          // active. The AnimatedBuilder rebuilds on session changes
          // (start / renew / end / expiry).
          AnimatedBuilder(
            animation: widget.controller.session,
            builder: (context, _) {
              final sessionActive = widget.controller.session.isActive;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!sessionActive)
                    ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: const Text('Settings are locked'),
                      subtitle: const Text(
                        'Impulse lock settings can only be changed during '
                        'a recovery session. Tap to open one.',
                      ),
                      trailing: const Icon(Icons.lock_open_outlined),
                      onTap: () =>
                          ensureRecoverySession(context, widget.controller),
                    ),
                  Text(
                    'Configuration',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  ListTile(
                    title: const Text('Duration'),
                    subtitle: Text('${config.durationMinutes} minutes (15–360)'),
                    trailing: SizedBox(
                      width: 180,
                      child: Slider(
                        value: config.durationMinutes.toDouble(),
                        min: 15,
                        max: 360,
                        divisions: 23,
                        label: '${config.durationMinutes} min',
                        onChanged: sessionActive
                            ? (v) => _saveConfig(
                                  config.copyWith(durationMinutes: v.round()),
                                )
                            : null,
                      ),
                    ),
                  ),
                  RadioListTile<ImpulseAction>(
                    title: const Text('Timer only'),
                    value: ImpulseAction.timerOnly,
                    groupValue: config.action,
                    onChanged: sessionActive
                        ? (v) => _saveConfig(config.copyWith(action: v))
                        : null,
                  ),
                  RadioListTile<ImpulseAction>(
                    title: const Text('Timer + suspend chosen apps'),
                    value: ImpulseAction.timerAndSuspend,
                    groupValue: config.action,
                    onChanged: sessionActive
                        ? (v) => _saveConfig(config.copyWith(action: v))
                        : null,
                  ),
                  ListTile(
                    title: Text('${config.suspendApps.length} app(s) to suspend'),
                    subtitle: Text(
                      config.suspendApps.map(_labelFor).take(3).join(', '),
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: sessionActive ? _pickSuspendApps : null,
                  ),
                  const Divider(),
                  Text(
                    'Access challenges (before a recovery session)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Text(
                    'The recovery code is asked for first; the selected '
                    'challenges then run, in order, before the session '
                    'starts.',
                  ),
                  for (final t in ChallengeType.values)
                    CheckboxListTile(
                      title: Text(t.label),
                      subtitle: t.isAvailableInV1
                          ? null
                          : const Text(
                              'Not available in this version — v1.1. It can '
                              'be selected in stored config but is skipped, never simulated.',
                            ),
                      value: _challenges.contains(t),
                      onChanged: t.isAvailableInV1 && sessionActive
                          ? (v) async {
                              final next = [..._challenges];
                              if (v == true) {
                                next.add(t);
                              } else {
                                next.remove(t);
                              }
                              if (next.isEmpty) next.add(ChallengeType.math);
                              await widget.controller.config
                                  .setChallengeSelection(next);
                              if (mounted) setState(() => _challenges = next);
                            }
                          : null,
                    ),
                  SwitchListTile(
                    title: const Text('Shuffled keypad for recovery code'),
                    subtitle: const Text(
                      'So the code cannot be learned from finger positions (F24).',
                    ),
                    value: _shuffle,
                    onChanged: (v) async {
                      if (v) {
                        // Turning the shuffle ON tightens: free, saved
                        // directly.
                        await widget.controller.config.setShuffleKeyboard(true);
                        if (mounted) setState(() => _shuffle = true);
                      } else {
                        // Shuffle → normal is a loosening (the
                        // original's ConfigTab: `loosening =
                        // shuffleKeyboard && !isShuffle`) and goes
                        // through the recovery gate.
                        await runLoosening(context, widget.controller, () async {
                          await widget.controller.config
                              .setShuffleKeyboard(false);
                          if (mounted) setState(() => _shuffle = false);
                        });
                      }
                    },
                  ),
                  ListTile(
                    title: Text(
                      '${_customPhrases.length} custom reading phrase(s)',
                    ),
                    subtitle: const Text('Added to the bundled reading passages'),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: sessionActive ? _editPhrases : null,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _editPhrases() async {
    final textController = TextEditingController(
      text: _customPhrases.join('\n'),
    );
    final saved = await showDialog<List<String>>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Custom reading phrases'),
        content: TextField(
          controller: textController,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'One phrase per line (your own words)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              textController.text
                  .split('\n')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList(),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == null) return;
    await widget.controller.config.setCustomReadingPhrases(saved);
    if (mounted) setState(() => _customPhrases = saved);
  }
}

// -------------------------------------------------------------------- Focus

class FocusModeScreen extends StatefulWidget {
  const FocusModeScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<FocusModeScreen> createState() => _FocusModeScreenState();
}

class _FocusModeScreenState extends State<FocusModeScreen> {
  FocusConfig? _config;
  FocusSession? _session;
  List<InstalledApp>? _apps;
  List<AppGroupModel>? _groups;
  Object? _error;
  Timer? _ticker;
  StreamSubscription<PrivilegedEvent>? _eventSub;

  @override
  void initState() {
    super.initState();
    _load();
    // The native session emits a phase-change event at every phase
    // boundary; mirror the new state when one arrives.
    _eventSub = widget.controller.channel.events.listen((e) {
      if (e.type == 'focusPhaseChanged') _refreshNative();
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _eventSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final config = await widget.controller.config.getFocusConfig();
      final apps = await widget.controller.channel.listInstalledApps();
      // Reflect the persisted native session (it survives process
      // death); never assume idle.
      final native = await widget.controller.channel.getFocusSession();
      if (mounted) {
        setState(() {
          _config = config;
          _apps = apps;
          _applyNative(native);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
    // Group names are picker/display data only; a failure here must
    // not take the screen down. The picker re-fetches on open and
    // surfaces errors there.
    try {
      final groups = await widget.controller.channel.getGroups();
      if (mounted) setState(() => _groups = groups);
    } catch (_) {
      // Ignored: see above.
    }
  }

  /// Rebuilds the display session from a native snapshot (null = no
  /// native session = idle).
  void _applyNative(NativeFocusSessionState? state) {
    final config = _config;
    if (config == null) return;
    _session = state == null
        ? FocusSession(config: config)
        : state.toFocusSession(
            config,
            elapsedRealtimeOffsetMs:
                widget.controller.channel.focusElapsedRealtimeOffsetMs,
            now: DateTime.now(),
          );
  }

  Future<void> _refreshNative() async {
    try {
      final native = await widget.controller.channel.getFocusSession();
      if (mounted) setState(() => _applyNative(native));
    } catch (_) {
      // Advisory re-sync: the next phase-change event or user action
      // re-reads the state; the last known snapshot stays on screen.
    }
  }

  String _labelFor(String pkg) =>
      _apps?.where((a) => a.packageName == pkg).firstOrNull?.label ?? pkg;

  String _groupNameFor(String id) =>
      _groups?.where((g) => g.id == id).firstOrNull?.name ?? id;

  Future<void> _saveConfig(FocusConfig c) async {
    await widget.controller.config.setFocusConfig(c);
    if (mounted) {
      setState(() {
        _config = c;
        final s = _session;
        if (s != null &&
            (s.phase == FocusPhase.idle || s.phase == FocusPhase.done)) {
          // No live session: the display follows the new config. A live
          // session keeps the snapshot it started with, like the
          // native side does.
          _session = FocusSession(config: c);
        }
      });
    }
  }

  /// Saves a config change, routing loosenings through the recovery
  /// gate first — the original's `recoveryGate.change(loosening)`
  /// pattern used for every focus setting.
  Future<void> _changeConfig(FocusConfig next, {required bool loosening}) async {
    if (loosening) {
      await runLoosening(context, widget.controller, () => _saveConfig(next));
    } else {
      await _saveConfig(next);
    }
  }

  // ------------------------------------------------------------ native drive

  Future<void> _startFocus() async {
    final config = _config!;
    try {
      final state = await widget.controller.channel.startFocusSession(
        focusMinutes: config.focusMinutes,
        breakMinutes: config.breakMinutes,
        longBreakMinutes: config.longBreakMinutes,
        cycles: config.cyclesBeforeLongBreak,
        autoStartFocus: config.autoStartFocus,
        soundEnabled: config.soundEnabled,
        vibrationEnabled: config.vibrationEnabled,
      );
      if (mounted) setState(() => _applyNative(state));
      await _ensureNotificationPermission();
    } catch (e) {
      await showErrorSnackBar(context, e);
    }
  }

  /// The original's starter asks for the notification permission after
  /// starting when the device-owner grant did not cover it
  /// (`FocusSessionCard.rememberFocusStarter`).
  Future<void> _ensureNotificationPermission() async {
    try {
      if (!await widget.controller.channel.hasNotificationPermission()) {
        await widget.controller.channel.requestNotificationPermission();
      }
    } catch (_) {
      // Best effort: the session runs regardless; only its status
      // notification may stay hidden.
    }
  }

  /// Plain pause: free, as in the original — the apps stay suspended.
  /// The releasing variant (long-press) is a loosening and is gated at
  /// the button.
  Future<void> _pauseFocus({bool releaseApps = false}) async {
    try {
      final state = await widget.controller.channel.pauseFocusSession(
        releaseApps: releaseApps,
      );
      if (mounted) setState(() => _applyNative(state));
    } catch (e) {
      await showErrorSnackBar(context, e);
    }
  }

  Future<void> _resumeFocus() async {
    try {
      final state = await widget.controller.channel.resumeFocusSession();
      if (mounted) setState(() => _applyNative(state));
    } catch (e) {
      await showErrorSnackBar(context, e);
    }
  }

  /// Skips the current break into the next focus phase (the original's
  /// `FocusMode.skipBreak`); offered during break phases only.
  Future<void> _skipBreak() async {
    try {
      final state = await widget.controller.channel.skipFocusSession();
      if (mounted) setState(() => _applyNative(state));
    } catch (e) {
      await showErrorSnackBar(context, e);
    }
  }

  Future<void> _stopFocus() async {
    try {
      await widget.controller.channel.stopFocusSession();
      if (mounted) setState(() => _applyNative(null));
    } catch (e) {
      await showErrorSnackBar(context, e);
    }
  }

  /// Ending a session loosens it, so it goes through the recovery gate
  /// — except in WAITING, where nothing is suspended and the original
  /// ends the session freely (`FocusSessionCard`).
  Future<void> _endFocus() async {
    if (_session?.phase == FocusPhase.waiting) {
      await _stopFocus();
    } else {
      await runLoosening(context, widget.controller, _stopFocus);
    }
  }

  void _onTick() {
    if (!mounted) return;
    final session = _session;
    if (session == null || !session.isRunning) return;
    if (session.isPhaseCompleteAt(DateTime.now())) {
      // The native alarm ends the phase and emits focusPhaseChanged;
      // re-read defensively in case the event was missed.
      _refreshNative();
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Focus mode')),
        body: ErrorView(error: _error!, onRetry: _load),
      );
    }
    final config = _config;
    final session = _session;
    if (config == null || session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Focus mode')),
        body: const LoadingView(message: 'Loading focus mode…'),
      );
    }
    final remaining = session.remainingAt(DateTime.now());
    // Timer ring is presentation only: every value below is derived
    // from the display view of the native session (remainingAt /
    // phaseDuration), and the buttons drive the native session through
    // the channel.
    final phaseLabel = switch (session.phase) {
      FocusPhase.idle => 'Not started',
      FocusPhase.focus => 'Focusing',
      FocusPhase.breakTime => 'Break',
      FocusPhase.longBreak => 'Long break',
      FocusPhase.waiting => 'Waiting',
      FocusPhase.paused => 'Paused',
      FocusPhase.done => 'Done',
    };
    final isBreakPhase =
        session.phase == FocusPhase.breakTime ||
        session.phase == FocusPhase.longBreak;
    // A break paused mid-way still offers Skip break, as in the
    // original's card: judge by the phase the session is paused from.
    final effectivePhase = session.isPaused ? session.pausedFrom : session.phase;
    final inBreakPhase =
        effectivePhase == FocusPhase.breakTime ||
        effectivePhase == FocusPhase.longBreak;
    final ringRemaining =
        session.phase == FocusPhase.idle ||
            session.phase == FocusPhase.done ||
            session.phase == FocusPhase.waiting
        ? Duration(minutes: config.focusMinutes)
        : remaining;
    final ringProgress = switch (session.phase) {
      FocusPhase.idle => 1.0,
      FocusPhase.done => 0.0,
      FocusPhase.waiting => 1.0,
      _ =>
        session.phaseDuration > Duration.zero
            ? remaining.inMilliseconds / session.phaseDuration.inMilliseconds
            : 0.0,
    };
    final currentCycle = (session.completedFocusPeriods + 1).clamp(
      1,
      config.cyclesBeforeLongBreak,
    );
    final idleLike =
        session.phase == FocusPhase.idle || session.phase == FocusPhase.done;
    return Scaffold(
      appBar: AppBar(title: const Text('Focus mode')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GradientCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                FocusTimerRing(
                  progress: ringProgress,
                  remainingText: formatClock(ringRemaining),
                  phaseLabel: phaseLabel,
                  isBreak: isBreakPhase,
                  cycleLabel: session.phase == FocusPhase.idle
                      ? '${config.focusMinutes} min focus · ${config.breakMinutes} min break'
                      : session.phase == FocusPhase.done
                      ? null
                      : session.phase == FocusPhase.waiting
                      ? 'Waiting to start the next focus'
                      : 'Cycle $currentCycle of ${config.cyclesBeforeLongBreak}',
                ),
                const SizedBox(height: 12),
                Text(
                  'Completed focus periods: ${session.completedFocusPeriods}',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    if (idleLike)
                      FilledButton.icon(
                        onPressed: _startFocus,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start'),
                      ),
                    if (session.phase == FocusPhase.waiting) ...[
                      FilledButton.icon(
                        onPressed: _startFocus,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start focus'),
                      ),
                      OutlinedButton(
                        onPressed: _stopFocus,
                        child: const Text('End session'),
                      ),
                    ],
                    if (session.isRunning) ...[
                      // A plain pause is free (the apps stay suspended);
                      // long-pressing pauses *and releases* the apps,
                      // which is a loosening and goes through the gate —
                      // the original's tap / long-press split.
                      OutlinedButton(
                        onPressed: () => _pauseFocus(),
                        onLongPress: session.phase == FocusPhase.focus
                            ? () => runLoosening(
                                context,
                                widget.controller,
                                () => _pauseFocus(releaseApps: true),
                              )
                            : null,
                        child: const Text('Pause'),
                      ),
                      OutlinedButton(
                        onPressed: _endFocus,
                        child: const Text('End (recovery)'),
                      ),
                    ],
                    if (session.isPaused) ...[
                      FilledButton(
                        onPressed: _resumeFocus,
                        child: const Text('Resume'),
                      ),
                      OutlinedButton(
                        onPressed: _endFocus,
                        child: const Text('End (recovery)'),
                      ),
                    ],
                    if (inBreakPhase)
                      OutlinedButton.icon(
                        onPressed: _skipBreak,
                        icon: const Icon(Icons.skip_next),
                        label: const Text('Skip break'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  session.phase == FocusPhase.waiting
                      ? 'The break is over. Nothing is suspended while '
                            'waiting — start the next focus when ready, or '
                            'end the session.'
                      : session.phase == FocusPhase.focus
                      ? 'Pause is free while the apps stay suspended. '
                            'Long-press Pause to release them instead '
                            '(recovery session required).'
                      : 'The session is kept by the native focus service: '
                            'it survives this app being closed, holds its '
                            'suspensions between phases, and this screen '
                            'mirrors it.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('Durations', style: Theme.of(context).textTheme.titleMedium),
          _durationRow(
            'Focus minutes',
            config.focusMinutes,
            min: FocusConfig.focusMinMinutes,
            max: FocusConfig.focusMaxMinutes,
            onChanged: (v) => _changeConfig(
              config.copyWith(focusMinutes: v),
              // A shorter focus phase loosens (original FocusModeScreen).
              loosening: v < config.focusMinutes,
            ),
          ),
          _durationRow(
            'Break minutes',
            config.breakMinutes,
            min: FocusConfig.shortBreakMinMinutes,
            max: FocusConfig.shortBreakMaxMinutes,
            onChanged: (v) => _changeConfig(
              config.copyWith(breakMinutes: v),
              // A longer break loosens.
              loosening: v > config.breakMinutes,
            ),
          ),
          _durationRow(
            'Long break minutes',
            config.longBreakMinutes,
            min: FocusConfig.longBreakMinMinutes,
            max: FocusConfig.longBreakMaxMinutes,
            onChanged: (v) => _changeConfig(
              config.copyWith(longBreakMinutes: v),
              loosening: v > config.longBreakMinutes,
            ),
          ),
          _durationRow(
            'Cycles before long break',
            config.cyclesBeforeLongBreak,
            min: FocusConfig.cyclesMin,
            max: FocusConfig.cyclesMax,
            onChanged: (v) => _changeConfig(
              config.copyWith(cyclesBeforeLongBreak: v),
              // Fewer cycles before the long break loosens.
              loosening: v < config.cyclesBeforeLongBreak,
            ),
          ),
          SwitchListTile(
            title: const Text('Auto-start next focus'),
            subtitle: const Text(
              'Start the next focus phase by itself when a break ends; '
              'otherwise the session waits. Turning it off is a loosening.',
            ),
            value: config.autoStartFocus,
            onChanged: (v) => _changeConfig(
              config.copyWith(autoStartFocus: v),
              loosening: !v,
            ),
          ),
          SwitchListTile(
            title: const Text('Sound'),
            subtitle: const Text('Play a sound at phase changes.'),
            value: config.soundEnabled,
            onChanged: (v) => _saveConfig(config.copyWith(soundEnabled: v)),
          ),
          SwitchListTile(
            title: const Text('Vibration'),
            subtitle: const Text('Vibrate at phase changes.'),
            value: config.vibrationEnabled,
            onChanged: (v) =>
                _saveConfig(config.copyWith(vibrationEnabled: v)),
          ),
          const Divider(),
          Text(
            'Suspended while focusing',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          ListTile(
            title: Text(
              '${config.suspendApps.length} app(s) suspended while focusing',
            ),
            subtitle: Text(
              config.suspendApps.map(_labelFor).take(3).join(', '),
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final result = await _pickApps(config.suspendApps);
              if (result != null) {
                await _changeConfig(
                  config.copyWith(suspendApps: result),
                  loosening: Loosening.isLooserSet(
                    oldSet: config.suspendApps.toSet(),
                    newSet: result.toSet(),
                  ),
                );
              }
            },
          ),
          ListTile(
            title: Text(
              '${config.suspendGroups.length} group(s) suspended while focusing',
            ),
            subtitle: Text(
              config.suspendGroups.map(_groupNameFor).take(3).join(', '),
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _pickGroups,
          ),
          ListTile(
            title: Text(
              '${config.restrictions.length} restriction(s) applied while focusing',
            ),
            subtitle: Text(config.restrictions.take(3).join(', ')),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _pickRestrictions,
          ),
          const UnavailableTile(
            icon: Icons.schedule_send_outlined,
            title: 'Focus schedules & reminders',
            note: 'Scheduled auto-start sessions are not in this version.',
          ),
        ],
      ),
    );
  }

  Widget _durationRow(
    String label,
    int value, {
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return ListTile(
      title: Text(label),
      trailing: SizedBox(
        width: 200,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: value > min ? () => onChanged(value - 1) : null,
            ),
            Expanded(child: Text('$value', textAlign: TextAlign.center)),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: value < max ? () => onChanged(value + 1) : null,
            ),
          ],
        ),
      ),
    );
  }

  Future<List<String>?> _pickApps(List<String> current) async {
    final selected = {...current};
    return showDialog<List<String>>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Apps to suspend while focusing'),
          content: SizedBox(
            width: 360,
            height: 400,
            child: ListView(
              children: [
                for (final app in _apps!)
                  CheckboxListTile(
                    title: Text(app.label),
                    value: selected.contains(app.packageName),
                    onChanged: (v) => setLocal(() {
                      if (v == true) {
                        selected.add(app.packageName);
                      } else {
                        selected.remove(app.packageName);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected.toList()),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  /// Group picker, following the original `FocusGroupPickerDialog`:
  /// every group with its member count, multi-select, confirm/cancel.
  /// The selection is written to the focus config, from which the
  /// native session takes its targets at start.
  Future<void> _pickGroups() async {
    final config = _config!;
    List<AppGroupModel> groups;
    try {
      groups = await widget.controller.channel.getGroups();
    } catch (e) {
      await showErrorSnackBar(context, e);
      return;
    }
    if (!mounted) return;
    setState(() => _groups = groups);
    final selected = {...config.suspendGroups};
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Groups to suspend while focusing'),
          content: SizedBox(
            width: 360,
            height: 400,
            child: groups.isEmpty
                ? const Center(child: Text('No groups yet'))
                : ListView(
                    children: [
                      for (final group in groups)
                        CheckboxListTile(
                          title: Text(group.name),
                          subtitle: Text('${group.packages.length} app(s)'),
                          value: selected.contains(group.id),
                          onChanged: (v) => setLocal(() {
                            if (v == true) {
                              selected.add(group.id);
                            } else {
                              selected.remove(group.id);
                            }
                          }),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected.toList()),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await _changeConfig(
      config.copyWith(suspendGroups: result),
      loosening: Loosening.isLooserSet(
        oldSet: config.suspendGroups.toSet(),
        newSet: result.toSet(),
      ),
    );
  }

  /// Restrictions picker, following the original
  /// `FocusRestrictionsDialog`: the system restriction keys (the same
  /// list the Restrictions tab offers), searchable, multi-select.
  /// Selected keys already in the config are kept even if they do not
  /// appear in the fetched list.
  Future<void> _pickRestrictions() async {
    final config = _config!;
    List<UserRestriction> all;
    try {
      all = await widget.controller.channel.listUserRestrictions();
    } catch (e) {
      await showErrorSnackBar(context, e);
      return;
    }
    if (!mounted) return;
    final selected = {...config.restrictions};
    var query = '';
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) {
          final visible = all
              .where(
                (r) =>
                    query.isEmpty ||
                    r.key.toLowerCase().contains(query.toLowerCase()),
              )
              .toList();
          return AlertDialog(
            title: const Text('Restrictions during focus'),
            content: SizedBox(
              width: 360,
              height: 440,
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Search restrictions',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setLocal(() => query = v),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final r in visible)
                          CheckboxListTile(
                            title: Text(r.key),
                            value: selected.contains(r.key),
                            onChanged: (v) => setLocal(() {
                              if (v == true) {
                                selected.add(r.key);
                              } else {
                                selected.remove(r.key);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, selected.toList()),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    if (result == null) return;
    await _changeConfig(
      config.copyWith(restrictions: result),
      loosening: Loosening.isLooserSet(
        oldSet: config.restrictions.toSet(),
        newSet: result.toSet(),
      ),
    );
  }
}
