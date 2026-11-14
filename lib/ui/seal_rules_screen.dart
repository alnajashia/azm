/// SEAL rules settings (v1.0.6 — Phase D): create / edit / enable /
/// disable / delete the user-defined rules under which Azm refuses
/// to remove itself. The rules and their evaluation are NATIVE
/// (`SealRules` in Kotlin); this screen only edits the rule list
/// through the channel. An ACTIVE seal is never cancellable here —
/// it ends only by expiry or by its condition clearing, and the
/// paper recovery code does not break it (stated in the intro copy).
///
/// Gate classification (standing rules): adding a rule, enabling
/// one, or lengthening an event duration TIGHTENS (free). Disabling
/// or deleting a rule, or shortening a duration, LOOSENS and goes
/// through the paper-code session ([sealChangeLoosens] /
/// [sealDeletionLoosens] decide). Rules are marked unenforceable
/// when Azm is not Device Owner (honest-limits copy).
library;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/privileged_channel.dart';
import '../domain/seal_rules.dart';
import '../l10n/l10n.dart';
import 'common.dart';
import 'recovery_ui.dart';

class SealRulesScreen extends StatefulWidget {
  const SealRulesScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<SealRulesScreen> createState() => _SealRulesScreenState();
}

class _SealRulesScreenState extends State<SealRulesScreen> {
  List<SealRule>? _rules;
  List<ActiveSeal> _activeSeals = const [];
  List<AppGroupModel>? _groups;
  List<InstalledApp>? _apps;
  bool _isOwner = false;
  Object? _error;
  bool _saving = false;

