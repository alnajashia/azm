/// Impulse lock (F21) + challenge configuration (F22), and Focus mode
/// (F25) screens.
///
/// Impulse settings mirror the original `ImpulseLockScreen`: every
/// settings control is enabled only while a recovery session is active
/// (starting the lock itself is not a setting and stays free). An
/// active impulse lock ends when its timer runs out — or early, when
/// the user completes the challenges they selected for Impulse Lock
/// (the challenge selection below IS the lock's unlock method, per the
/// user's directive that challenges live only inside Impulse Lock;
/// v1.0.5 audit H-1 wired the runner, which previously was dead code).
/// Both end paths release the apps the lock suspended through the same
/// `AppController` release (see `AppController.completeImpulseLockEarly`).
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
import '../data/tetris_sounds.dart';
import '../domain/challenges.dart';
import '../domain/focus.dart';
import '../domain/recovery.dart';
import '../l10n/l10n.dart';
import 'challenges_ui.dart';
import 'common.dart';
import 'lockdown_screen.dart';
import 'recovery_ui.dart';

/// Localized display name for a challenge type (the domain enum's
/// `label` stays the stable English identifier for logic/tests).
String challengeTypeLabel(BuildContext context, ChallengeType t) {
  final l10n = context.l10n;
  return switch (t) {
    ChallengeType.math => l10n.challengeMath,
    ChallengeType.words => l10n.challengeWords,
    ChallengeType.reading => l10n.challengeReading,
    ChallengeType.tetris => l10n.challengeTetris,
  };
}

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
  // Tetris (Batch I-C, item 2): loaded failure-tolerantly — the
  // defaults (3 minutes, sound on) apply when a read fails, so a
  // settings-read failure never blocks the screen.
  int _tetrisMinutes = ConfigStore.tetrisDefaultMinutes;
  bool _tetrisSoundOn = true;
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
      int tetrisMinutes = ConfigStore.tetrisDefaultMinutes;
      bool tetrisSoundOn = true;
      try {
        tetrisMinutes =
            await widget.controller.config.getTetrisMinutes();
      } catch (_) {}
      try {
        tetrisSoundOn =
            await widget.controller.config.isTetrisSoundEnabled();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _config = config;
          _challenges = challenges;
          _customPhrases = phrases;
          _shuffle = shuffle;
          _apps = apps;
          _tetrisMinutes = tetrisMinutes;
          _tetrisSoundOn = tetrisSoundOn;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String _labelFor(String pkg) =>
      _apps?.where((a) => a.packageName == pkg).firstOrNull?.label ?? pkg;

  Future<void> _saveConfig(ImpulseConfig c) async {
    // Save failures surface here (v1.0.5 audit C-M3): most callers are
    // fire-and-forget control callbacks, so the error must not escape
    // as an unhandled async error.
    try {
      await widget.controller.config.setImpulseConfig(c);
      if (mounted) setState(() => _config = c);
    } catch (e) {
      if (mounted) await showErrorCard(context, e);
    }
  }

  /// Tetris "Time to play" (Batch I-C, item 2): persists the slider
  /// value; a failure surfaces instead of silently keeping the old
  /// value on screen.
  Future<void> _saveTetrisMinutes(int minutes) async {
    try {
      await widget.controller.config.setTetrisMinutes(minutes);
      if (mounted) setState(() => _tetrisMinutes = minutes);
    } catch (e) {
      if (mounted) await showErrorCard(context, e);
    }
  }

  /// The challenge early-end (v1.0.5 audit H-1): runs the challenges
  /// the user selected for Impulse Lock — and ONLY those — and, when
  /// all complete, ends the lock through the controller's shared
  /// release path. This is the challenge runner's only call site in
  /// the app; the recovery gate never runs challenges.
  Future<void> _showChallengeUnlock() async {
    final available =
        _challenges.where((t) => t.isAvailableInV1).toList();
    if (available.isEmpty) {
      // An empty selection must not end the lock by "completing"
      // zero challenges (the selection UI forces at least Math, so
      // this is a safety net, not a reachable path).
      await showErrorCard(
        context,
        PrivilegedException('UNAVAILABLE', context.l10n.challengeUnavailableNote),
      );
      return;
    }
    final done = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.impulseUnlockTitle),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(dialogContext.l10n.impulseUnlockBody),
                const SizedBox(height: 16),
                ChallengeRunnerView(
                  types: available,
                  customPhrases: _customPhrases,
                  onAllComplete: () => Navigator.pop(dialogContext, true),
                  tetrisMinutes: _tetrisMinutes,
                  tetrisSoundOn: _tetrisSoundOn,
                  tetrisSounds:
                      TetrisSounds(widget.controller.channel),
                  onTetrisSoundChanged: (v) async {
                    try {
                      await widget.controller.config
                          .setTetrisSoundEnabled(v);
                      if (mounted) {
                        setState(() => _tetrisSoundOn = v);
                      }
                    } catch (e) {
                      if (mounted) await showErrorCard(context, e);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.l10n.cancel),
          ),
        ],
      ),
    );
    if (done != true) return;
    await widget.controller.completeImpulseLockEarly();
    if (mounted) {
      showInfoSnackBar(context, context.l10n.impulseLockEndedEarly);
      setState(() {});
    }
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
        if (!mounted) return;
        await showErrorCard(context, e);
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
          title: Text(context.l10n.appsSuspendedDuringImpulse),
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
              child: Text(context.l10n.cancel),
            ),
            // Batch J: select-all for this app picker.
            selectAllAction(
              l10n: context.l10n,
              allSelected: _apps!.isNotEmpty &&
                  _apps!.every((a) => selected.contains(a.packageName)),
              enabled: _apps!.isNotEmpty,
              onPressed: () => setLocal(() {
                if (_apps!.every((a) => selected.contains(a.packageName))) {
                  selected.clear();
                } else {
                  selected.addAll(_apps!.map((a) => a.packageName));
                }
              }),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected.toList()),
              child: Text(context.l10n.save),
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
    final l10n = context.l10n;
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.impulseLockTitle)),
        body: ErrorView(error: _error!, onRetry: _load),
      );
    }
    final config = _config;
    if (config == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.impulseLockTitle)),
        body: LoadingView(message: l10n.loadingImpulseLock),
      );
    }
    final lock = widget.controller.impulseLock;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.impulseLockTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (lock.active && !lock.isComplete)
            HeroCard(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    leading: const Icon(Icons.lock_clock_outlined),
                    title: Text(
                      l10n.impulseActiveLeft(
                        formatDuration(lock.remaining, l10n),
                      ),
                    ),
                    subtitle: Text(l10n.impulseNoEarlyStop),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: OutlinedButton.icon(
                      onPressed: _showChallengeUnlock,
                      icon: const Icon(Icons.extension_outlined),
                      label: Text(l10n.impulseUnlockEarly),
                    ),
                  ),
                ],
              ),
            )
          else
            FilledButton.icon(
              onPressed: _startLock,
              icon: const Icon(Icons.emergency_outlined),
              label: Text(l10n.startImpulseLock(config.durationMinutes)),
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!sessionActive)
                    ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: Text(l10n.settingsLocked),
                      subtitle: Text(l10n.settingsLockedSub),
                      trailing: const Icon(Icons.lock_open_outlined),
                      onTap: () =>
                          ensureRecoverySession(context, widget.controller),
                    ),
                  // v1.0.5 UX (user directive): titled card groups,
                  // like the Status tab — no flat ungrouped settings.
                  SectionCard(
                    title: l10n.configurationSection,
                    children: [
                      ListTile(
                        title: Text(l10n.durationLabel),
                        subtitle: Text(
                          l10n.durationMinutes(config.durationMinutes),
                        ),
                        trailing: SizedBox(
                          width: 180,
                          child: Slider(
                            value: config.durationMinutes.toDouble(),
                            min: 15,
                            max: 360,
                            divisions: 23,
                            label: l10n.minutesShort(config.durationMinutes),
                            onChanged: sessionActive
                                ? (v) => _saveConfig(
                                    config.copyWith(durationMinutes: v.round()),
                                  )
                                : null,
                          ),
                        ),
                      ),
                      // RadioGroup migration (Flutter 3.32+ deprecates
                      // RadioListTile.groupValue/onChanged): the group now
                      // carries the value and the change handler — same values,
                      // same initial selection. RadioGroup.onChanged is
                      // non-nullable in the new API, so the session gate moves
                      // to each tile's `enabled` flag: with no active session
                      // both tiles are disabled and can never fire the handler,
                      // exactly as null per-tile handlers behaved before.
                      RadioGroup<ImpulseAction>(
                        groupValue: config.action,
                        onChanged: (v) =>
                            _saveConfig(config.copyWith(action: v)),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RadioListTile<ImpulseAction>(
                              title: Text(l10n.timerOnly),
                              value: ImpulseAction.timerOnly,
                              enabled: sessionActive,
                            ),
                            RadioListTile<ImpulseAction>(
                              title: Text(l10n.timerAndSuspend),
                              value: ImpulseAction.timerAndSuspend,
                              enabled: sessionActive,
                            ),
                          ],
                        ),
                      ),
                      ListTile(
                        title: Text(
                          l10n.appsToSuspendCount(config.suspendApps.length),
                        ),
                        subtitle: Text(
                          config.suspendApps.map(_labelFor).take(3).join(', '),
                        ),
                        trailing: const Icon(Icons.edit_outlined),
                        // Batch G, item 11: the app picker is available
                        // ONLY in "timer + suspend" mode. In "timer only"
                        // the saved list is ignored by enforcement
                        // (AppController.startImpulseLock records it only
                        // for timerAndSuspend), so offering the picker
                        // there let the user pick apps that would never
                        // be suspended.
                        onTap:
                            sessionActive &&
                                    config.action ==
                                        ImpulseAction.timerAndSuspend
                                ? _pickSuspendApps
                                : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: l10n.accessChallengesSection,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                        child: Text(l10n.accessChallengesBody),
                      ),
                      for (final t in ChallengeType.values)
                        CheckboxListTile(
                          title: Text(challengeTypeLabel(context, t)),
                          subtitle: t.isAvailableInV1
                              ? null
                              : Text(l10n.challengeUnavailableNote),
                          value: _challenges.contains(t),
                          onChanged: t.isAvailableInV1 && sessionActive
                              ? (v) async {
                                  final next = [..._challenges];
                                  if (v == true) {
                                    next.add(t);
                                  } else {
                                    next.remove(t);
                                  }
                                  if (next.isEmpty) {
                                    next.add(ChallengeType.math);
                                  }
                                  try {
                                    await widget.controller.config
                                        .setChallengeSelection(next);
                                    if (mounted) {
                                      setState(() => _challenges = next);
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      await showErrorCard(context, e);
                                    }
                                  }
                                }
                              : null,
                        ),
                      // Tetris (Batch I-C, item 2): "Time to play" — how
                      // long the user must actively play (1–15 min,
                      // default 3, the evidence-based dose). Shown only
                      // while Tetris is selected. Saved when the drag
                      // ends, not per tick.
                      if (_challenges.contains(ChallengeType.tetris)) ...[
                        ListTile(
                          title: Text(l10n.tetrisDuration),
                          subtitle:
                              Text(l10n.tetrisMinutes(_tetrisMinutes)),
                        ),
                        Slider(
                          min: ConfigStore.tetrisMinMinutes.toDouble(),
                          max: ConfigStore.tetrisMaxMinutes.toDouble(),
                          divisions: ConfigStore.tetrisMaxMinutes -
                              ConfigStore.tetrisMinMinutes,
                          value: _tetrisMinutes.toDouble(),
                          label: l10n.tetrisMinutes(_tetrisMinutes),
                          onChanged: sessionActive
                              ? (v) {
                                  setState(
                                    () => _tetrisMinutes = v.round(),
                                  );
                                }
                              : null,
                          onChangeEnd: (v) => _saveTetrisMinutes(v.round()),
                        ),
                      ],
                      SwitchListTile(
                        title: Text(l10n.shuffledKeypad),
                        subtitle: Text(l10n.shuffledKeypadSub),
                        value: _shuffle,
                        // Disabled without a session, like every sibling
                        // setting on this screen (v1.0.5 audit C-L2);
                        // the "settings locked" tile above opens the
                        // gate. (Its loosening direction still routes
                        // through runLoosening when a session is active
                        // but the change itself loosens — defence in
                        // depth, unchanged.)
                        onChanged: sessionActive
                            ? (v) async {
                          if (v) {
                            // Turning the shuffle ON tightens: free, saved
                            // directly (errors surfaced, audit C-M3).
                            try {
                              await widget.controller.config
                                  .setShuffleKeyboard(true);
                              if (mounted) setState(() => _shuffle = true);
                            } catch (e) {
                              if (context.mounted) {
                                await showErrorCard(context, e);
                              }
                            }
                          } else {
                            // Shuffle → normal is a loosening (the
                            // original's ConfigTab: `loosening =
                            // shuffleKeyboard && !isShuffle`) and goes
                            // through the recovery gate.
                            await runLoosening(
                              context,
                              widget.controller,
                              () async {
                                await widget.controller.config
                                    .setShuffleKeyboard(false);
                                if (mounted) setState(() => _shuffle = false);
                              },
                            );
                          }
                            }
                            : null,
                      ),
                      ListTile(
                        title: Text(
                          l10n.customPhrasesCount(_customPhrases.length),
                        ),
                        subtitle: Text(l10n.customPhrasesSub),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: sessionActive ? _editPhrases : null,
                      ),
                    ],
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
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.customReadingPhrases),
        content: TextField(
          controller: textController,
          maxLines: 8,
          decoration: InputDecoration(
            labelText: dialogContext.l10n.onePhrasePerLine,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              textController.text
                  .split('\n')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList(),
            ),
            child: Text(dialogContext.l10n.save),
          ),
        ],
      ),
    );
    if (saved == null) return;
    try {
      await widget.controller.config.setCustomReadingPhrases(saved);
      if (mounted) setState(() => _customPhrases = saved);
    } catch (e) {
      if (mounted) await showErrorCard(context, e);
    }
  }
}

