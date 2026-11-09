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
    required bool currentValue,
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
      // Tightening: free, with 5 s undo (F23).
      await runTighteningWithUndo(
        context,
        PendingChange(
          description: '$label enabled for ${_app.label}',
          direction: ChangeDirection.tightening,
          apply: doApply,
          revert: () async {
            final verified = await apply(currentValue);
            if (mounted) setState(() => onVerified(verified));
          },
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
                      currentValue: _app.isSuspended,
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
                      currentValue: _app.isHidden,
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
                      currentValue: _app.isUninstallBlocked,
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
    final loosening = Loosening.isLooserLimit(
      oldDaily: current.dailyMinutes,
      oldWeekly: current.weeklyMinutes,
      newDaily: result.daily,
      newWeekly: result.weekly,
    );
    Future<void> save() async {
      final updated = await _channel.setTimeLimit(
        _app.packageName,
        dailyMinutes: result.daily,
        weeklyMinutes: result.weekly,
        reopenSeconds: result.reopen,
      );
      if (mounted) setState(() => _enforcement = updated);
    }

    if (loosening) {
      await runLoosening(context, widget.controller, save);
    } else {
      try {
        await save();
      } catch (e) {
        await showErrorSnackBar(context, e);
      }
    }
  }

  Future<void> _editWindows() async {
    final current = _enforcement!;
    final result = await showDialog<List<TimeWindowModel>>(
      context: context,
      builder: (_) => TimeWindowsEditor(windows: current.dailyWindows),
    );
    if (result == null || !mounted) return;
    final loosening = Loosening.isLooserWindows(
      oldWindows: current.dailyWindows.map((w) => (w.startMinute, w.endMinute)).toList(),
      newWindows: result.map((w) => (w.startMinute, w.endMinute)).toList(),
    );
    Future<void> save() async {
      final updated = await _channel.setTimeWindows(_app.packageName, dailyWindows: result);
      if (mounted) setState(() => _enforcement = updated);
    }

    if (loosening) {
      await runLoosening(context, widget.controller, save);
    } else {
      try {
        await save();
      } catch (e) {
        await showErrorSnackBar(context, e);
      }
    }
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
    if (result == null || _groups == null) return;
    await _save([
      for (final g in _groups!)
        if (g.id == group.id) g.copyWith(packages: result) else g,
    ]);
  }

  Future<void> _editGroupLimit(AppGroupModel group) async {
    final result = await showDialog<({int? daily, List<int>? weekly, int reopen})>(
      context: context,
      builder: (_) => TimeLimitEditor(
        dailyMinutes: group.dailyMinutes,
        weeklyMinutes: group.weeklyMinutes,
        reopenSeconds: 0,
      ),
    );
    if (result == null || _groups == null) return;
    final loosening = Loosening.isLooserLimit(
      oldDaily: group.dailyMinutes,
      oldWeekly: group.weeklyMinutes,
      newDaily: result.daily,
      newWeekly: result.weekly,
    );
    Future<void> save() => _save([
          for (final g in _groups!)
            if (g.id == group.id)
              g.copyWith(
                dailyMinutes: result.daily ?? 0,
                weeklyMinutes: result.weekly,
                clearWeeklyMinutes: result.weekly == null,
              )
            else
              g,
        ]);
    if (loosening) {
      await runLoosening(context, widget.controller, save);
    } else {
      await save();
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
  Map<String, dynamic>? _restrictions;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.controller.channel
          .getApplicationRestrictions(widget.packageName);
      if (mounted) {
        setState(() {
          _restrictions = r;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save(Map<String, dynamic> next) async {
    final current = _restrictions ?? const {};
    final loosening = Loosening.isLooserRestrictions(
      oldRestrictions: current,
      newRestrictions: next,
    );
    Future<void> apply() async {
      setState(() => _busy = true);
      try {
        final saved = await widget.controller.channel
            .setApplicationRestrictions(widget.packageName, next, merge: false);
        if (mounted) setState(() => _restrictions = saved);
      } catch (e) {
        await showErrorSnackBar(context, e);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    if (loosening) {
      await runLoosening(context, widget.controller, apply);
    } else {
      await apply();
    }
  }

  Future<void> _editValue(String key, Object? value) async {
    if (value is bool) {
      await _save({...?_restrictions, key: !value});
      return;
    }
    final textController = TextEditingController(text: value?.toString() ?? '');
    final text = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(key),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            labelText: 'Value (comma-separated for lists)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, '__DELETE__'),
            child: const Text('Remove key'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, textController.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (text == null) return;
    final next = {...?_restrictions};
    if (text == '__DELETE__') {
      next.remove(key);
    } else if (value is List) {
      next[key] = text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    } else if (value is num) {
      next[key] = int.tryParse(text.trim()) ?? text;
    } else {
      next[key] = text;
    }
    await _save(next);
  }

  Future<void> _addKey() async {
    final keyController = TextEditingController();
    final key = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add restriction key'),
        content: TextField(
          controller: keyController,
          decoration: const InputDecoration(labelText: 'Key, e.g. URLBlocklist'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, keyController.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (key == null || key.isEmpty) return;
    await _editValue(key, '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Restrictions — ${widget.label}'),
        actions: [
          IconButton(onPressed: _busy ? null : _addKey, icon: const Icon(Icons.add)),
        ],
      ),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : _restrictions == null
              ? const LoadingView(message: 'Loading managed restrictions…')
              : _restrictions!.isEmpty
                  ? const EmptyView(
                      icon: Icons.policy_outlined,
                      message: 'No managed restrictions are set for this app. '
                          'Add keys the app declares (for browsers: URLBlocklist, '
                          'ForceGoogleSafeSearch).',
                    )
                  : ListView(
                      children: [
                        for (final entry in _restrictions!.entries)
                          ListTile(
                            title: Text(entry.key),
                            subtitle: Text(entry.value.toString()),
                            trailing: entry.value is bool
                                ? Switch(
                                    value: entry.value as bool,
                                    onChanged: _busy ? null : (_) => _editValue(entry.key, entry.value),
                                  )
                                : const Icon(Icons.edit_outlined),
                            onTap: _busy ? null : () => _editValue(entry.key, entry.value),
                          ),
                      ],
                    ),
    );
  }
}
