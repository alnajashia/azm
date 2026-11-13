/// Activity blocker screen (Batch C, C2 — audit item 7).
///
/// The engine already lived in Kotlin (the accessibility service
/// closes a blocked activity with BACK, plus the in-memory
/// seen-activities log); this screen is the missing UI: the blocked
/// list, the recently-accessed activities grouped by app, and manual
/// add. Blocking one more activity is a tightening, so it saves
/// directly; removing one is a loosening, so it goes through the
/// confirmation card and the recovery gate ([runLoosening]).
///
/// Protected activities (launcher, system UI, Settings, in-call UI,
/// Azm itself) can never be blocked: the native side refuses them
/// with INVALID_ARGUMENT and writes nothing, and the manual-add
/// dialog rejects the obvious patterns up front.
library;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/privileged_channel.dart';
import '../l10n/l10n.dart';
import 'common.dart';
import 'recovery_ui.dart';

class ActivityBlockerScreen extends StatefulWidget {
  const ActivityBlockerScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<ActivityBlockerScreen> createState() => _ActivityBlockerScreenState();
}

class _ActivityBlockerScreenState extends State<ActivityBlockerScreen> {
  List<String>? _blocked;
  List<ActivityLogEntry>? _accessed;
  List<InstalledApp>? _apps;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final blocked = await widget.controller.channel.getBlockedActivities();
      final accessed =
          await widget.controller.channel.getAccessedActivities();
      List<InstalledApp> apps = const [];
      try {
        apps = await widget.controller.channel.listInstalledApps();
      } catch (_) {
        // Labels degrade to package names; the lists still work.
      }
      if (mounted) {
        setState(() {
          _blocked = blocked;
          _accessed = accessed;
          _apps = apps;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String _labelFor(String packageName) =>
      _apps
          ?.where((a) => a.packageName == packageName)
          .firstOrNull
          ?.label ??
      packageName;

  /// The package part of a fully-qualified activity class name.
  String _packageOf(String className) {
    final dot = className.lastIndexOf('.');
    return dot > 0 ? className.substring(0, dot) : className;
  }

  /// Client-side obvious-protected check. The native side remains
  /// authoritative — anything this misses, it refuses.
  bool _looksProtected(String className) {
    final lower = className.toLowerCase();
    return lower.contains('launcher') ||
        lower.contains('incall') ||
        lower.startsWith('com.android.systemui.') ||
        lower.startsWith('com.android.settings.') ||
        lower.startsWith('com.android.server.telecom.');
  }

  bool _looksLikeClassName(String value) {
    final v = value.trim();
    if (v.isEmpty || v.contains(' ') || !v.contains('.')) return false;
    return RegExp(r'^[A-Za-z_][A-Za-z0-9_.$]*$').hasMatch(v);
  }

  Future<void> _saveBlocked(List<String> next) async {
    setState(() => _busy = true);
    try {
      final saved = await widget.controller.channel.setBlockedActivities(next);
      if (mounted) setState(() => _blocked = saved);
    } catch (e) {
      if (mounted) await showErrorCard(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeBlocked(String className) async {
    final l10n = context.l10n;
    final confirmed = await showDestructiveConfirmDialog(
      context,
      title: l10n.unblockActivityConfirmTitle,
      message: l10n.unblockActivityConfirmMessage(className),
      confirmText: l10n.unblock,
    );
    if (!confirmed || !mounted) return;
    final next = (_blocked ?? const []).where((c) => c != className).toList();
    // Loosening: confirm (done above) + recovery gate.
    await runLoosening(context, widget.controller, () => _saveBlocked(next));
  }

  Future<void> _blockActivity(String className) async {
    // Tightening: direct save, no gate.
    final next = {...?_blocked, className}.toList()..sort();
    await _saveBlocked(next);
  }

  /// v1.0.1 follow-up: block the whole app — every activity it
  /// declares, not just the ones the service already saw. The
  /// protected ones are filtered client-side first, because the
  /// native side refuses the entire save if any entry is protected.
  Future<void> _blockWholeApp(String packageName) async {
    setState(() => _busy = true);
    try {
      final all =
          await widget.controller.channel.getAppActivities(packageName);
      final blockable = all
          .where((c) => !_looksProtected(c))
          .toSet()
          .difference(_blocked?.toSet() ?? const {})
          .toList();
      if (!mounted) return;
      if (blockable.isEmpty) {
        showInfoSnackBar(context, context.l10n.noBlockableActivities);
        return;
      }
      final next = {...?_blocked, ...blockable}.toList()..sort();
      await _saveBlocked(next);
      if (mounted) {
        showInfoSnackBar(
          context,
          context.l10n.blockedWholeApp(blockable.length),
        );
      }
    } on Object catch (e) {
      if (mounted) await showErrorCard(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// v1.0.1: pick the app first (search + system-apps toggle, the
  /// shared picker), then pick one of its recently seen activities —
  /// or type a class name. The old flow was a bare text field that
  /// demanded the full class name from memory.
  Future<void> _addManually() async {
    final picked = await showAppPicker(
      context: context,
      channel: widget.controller.channel,
      title: context.l10n.addActivityTitle,
      singleSelect: true,
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    final packageName = picked.first;
    final seen = (_accessed ?? const [])
        .where((e) => e.packageName == packageName)
        .toList();
    final controller = TextEditingController();
    String? error;
    var blockWhole = false;
    final saved = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(_labelFor(packageName)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (seen.isNotEmpty) ...[
                Text(dialogContext.l10n.recentlyAccessedActivities),
                const SizedBox(height: 8),
                // Plain Column, not a ListView: a viewport inside a
                // dialog's min-sized content cannot report intrinsic
                // dimensions, and the dialog itself scrolls when tall.
                for (final entry in seen)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(entry.className),
                    onTap: () {
                      // Same guards as the manual field; the
                      // native side remains authoritative.
                      String? problem;
                      if (_looksProtected(entry.className)) {
                        problem = dialogContext.l10n.addActivityProtected;
                      } else if ((_blocked ?? const [])
                          .contains(entry.className)) {
                        problem =
                            dialogContext.l10n.addActivityAlreadyBlocked;
                      }
                      if (problem != null) {
                        setDialogState(() => error = problem);
                        return;
                      }
                      Navigator.pop(dialogContext, entry.className);
                    },
                  ),
                const SizedBox(height: 12),
              ],
              // Block the whole app at once — every activity it
              // declares (not just the seen ones).
              FilledButton.icon(
                onPressed: () {
                  blockWhole = true;
                  Navigator.pop(dialogContext);
                },
                icon: const Icon(Icons.block_outlined),
                label: Text(dialogContext.l10n.blockEntireApp),
              ),
              const SizedBox(height: 12),
              Text(dialogContext.l10n.addActivityBody),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: dialogContext.l10n.activityClassNameLabel,
                  hintText: '$packageName.MainActivity',
                  border: const OutlineInputBorder(),
                  errorText: error,
                ),
                onChanged: (_) {
                  if (error != null) setDialogState(() => error = null);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(dialogContext.l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                String? problem;
                if (!_looksLikeClassName(value)) {
                  problem = dialogContext.l10n.addActivityInvalid;
                } else if (_looksProtected(value)) {
                  problem = dialogContext.l10n.addActivityProtected;
                } else if ((_blocked ?? const []).contains(value)) {
                  problem = dialogContext.l10n.addActivityAlreadyBlocked;
                }
                if (problem != null) {
                  setDialogState(() => error = problem);
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: Text(dialogContext.l10n.save),
            ),
          ],
        ),
      ),
    );
    if (blockWhole) {
      await _blockWholeApp(packageName);
      return;
    }
    if (saved == null || !mounted) return;
    await _blockActivity(saved);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.activityBlocker),
        actions: [
          IconButton(
            onPressed: _blocked == null || _busy ? null : _addManually,
            icon: const Icon(Icons.add_outlined),
            tooltip: l10n.addActivityTitle,
          ),
          IconButton(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh_outlined),
            tooltip: l10n.refresh,
          ),
        ],
      ),
      body: _blocked == null || _accessed == null
          ? (_error != null
                ? ErrorView(error: _error!, onRetry: _load)
                : LoadingView(message: l10n.loading))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(l10n.activityBlockerDescription),
                const SizedBox(height: 12),
                SectionCard(
                  title: l10n.blockedActivities,
                  children: [
                    if (_blocked!.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(l10n.noBlockedActivities),
                      )
                    else
                      for (final className in _blocked!)
                        ListTile(
                          title: Text(className),
                          subtitle: Text(_labelFor(_packageOf(className))),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: _busy
                                ? null
                                : () => _removeBlocked(className),
                          ),
                        ),
                  ],
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: l10n.recentlyAccessedActivities,
                  children: [
                    if (_accessed!.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(l10n.noAccessedActivities),
                      )
                    else
                      for (final group in _groupByApp(_accessed!))
                        ExpansionTile(
                          title: Text(group.key),
                          subtitle: Text(
                            l10n.activitiesCount(group.value.length),
                          ),
                          children: [
                            for (final entry in group.value)
                              ListTile(
                                title: Text(entry.className),
                                subtitle: Text(entry.appName),
                                trailing: (_blocked ?? const []).contains(
                                  entry.className,
                                )
                                    ? Text(
                                        l10n.blocked,
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.error,
                                        ),
                                      )
                                    : TextButton(
                                        onPressed: _busy
                                            ? null
                                            : () =>
                                                  _blockActivity(entry.className),
                                        child: Text(l10n.block),
                                      ),
                              ),
                          ],
                        ),
                  ],
                ),
              ],
            ),
    );
  }

  /// Groups the log by app label, keeping first-seen order.
  List<MapEntry<String, List<ActivityLogEntry>>> _groupByApp(
    List<ActivityLogEntry> entries,
  ) {
    final groups = <String, List<ActivityLogEntry>>{};
    for (final entry in entries) {
      final label = _labelFor(entry.packageName);
      (groups[label] ??= []).add(entry);
    }
    return groups.entries.toList();
  }
}
