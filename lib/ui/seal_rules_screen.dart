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
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

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

  String _ruleSummary(AppLocalizations l10n, SealRule rule) {
    final base = _triggerLabel(l10n, rule.trigger);
    final app = rule.packageName;
    final withApp = app == null ? base : '$base — $app';
    if (rule.trigger.isEvent && rule.durationMinutes != null) {
      return '$withApp · ${_durationLabel(l10n, rule.durationMinutes!)}';
    }
    return withApp;
  }

  Future<String?> _pickApp() async {
    final l10n = context.l10n;
    List<InstalledApp> apps;
    try {
      apps = await _c.channel.listInstalledApps();
    } catch (e) {
      if (mounted) await showErrorCard(context, e);
      return null;
    }
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.sealChooseApp),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final app in apps)
                ListTile(
                  title: Text(app.label),
                  subtitle: Text(app.packageName),
                  onTap: () => Navigator.pop(dialogContext, app.packageName),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
  }

  Future<void> _editRule(SealRule? existing) async {
    final l10n = context.l10n;
    var trigger = existing?.trigger ?? SealTrigger.appBlocked;
    var packageName = existing?.packageName;
    var duration = existing?.durationMinutes ?? 60;
    var enabled = existing?.enabled ?? true;
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
                    title: Text(l10n.sealApp),
                    subtitle: Text(packageName ?? l10n.sealChooseApp),
                    trailing: const Icon(Icons.navigate_next_outlined),
                    onTap: () async {
                      final picked = await _pickApp();
                      if (picked != null) {
                        setDialogState(() => packageName = picked);
                      }
                    },
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
              onPressed: trigger.needsApp && packageName == null
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
        packageName: trigger.needsApp ? packageName : null,
        durationMinutes: trigger.isEvent ? duration : null,
        enabled: enabled,
      );
      await _save([...rules, rule], loosens: false);
    } else {
      final next = existing.copyWith(
        trigger: trigger,
        packageName: trigger.needsApp ? packageName : null,
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
