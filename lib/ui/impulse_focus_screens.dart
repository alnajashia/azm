/// Impulse lock (F21) + challenge configuration (F22), and Focus mode
/// (F25) screens.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/config_store.dart';
import '../data/privileged_channel.dart';
import '../domain/challenges.dart';
import '../domain/focus.dart';
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

  Future<void> _stopLock() async {
    await runLoosening(context, widget.controller, () async {
      await widget.controller.stopImpulseLock();
      final config = _config;
      if (config != null && config.suspendApps.isNotEmpty) {
        await widget.controller.channel.setAppSuspended(
          config.suspendApps,
          false,
        );
      }
      if (mounted) setState(() {});
    });
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
                  'Stopping early is a loosening action and needs a recovery session.',
                ),
                trailing: TextButton(
                  onPressed: _stopLock,
                  child: const Text('Stop'),
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
          Text('Configuration', style: Theme.of(context).textTheme.titleMedium),
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
                onChanged: (v) =>
                    _saveConfig(config.copyWith(durationMinutes: v.round())),
              ),
            ),
          ),
          RadioListTile<ImpulseAction>(
            title: const Text('Timer only'),
            value: ImpulseAction.timerOnly,
            groupValue: config.action,
            onChanged: (v) => _saveConfig(config.copyWith(action: v)),
          ),
          RadioListTile<ImpulseAction>(
            title: const Text('Timer + suspend chosen apps'),
            value: ImpulseAction.timerAndSuspend,
            groupValue: config.action,
            onChanged: (v) => _saveConfig(config.copyWith(action: v)),
          ),
          ListTile(
            title: Text('${config.suspendApps.length} app(s) to suspend'),
            subtitle: Text(
              config.suspendApps.map(_labelFor).take(3).join(', '),
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _pickSuspendApps,
          ),
          const Divider(),
          Text(
            'Access challenges (before a recovery session)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Text(
            'Selected challenges run, in order, before the recovery code '
            'can be entered.',
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
              onChanged: t.isAvailableInV1
                  ? (v) async {
                      final next = [..._challenges];
                      if (v == true) {
                        next.add(t);
                      } else {
                        next.remove(t);
                      }
                      if (next.isEmpty) next.add(ChallengeType.math);
                      await widget.controller.config.setChallengeSelection(
                        next,
                      );
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
              await widget.controller.config.setShuffleKeyboard(v);
              if (mounted) setState(() => _shuffle = v);
            },
          ),
          ListTile(
            title: Text('${_customPhrases.length} custom reading phrase(s)'),
            subtitle: const Text('Added to the bundled reading passages'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _editPhrases,
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
  Object? _error;
  Timer? _ticker;
  bool _effectsApplied = false;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final config = await widget.controller.config.getFocusConfig();
      final apps = await widget.controller.channel.listInstalledApps();
      if (mounted) {
        setState(() {
          _config = config;
          _session = FocusSession(config: config);
          _apps = apps;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String _labelFor(String pkg) =>
      _apps?.where((a) => a.packageName == pkg).firstOrNull?.label ?? pkg;

  Future<void> _saveConfig(FocusConfig c) async {
    await widget.controller.config.setFocusConfig(c);
    if (mounted) {
      setState(() {
        _config = c;
        if (_session != null && _session!.phase == FocusPhase.idle) {
          _session = FocusSession(config: c);
        }
      });
    }
  }

  /// Applies / releases the Kotlin effects of the current phase: suspend
  /// the configured apps + apply focus restrictions during focus; release
  /// during breaks and at the end.
  Future<void> _syncEffects() async {
    final session = _session!;
    final shouldEnforce = session.phase == FocusPhase.focus;
    if (shouldEnforce == _effectsApplied) return;
    final config = session.config;
    try {
      if (shouldEnforce) {
        if (config.suspendApps.isNotEmpty) {
          await widget.controller.channel.setAppSuspended(
            config.suspendApps,
            true,
            reason: 'FOCUS_MODE',
          );
        }
        for (final key in config.restrictions) {
          await widget.controller.channel.applyUserRestriction(key);
        }
      } else {
        if (config.suspendApps.isNotEmpty) {
          await widget.controller.channel.setAppSuspended(
            config.suspendApps,
            false,
          );
        }
        for (final key in config.restrictions) {
          await widget.controller.channel.clearUserRestriction(key);
        }
      }
      _effectsApplied = shouldEnforce;
    } catch (e) {
      await showErrorSnackBar(context, e);
    }
  }

  void _onTick() {
    final session = _session;
    if (session == null || !session.isRunning) return;
    if (session.isPhaseCompleteAt(DateTime.now())) {
      setState(() => _session = session.advance(DateTime.now()));
      _syncEffects();
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
    // Timer ring is presentation only: every value below is derived from
    // the existing FocusSession model (remainingAt / phaseDuration), and
    // the buttons below keep their exact original effects.
    final phaseLabel = switch (session.phase) {
      FocusPhase.idle => 'Not started',
      FocusPhase.focus => 'Focusing',
      FocusPhase.breakTime => 'Break',
      FocusPhase.longBreak => 'Long break',
      FocusPhase.paused => 'Paused',
      FocusPhase.done => 'Done',
    };
    final isBreakPhase =
        session.phase == FocusPhase.breakTime ||
        session.phase == FocusPhase.longBreak;
    final ringRemaining = session.phase == FocusPhase.idle
        ? Duration(minutes: config.focusMinutes)
        : remaining;
    final ringProgress = switch (session.phase) {
      FocusPhase.idle => 1.0,
      FocusPhase.done => 0.0,
      _ =>
        session.phaseDuration > Duration.zero
            ? remaining.inMilliseconds / session.phaseDuration.inMilliseconds
            : 0.0,
    };
    final currentCycle = (session.completedFocusPeriods + 1).clamp(
      1,
      config.cyclesBeforeLongBreak,
    );
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
                    if (session.phase == FocusPhase.idle)
                      FilledButton.icon(
                        onPressed: () async {
                          setState(
                            () => _session = session.start(DateTime.now()),
                          );
                          await _syncEffects();
                        },
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start'),
                      ),
                    if (session.isRunning) ...[
                      // Skipping a break is free; pausing is gated (F25).
                      if (session.phase != FocusPhase.focus)
                        FilledButton.tonal(
                          onPressed: () async {
                            setState(
                              () => _session = session.advance(DateTime.now()),
                            );
                            await _syncEffects();
                          },
                          child: const Text('Skip break'),
                        ),
                      OutlinedButton(
                        onPressed: () =>
                            runLoosening(context, widget.controller, () async {
                              setState(
                                () => _session = session.pause(DateTime.now()),
                              );
                            }),
                        child: const Text('Pause (recovery)'),
                      ),
                      OutlinedButton(
                        onPressed: () =>
                            runLoosening(context, widget.controller, () async {
                              setState(() => _session = session.end());
                              await _syncEffects();
                            }),
                        child: const Text('End (recovery)'),
                      ),
                    ],
                    if (session.isPaused)
                      FilledButton(
                        onPressed: () async {
                          setState(
                            () => _session = session.resume(DateTime.now()),
                          );
                          await _syncEffects();
                        },
                        child: const Text('Resume'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Note: the countdown runs while this app is alive. The '
                  'native foreground-service timer of the original is not '
                  'part of this version — suspensions are released if you '
                  'end the session here.',
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
            (v) => _saveConfig(config.copyWith(focusMinutes: v)),
          ),
          _durationRow(
            'Break minutes',
            config.breakMinutes,
            (v) => _saveConfig(config.copyWith(breakMinutes: v)),
          ),
          _durationRow(
            'Long break minutes',
            config.longBreakMinutes,
            (v) => _saveConfig(config.copyWith(longBreakMinutes: v)),
          ),
          _durationRow(
            'Cycles before long break',
            config.cyclesBeforeLongBreak,
            (v) => _saveConfig(config.copyWith(cyclesBeforeLongBreak: v)),
            min: 1,
            max: 12,
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
              if (result != null)
                await _saveConfig(config.copyWith(suspendApps: result));
            },
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
    int value,
    ValueChanged<int> onChanged, {
    int min = 1,
    int max = 180,
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
}
