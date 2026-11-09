/// Apps tab (F8, F9, F10, F13): searchable installed-app list; per-app
/// hide / suspend / uninstall-block (Device Owner, verified natively);
/// time-limit and time-window editors persisted to the native store the
/// Accessibility Service reads; basic app groups.
///
/// Gate semantics (F23): turning a protection ON is tightening (free, 5 s
/// undo); turning it OFF — or raising a limit / widening windows — is
/// loosening and requires a recovery session.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../data/privileged_channel.dart';
import '../domain/recovery.dart';
import 'common.dart';
import 'recovery_ui.dart';

class AppsTab extends StatefulWidget {
  const AppsTab({super.key, required this.controller});
  final AppController controller;
  @override
  State<AppsTab> createState() => _AppsTabState();
}

class _AppsTabState extends State<AppsTab> {
  List<InstalledApp>? _apps;
  Object? _error;
  bool _includeSystem = false;
  String _query = '';
  UsageToday? _usage;

  PrivilegedChannel get _channel => widget.controller.channel;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _apps = null;
      _error = null;
    });
    try {
      final apps = await _channel.listInstalledApps(includeSystem: _includeSystem);
      UsageToday? usage;
      try {
        usage = await _channel.getUsageToday();
      } catch (_) {
        usage = null; // usage is a display extra; the list is authoritative
      }
      if (mounted) {
        setState(() {
          _apps = apps;
          _usage = usage;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  List<InstalledApp> get _filtered {
    final apps = _apps ?? const [];
    if (_query.isEmpty) return apps;
    final q = _query.toLowerCase();
    return apps
        .where((a) => a.label.toLowerCase().contains(q) || a.packageName.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Search apps',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        SwitchListTile(
          title: const Text('Include system apps'),
          value: _includeSystem,
          onChanged: (v) {
            setState(() => _includeSystem = v);
            _load();
          },
        ),
        ListTile(
          leading: const Icon(Icons.group_work_outlined),
          title: const Text('App groups'),
          subtitle: const Text('Shared limits and windows for a set of apps'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _apps == null
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => GroupsScreen(
                      controller: widget.controller,
                      apps: _apps!,
                    ),
                  )),
        ),
        const Divider(height: 1),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_error != null) return ErrorView(error: _error!, onRetry: _load);
    if (_apps == null) return const LoadingView(message: 'Loading installed apps…');
    if (_filtered.isEmpty) {
      return const EmptyView(
        icon: Icons.apps_outlined,
        message: 'No apps match. Try a different search, or include system apps.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _filtered.length,
        itemBuilder: (context, i) {
          final app = _filtered[i];
          final usedMs = _usage?.packages[app.packageName];
          return ListTile(
            leading: const Icon(Icons.android),
            title: Text(app.label),
            subtitle: Text([
              app.packageName,
              if (app.isSystem) 'system',
              if (app.isHidden) 'hidden',
              if (app.isSuspended) 'suspended',
              if (app.isUninstallBlocked) 'uninstall blocked',
              if (usedMs != null) 'used ${formatDuration(Duration(milliseconds: usedMs))} today',
            ].join(' · ')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openApp(app),
          );
        },
      ),
    );
  }

  Future<void> _openApp(InstalledApp app) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AppManagementSheet(controller: widget.controller, app: app),
    );
    _load();
  }
}

class AppManagementSheet extends StatefulWidget {
  const AppManagementSheet({super.key, required this.controller, required this.app});
  final AppController controller;
  final InstalledApp app;
  @override
  State<AppManagementSheet> createState() => _AppManagementSheetState();
}

class _AppManagementSheetState extends State<AppManagementSheet> {
  late InstalledApp _app;
  AppEnforcement? _enforcement;
  Object? _enforcementError;
  bool _busy = false;

  PrivilegedChannel get _channel => widget.controller.channel;

  @override
  void initState() {
    super.initState();
    _app = widget.app;
    _loadEnforcement();
  }

  Future<void> _loadEnforcement() async {
    try {
      final e = await _channel.getAppEnforcement(_app.packageName);
      if (mounted) setState(() => _enforcement = e);
    } catch (err) {
      if (mounted) setState(() => _enforcementError = err);
    }
  }