  AppController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final m = await _c.channel.getSealRules();
      final groups = await _c.channel.getGroups();
      final apps = await _c.channel.listInstalledApps();
      if (mounted) {
        setState(() {
          _rules = [
            for (final e in (m['rules'] as List? ?? const []))
              if (SealRule.fromMap((e as Map).cast<String, dynamic>())
                  case final r?)
                r,
          ];
          _activeSeals = [
            for (final e in (m['activeSeals'] as List? ?? const []))
              if (ActiveSeal.fromMap((e as Map).cast<String, dynamic>())
                  case final s?)
                s,
          ];
          _isOwner = m['isDeviceOwner'] as bool? ?? false;
          _groups = groups;
          _apps = apps;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String _labelFor(String pkg) =>
      _apps?.where((a) => a.packageName == pkg).firstOrNull?.label ?? pkg;

  Future<void> _save(List<SealRule> next, {required bool loosens}) async {
    Future<void> persist() async {
      setState(() => _saving = true);
      try {
        final m = await _c.channel.setSealRules([
          for (final r in next) r.toMap(),
        ]);
        if (mounted) {
          setState(() {
            _saving = false;
            _rules = [
              for (final e in (m['rules'] as List? ?? const []))
                if (SealRule.fromMap((e as Map).cast<String, dynamic>())
                    case final r?)
                  r,
            ];
            _activeSeals = [
              for (final e in (m['activeSeals'] as List? ?? const []))
                if (ActiveSeal.fromMap((e as Map).cast<String, dynamic>())
                    case final s?)
                  s,
            ];
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() => _saving = false);
          await showErrorCard(context, e);
        }
      }
    }

    if (loosens) {
      await runLoosening(context, _c, persist);
    } else {
      await persist();
    }
  }

  String _triggerLabel(AppLocalizations l10n, SealTrigger trigger) =>
      switch (trigger) {
        SealTrigger.appBlocked => l10n.sealTriggerAppBlocked,
        SealTrigger.appSuspended => l10n.sealTriggerAppSuspended,
        SealTrigger.focusRunning => l10n.sealTriggerFocusRunning,
        SealTrigger.lockdownRunning => l10n.sealTriggerLockdownRunning,
        SealTrigger.visualDetection => l10n.sealTriggerVisual,
        SealTrigger.bannedWord => l10n.sealTriggerWord,
      };

  String _durationLabel(AppLocalizations l10n, int minutes) =>
      switch (minutes) {
        30 => l10n.sealDuration30m,
        60 => l10n.sealDuration1h,
        360 => l10n.sealDuration6h,
        1440 => l10n.sealDuration24h,
        10080 => l10n.sealDuration7d,
        _ => '$minutes',
      };

  /// The rule's targets: its group (by name) and its apps — one app
  /// by label, several as a count. A rule watches its apps AND the
  /// group's members (Batch H, item 12).
  String _targetsSummary(AppLocalizations l10n, SealRule rule) {
    final parts = <String>[];
    final groupId = rule.groupId;
    final group = groupId == null
        ? null
        : _groups?.where((g) => g.id == groupId).firstOrNull;
    if (group != null) parts.add('${l10n.sealGroup}: ${group.name}');
    if (rule.packageNames.isNotEmpty) {
      parts.add(
        rule.packageNames.length == 1
            ? _labelFor(rule.packageNames.first)
            : l10n.targetAppsCount(rule.packageNames.length),
      );
    }
    return parts.join(' + ');
  }

  String _ruleSummary(AppLocalizations l10n, SealRule rule) {
    final base = _triggerLabel(l10n, rule.trigger);
    final targets = rule.trigger.needsApp
        ? _targetsSummary(l10n, rule)
        : '';
    final withTargets = targets.isEmpty ? base : '$base — $targets';
    if (rule.trigger.isEvent && rule.durationMinutes != null) {
      return '$withTargets · ${_durationLabel(l10n, rule.durationMinutes!)}';
    }
    return withTargets;
  }

  Future<Set<String>?> _pickApps(Set<String> initial) async {
    final result = await showAppPicker(
      context: context,
      channel: _c.channel,
      title: context.l10n.sealChooseApp,
      initialSelected: initial,
      preloadedApps: _apps,
    );
    return result;
  }

  Future<void> _editRule(SealRule? existing) async {
    final l10n = context.l10n;
    var trigger = existing?.trigger ?? SealTrigger.appBlocked;
    var packageNames = {...?existing?.packageNames};
    var groupId = existing?.groupId;
    var duration = existing?.durationMinutes ?? 60;
    var enabled = existing?.enabled ?? true;
    final groups = _groups ?? const <AppGroupModel>[];
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(
            existing == null ? l10n.sealAddRule : l10n.sealEditRule,
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.sealTrigger),
                const SizedBox(height: 8),
                DropdownButton<SealTrigger>(
                  value: trigger,
                  isExpanded: true,
                  items: [
                    for (final t in SealTrigger.values)
                      DropdownMenuItem(
                        value: t,
                        child: Text(_triggerLabel(l10n, t)),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => trigger = v);
                  },
                ),
                if (trigger.needsApp) ...[
                  const SizedBox(height: 12),
                  ListTile(
                    leading: const Icon(Icons.apps_outlined),
                    title: Text(l10n.sealApps),
                    subtitle: Text(
                      packageNames.isEmpty
                          ? l10n.sealChooseApp
                          : packageNames.length == 1
                          ? _labelFor(packageNames.first)
                          : l10n.targetAppsCount(packageNames.length),
                    ),
                    trailing: const Icon(Icons.navigate_next_outlined),
                    onTap: () async {
                      final picked = await _pickApps(packageNames);
                      if (picked != null) {
                        setDialogState(() => packageNames = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(l10n.sealGroup),
                  const SizedBox(height: 8),
                  DropdownButton<String?>(
                    value: groupId,
                    isExpanded: true,
                    items: [
                      DropdownMenuItem<String?>(
                        child: Text(l10n.sealNoGroup),
                      ),
                      for (final g in groups)
                        DropdownMenuItem<String?>(
                          value: g.id,
                          child: Text(g.name),
                        ),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => groupId = v),
                  ),
                ],
                if (trigger.isEvent) ...[
                  const SizedBox(height: 12),
                  Text(l10n.sealDuration),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final d in sealEventDurationsMinutes)
                        ChoiceChip(
                          label: Text(_durationLabel(l10n, d)),
                          selected: duration == d,
                          onSelected: (_) => setDialogState(() => duration = d),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                SwitchListTile(
                  title: Text(l10n.sealRuleEnabled),
                  value: enabled,
                  onChanged: (v) => setDialogState(() => enabled = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed:
                  trigger.needsApp &&
                      packageNames.isEmpty &&
                      groupId == null
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
    if (result != true || !mounted) return;
    final rules = [...?_rules];
    if (existing == null) {
      final rule = SealRule(
        id: 'seal-${DateTime.now().microsecondsSinceEpoch}',
        trigger: trigger,
        packageNames: trigger.needsApp ? packageNames.toList() : const [],
        groupId: trigger.needsApp ? groupId : null,
        durationMinutes: trigger.isEvent ? duration : null,
        enabled: enabled,
      );
      await _save([...rules, rule], loosens: false);
    } else {
      final next = existing.copyWith(
        trigger: trigger,
        packageNames: trigger.needsApp ? packageNames.toList() : const [],
        groupId: trigger.needsApp ? groupId : null,
        clearGroupId: !trigger.needsApp || groupId == null,
        durationMinutes: trigger.isEvent ? duration : null,
        enabled: enabled,
      );
      if (next == existing) return;
      await _save(
        [for (final r in rules) r.id == existing.id ? next : r],
        loosens: sealChangeLoosens(existing, next),
      );
    }
  }

  Future<void> _deleteRule(SealRule rule) async {
    final confirmed = await showDestructiveConfirmDialog(
      context,
      title: context.l10n.deleteRuleConfirmTitle,
      message: context.l10n.deleteRuleConfirmMessage(_ruleSummary(context.l10n, rule)),
      confirmText: context.l10n.sealDeleteRule,
    );
    if (!confirmed || !mounted) return;
    final rules = [...?_rules];
    await _save(
      rules.where((r) => r.id != rule.id).toList(),
      loosens: sealDeletionLoosens(rule),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rules = _rules;
    final activeIds = {for (final s in _activeSeals) s.ruleId};
    return Scaffold(
      appBar: AppBar(title: Text(l10n.sealRulesTitle)),
      body: _error != null && rules == null
          ? ErrorView(error: _error!, onRetry: _load)
          : rules == null
          ? const LoadingView()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SectionCard(
                  title: l10n.sealRulesTitle,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Text(l10n.sealIntro),
                    ),
                    if (!_isOwner)
                      ListTile(
                        leading: const Icon(Icons.warning_amber_outlined),
                        title: Text(l10n.sealNotEnforceable),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: l10n.sealRulesTitle,
                  children: [
                    if (rules.isEmpty)
                      ListTile(title: Text(l10n.sealNoRules))
                    else
                      for (final rule in rules)
                        ListTile(
                          leading: Icon(
                            activeIds.contains(rule.id)
                                ? Icons.lock_outlined
                                : Icons.lock_open_outlined,
                          ),
                          title: Text(_ruleSummary(l10n, rule)),
                          subtitle: activeIds.contains(rule.id)
                              ? Text(l10n.sealActiveTitle)
                              : null,
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) {
                              if (_saving) return;
                              if (action == 'edit') _editRule(rule);
                              if (action == 'delete') _deleteRule(rule);
                            },
                            itemBuilder: (itemContext) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text(l10n.sealEditRule),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text(l10n.sealDeleteRule),
                              ),
                            ],
                          ),
                          onTap: _saving ? null : () => _editRule(rule),
                        ),
                    ListTile(
                      leading: const Icon(Icons.add_outlined),
                      title: Text(l10n.sealAddRule),
                      onTap: _saving ? null : () => _editRule(null),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
