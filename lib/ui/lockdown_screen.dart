/// Full-phone lockdown (Batch I-B, item 14): two tiers, user-chosen
/// in-app with a per-tier explanation.
///
///  - **Tier 1** (strict = false): suspends the chosen targets and
///    locks the phone now. The home screen stays, with greyed-out
///    icons.
///  - **Tier 2** (strict = true): everything in Tier 1, plus the
///    native kiosk activity — only Azm's countdown is visible.
///
/// Starting a lockdown is a tightening action and needs no code.
/// Ending one early is a loosening action and goes through the
/// recovery gate — in Tier 1 here, in Tier 2 in the kiosk activity
/// itself (the Flutter UI is unreachable while the kiosk runs).
///
/// Recurring windows always enforce when they fire, so adding,
/// deleting, enabling or disabling one needs the code; editing a
/// window's time, days, scope or tier is free.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/privileged_channel.dart';
import '../domain/lockdown.dart';
import '../l10n/l10n.dart';
import 'common.dart';
import 'recovery_ui.dart';

class LockdownScreen extends StatefulWidget {
  const LockdownScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<LockdownScreen> createState() => _LockdownScreenState();
}

class _LockdownScreenState extends State<LockdownScreen>
    with WidgetsBindingObserver {
  LockdownState? _state;
  List<AppGroupModel>? _groups;
  List<InstalledApp>? _apps;
  Timer? _timer;
  int? _remainingMs;

  // One-shot start form.
  int _durationMinutes = 180;
  LockdownScope _scope = LockdownScope.allApps;
  Set<String> _targetApps = {};
  Set<String> _targetGroups = {};
  bool _strict = false;
  final _labelController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = _remainingMs;
      if (remaining == null) return;
      if (remaining <= 1000) {
        // The lockdown just ended natively — reload the state.
        _loadState();
        return;
      }
      if (mounted) setState(() => _remainingMs = remaining - 1000);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _labelController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    await _loadState();
    try {
      _groups = await widget.controller.channel.getGroups();
    } catch (_) {
      _groups = const [];
    }
    try {
      _apps = await widget.controller.channel.listInstalledApps();
    } catch (_) {
      _apps = const [];
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadState() async {
    try {
      final state = await widget.controller.channel.getLockdownState();
      if (mounted) {
        setState(() {
          _state = state;
          _remainingMs = state.active?.remainingMs;
        });
      }
    } catch (e) {
      if (mounted) await showErrorCard(context, e);
    }
  }

  String _formatRemaining(int ms) {
    final totalSeconds = ms ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
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

  String _scopeLabel(AppLocalizations l10n, LockdownScope scope) => switch (scope) {
        LockdownScope.allApps => l10n.lockdownScopeAll,
        LockdownScope.apps => l10n.lockdownScopeApps,
        LockdownScope.groups => l10n.lockdownScopeGroups,
      };

  String _appLabel(String packageName) {
    final apps = _apps;
    if (apps == null) return packageName;
    for (final app in apps) {
      if (app.packageName == packageName) return app.label;
    }
    return packageName;
  }

  String _groupName(String groupId) {
    final groups = _groups;
    if (groups == null) return groupId;
    for (final group in groups) {
      if (group.id == groupId) return group.name;
    }
    return groupId;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = _state;
    final active = state?.active;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.lockdownTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state == null)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (active != null) _activeCard(context, l10n, active),
              if (active != null) const SizedBox(height: 12),
              if (active == null) _startCard(context, l10n),
              if (active == null) const SizedBox(height: 12),
              _windowsCard(context, l10n),
            ],
          ],
        ),
      ),
    );
  }

  Widget _activeCard(
    BuildContext context,
    AppLocalizations l10n,
    ActiveLockdown active,
  ) {
    final remaining = _remainingMs ?? active.remainingMs;
    final endTime = DateTime.fromMillisecondsSinceEpoch(active.endWallClockMs);
    final endText =
        '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';
    return SectionCard(
      title: l10n.lockdownActive,
      children: [
        ListTile(
          leading: const Icon(Icons.lock_outlined),
          title: Text(
            _formatRemaining(remaining),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            [
              if (active.label.isNotEmpty) active.label,
              l10n.lockdownEndsAt(endText),
              active.strict ? l10n.lockdownStrictBadge : l10n.lockdownTier1Badge,
              l10n.lockdownClaimed(active.claimedCount),
            ].join(' · '),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: FilledButton.icon(
            onPressed: _endEarly,
            icon: const Icon(Icons.lock_open_outlined),
            label: Text(l10n.lockdownEndEarly),
          ),
        ),
      ],
    );
  }

  Future<void> _endEarly() async {
    await runLoosening(context, widget.controller, () async {
      try {
        final state = await widget.controller.channel.endLockdown();
        if (mounted) {
          setState(() {
            _state = state;
            _remainingMs = state.active?.remainingMs;
          });
        }
      } catch (e) {
        if (mounted) await showErrorCard(context, e);
      }
    });
  }

  Widget _startCard(BuildContext context, AppLocalizations l10n) {
    return SectionCard(
      title: l10n.lockdownStartTitle,
      children: [
        ListTile(
          title: Text(l10n.lockdownDuration),
          subtitle: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 15, label: Text('15')),
              ButtonSegment(value: 30, label: Text('30')),
              ButtonSegment(value: 60, label: Text('60')),
              ButtonSegment(value: 180, label: Text('180')),
            ],
            selected: {_durationMinutes},
            onSelectionChanged: (s) =>
                setState(() => _durationMinutes = s.first),
          ),
        ),
        ListTile(
          title: Text(l10n.lockdownScope),
          subtitle: SegmentedButton<LockdownScope>(
            segments: [
              ButtonSegment(
                value: LockdownScope.allApps,
                label: Text(l10n.lockdownScopeAll),
              ),
              ButtonSegment(
                value: LockdownScope.apps,
                label: Text(l10n.lockdownScopeApps),
              ),
              ButtonSegment(
                value: LockdownScope.groups,
                label: Text(l10n.lockdownScopeGroups),
              ),
            ],
            selected: {_scope},
            onSelectionChanged: (s) => setState(() => _scope = s.first),
          ),
        ),
        if (_scope == LockdownScope.apps)
          ListTile(
            title: Text(l10n.lockdownChooseApps),
            subtitle: Text(
              _targetApps.isEmpty
                  ? l10n.lockdownNoApps
                  : _targetApps.map(_appLabel).join(', '),
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _pickApps,
          ),
        if (_scope == LockdownScope.groups)
          ListTile(
            title: Text(l10n.lockdownChooseGroups),
            subtitle: Text(
              _targetGroups.isEmpty
                  ? l10n.lockdownNoGroups
                  : _targetGroups.map(_groupName).join(', '),
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _pickGroups,
          ),
        RadioGroup<bool>(
          groupValue: _strict,
          onChanged: (v) => setState(() => _strict = v ?? false),
          child: Column(
            children: [
              RadioListTile<bool>(
                title: Text(l10n.lockdownTier1),
                subtitle: Text(l10n.lockdownTier1Sub),
                value: false,
              ),
              RadioListTile<bool>(
                title: Text(l10n.lockdownTier2),
                subtitle: Text(l10n.lockdownTier2Sub),
                value: true,
              ),
            ],
          ),
        ),
        ListTile(
          title: Text(l10n.lockdownLimitsNote),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _labelController,
            decoration: InputDecoration(labelText: l10n.lockdownLabel),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: FilledButton.icon(
            onPressed: _startEnabled ? _start : null,
            icon: const Icon(Icons.lock_outlined),
            label: Text(l10n.lockdownStart),
          ),
        ),
      ],
    );
  }

  bool get _startEnabled {
    if (_scope == LockdownScope.apps) return _targetApps.isNotEmpty;
    if (_scope == LockdownScope.groups) return _targetGroups.isNotEmpty;
    return true;
  }

  Future<void> _start() async {
    // Starting is a tightening action: no code.
    final lockdown = Lockdown(
      id: 'lockdown-${DateTime.now().microsecondsSinceEpoch}',
      kind: LockdownKind.oneShot,
      durationMinutes: _durationMinutes,
      scope: _scope,
      targetApps: _scope == LockdownScope.apps ? _targetApps : const {},
      targetGroups:
          _scope == LockdownScope.groups ? _targetGroups : const {},
      strict: _strict,
      label: _labelController.text.trim(),
    );
    try {
      final state = await widget.controller.channel.startLockdown(lockdown);
      if (mounted) {
        setState(() {
          _state = state;
          _remainingMs = state.active?.remainingMs;
        });
      }
    } catch (e) {
      if (mounted) await showErrorCard(context, e);
    }
  }

  Future<void> _pickApps() async {
    final selected = await showAppPicker(
      context: context,
      channel: widget.controller.channel,
      title: context.l10n.lockdownChooseApps,
      initialSelected: _targetApps,
      preloadedApps: _apps,
    );
    if (selected != null && mounted) {
      setState(() => _targetApps = selected);
    }
  }

  Future<void> _pickGroups() async {
    final groups = _groups ?? const [];
    var selected = Set<String>.from(_targetGroups);
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(context.l10n.lockdownChooseGroups),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final group in groups)
                  CheckboxListTile(
                    title: Text(group.name),
                    value: selected.contains(group.id),
                    onChanged: (v) => setDialogState(() {
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
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(context.l10n.cancel),
            ),
            // Batch J: select-all for this group picker.
            selectAllAction(
              l10n: context.l10n,
              allSelected: groups.isNotEmpty &&
                  groups.every((g) => selected.contains(g.id)),
              enabled: groups.isNotEmpty,
              onPressed: () => setDialogState(() {
                if (groups.every((g) => selected.contains(g.id))) {
                  selected.clear();
                } else {
                  selected.addAll(groups.map((g) => g.id));
                }
              }),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(selected),
              child: Text(context.l10n.save),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _targetGroups = result);
    }
  }

  Widget _windowsCard(BuildContext context, AppLocalizations l10n) {
    final state = _state;
    final windows =
        (state?.lockdowns ?? const []).where((l) => l.kind == LockdownKind.recurring).toList()
          ..sort((a, b) {
            final byTime = (a.startHour * 60 + a.startMinute)
                .compareTo(b.startHour * 60 + b.startMinute);
            return byTime != 0 ? byTime : a.label.compareTo(b.label);
          });
    final dayNames = _dayNames(l10n);
    return SectionCard(
      title: l10n.lockdownWindowsTitle,
      children: [
        if (state != null && !state.canScheduleExactAlarms)
          ListTile(
            leading: const Icon(Icons.warning_amber_outlined),
            title: Text(l10n.lockdownExactAlarmOff),
            trailing: TextButton(
              onPressed: () async {
                await widget.controller.channel.openExactAlarmSettings();
              },
              child: Text(l10n.focusScheduleOpenSettings),
            ),
          ),
        if (state == null)
          const ListTile(
            leading: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: Text('…'),
          )
        else if (windows.isEmpty)
          ListTile(title: Text(l10n.lockdownWindowsEmpty))
        else
          for (final window in windows)
            ListTile(
              title: Text(
                window.label.isEmpty
                    ? '${window.formattedStart} – ${window.formattedEnd}'
                    : '${window.formattedStart} – ${window.formattedEnd} · ${window.label}',
              ),
              subtitle: Text(
                [
                  window.daysSummary(
                    everyDay: l10n.focusScheduleDaysEveryDay,
                    weekdays: l10n.focusScheduleDaysWeekdays,
                    weekend: l10n.focusScheduleDaysWeekend,
                    dayNames: dayNames,
                  ),
                  _scopeLabel(l10n, window.scope),
                  window.strict
                      ? l10n.lockdownStrictBadge
                      : l10n.lockdownTier1Badge,
                ].join(' · '),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: window.enabled,
                    onChanged: (v) async {
                      final current = _state?.lockdowns ?? const [];
                      final next = current
                          .map(
                            (l) => l.id == window.id
                                ? l.copyWith(enabled: v)
                                : l,
                          )
                          .toList();
                      await _saveLockdowns(
                        next,
                        loosening: _lockdownsChangeNeedsCode(current, next),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outlined),
                    tooltip: l10n.delete,
                    onPressed: () => _deleteWindow(window),
                  ),
                ],
              ),
              onTap: () => _editWindow(window),
            ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: FilledButton.icon(
            onPressed: () => _editWindow(null),
            icon: const Icon(Icons.add_outlined),
            label: Text(l10n.lockdownWindowAdd),
          ),
        ),
      ],
    );
  }

  Future<void> _deleteWindow(Lockdown window) async {
    final current = _state?.lockdowns ?? const [];
    final next = current.where((l) => l.id != window.id).toList();
    await _saveLockdowns(
      next,
      loosening: _lockdownsChangeNeedsCode(current, next),
    );
  }

  Future<void> _saveLockdowns(
    List<Lockdown> next, {
    required bool loosening,
  }) async {
    Future<void> save() async {
      try {
        final state = await widget.controller.channel.setLockdowns(next);
        if (mounted) {
          setState(() {
            _state = state;
            _remainingMs = state.active?.remainingMs;
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

  /// True when the change touches a window's enforcement: adding,
  /// deleting, enabling or disabling one. A window always enforces
  /// when it fires, so its membership and enabled flag are gated;
  /// edits to an existing window's time, days, scope or tier are
  /// free — they change when it fires, not whether it enforces.
  bool _lockdownsChangeNeedsCode(
    List<Lockdown> oldList,
    List<Lockdown> nextList,
  ) {
    final oldById = {for (final l in oldList) l.id: l};
    final nextById = {for (final l in nextList) l.id: l};
    for (final id in oldById.keys) {
      final old = oldById[id]!;
      final next = nextById[id];
      if (next == null) return true; // deleted
      if (old.enabled && !next.enabled) return true; // disabled
      if (!old.enabled && next.enabled) return true; // enabled
    }
    for (final id in nextById.keys) {
      if (!oldById.containsKey(id)) return true; // added
    }
    return false;
  }

  Future<void> _editWindow(Lockdown? existing) async {
    final l10n = context.l10n;
    final isNew = existing == null;
    var startHour = existing?.startHour ?? 6;
    var startMinute = existing?.startMinute ?? 0;
    var endHour = existing?.endHour ?? 10;
    var endMinute = existing?.endMinute ?? 0;
    var days = Set<int>.from(
      existing?.daysOfWeek ?? const {1, 2, 3, 4, 5},
    );
    var scope = existing?.scope ?? LockdownScope.allApps;
    var targetApps = Set<String>.from(existing?.targetApps ?? const {});
    var targetGroups = Set<String>.from(existing?.targetGroups ?? const {});
    var strict = existing?.strict ?? false;
    // The dialog's TextEditingController is intentionally not
    // disposed: disposing it right after showDialog returns crashes
    // ("used after being disposed" — the route is still animating
    // out). Same pattern as the blocked-words and schedule editors.
    final labelController =
        TextEditingController(text: existing?.label ?? '');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          bool invalidTime() =>
              // Start == end would be a 24-hour window; end before
              // start means overnight (the end is the next day).
              startHour * 60 + startMinute == endHour * 60 + endMinute;
          return AlertDialog(
            title: Text(
              isNew ? l10n.lockdownWindowAdd : l10n.lockdownWindowEdit,
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    title: Text(l10n.lockdownWindowStart),
                    trailing: Text(
                      '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')}',
                    ),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: dialogContext,
                        initialTime: TimeOfDay(
                          hour: startHour,
                          minute: startMinute,
                        ),
                      );
                      if (picked != null) {
                        setDialogState(() {
                          startHour = picked.hour;
                          startMinute = picked.minute;
                        });
                      }
                    },
                  ),
                  ListTile(
                    title: Text(l10n.lockdownWindowEnd),
                    trailing: Text(
                      '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}',
                    ),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: dialogContext,
                        initialTime: TimeOfDay(
                          hour: endHour,
                          minute: endMinute,
                        ),
                      );
                      if (picked != null) {
                        setDialogState(() {
                          endHour = picked.hour;
                          endMinute = picked.minute;
                        });
                      }
                    },
                  ),
                  Wrap(
                    spacing: 4,
                    children: [
                      for (var d = 1; d <= 7; d++)
                        FilterChip(
                          label: Text(_dayNames(l10n)[d - 1]),
                          selected: days.contains(d),
                          onSelected: (v) => setDialogState(() {
                            if (v) {
                              days.add(d);
                            } else {
                              days.remove(d);
                            }
                          }),
                        ),
                      ActionChip(
                        label: Text(l10n.focusScheduleWeekdays),
                        onPressed: () => setDialogState(
                          () => days = {1, 2, 3, 4, 5},
                        ),
                      ),
                      ActionChip(
                        label: Text(l10n.focusScheduleAllDays),
                        onPressed: () => setDialogState(
                          () => days = {1, 2, 3, 4, 5, 6, 7},
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<LockdownScope>(
                    segments: [
                      ButtonSegment(
                        value: LockdownScope.allApps,
                        label: Text(l10n.lockdownScopeAll),
                      ),
                      ButtonSegment(
                        value: LockdownScope.apps,
                        label: Text(l10n.lockdownScopeApps),
                      ),
                      ButtonSegment(
                        value: LockdownScope.groups,
                        label: Text(l10n.lockdownScopeGroups),
                      ),
                    ],
                    selected: {scope},
                    onSelectionChanged: (s) =>
                        setDialogState(() => scope = s.first),
                  ),
                  if (scope == LockdownScope.apps)
                    ListTile(
                      title: Text(l10n.lockdownChooseApps),
                      subtitle: Text(
                        targetApps.isEmpty
                            ? l10n.lockdownNoApps
                            : targetApps.map(_appLabel).join(', '),
                      ),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () async {
                        final selected = await showAppPicker(
                          context: dialogContext,
                          channel: widget.controller.channel,
                          title: l10n.lockdownChooseApps,
                          initialSelected: targetApps,
                          preloadedApps: _apps,
                        );
                        if (selected != null) {
                          setDialogState(() => targetApps = selected);
                        }
                      },
                    ),
                  if (scope == LockdownScope.groups)
                    ListTile(
                      title: Text(l10n.lockdownChooseGroups),
                      subtitle: Text(
                        targetGroups.isEmpty
                            ? l10n.lockdownNoGroups
                            : targetGroups.map(_groupName).join(', '),
                      ),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () async {
                        final groups = _groups ?? const [];
                        var selected = Set<String>.from(targetGroups);
                        final result = await showDialog<Set<String>>(
                          context: dialogContext,
                          builder: (groupDialogContext) => StatefulBuilder(
                            builder: (groupDialogContext, setGroupState) =>
                                AlertDialog(
                              title: Text(l10n.lockdownChooseGroups),
                              content: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (final group in groups)
                                      CheckboxListTile(
                                        title: Text(group.name),
                                        value: selected.contains(group.id),
                                        onChanged: (v) => setGroupState(() {
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
                                  onPressed: () =>
                                      Navigator.of(groupDialogContext).pop(),
                                  child: Text(l10n.cancel),
                                ),
                                // Batch J: select-all for this group picker.
                                selectAllAction(
                                  l10n: l10n,
                                  allSelected: groups.isNotEmpty &&
                                      groups.every(
                                        (g) => selected.contains(g.id),
                                      ),
                                  enabled: groups.isNotEmpty,
                                  onPressed: () => setGroupState(() {
                                    if (groups.every(
                                      (g) => selected.contains(g.id),
                                    )) {
                                      selected.clear();
                                    } else {
                                      selected.addAll(
                                        groups.map((g) => g.id),
                                      );
                                    }
                                  }),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.of(
                                    groupDialogContext,
                                  ).pop(selected),
                                  child: Text(l10n.save),
                                ),
                              ],
                            ),
                          ),
                        );
                        if (result != null) {
                          setDialogState(() => targetGroups = result);
                        }
                      },
                    ),
                  SwitchListTile(
                    title: Text(l10n.lockdownTier2),
                    subtitle: Text(l10n.lockdownTier2Sub),
                    value: strict,
                    onChanged: (v) => setDialogState(() => strict = v),
                  ),
                  TextField(
                    controller: labelController,
                    decoration:
                        InputDecoration(labelText: l10n.lockdownLabel),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: days.isEmpty ||
                        invalidTime() ||
                        (scope == LockdownScope.apps &&
                            targetApps.isEmpty) ||
                        (scope == LockdownScope.groups &&
                            targetGroups.isEmpty)
                    ? null
                    : () {
                        final current = _state?.lockdowns ?? const [];
                        final window = (existing ??
                                Lockdown(
                                  id:
                                      'lockdown-${DateTime.now().microsecondsSinceEpoch}',
                                ))
                            .copyWith(
                          kind: LockdownKind.recurring,
                          startHour: startHour,
                          startMinute: startMinute,
                          endHour: endHour,
                          endMinute: endMinute,
                          daysOfWeek: days,
                          scope: scope,
                          targetApps:
                              scope == LockdownScope.apps ? targetApps : {},
                          targetGroups: scope == LockdownScope.groups
                              ? targetGroups
                              : {},
                          strict: strict,
                          label: labelController.text.trim(),
                        );
                        final next = isNew
                            ? [...current, window]
                            : current
                                .map(
                                  (l) => l.id == window.id ? window : l,
                                )
                                .toList();
                        Navigator.of(dialogContext).pop();
                        _saveLockdowns(
                          next,
                          loosening:
                              _lockdownsChangeNeedsCode(current, next),
                        );
                      },
                child: Text(l10n.save),
              ),
            ],
          );
        },
      ),
    );
  }
}