  Future<void> _toggleProtection({
    required bool newValue,
    required String label,
    required Future<bool> Function(bool) apply,
    required void Function(bool verified) onVerified,
  }) async {
    Future<void> doApply() async {
      final verified = await apply(newValue);
      if (mounted) setState(() => onVerified(verified));
    }

    if (newValue) {
      // Tightening: free, deferred behind the 5 s undo window (F23) — the
      // change is only applied once the window lapses; undoing inside the
      // window means it is never applied at all. No onUndo rollback is
      // needed: this sheet's state changes only inside doApply, after the
      // native side verifies, so while the window is open there is no
      // optimistic UI state to restore.
      await runTighteningWithUndo(
        context,
        PendingChange(
          description: '$label enabled for ${_app.label}',
          direction: ChangeDirection.tightening,
          apply: doApply,
        ),
      );
    } else {
      // Loosening: recovery session required.
      await runLoosening(context, widget.controller, doApply);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          Text(_app.label, style: Theme.of(context).textTheme.titleLarge),
          Text(_app.packageName, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Suspended'),
            subtitle: const Text('The app cannot be opened while suspended.'),
            value: _app.isSuspended,
            onChanged: _busy
                ? null
                : (v) => _toggleProtection(
                      newValue: v,
                      label: 'Suspension',
                      apply: (value) async {
                        final r = await _channel
                            .setAppSuspended([_app.packageName], value, reason: 'MANUAL');
                        return r.first.isSuspended;
                      },
                      onVerified: (verified) =>
                          _app = _app.copyWith(isSuspended: verified),
                    ),
          ),
          SwitchListTile(
            title: const Text('Hidden'),
            subtitle: const Text('Removed from the launcher and app list.'),
            value: _app.isHidden,
            onChanged: _busy
                ? null
                : (v) => _toggleProtection(
                      newValue: v,
                      label: 'Hiding',
                      apply: (value) => _channel.setAppHidden(_app.packageName, value),
                      onVerified: (verified) => _app = _app.copyWith(isHidden: verified),
                    ),
          ),
          SwitchListTile(
            title: const Text('Uninstall blocked'),
            value: _app.isUninstallBlocked,
            onChanged: _busy
                ? null
                : (v) => _toggleProtection(
                      newValue: v,
                      label: 'Uninstall block',
                      apply: (value) =>
                          _channel.setUninstallBlocked(_app.packageName, value),
                      onVerified: (verified) =>
                          _app = _app.copyWith(isUninstallBlocked: verified),
                    ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Time limit'),
            subtitle: Text(_enforcement == null
                ? 'Loading…'
                : _enforcement!.hasLimit
                    ? 'Today: ${formatMinutes(_enforcement!.todayLimitMinutes)}'
                        '${_enforcement!.weeklyMinutes != null ? ' (per-weekday)' : ''}'
                    : 'No limit set'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _enforcement == null ? null : _editLimit,
          ),
          ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('Allowed time windows'),
            subtitle: Text(_enforcement == null
                ? 'Loading…'
                : _enforcement!.hasWindows
                    ? '${_enforcement!.dailyWindows.length + (_enforcement!.weeklyWindows?.expand((d) => d).length ?? 0)} window(s)'
                    : 'Usable at any time'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _enforcement == null ? null : _editWindows,
          ),
          ListTile(
            leading: const Icon(Icons.policy_outlined),
            title: const Text('Managed restrictions'),
            subtitle: const Text('Edit this app\'s declared managed configuration'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AppRestrictionsScreen(
                controller: widget.controller,
                packageName: _app.packageName,
                label: _app.label,
              ),
            )),
          ),
          if (_enforcementError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _enforcementError is PrivilegedException
                    ? friendlyError(_enforcementError! as PrivilegedException)
                    : _enforcementError.toString(),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editLimit() async {
    final current = _enforcement!;
    final result = await showDialog<({int? daily, List<int>? weekly, int reopen})>(
      context: context,
      builder: (_) => TimeLimitEditor(
        dailyMinutes: current.dailyMinutes,
        weeklyMinutes: current.weeklyMinutes,
        reopenSeconds: current.reopenSeconds,
      ),
    );
    if (result == null || !mounted) return;
    // Original gate formula (AppsTab.kt:260-266): a limit change loosens
    // when the cap grows on any day OR the reopening cooldown shrinks.
    final loosening = Loosening.isLooserLimit(
          oldDaily: current.dailyMinutes,
          oldWeekly: current.weeklyMinutes,
          newDaily: result.daily,
          newWeekly: result.weekly,
        ) ||
        result.reopen < current.reopenSeconds;
    Future<void> save() async {
      try {
        final updated = await _channel.setTimeLimit(
          _app.packageName,
          dailyMinutes: result.daily,
          weeklyMinutes: result.weekly,
          reopenSeconds: result.reopen,
        );
        if (mounted) setState(() => _enforcement = updated);
      } catch (e) {
        if (mounted) await showErrorSnackBar(context, e);
      }
    }

    if (loosening) {
      await runLoosening(context, widget.controller, save);
    } else {
      // Tightening (or neutral): free, but deferred behind the 5 s undo
      // window, exactly like the original's change(loosening=false).
      await runTighteningWithUndo(
        context,
        PendingChange(
          description: 'Time limit updated for ${_app.label}',
          direction: ChangeDirection.tightening,
          apply: save,
        ),
      );
    }
  }

  Future<void> _editWindows() async {
    final current = _enforcement!;
    final result = await showDialog<List<TimeWindowModel>>(
      context: context,
      builder: (_) => TimeWindowsEditor(windows: current.dailyWindows),
    );
    if (result == null || !mounted) return;
    List<(int, int)> tuples(List<TimeWindowModel> ws) =>
        ws.map((w) => (w.startMinute, w.endMinute)).toList();
    final newDaily = tuples(result);
    // The editor edits daily windows only, and the native store replaces
    // the whole TimeWindows on a daily save — so any per-weekday windows
    // are part of what this save decides. Judge loosening over the full
    // week (old weekly vs daily-only new), never on the daily part alone:
    // dropping weekly windows that allowed a minute the new set does not
    // is a loosening and must be gated.
    final loosening = Loosening.isLooserWindowsForWeek(
      oldDaily: tuples(current.dailyWindows),
      oldWeekly: current.weeklyWindows?.map(tuples).toList(),
      newDaily: newDaily,
      newWeekly: null,
    );
    // Even when the weekly drop does not loosen, it destroys per-day data
    // this daily-only editor never showed. That loss must not be silent:
    // require a session whenever real per-weekday windows would be
    // replaced by something different. (A weekly structure identical to
    // the daily result on every day converts losslessly and stays free.)
    final weekly = current.weeklyWindows;
    final dropsWeekly = weekly != null &&
        weekly.length == 7 &&
        weekly.any((d) => d.isNotEmpty) &&
        !List.generate(7, (day) => day)
            .every((day) => _sameWindowSet(weekly[day], newDaily));
    Future<void> save() async {
      try {
        final updated = await _channel.setTimeWindows(_app.packageName, dailyWindows: result);
        if (mounted) setState(() => _enforcement = updated);
      } catch (e) {
        if (mounted) await showErrorSnackBar(context, e);
      }
    }

    if (loosening || dropsWeekly) {
      await runLoosening(context, widget.controller, save);
    } else {
      await runTighteningWithUndo(
        context,
        PendingChange(
          description: 'Time windows updated for ${_app.label}',
          direction: ChangeDirection.tightening,
          apply: save,
        ),
      );
    }
  }

  static bool _sameWindowSet(List<TimeWindowModel> a, List<(int, int)> b) {
    final sa = a.map((w) => (w.startMinute, w.endMinute)).toSet();
    final sb = b.toSet();
    return sa.length == sb.length && sa.containsAll(sb);
  }
}

/// Daily or per-weekday time-limit editor. Per-weekday values map to the
/// Kotlin DayOfWeek order (Monday first).
class TimeLimitEditor extends StatefulWidget {
  const TimeLimitEditor({
    super.key,
    required this.dailyMinutes,
    required this.weeklyMinutes,
    required this.reopenSeconds,
  });
  final int dailyMinutes;
  final List<int>? weeklyMinutes;
  final int reopenSeconds;
  @override
  State<TimeLimitEditor> createState() => _TimeLimitEditorState();
}

class _TimeLimitEditorState extends State<TimeLimitEditor> {
  late bool _perWeekday;
  late final TextEditingController _daily;
  late final List<TextEditingController> _days;
  late final TextEditingController _reopen;

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    _perWeekday = widget.weeklyMinutes != null;
    _daily = TextEditingController(text: widget.dailyMinutes.toString());
    _days = List.generate(
      7,
      (i) => TextEditingController(
          text: (widget.weeklyMinutes?[i] ?? widget.dailyMinutes).toString()),
    );
    _reopen = TextEditingController(text: widget.reopenSeconds.toString());
  }

  @override
  void dispose() {
    _daily.dispose();
    for (final d in _days) d.dispose();
    _reopen.dispose();
    super.dispose();
  }

  int _parse(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Time limit (minutes)'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Daily')),
                  ButtonSegment(value: true, label: Text('Per weekday')),
                ],
                selected: {_perWeekday},
                onSelectionChanged: (s) => setState(() => _perWeekday = s.first),
              ),
              const SizedBox(height: 16),
              if (!_perWeekday)
                TextField(
                  controller: _daily,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Minutes per day (0 = no limit)',
                    border: OutlineInputBorder(),
                  ),
                )
              else
                for (var i = 0; i < 7; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: _days[i],
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '${_dayNames[i]} (0 = no limit)',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
              const SizedBox(height: 8),
              TextField(
                controller: _reopen,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Reopening cooldown, seconds (stored; enforcement is v1.1)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final reopen = _parse(_reopen).clamp(0, 86400);
            if (_perWeekday) {
              Navigator.pop(context, (
                daily: null,
                weekly: _days.map(_parse).map((v) => v.clamp(0, 1440)).toList(),
                reopen: reopen,
              ));
            } else {
              Navigator.pop(context, (
                daily: _parse(_daily).clamp(0, 1440),
                weekly: null,
                reopen: reopen,
              ));
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class TimeWindowsEditor extends StatefulWidget {
  const TimeWindowsEditor({super.key, required this.windows});
  final List<TimeWindowModel> windows;
  @override
  State<TimeWindowsEditor> createState() => _TimeWindowsEditorState();
}

class _TimeWindowsEditorState extends State<TimeWindowsEditor> {
  late List<TimeWindowModel> _windows;

  @override
  void initState() {
    super.initState();
    _windows = [...widget.windows];
  }

  Future<void> _add() async {
    final start = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 7, minute: 0),
      helpText: 'Window start',
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 21, minute: 0),
      helpText: 'Window end (may be next day)',
    );
    if (end == null) return;
    setState(() => _windows.add(TimeWindowModel(
          start.hour * 60 + start.minute,
          end.hour * 60 + end.minute == start.hour * 60 + start.minute
              ? (end.hour * 60 + end.minute) + 1
              : end.hour * 60 + end.minute,
        )));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Allowed windows (daily)'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Outside these windows the app is blocked. An empty list '
              'means usable at any time.',
            ),
            const SizedBox(height: 12),
            if (_windows.isEmpty)
              const Text('No windows set.')
            else
              for (var i = 0; i < _windows.length; i++)
                ListTile(
                  dense: true,
                  title: Text(_windows[i].formatted),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _windows.removeAt(i)),
                  ),
                ),
            TextButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const Text('Add window'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _windows),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------------- Groups

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key, required this.controller, required this.apps});
  final AppController controller;
  final List<InstalledApp> apps;
  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  List<AppGroupModel>? _groups;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final groups = await widget.controller.channel.getGroups();
      if (mounted) setState(() => _groups = groups);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save(List<AppGroupModel> groups) async {
    try {
      final saved = await widget.controller.channel.setGroups(groups);
      if (mounted) setState(() => _groups = saved);
    } catch (e) {
      await showErrorSnackBar(context, e);
    }
  }

  Future<void> _create() async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New group'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Group name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || _groups == null) return;
    await _save([
      ..._groups!,
      AppGroupModel(id: DateTime.now().microsecondsSinceEpoch.toString(), name: name),
    ]);
  }

  Future<void> _rename(AppGroupModel group) async {
    final nameController = TextEditingController(text: group.name);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename group'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Group name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (name == null || name.isEmpty || name == group.name || _groups == null) return;
    // Renaming neither loosens nor tightens; it saves directly, like group
    // creation (the original folds rename into its group-edit dialog,
    // whose save is gated only by that dialog's loosening terms).
    await _save([
      for (final g in _groups!)
        if (g.id == group.id) g.copyWith(name: name) else g,
    ]);
  }

  /// Whether the group currently restricts its members at all — the
  /// condition under which stripping membership loosens an app.
  static bool _groupHasRestrictions(AppGroupModel g) =>
      g.dailyMinutes > 0 ||
      (g.weeklyMinutes?.any((m) => m > 0) ?? false) ||
      g.reopenSeconds > 0 ||
      g.dailyWindows.isNotEmpty ||
      (g.weeklyWindows?.any((d) => d.isNotEmpty) ?? false);

  Future<void> _editMembers(AppGroupModel group) async {
    final selected = {...group.packages};
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Members of ${group.name}'),
          content: SizedBox(
            width: 360,
            height: 400,
            child: ListView(
              children: [
                for (final app in widget.apps)
                  CheckboxListTile(
                    title: Text(app.label),
                    subtitle: Text(app.packageName),
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
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected.toList()),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result == null || _groups == null || !mounted) return;
    // Removing a member strips the group's limit/windows/cooldown from
    // that app — a loosening the original explicitly gates (group-save
    // loosening includes `!newPackages.containsAll(oldPackages)`,
    // AppManagementDialogs.kt:166-175). Pure additions tighten and stay
    // ungated, as does removal from a group carrying no restrictions.
    final loosening = Loosening.isLooserSet(
          oldSet: group.packages.toSet(),
          newSet: result.toSet(),
        ) &&
        _groupHasRestrictions(group);
    Future<void> save() => _save([
          for (final g in _groups!)
            if (g.id == group.id) g.copyWith(packages: result) else g,
        ]);
    if (loosening) {
      await runLoosening(context, widget.controller, save);
    } else {
      await runTighteningWithUndo(
        context,
        PendingChange(
          description: 'Members of ${group.name} updated',
          direction: ChangeDirection.tightening,
          apply: save,
        ),
      );
    }
  }

  Future<void> _editGroupLimit(AppGroupModel group) async {
    final result = await showDialog<({int? daily, List<int>? weekly, int reopen})>(
      context: context,
      builder: (_) => TimeLimitEditor(
        dailyMinutes: group.dailyMinutes,
        weeklyMinutes: group.weeklyMinutes,
        reopenSeconds: group.reopenSeconds,
      ),
    );
    if (result == null || _groups == null || !mounted) return;
    // Same gate formula as per-app limits: cap growth on any day, or a
    // shrinking reopening cooldown, loosens.
    final loosening = Loosening.isLooserLimit(
          oldDaily: group.dailyMinutes,
          oldWeekly: group.weeklyMinutes,
          newDaily: result.daily,
          newWeekly: result.weekly,
        ) ||
        result.reopen < group.reopenSeconds;
    Future<void> save() => _save([
          for (final g in _groups!)
            if (g.id == group.id)
              g.copyWith(
                // In per-weekday mode the editor returns no daily value;
                // preserve the stored daily fallback instead of zeroing
                // it (the original always stores both). Switching the
                // editor to Daily mode is the user's explicit choice and
                // clears the weekly values, judged by the gate above.
                dailyMinutes: result.daily ?? group.dailyMinutes,
                weeklyMinutes: result.weekly,
                clearWeeklyMinutes: result.weekly == null,
                reopenSeconds: result.reopen,
              )
            else
              g,
        ]);
    if (loosening) {
      await runLoosening(context, widget.controller, save);
    } else {
      await runTighteningWithUndo(
        context,
        PendingChange(
          description: 'Limit of ${group.name} updated',
          direction: ChangeDirection.tightening,
          apply: save,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('App groups'),
        actions: [
          IconButton(onPressed: _create, icon: const Icon(Icons.add), tooltip: 'New group'),
        ],
      ),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : _groups == null
              ? const LoadingView(message: 'Loading groups…')
              : _groups!.isEmpty
                  ? const EmptyView(
                      icon: Icons.group_work_outlined,
                      message: 'No groups yet. Create one to share a limit across apps.',
                    )
                  : ListView(
                      children: [
                        for (final g in _groups!)
                          ListTile(
                            title: Text(g.name),
                            subtitle: Text(
                              '${g.packages.length} apps · limit ${formatMinutes(g.weeklyMinutes != null ? g.weeklyMinutes![DateTime.now().weekday - 1] : g.dailyMinutes)}',
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (action) async {
                                if (action == 'members') _editMembers(g);
                                if (action == 'limit') _editGroupLimit(g);
                                if (action == 'rename') _rename(g);
                                if (action == 'delete') {
                                  await runLoosening(context, widget.controller, () async {
                                    await _save(
                                        _groups!.where((x) => x.id != g.id).toList());
                                  });
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'members', child: Text('Edit members')),
                                PopupMenuItem(value: 'limit', child: Text('Edit limit')),
                                PopupMenuItem(value: 'rename', child: Text('Rename group')),
                                PopupMenuItem(value: 'delete', child: Text('Delete group')),
                              ],
                            ),
                            onTap: () => _editMembers(g),
                          ),
                      ],
                    ),
    );
  }
}

// ------------------------------------------------------- Per-app restrictions

/// Which subset of declared restrictions the editor shows — a direct port
/// of the original's `RestrictionFilter` (`AppRestrictionsScreen.kt:143-145`):
/// ALL shows everything, ACTIVE only restrictions currently applied
/// (managed), DEFAULT only restrictions not currently applied.
enum _RestrictionFilter { all, active, defaults }

/// Draft state for one declared restriction — a port of the original's
/// `ManagedRestrictionState` (`AppRestrictionsScreen.kt:43-141`).
///
/// Nothing here is persisted until the screen's Save builds a bundle from
/// the drafts (see [_AppRestrictionsScreenState._buildDraftBundle]); a draft
/// contributes its key only while [managed] is true, exactly like
/// `writeToBundle` returning early for unmanaged entries.
class _RestrictionDraft {
  _RestrictionDraft(this.entry, Object? current) {
    _init(current);
  }

  /// Builds a draft from a declared entry, seeded with the entry's own
  /// currently applied value (null when the key is not set).
  factory _RestrictionDraft.fromEntry(AvailableRestriction entry) =>
      _RestrictionDraft(entry, entry.currentValue);

  final AvailableRestriction entry;

  /// Whether this key will be written on save — the original's `isManaged`,
  /// initialised from `currentRestrictions.containsKey(entry.key)`, here
  /// from `entry.currentValue != null`.
  bool managed = false;

  bool boolValue = false;
  String stringValue = '';

  /// Integer values stay text while editing, as in the original; an
  /// unparseable value omits the key on save instead of writing garbage.
  String intText = '';

  /// Selected values for a `stringList` (multi-select) entry, in insertion
  /// order; membership is what matters.
  List<String> listValues = const [];

  /// Whether a `bundle` entry is really a bundle *array*. The channel model
  /// maps both BUNDLE and BUNDLE_ARRAY to type `bundle` (for arrays the
  /// declared children are the per-item template, with defaults only), so
  /// the two are told apart by the shape of the current value: a List means
  /// an array of item bundles.
  bool isBundleArray = false;

  /// Child drafts for a plain `bundle` entry.
  List<_RestrictionDraft> children = const [];

  /// Item drafts for a bundle array: one child-draft list per item.
  List<List<_RestrictionDraft>> items = const [];

  /// Whether the (possibly long) description is shown in full.
  bool descExpanded = false;

  TextEditingController? _textController;
  TextEditingController? _addController;

  /// Editor controller for `string` / `int` entries, created lazily and
  /// owned by this draft.
  TextEditingController get textController => _textController ??=
      TextEditingController(text: entry.type == 'int' ? intText : stringValue);

  /// Controller for the free-form list editor's "add value" field.
  TextEditingController get addController =>
      _addController ??= TextEditingController();

  void _init(Object? current) {
    managed = current != null;
    switch (entry.type) {
      case 'bool':
        // Original: the current value when set; an unmanaged BOOLEAN entry
        // starts at `true` (`AppRestrictionsScreen.kt:52-56` — its declared
        // selectedState is only the fallback for non-boolean types).
        boolValue = current is bool ? current : true;
      case 'string':
        stringValue =
            current?.toString() ?? entry.defaultValue?.toString() ?? '';
      case 'int':
        intText = current?.toString() ??
            entry.defaultValue?.toString() ??
            '';
      case 'stringList':
        final source = current is List
            ? current
            : (entry.defaultValue is List
                ? entry.defaultValue as List
                : const []);
        listValues = source.map((e) => e.toString()).toList();
      case 'bundle':
        if (current is List) {
          isBundleArray = true;
          items = [for (final element in current) _itemDrafts(element)];
        } else {
          final map = current is Map ? current : null;
          children = [
            for (final child in entry.children)
              _RestrictionDraft(
                child,
                map != null ? map[child.key] : child.currentValue,
              ),
          ];
        }
    }
  }

  /// Builds one bundle-array item from the declared template children,
  /// overlaid with [element]'s values (a null element — a newly added
  /// item — yields the template defaults, all unmanaged, exactly like the
  /// original's `addBundleArrayItem` seeding from an empty Bundle).
  List<_RestrictionDraft> _itemDrafts(Object? element) {
    final map = element is Map ? element : null;
    return [
      for (final child in entry.children)
        _RestrictionDraft(child, map?[child.key]),
    ];
  }

  /// Adds a new bundle-array item built from the template defaults and
  /// marks the entry managed, as `addBundleArrayItem` does.
  void addBundleArrayItem() {
    items = [...items, _itemDrafts(null)];
    managed = true;
  }

  void removeBundleArrayItem(int index) {
    if (index < 0 || index >= items.length) return;
    items = [...items]..removeAt(index);
  }

  /// Writes this entry into [out] when managed — a port of the original's
  /// `writeToBundle` (`AppRestrictionsScreen.kt:109-141`): booleans,
  /// strings/choices and integers (unparseable integers are omitted) write
  /// directly; string lists write as arrays; bundles recurse into a nested
  /// map; bundle arrays write a list of item maps.
  void writeTo(Map<String, dynamic> out) {
    if (!managed) return;
    switch (entry.type) {
      case 'bool':
        out[entry.key] = boolValue;
      case 'string':
        out[entry.key] = stringValue;
      case 'int':
        final parsed = int.tryParse(intText);
        if (parsed != null) out[entry.key] = parsed;
      case 'stringList':
        out[entry.key] = _orderedListValues();
      case 'bundle':
        if (isBundleArray) {
          out[entry.key] = [
            for (final item in items) _writeChildren(item),
          ];
        } else {
          out[entry.key] = _writeChildren(children);
        }
    }
  }

  /// Multi-select values in declaration order (values not among the
  /// declared choices — possible when they arrived from the applied bundle —
  /// keep their relative order at the end), mirroring how the original's
  /// selected set round-trips through `writeToBundle`.
  List<String> _orderedListValues() {
    final choices = entry.choices;
    if (choices.isEmpty) return List<String>.of(listValues);
    final selected = listValues.toSet();
    return [
      for (final choice in choices)
        if (selected.contains(choice)) choice,
      for (final value in listValues)
        if (!choices.contains(value)) value,
    ];
  }

  static Map<String, dynamic> _writeChildren(List<_RestrictionDraft> drafts) {
    final out = <String, dynamic>{};
    for (final draft in drafts) {
      draft.writeTo(out);
    }
    return out;
  }

  void dispose() {
    _textController?.dispose();
    _addController?.dispose();
    for (final child in children) {
      child.dispose();
    }
    for (final item in items) {
      for (final child in item) {
        child.dispose();
      }
    }
  }
}

/// Structural equality for restriction bundles (maps, lists, sets and
/// scalars), used to tell whether the draft differs from what is applied.
bool _restrictionsDeepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_restrictionsDeepEquals(a[key], b[key])) {
        return false;
      }
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_restrictionsDeepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Set && b is Set) {
    return a.length == b.length && a.containsAll(b);
  }
  return a == b;
}