// -------------------------------------------------------------------- Focus

class FocusModeScreen extends StatefulWidget {
  const FocusModeScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<FocusModeScreen> createState() => _FocusModeScreenState();
}

class _FocusModeScreenState extends State<FocusModeScreen>
    with WidgetsBindingObserver {
  FocusConfig? _config;
  FocusSession? _session;
  List<InstalledApp>? _apps;
  List<AppGroupModel>? _groups;
  List<FocusSchedule>? _schedules;
  bool _canScheduleExactAlarms = true;
  Object? _error;
  Timer? _ticker;
  StreamSubscription<PrivilegedEvent>? _eventSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    // The native session emits a phase-change event at every phase
    // boundary; mirror the new state when one arrives.
    _eventSub = widget.controller.channel.events.listen((e) {
      if (e.type == 'focusPhaseChanged') _refreshNative();
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from the exact-alarm settings page (or the reminder
    // activity) may have changed the schedules or the permission —
    // re-read both instead of showing a stale banner.
    if (state == AppLifecycleState.resumed) _loadSchedules();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    await _loadSchedules();
  }

  /// Schedules are advisory like groups: a failure shows an error
  /// banner state (empty list + exact-alarms assumed on) instead of
  /// taking the screen down.
  Future<void> _loadSchedules() async {
    try {
      final state = await widget.controller.channel.getFocusSchedules();
      if (mounted) {
        setState(() {
          _schedules = state.schedules;
          _canScheduleExactAlarms = state.canScheduleExactAlarms;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _schedules = const []);
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
    // Direct callers (sound/vibration switches, tightening changes)
    // are fire-and-forget: surface failures here instead of letting
    // them escape unhandled (v1.0.5 audit C-M3).
    try {
      await widget.controller.config.setFocusConfig(c);
    } catch (e) {
      if (mounted) await showErrorCard(context, e);
      return;
    }
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
  Future<void> _changeConfig(
    FocusConfig next, {
    required bool loosening,
  }) async {
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
      if (!mounted) return;
      await showErrorCard(context, e);
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
      if (!mounted) return;
      await showErrorCard(context, e);
    }
  }

  Future<void> _resumeFocus() async {
    try {
      final state = await widget.controller.channel.resumeFocusSession();
      if (mounted) setState(() => _applyNative(state));
    } catch (e) {
      if (!mounted) return;
      await showErrorCard(context, e);
    }
  }

  /// Skips the current break into the next focus phase (the original's
  /// `FocusMode.skipBreak`); offered during break phases only.
  Future<void> _skipBreak() async {
    try {
      final state = await widget.controller.channel.skipFocusSession();
      if (mounted) setState(() => _applyNative(state));
    } catch (e) {
      if (!mounted) return;
      await showErrorCard(context, e);
    }
  }

  Future<void> _stopFocus() async {
    try {
      await widget.controller.channel.stopFocusSession();
      if (mounted) setState(() => _applyNative(null));
    } catch (e) {
      if (!mounted) return;
      await showErrorCard(context, e);
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
    final l10n = context.l10n;
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.focusMode)),
        body: ErrorView(error: _error!, onRetry: _load),
      );
    }
    final config = _config;
    final session = _session;
    if (config == null || session == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.focusMode)),
        body: LoadingView(message: l10n.loadingFocusMode),
      );
    }
    final remaining = session.remainingAt(DateTime.now());
    // Timer ring is presentation only: every value below is derived
    // from the display view of the native session (remainingAt /
    // phaseDuration), and the buttons drive the native session through
    // the channel.
    final phaseLabel = switch (session.phase) {
      FocusPhase.idle => l10n.phaseNotStarted,
      FocusPhase.focus => l10n.phaseFocusing,
      FocusPhase.breakTime => l10n.phaseBreak,
      FocusPhase.longBreak => l10n.focusLongBreak,
      FocusPhase.waiting => l10n.phaseWaiting,
      FocusPhase.paused => l10n.phasePaused,
      FocusPhase.done => l10n.phaseDone,
    };
    final isBreakPhase =
        session.phase == FocusPhase.breakTime ||
        session.phase == FocusPhase.longBreak;
    // A break paused mid-way still offers Skip break, as in the
    // original's card: judge by the phase the session is paused from.
    final effectivePhase = session.isPaused
        ? session.pausedFrom
        : session.phase;
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
      appBar: AppBar(title: Text(l10n.focusMode)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          HeroCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                FocusTimerRing(
                  progress: ringProgress,
                  remainingText: formatClock(ringRemaining),
                  phaseLabel: phaseLabel,
                  isBreak: isBreakPhase,
                  cycleLabel: session.phase == FocusPhase.idle
                      ? l10n.focusIdleSummary(
                          config.focusMinutes,
                          config.breakMinutes,
                        )
                      : session.phase == FocusPhase.done
                      ? null
                      : session.phase == FocusPhase.waiting
                      ? l10n.waitingNextFocus
                      : l10n.cycleOf(
                          currentCycle,
                          config.cyclesBeforeLongBreak,
                        ),
                ),
                const SizedBox(height: 12),
                Text(l10n.completedFocusPeriods(session.completedFocusPeriods)),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    if (idleLike)
                      FilledButton.icon(
                        onPressed: _startFocus,
                        icon: const Icon(Icons.play_arrow_outlined),
                        label: Text(l10n.startAction),
                      ),
                    if (session.phase == FocusPhase.waiting) ...[
                      FilledButton.icon(
                        onPressed: _startFocus,
                        icon: const Icon(Icons.play_arrow_outlined),
                        label: Text(l10n.startFocusAction),
                      ),
                      OutlinedButton(
                        onPressed: _stopFocus,
                        child: Text(l10n.endSession),
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
                        child: Text(l10n.pauseAction),
                      ),
                      OutlinedButton(
                        onPressed: _endFocus,
                        child: Text(l10n.endRecovery),
                      ),
                    ],
                    if (session.isPaused) ...[
                      FilledButton(
                        onPressed: _resumeFocus,
                        child: Text(l10n.resumeAction),
                      ),
                      OutlinedButton(
                        onPressed: _endFocus,
                        child: Text(l10n.endRecovery),
                      ),
                    ],
                    if (inBreakPhase)
                      OutlinedButton.icon(
                        onPressed: _skipBreak,
                        icon: const Icon(Icons.skip_next_outlined),
                        label: Text(l10n.skipBreakAction),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  session.phase == FocusPhase.waiting
                      ? l10n.waitingBody
                      : session.phase == FocusPhase.focus
                      ? l10n.focusPauseNote
                      : l10n.focusNativeNote,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // v1.0.5 UX (user directive): titled card groups throughout.
          SectionCard(
            title: l10n.durationsSection,
            children: [
              _durationRow(
                l10n.focusMinutesLabel,
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
                l10n.breakMinutesLabel,
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
                l10n.longBreakMinutesLabel,
                config.longBreakMinutes,
                min: FocusConfig.longBreakMinMinutes,
                max: FocusConfig.longBreakMaxMinutes,
                onChanged: (v) => _changeConfig(
                  config.copyWith(longBreakMinutes: v),
                  loosening: v > config.longBreakMinutes,
                ),
              ),
              _durationRow(
                l10n.cyclesLabel,
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
                title: Text(l10n.autoStartTitle),
                subtitle: Text(l10n.autoStartSub),
                value: config.autoStartFocus,
                onChanged: (v) => _changeConfig(
                  config.copyWith(autoStartFocus: v),
                  loosening: !v,
                ),
              ),
              SwitchListTile(
                title: Text(l10n.soundTitle),
                subtitle: Text(l10n.soundSub),
                value: config.soundEnabled,
                onChanged: (v) => _saveConfig(config.copyWith(soundEnabled: v)),
              ),
              SwitchListTile(
                title: Text(l10n.vibrationTitle),
                subtitle: Text(l10n.vibrationSub),
                value: config.vibrationEnabled,
                onChanged: (v) =>
                    _saveConfig(config.copyWith(vibrationEnabled: v)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: l10n.suspendedWhileFocusing,
            children: [
              ListTile(
                title: Text(
                  l10n.appsSuspendedWhileFocusing(config.suspendApps.length),
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
                      // The `loosening` flag here means "session required":
                      // removals loosen (F23), and ADDING a target ACTIVATES
                      // focus blocking for it — code-gated by the user's
                      // v1.0.4 directive (see docs/CODE_AUDIT_v1.0.4.md).
                      // The same rule applies to the groups/restrictions
                      // pickers below.
                      loosening:
                          Loosening.isLooserSet(
                            oldSet: config.suspendApps.toSet(),
                            newSet: result.toSet(),
                          ) ||
                          result.any((e) => !config.suspendApps.contains(e)),
                    );
                  }
                },
              ),
              ListTile(
                title: Text(
                  l10n.groupsSuspendedCount(config.suspendGroups.length),
                ),
                subtitle: Text(
                  config.suspendGroups.map(_groupNameFor).take(3).join(', '),
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: _pickGroups,
              ),
              ListTile(
                title: Text(
                  l10n.restrictionsAppliedCount(config.restrictions.length),
                ),
                subtitle: Text(config.restrictions.take(3).join(', ')),
                trailing: const Icon(Icons.edit_outlined),
                onTap: _pickRestrictions,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _schedulesCard(context, l10n),
          const SizedBox(height: 12),
          // Full-phone lockdown (Batch I-B, item 14): its own screen
          // — one-shot durations, recurring windows, both tiers.
          SectionCard(
            title: l10n.lockdownTitle,
            children: [
              ListTile(
                leading: const Icon(Icons.lock_outlined),
                title: Text(l10n.lockdownTitle),
                subtitle: Text(l10n.lockdownEntrySub),
                trailing: const Icon(Icons.chevron_right_outlined),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        LockdownScreen(controller: widget.controller),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Focus schedules (Batch I-A, item 13): the v1.1 placeholder
  /// replaced by the real card — list, exact-alarm banner, add button.
  Widget _schedulesCard(BuildContext context, AppLocalizations l10n) {
    final schedules = _schedules;
    final dayNames = _dayNames(l10n);
    return SectionCard(
      title: l10n.focusSchedulesTitle,
      children: [
        if (!_canScheduleExactAlarms)
          ListTile(
            leading: const Icon(Icons.warning_amber_outlined),
            title: Text(l10n.focusScheduleExactAlarmOff),
            trailing: TextButton(
              onPressed: () async {
                await widget.controller.channel.openExactAlarmSettings();
              },
              child: Text(l10n.focusScheduleOpenSettings),
            ),
          ),
        if (schedules == null)
          const ListTile(
            leading: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: Text('…'),
          )
        else if (schedules.isEmpty)
          ListTile(title: Text(l10n.focusSchedulesEmpty))
        else
          for (final schedule in schedules)
            ListTile(
              title: Text(
                schedule.label.isEmpty
                    ? schedule.formattedTime
                    : '${schedule.formattedTime} · ${schedule.label}',
              ),
              subtitle: Text(
                [
                  schedule.daysSummary(
                    everyDay: l10n.focusScheduleDaysEveryDay,
                    weekdays: l10n.focusScheduleDaysWeekdays,
                    weekend: l10n.focusScheduleDaysWeekend,
                    dayNames: dayNames,
                  ),
                  schedule.autoStart
                      ? l10n.focusScheduleAutoStartBadge
                      : l10n.focusScheduleRemindBadge,
                  if (schedule.remindMinutesBefore > 0)
                    l10n.focusScheduleRemindMinutes(
                      schedule.remindMinutesBefore,
                    ),
                ].join(' · '),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: schedule.enabled,
                    onChanged: (v) async {
                      final current = _schedules ?? const [];
                      final next = current
                          .map(
                            (s) => s.id == schedule.id
                                ? s.copyWith(enabled: v)
                                : s,
                          )
                          .toList();
                      await _saveSchedules(
                        next,
                        loosening: _schedulesChangeNeedsCode(current, next),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outlined),
                    tooltip: l10n.delete,
                    onPressed: () => _deleteSchedule(schedule),
                  ),
                ],
              ),
              onTap: () => _editSchedule(schedule),
            ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: FilledButton.icon(
            onPressed: () => _editSchedule(null),
            icon: const Icon(Icons.add_outlined),
            label: Text(l10n.focusScheduleAdd),
          ),
        ),
      ],
    );
  }

  List<String> _dayNames(AppLocalizations l10n) => [
        l10n.dayMon,
        l10n.dayTue,
        l10n.dayWed,
        l10n.dayThu,
        l10n.dayFri,
        l10n.daySat,
        l10n.daySun,
      ];

  /// Saves a schedule list, routing code-gated changes through the
  /// recovery gate first — the same rule the focus config uses:
  /// anything that ADDS automatic enforcement (a new or newly enabled
  /// auto-start schedule) or REMOVES it (deleting, disabling, or
  /// switching off auto-start on one) needs the paper code. Plain
  /// reminder-only schedules are free, and so are time/day/label
  /// edits — they change when Azm reminds, not whether it enforces.
  Future<void> _saveSchedules(
    List<FocusSchedule> next, {
    required bool loosening,
  }) async {
    Future<void> save() async {
      try {
        final state = await widget.controller.channel.setFocusSchedules(next);
        if (mounted) {
          setState(() {
            _schedules = state.schedules;
            _canScheduleExactAlarms = state.canScheduleExactAlarms;
          });
        }
      } catch (e) {
        if (mounted) await showErrorCard(context, e);
      }
    }

    if (loosening) {
      await runLoosening(context, widget.controller, save);
    } else {
      await save();
    }
  }

  /// True when the change touches an auto-start schedule's enforcement:
  /// deleting one, disabling one, switching its auto-start off, or
  /// adding/enabling a new auto-start one. Reminder-only schedules
  /// never enforce, so their changes are free.
  bool _schedulesChangeNeedsCode(
    List<FocusSchedule> oldList,
    List<FocusSchedule> nextList,
  ) {
    final oldById = {for (final s in oldList) s.id: s};
    final nextById = {for (final s in nextList) s.id: s};
    for (final entry in oldById.entries) {
      final next = nextById[entry.key];
      final wasEnforcing = entry.value.enabled && entry.value.autoStart;
      if (next == null) {
        if (wasEnforcing) return true;
        continue;
      }
      if (wasEnforcing != (next.enabled && next.autoStart)) return true;
    }
    for (final entry in nextById.entries) {
      if (!oldById.containsKey(entry.key) &&
          entry.value.enabled &&
          entry.value.autoStart) {
        return true;
      }
    }
    return false;
  }

  Future<void> _deleteSchedule(FocusSchedule schedule) async {
    final current = _schedules ?? const [];
    final next = current.where((s) => s.id != schedule.id).toList();
    await _saveSchedules(
      next,
      loosening: _schedulesChangeNeedsCode(current, next),
    );
  }

  /// Schedule editor: time picker + day chips (with Weekdays / Every
  /// day quick chips, as in the original's `FocusScheduleDialog`) +
  /// label + auto-start switch + pre-reminder choice. A new schedule
  /// defaults to Mon–Fri 08:00, the original's default.
  Future<void> _editSchedule(FocusSchedule? existing) async {
    final l10n = context.l10n;
    final dayNames = _dayNames(l10n);
    var hour = existing?.hour ?? 8;
    var minute = existing?.minute ?? 0;
    var days = {...(existing?.daysOfWeek ?? {1, 2, 3, 4, 5})};
    var autoStart = existing?.autoStart ?? false;
    // Only 0/5/10 are offered; normalize any foreign stored value.
    var remind = switch (existing?.remindMinutesBefore) {
      5 => 5,
      10 => 10,
      _ => 0,
    };
    // Intentionally not disposed after the dialog returns (Batch H
    // lesson: disposing while the route animates out crashes).
    final labelController = TextEditingController(text: existing?.label ?? '');
    final result = await showDialog<FocusSchedule>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          final time = TimeOfDay(hour: hour, minute: minute);
          return AlertDialog(
            title: Text(
              existing == null
                  ? l10n.focusScheduleAdd
                  : l10n.focusScheduleEdit,
            ),
            content: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.focusScheduleTime),
                      trailing: TextButton(
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: time,
                          );
                          if (picked != null) {
                            setLocal(() {
                              hour = picked.hour;
                              minute = picked.minute;
                            });
                          }
                        },
                        child: Text(time.format(context)),
                      ),
                    ),
                    TextField(
                      controller: labelController,
                      decoration: InputDecoration(
                        labelText: l10n.focusScheduleLabel,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(l10n.focusScheduleDays),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (var d = 1; d <= 7; d++)
                          FilterChip(
                            label: Text(dayNames[d - 1]),
                            selected: days.contains(d),
                            onSelected: (v) => setLocal(() {
                              if (v) {
                                days.add(d);
                              } else {
                                days.remove(d);
                              }
                            }),
                          ),
                        ActionChip(
                          label: Text(l10n.focusScheduleWeekdays),
                          onPressed: () =>
                              setLocal(() => days = {1, 2, 3, 4, 5}),
                        ),
                        ActionChip(
                          label: Text(l10n.focusScheduleAllDays),
                          onPressed: () => setLocal(
                            () => days = {1, 2, 3, 4, 5, 6, 7},
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.focusScheduleAutoStart),
                      subtitle: Text(l10n.focusScheduleAutoStartSub),
                      value: autoStart,
                      onChanged: (v) => setLocal(() => autoStart = v),
                    ),
                    const SizedBox(height: 4),
                    Text(l10n.focusScheduleRemindBefore),
                    const SizedBox(height: 6),
                    SegmentedButton<int>(
                      segments: [
                        ButtonSegment(
                          value: 0,
                          label: Text(l10n.focusScheduleRemindNone),
                        ),
                        ButtonSegment(
                          value: 5,
                          label: Text(l10n.focusScheduleRemindMinutes(5)),
                        ),
                        ButtonSegment(
                          value: 10,
                          label: Text(l10n.focusScheduleRemindMinutes(10)),
                        ),
                      ],
                      selected: {remind},
                      onSelectionChanged: (s) =>
                          setLocal(() => remind = s.first),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: days.isEmpty
                    ? null
                    : () => Navigator.pop(
                          context,
                          FocusSchedule(
                            id: existing?.id ??
                                'schedule-${DateTime.now().microsecondsSinceEpoch}',
                            daysOfWeek: days,
                            hour: hour,
                            minute: minute,
                            enabled: existing?.enabled ?? true,
                            autoStart: autoStart,
                            remindMinutesBefore: remind,
                            label: labelController.text.trim(),
                          ),
                        ),
                child: Text(l10n.save),
              ),
            ],
          );
        },
      ),
    );
    if (result == null) return;
    final current = _schedules ?? const [];
    final next = [
      ...current.where((s) => s.id != result.id),
      result,
    ]..sort((a, b) {
        final byTime = (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute);
        return byTime != 0 ? byTime : a.label.compareTo(b.label);
      });
    await _saveSchedules(
      next,
      loosening: _schedulesChangeNeedsCode(current, next),
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
    final result = await showAppPicker(
      context: context,
      channel: widget.controller.channel,
      title: context.l10n.appsToSuspendWhileFocusing,
      initialSelected: current.toSet(),
      preloadedApps: _apps,
    );
    return result?.toList();
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
      if (!mounted) return;
      await showErrorCard(context, e);
      return;
    }
    if (!mounted) return;
    setState(() => _groups = groups);
    final selected = {...config.suspendGroups};
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(context.l10n.groupsToSuspendWhileFocusing),
          content: SizedBox(
            width: 360,
            height: 400,
            child: groups.isEmpty
                ? Center(child: Text(context.l10n.noGroupsYet))
                : ListView(
                    children: [
                      for (final group in groups)
                        CheckboxListTile(
                          title: Text(group.name),
                          subtitle: Text(
                            context.l10n.memberCount(group.packages.length),
                          ),
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
              child: Text(context.l10n.cancel),
            ),
            // Batch J: select-all for this group picker.
            selectAllAction(
              l10n: context.l10n,
              allSelected: groups.isNotEmpty &&
                  groups.every((g) => selected.contains(g.id)),
              enabled: groups.isNotEmpty,
              onPressed: () => setLocal(() {
                if (groups.every((g) => selected.contains(g.id))) {
                  selected.clear();
                } else {
                  selected.addAll(groups.map((g) => g.id));
                }
              }),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected.toList()),
              child: Text(context.l10n.save),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await _changeConfig(
      config.copyWith(suspendGroups: result),
      loosening:
          Loosening.isLooserSet(
            oldSet: config.suspendGroups.toSet(),
            newSet: result.toSet(),
          ) ||
          result.any((e) => !config.suspendGroups.contains(e)),
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
      if (!mounted) return;
      await showErrorCard(context, e);
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
            title: Text(context.l10n.restrictionsDuringFocus),
            content: SizedBox(
              width: 360,
              height: 440,
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_outlined),
                      labelText: context.l10n.searchRestrictions,
                      border: const OutlineInputBorder(),
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
                child: Text(context.l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, selected.toList()),
                child: Text(context.l10n.save),
              ),
            ],
          );
        },
      ),
    );
    if (result == null) return;
    await _changeConfig(
      config.copyWith(restrictions: result),
      loosening:
          Loosening.isLooserSet(
            oldSet: config.restrictions.toSet(),
            newSet: result.toSet(),
          ) ||
          result.any((e) => !config.restrictions.contains(e)),
    );
  }
}