/// Human-readable label for a declared restriction. The channel model's
/// `titleKey` carries the target app's declared title (or the raw key when
/// the app declares none); like the original's `entry.title ?: entry.key`
/// with its string-resource fallback, an absent or key-identical title
/// falls back to a humanised form of the key. The raw key itself is always
/// shown separately under the label, as the original's card does.
String _restrictionLabel(AvailableRestriction entry) {
  final title = entry.titleKey.trim();
  if (title.isEmpty || title == entry.key) return _humaniseKey(entry.key);
  return title.replaceAll('_', ' ');
}

String _humaniseKey(String key) {
  final words =
      key.split(RegExp(r'[_\.\-]+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return key;
  return words
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

/// Per-app declared-restrictions editor (F4) — a port of the original's
/// `AppRestrictionsScreen.kt`.
///
/// The data model is the app's **declared** restrictions
/// (`getAvailableRestrictions`), not the currently-set raw values: every
/// restriction the app declares is listed, managed or not, and edits
/// accumulate in a draft ([_RestrictionDraft]) until Save. Entries the
/// channel flags hidden (e.g. `URLBlocklist`, owned by the browser
/// restrictions flow) are never offered for editing, and on save their
/// currently applied values are force-preserved into the applied bundle —
/// the original's explicit `URLBlocklist` preservation
/// (`AppRestrictionsScreen.kt:392-395`), generalised to every hidden entry.
class AppRestrictionsScreen extends StatefulWidget {
  const AppRestrictionsScreen({
    super.key,
    required this.controller,
    required this.packageName,
    required this.label,
  });
  final AppController controller;
  final String packageName;
  final String label;
  @override
  State<AppRestrictionsScreen> createState() => _AppRestrictionsScreenState();
}

class _AppRestrictionsScreenState extends State<AppRestrictionsScreen> {
  /// Every restriction the app declares, hidden ones included (they are
  /// needed on save for force-preservation).
  List<AvailableRestriction>? _available;

  /// The currently applied restrictions bundle — the authoritative "old"
  /// side for the loosening judgement and for hidden preservation.
  Map<String, dynamic>? _current;

  /// Drafts for the visible (non-hidden) declared entries.
  List<_RestrictionDraft> _drafts = const [];

  /// The draft bundle as loaded (or as last saved): the dirty baseline.
  Map<String, dynamic> _initialBundle = const {};

  Object? _error;
  bool _busy = false;
  bool _allowPop = false;
  String _query = '';
  _RestrictionFilter _filter = _RestrictionFilter.all;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _available = null;
      _current = null;
    });
    try {
      final results = await Future.wait<Object?>([
        widget.controller.channel
            .getAvailableRestrictions(widget.packageName),
        widget.controller.channel
            .getApplicationRestrictions(widget.packageName),
      ]);
      final available = results[0] as List<AvailableRestriction>;
      final current = results[1] as Map<String, dynamic>;
      if (!mounted) return;
      for (final draft in _drafts) {
        draft.dispose();
      }
      setState(() {
        _available = available;
        _current = current;
        // The original filters `URLBlocklist` out of the editor
        // (`AppRestrictionsScreen.kt:156-158`); the channel also flags it
        // (and any other owned key) as hidden. Both guards are applied.
        _drafts = [
          for (final entry in available)
            if (!entry.hidden &&
                entry.key.toLowerCase() != 'urlblocklist')
              _RestrictionDraft.fromEntry(entry),
        ];
        _initialBundle = _buildDraftBundle();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// The bundle the current draft would apply, before hidden preservation.
  Map<String, dynamic> _buildDraftBundle() {
    final bundle = <String, dynamic>{};
    for (final draft in _drafts) {
      draft.writeTo(bundle);
    }
    return bundle;
  }

  /// The bundle Save applies: the draft bundle plus every hidden entry's
  /// currently applied value, force-preserved exactly as the original
  /// preserves an existing `URLBlocklist` before writing the managed
  /// entries (`AppRestrictionsScreen.kt:392-395`).
  Map<String, dynamic> _buildFinalBundle() {
    final bundle = _buildDraftBundle();
    for (final entry in _available ?? const <AvailableRestriction>[]) {
      if (entry.hidden && entry.currentValue != null) {
        bundle[entry.key] = entry.currentValue;
      }
    }
    final current = _current ?? const <String, dynamic>{};
    if (current.containsKey('URLBlocklist') &&
        !bundle.containsKey('URLBlocklist')) {
      bundle['URLBlocklist'] = current['URLBlocklist'];
    }
    return bundle;
  }

  bool get _isDirty =>
      _available != null &&
      !_restrictionsDeepEquals(_buildDraftBundle(), _initialBundle);

  int get _activeCount => _drafts.where((d) => d.managed).length;

  List<_RestrictionDraft> get _filteredDrafts {
    final query = _query.trim().toLowerCase();
    return _drafts.where((draft) {
      final matchesFilter = switch (_filter) {
        _RestrictionFilter.all => true,
        _RestrictionFilter.active => draft.managed,
        _RestrictionFilter.defaults => !draft.managed,
      };
      if (!matchesFilter) return false;
      if (query.isEmpty) return true;
      // The original's search matches title, key or description,
      // case-insensitively (`AppRestrictionsScreen.kt:175-194`).
      final entry = draft.entry;
      return _restrictionLabel(entry).toLowerCase().contains(query) ||
          entry.key.toLowerCase().contains(query) ||
          (entry.description?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  Future<void> _save() async {
    if (_busy) return;
    final finalBundle = _buildFinalBundle();
    // The original judges the rebuilt bundle against the current one with
    // `isLooserRestrictions` and only then applies, with `merge = false`
    // (`AppRestrictionsScreen.kt:390-400`).
    final loosening = Loosening.isLooserRestrictions(
      oldRestrictions: _current ?? const {},
      newRestrictions: finalBundle,
    );
    Future<void> apply() async {
      setState(() => _busy = true);
      try {
        final saved = await widget.controller.channel
            .setApplicationRestrictions(
          widget.packageName,
          finalBundle,
          merge: false,
        );
        if (mounted) {
          setState(() {
            _current = saved;
            _initialBundle = _buildDraftBundle();
          });
        }
      } catch (e) {
        if (mounted) await showErrorSnackBar(context, e);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    if (loosening) {
      final done = await runLoosening(context, widget.controller, apply);
      if (done && mounted) _pop();
    } else {
      // Tightening (or neutral): free, but deferred behind the original's
      // 5-second undo window — the change is not live until it lapses.
      await runTighteningWithUndo(
        context,
        PendingChange(
          description: 'Restrictions updated for ${widget.label}',
          direction: ChangeDirection.tightening,
          apply: apply,
        ),
      );
      if (mounted) _pop();
    }
  }

  void _pop() {
    _allowPop = true;
    Navigator.of(context).pop();
  }

  /// The original's clear-all (`AppRestrictionsScreen.kt:415-439`): after
  /// confirmation every entry is unmanaged **in the draft only** — nothing
  /// is applied until Save.
  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear all restrictions'),
        content: Text(
          'Remove every managed restriction for ${widget.label}? '
          'This only edits the draft — tap Save to apply it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Confirm',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        for (final draft in _drafts) {
          draft.managed = false;
        }
      });
    }
  }

  Future<void> _onPopInvoked(bool didPop) async {
    if (didPop || _allowPop || !_isDirty) return;
    final discard = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text(
          'You have unsaved restriction changes. Discard them?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Discard',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (discard == true && mounted) _pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop || !_isDirty,
      onPopInvokedWithResult: (didPop, _) => _onPopInvoked(didPop),
      child: Scaffold(
        appBar: AppBar(title: Text('Restrictions — ${widget.label}')),
        body: _error != null
            ? ErrorView(error: _error!, onRetry: _load)
            : _available == null
                ? const LoadingView(
                    message: 'Loading declared restrictions…')
                : _drafts.isEmpty
                    ? EmptyView(
                        icon: Icons.policy_outlined,
                        message: 'No restrictions available for '
                            '${widget.label}. This app does not declare any '
                            'managed restrictions.',
                      )
                    : _buildEditor(),
      ),
    );
  }

  Widget _buildEditor() {
    final filtered = _filteredDrafts;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _buildHeaderCard(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              labelText: 'Search restrictions',
              border: const OutlineInputBorder(),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              FilterChip(
                label: const Text('All'),
                selected: _filter == _RestrictionFilter.all,
                onSelected: (_) =>
                    setState(() => _filter = _RestrictionFilter.all),
              ),
              const SizedBox(width: 6),
              FilterChip(
                label: Text('Active ($_activeCount)'),
                selected: _filter == _RestrictionFilter.active,
                onSelected: (_) =>
                    setState(() => _filter = _RestrictionFilter.active),
              ),
              const SizedBox(width: 6),
              FilterChip(
                label: Text('Default (${_drafts.length - _activeCount})'),
                selected: _filter == _RestrictionFilter.defaults,
                onSelected: (_) =>
                    setState(() => _filter = _RestrictionFilter.defaults),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _query.trim().isNotEmpty
                          ? 'No restrictions matching "${_query.trim()}"'
                          : 'No restrictions available for ${widget.label}',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _RestrictionCardView(
                    draft: filtered[i],
                    busy: _busy,
                    onChanged: () => setState(() {}),
                  ),
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: FilledButton.icon(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.save_outlined),
              label: Text(_busy ? 'Saving…' : 'Save restrictions'),
            ),
          ),
        ),
      ],
    );
  }

  /// The original's header card (`AppRestrictionsScreen.kt:206-269`): app
  /// name with the `• active/total` managed count, the package name in
  /// monospace, and the clear-all (refresh) action in error colour.
  Widget _buildHeaderCard() {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.apps_outlined, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.label,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '• $_activeCount/${_drafts.length}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: _activeCount > 0
                                  ? scheme.primary
                                  : scheme.outline,
                            ),
                      ),
                    ],
                  ),
                  Text(
                    widget.packageName,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Clear all restrictions',
              onPressed: _busy ? null : _confirmClearAll,
              icon: Icon(Icons.refresh, color: scheme.error, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

/// One restriction's card — a port of the original's
/// `ManagedRestrictionCard` (`AppRestrictionsScreen.kt:446-594`): humanised
/// label with the raw key in monospace beneath it, the managed switch, the
/// description (truncated at 120 characters behind a See more / See less
/// toggle), and — only while managed — the per-type value editor.
///
/// All edits mutate the [draft] and then call [onChanged] so the owning
/// screen can rebuild (dirty state, counts, filters); nothing is persisted
/// from here.
class _RestrictionCardView extends StatelessWidget {
  const _RestrictionCardView({
    required this.draft,
    required this.busy,
    required this.onChanged,
  });

  final _RestrictionDraft draft;
  final bool busy;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final entry = draft.entry;
    final scheme = Theme.of(context).colorScheme;
    final description = entry.description;
    return Card(
      elevation: 0,
      color: draft.managed
          ? scheme.surface
          : scheme.surfaceContainerHighest.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _restrictionLabel(entry),
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        entry.key,
                        style:
                            Theme.of(context).textTheme.labelSmall?.copyWith(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: scheme.secondary,
                                ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: draft.managed,
                  onChanged: busy
                      ? null
                      : (v) {
                          draft.managed = v;
                          onChanged();
                        },
                ),
              ],
            ),
            if (description != null && description.trim().isNotEmpty)
              _buildDescription(context, description),
            if (draft.managed) ...[
              const SizedBox(height: 8),
              Divider(color: scheme.outlineVariant),
              const SizedBox(height: 8),
              _buildEditor(context),
            ],
          ],
        ),
      ),
    );
  }

  /// The original truncates descriptions longer than 120 characters behind
  /// a See more / See less toggle (`AppRestrictionsScreen.kt:489-520`).
  Widget _buildDescription(BuildContext context, String description) {
    final scheme = Theme.of(context).colorScheme;
    final isLong = description.length > 120;
    final shown = isLong && !draft.descExpanded
        ? '${description.substring(0, 120)}…'
        : description;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            shown,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (isLong)
            InkWell(
              onTap: () {
                draft.descExpanded = !draft.descExpanded;
                onChanged();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      draft.descExpanded ? 'See less' : 'See more',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: scheme.primary),
                    ),
                    Icon(
                      draft.descExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 16,
                      color: scheme.primary,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    final entry = draft.entry;
    return switch (entry.type) {
      'bool' => SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Enabled')),
            ButtonSegment(value: false, label: Text('Disabled')),
          ],
          selected: {draft.boolValue},
          onSelectionChanged: busy
              ? null
              : (selection) {
                  draft.boolValue = selection.first;
                  onChanged();
                },
        ),
      'string' => entry.choices.isNotEmpty
          ? _buildChoiceEditor(context)
          : TextField(
              controller: draft.textController,
              decoration: InputDecoration(
                labelText: _restrictionLabel(entry),
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) {
                draft.stringValue = v;
                onChanged();
              },
            ),
      'int' => TextField(
          controller: draft.textController,
          decoration: InputDecoration(
            labelText: _restrictionLabel(entry),
            border: const OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (v) {
            draft.intText = v;
            onChanged();
          },
        ),
      'stringList' => entry.choices.isNotEmpty
          ? _buildMultiSelectEditor(context)
          : _buildFreeListEditor(context),
      'bundle' => draft.isBundleArray
          ? _buildBundleArrayEditor(context)
          : _buildBundleEditor(context),
      _ => Text(
          'Unsupported restriction type: ${entry.type}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
    };
  }

  /// Choice entries are a radio list over the declared values — the
  /// original's `ChoiceSelectorView` (`AppRestrictionsScreen.kt:596-642`);
  /// the channel model carries the choice values (its display entries are
  /// the values themselves when the app declares no separate labels).
  Widget _buildChoiceEditor(BuildContext context) {
    return RadioGroup<String>(
      groupValue: draft.stringValue,
      onChanged: (v) {
        if (v == null) return;
        draft.stringValue = v;
        onChanged();
      },
      child: Column(
        children: [
          for (final choice in draft.entry.choices)
            RadioListTile<String>(
              value: choice,
              title: Text(choice),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }

  /// Multi-select entries are a checkbox list over the declared values —
  /// the original's `MultiSelectSelectorView`
  /// (`AppRestrictionsScreen.kt:644-698`).
  Widget _buildMultiSelectEditor(BuildContext context) {
    return Column(
      children: [
        for (final choice in draft.entry.choices)
          CheckboxListTile(
            value: draft.listValues.contains(choice),
            onChanged: busy
                ? null
                : (checked) {
                    final values = List<String>.of(draft.listValues);
                    if (checked == true) {
                      if (!values.contains(choice)) values.add(choice);
                    } else {
                      values.remove(choice);
                    }
                    draft.listValues = values;
                    onChanged();
                  },
            title: Text(choice),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
      ],
    );
  }

  /// A string-list entry whose app declares no choice values: the values
  /// are edited directly (one row per value, plus an add row), so such an
  /// entry stays fully editable even without an enumeration.
  Widget _buildFreeListEditor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < draft.listValues.length; i++)
          Row(
            children: [
              Expanded(
                child: Text(
                  draft.listValues[i],
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontFamily: 'monospace'),
                ),
              ),
              IconButton(
                tooltip: 'Remove value',
                onPressed: busy
                    ? null
                    : () {
                        draft.listValues = List<String>.of(draft.listValues)
                          ..removeAt(i);
                        onChanged();
                      },
                icon: Icon(Icons.delete_outline, color: scheme.error),
              ),
            ],
          ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: draft.addController,
                decoration: const InputDecoration(
                  labelText: 'Add value',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _addFreeValue(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Add value',
              onPressed: busy ? null : _addFreeValue,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }

  void _addFreeValue() {
    final value = draft.addController.text.trim();
    if (value.isEmpty) return;
    if (!draft.listValues.contains(value)) {
      draft.listValues = [...draft.listValues, value];
    }
    draft.addController.clear();
    onChanged();
  }

  /// A plain bundle's children are nested cards inside an inset surface —
  /// the original's `BundleEditorView` (`AppRestrictionsScreen.kt:700-714`).
  Widget _buildBundleEditor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          for (var i = 0; i < draft.children.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _RestrictionCardView(
              draft: draft.children[i],
              busy: busy,
              onChanged: onChanged,
            ),
          ],
        ],
      ),
    );
  }

  /// A bundle array's items are numbered cards built from the declared
  /// template children, each removable, with an Add item button — the
  /// original's `BundleArrayEditorView`
  /// (`AppRestrictionsScreen.kt:716-764`).
  Widget _buildBundleArrayEditor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (var i = 0; i < draft.items.length; i++)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Item ${i + 1}',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove item',
                        onPressed: busy
                            ? null
                            : () {
                                draft.removeBundleArrayItem(i);
                                onChanged();
                              },
                        icon: Icon(Icons.delete_outline, color: scheme.error),
                      ),
                    ],
                  ),
                  for (var j = 0; j < draft.items[i].length; j++) ...[
                    if (j > 0) const SizedBox(height: 8),
                    _RestrictionCardView(
                      draft: draft.items[i][j],
                      busy: busy,
                      onChanged: onChanged,
                    ),
                  ],
                ],
              ),
            ),
          ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () {
                  draft.addBundleArrayItem();
                  onChanged();
                },
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add item'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(40),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }
}
