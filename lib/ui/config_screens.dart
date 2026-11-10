/// Config sub-screens: Browser restrictions (F5), Blocked words (F14/F15),
/// Usage warnings (F12), Suspension logs (F27), Impulse lock (F21) +
/// challenge settings (F22), Focus mode (F25).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../data/config_store.dart';
import '../data/privileged_channel.dart';
import '../l10n/l10n.dart';
import 'common.dart';
import 'recovery_ui.dart';

// ------------------------------------------------------------ Browser (F5)

class BrowserRestrictionsScreen extends StatefulWidget {
  const BrowserRestrictionsScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<BrowserRestrictionsScreen> createState() =>
      _BrowserRestrictionsScreenState();
}

class _BrowserRestrictionsScreenState extends State<BrowserRestrictionsScreen> {
  List<BlockedList>? _lists;
  List<CapableApp>? _browsers;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final lists = await widget.controller.config.getBlockedLists();
      List<CapableApp> browsers = const [];
      Object? browserError;
      try {
        // The key actually pushed is URLBlocklist (the original's
        // `applyRestrictions`); ForceGoogleSafeSearch is only added by
        // the native side when a browser is newly installed
        // (`installed = true`), never by this screen's apply.
        browsers = await widget.controller.channel.listRestrictionCapableApps(
          requiredKeys: const ['URLBlocklist'],
        );
      } catch (e) {
        browserError = e;
      }
      if (mounted) {
        setState(() {
          _lists = lists;
          _browsers = browsers;
          _error = browserError;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _saveLists(List<BlockedList> lists) async {
    // The original's editor discards blank-title lists outright
    // (`BrowserRestrictionsScreen.kt`: save only `if (title.isNotBlank())`),
    // so they are never persisted.
    final kept = lists.where((l) => l.title.trim().isNotEmpty).toList();
    Future<void> save() async {
      await widget.controller.config.setBlockedLists(kept);
      if (mounted) setState(() => _lists = kept);
      // The original re-applies after every save and every delete
      // (`BrowserRestrictionsViewModel.saveOrUpdateList`/`removeList`
      // both end in `manager.applyRestrictions()`).
      await _applyRestrictions(kept, silent: true);
    }

    // EVERY save is recovery-gated: a save re-applies the lists to the
    // browsers immediately (above), so it is never a purely local edit —
    // it either ACTIVATES URL blocking (user directive, v1.0.4 audit:
    // activations are code-gated) or loosens it (F23). An already-active
    // session passes through without a prompt.
    await runLoosening(context, widget.controller, save);
  }

  /// Pushes the union of all lists' sites to every target browser,
  /// mirroring `BrowserRestrictionsManager.applyRestrictions`
  /// (`BrowserRestrictionsManager.kt:124-149`): bundle is exactly
  /// `{URLBlocklist: sites}` — SafeSearch is NOT forced here — and the
  /// write MERGES with each browser's existing restrictions
  /// (`merge = true`), never replacing them.
  Future<void> _applyRestrictions(
    List<BlockedList> lists, {
    required bool silent,
  }) async {
    final browsers = _browsers ?? const [];
    if (browsers.isEmpty) return;
    final sites = <String>{for (final l in lists) ...l.sites}.toList()..sort();
    final bundle = <String, dynamic>{'URLBlocklist': sites};
    try {
      for (final b in browsers) {
        await widget.controller.channel.setApplicationRestrictions(
          b.packageName,
          bundle,
          merge: true,
        );
      }
      if (!silent && mounted) {
        showInfoSnackBar(
          context,
          context.l10n.appliedToBrowsers(browsers.length),
        );
      }
    } catch (e) {
      if (mounted) await showErrorCard(context, e);
    }
  }

  Future<void> _editList(BlockedList? existing) async {
    final titleC = TextEditingController(text: existing?.title ?? '');
    final sitesC = TextEditingController(
      text: (existing?.sites ?? const []).join('\n'),
    );
    final saved = await showDialog<BlockedList>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          existing == null
              ? dialogContext.l10n.newBlocklist
              : dialogContext.l10n.editBlocklist,
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleC,
                decoration: InputDecoration(
                  labelText: dialogContext.l10n.titleLabel,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sitesC,
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: dialogContext.l10n.sitesLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.l10n.cancel),
          ),
          FilledButton(
            // A blank title discards the list, exactly as the original:
            // the dialog closes and nothing is saved or applied.
            onPressed: () => Navigator.pop(
              dialogContext,
              titleC.text.trim().isEmpty
                  ? null
                  : BlockedList(
                      id:
                          existing?.id ??
                          DateTime.now().microsecondsSinceEpoch.toString(),
                      title: titleC.text.trim(),
                      sites: sitesC.text
                          .split('\n')
                          .map((s) => s.trim())
                          .where((s) => s.isNotEmpty)
                          .toList(),
                    ),
            ),
            child: Text(dialogContext.l10n.save),
          ),
        ],
      ),
    );
    if (saved == null || _lists == null) return;
    final next = [
      for (final l in _lists!)
        if (l.id == saved.id) saved else l,
      if (existing == null) saved,
    ];
    await _saveLists(next);
  }

  Future<void> _applyToBrowsers() async {
    final browsers = _browsers ?? const [];
    if (browsers.isEmpty || _lists == null) return;
    Future<void> apply() async {
      setState(() => _busy = true);
      try {
        await _applyRestrictions(_lists!, silent: false);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    if (!mounted) return;
    // Pushing the blocklists ACTIVATES (or loosens) URL blocking in the
    // browsers — recovery-gated in both directions (user directive,
    // v1.0.4 audit; see _saveLists).
    await runLoosening(context, widget.controller, apply);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.browserRestrictions),
        actions: [
          IconButton(
            onPressed: () => _editList(null),
            icon: const Icon(Icons.add_outlined),
            tooltip: l10n.newBlocklist,
          ),
        ],
      ),
      body: _lists == null
          ? LoadingView(message: l10n.loadingBlocklists)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error is PrivilegedException
                          ? friendlyError(_error! as PrivilegedException, l10n)
                          : l10n.errGeneric,
                    ),
                  ),
                // v1.0.5 UX (user directive): titled card groups.
                SectionCard(
                  title: l10n.supportingBrowsers,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: _browsers == null || _browsers!.isEmpty
                          ? Text(l10n.noCapableBrowser)
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final b in _browsers!)
                                  Text('• ${b.label} (${b.packageName})'),
                              ],
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: l10n.blocklistsSection,
                  children: [
                    if (_lists!.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                        child: Text(l10n.noBlocklistsYet),
                      )
                    else
                      for (final l in _lists!)
                        ListTile(
                          title: Text(l.title),
                          subtitle: Text(l10n.sitesCount(l.sites.length)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _saveLists(
                              _lists!.where((x) => x.id != l.id).toList(),
                            ),
                          ),
                          onTap: () => _editList(l),
                        ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy || (_browsers?.isEmpty ?? true)
                      ? null
                      : _applyToBrowsers,
                  icon: const Icon(Icons.upload_outlined),
                  label: Text(l10n.applyBlocklists),
                ),
              ],
            ),
    );
  }
}

// ------------------------------------------------------------ Blocked words

class BlockedWordsScreen extends StatefulWidget {
  const BlockedWordsScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<BlockedWordsScreen> createState() => _BlockedWordsScreenState();
}

class _BlockedWordsScreenState extends State<BlockedWordsScreen> {
  BlockedWordsState? _state;
  List<InstalledApp>? _apps;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final state = await widget.controller.channel.getBlockedWords();
      final apps = await widget.controller.channel.listInstalledApps();
      if (mounted) {
        setState(() {
          _state = state;
          _apps = apps;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String _labelFor(String pkg) =>
      _apps?.where((a) => a.packageName == pkg).firstOrNull?.label ?? pkg;

  Future<void> _editWords() async {
    final controller = TextEditingController(text: _state!.words.join('\n'));
    final saved = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.activeBlockingWords),
        content: TextField(
          controller: controller,
          maxLines: 8,
          decoration: InputDecoration(
            labelText: dialogContext.l10n.oneWordPerLine,
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
              controller.text
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
    final loosening =
        saved.length < _state!.words.length ||
        !_state!.words.every(saved.contains);
    Future<void> save() async {
      final s = await widget.controller.channel.setBlockedWords(
        saved,
        _state!.targetPackages,
      );
      if (mounted) setState(() => _state = s);
    }

    if (!mounted) return;
    if (loosening) {
      await runLoosening(context, widget.controller, save);
    } else {
      // Tightening saves surface failures too (v1.0.5 audit C-M3):
      // runLoosening already snackbars gated saves; the direct path
      // must not let a channel error escape unhandled.
      try {
        await save();
      } catch (e) {
        if (mounted) await showErrorCard(context, e);
      }
    }
  }

  Future<void> _pickTargets() async {
    final selected = {..._state!.targetPackages};
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(context.l10n.appsWhereWordsBlock),
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
            FilledButton(
              onPressed: () => Navigator.pop(context, selected.toList()),
              child: Text(context.l10n.save),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    // ANY change to the target set is recovery-gated: removing a target
    // loosens (F23), and ADDING one ACTIVATES word blocking inside an
    // app that did not have it (user directive, v1.0.4 audit).
    final changed =
        result.length != _state!.targetPackages.length ||
        !_state!.targetPackages.every(result.contains);
    Future<void> save() async {
      final s = await widget.controller.channel.setBlockedWords(
        _state!.words,
        result,
      );
      if (mounted) setState(() => _state = s);
    }

    if (!mounted) return;
    if (changed) {
      await runLoosening(context, widget.controller, save);
    } else {
      await save();
    }
  }

  Future<void> _editPassive(String packageName) async {
    final current = _state!.passiveWords[packageName] ?? const [];
    final controller = TextEditingController(text: current.join('\n'));
    final saved = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          dialogContext.l10n.onScreenWordsFor(_labelFor(packageName)),
        ),
        content: TextField(
          controller: controller,
          maxLines: 8,
          decoration: InputDecoration(
            labelText: dialogContext.l10n.oneWordPerLine,
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
              controller.text
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
    final loosening =
        saved.length < current.length || !current.every(saved.contains);
    // Creating a per-app list where none existed ACTIVATES on-screen
    // word blocking for that app — code-gated (user directive, v1.0.4
    // audit), like the loosening direction already was.
    final creating = !_state!.passiveWords.containsKey(packageName);
    Future<void> save() async {
      final s = await widget.controller.channel.setPassiveWords(
        packageName,
        saved,
      );
      if (mounted) setState(() => _state = s);
    }

    if (!mounted) return;
    if (loosening || creating) {
      await runLoosening(context, widget.controller, save);
    } else {
      try {
        await save();
      } catch (e) {
        if (mounted) await showErrorCard(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.blockedWords)),
        body: ErrorView(error: _error!, onRetry: _load),
      );
    }
    if (_state == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.blockedWords)),
        body: LoadingView(message: l10n.loadingBlockedWords),
      );
    }
    final s = _state!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.blockedWords)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // v1.0.5 UX (user directive): titled card groups.
          SectionCard(
            title: l10n.activeBlockingSection,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(l10n.activeBlockingBody),
              ),
              ListTile(
                title: Text(l10n.wordsCount(s.words.length)),
                subtitle: Text(s.words.take(5).join(', ')),
                trailing: const Icon(Icons.edit_outlined),
                onTap: _editWords,
              ),
              ListTile(
                title: Text(l10n.targetAppsCount(s.targetPackages.length)),
                subtitle: Text(
                  s.targetPackages.map(_labelFor).take(3).join(', '),
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: _pickTargets,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: l10n.passiveBlockingSection,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(l10n.passiveBlockingBody),
              ),
              if (s.passiveWords.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(l10n.noPerAppLists),
                )
              else
                for (final entry in s.passiveWords.entries)
                  ListTile(
                    title: Text(_labelFor(entry.key)),
                    subtitle: Text(l10n.wordsCount(entry.value.length)),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => _editPassive(entry.key),
                  ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () async {
                    // Add a passive list for one of the target apps not yet listed.
                    final candidates = s.targetPackages
                        .where((p) => !s.passiveWords.containsKey(p))
                        .toList();
                    if (candidates.isEmpty) {
                      showInfoSnackBar(context, l10n.addTargetAppsFirst);
                      return;
                    }
                    await _editPassive(candidates.first);
                  },
                  icon: const Icon(Icons.add_outlined),
                  label: Text(l10n.addPerAppList),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ Usage warnings

class UsageWarningsScreen extends StatefulWidget {
  const UsageWarningsScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<UsageWarningsScreen> createState() => _UsageWarningsScreenState();
}

class _UsageWarningsScreenState extends State<UsageWarningsScreen> {
  bool? _enabled;
  List<UsageWarningStage>? _stages;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.controller.config.getUsageWarnings();
      if (mounted) {
        setState(() {
          _enabled = r.enabled;
          _stages = r.stages;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save(bool enabled, List<UsageWarningStage> stages) async {
    final loosening =
        (_enabled == true && !enabled) ||
        stages.length < (_stages?.length ?? 0);
    Future<void> save() async {
      await widget.controller.config.setUsageWarnings(enabled, stages);
      if (mounted) {
        setState(() {
          _enabled = enabled;
          _stages = stages;
        });
      }
    }

    if (loosening) {
      await runLoosening(context, widget.controller, save);
    } else {
      try {
        await save();
      } catch (e) {
        if (mounted) await showErrorCard(context, e);
      }
    }
  }

  void _updateStage(UsageWarningStage updated) {
    _save(_enabled ?? false, [
      for (final s in _stages!)
        if (s.id == updated.id) updated else s,
    ]);
  }

  void _removeStage(UsageWarningStage stage) {
    _save(_enabled ?? false, _stages!.where((s) => s.id != stage.id).toList());
  }

  /// The original's `addStage` (`UsageWarningViewModel.kt:32-35`): the
  /// new stage starts at half the earliest existing stage's minutes
  /// (floored at the 0.1 minimum; 10 minutes when there are no stages),
  /// with type SOUND. The row it creates is itself the editor.
  void _addStage() {
    final stages = _stages!;
    final base = stages.isEmpty
        ? 10.0
        : stages.map((s) => s.minutesBefore).reduce((a, b) => a < b ? a : b);
    var minutes = base / 2;
    if (minutes < 0.1) minutes = 0.1;
    _save(_enabled ?? false, [
      ...stages,
      UsageWarningStage(
        // The original assigns a fresh UUID in `addStage`; any unique
        // opaque id satisfies the stored schema.
        id: 'stage-${DateTime.now().microsecondsSinceEpoch}',
        minutesBefore: minutes,
        type: UsageWarningType.sound,
        vibrationCount: 1,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.usageWarnings)),
        body: ErrorView(error: _error!, onRetry: _load),
      );
    }
    if (_stages == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.usageWarnings)),
        body: LoadingView(message: l10n.loadingWarningStages),
      );
    }
    final enabled = _enabled ?? false;
    // Display order mirrors the original: descending by minutes.
    final sorted = [..._stages!]
      ..sort((a, b) => b.minutesBefore.compareTo(a.minutesBefore));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.usageWarnings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // The master switch and its explanation form one card group
          // (v1.0.5); each stage below is already its own card.
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  title: Text(l10n.stagedWarningsTitle),
                  value: enabled,
                  onChanged: (v) => _save(v, _stages!),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(l10n.usageWarningsBody),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (sorted.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                l10n.noWarningStages,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          for (final stage in sorted)
            _UsageStageCard(
              key: ValueKey(stage.id),
              stage: stage,
              enabled: enabled,
              onChanged: _updateStage,
              onRemove: () => _removeStage(stage),
            ),
          TextButton.icon(
            onPressed: enabled ? _addStage : null,
            icon: const Icon(Icons.add_outlined),
            label: Text(l10n.addStage),
          ),
        ],
      ),
    );
  }
}

/// One editable warning stage — a direct port of the original's
/// `UsageAlertStageRow` (`UsageWarningScreen.kt:144-240`): a minutes
/// field (decimal, at most 3 integer + 2 fraction digits, comma accepted
/// as the decimal separator, committed only inside 0.1–180), a
/// Silent/Sound/Vibrate segmented choice, and a vibration-count field
/// shown only for Vibrate stages (1–10). All controls are disabled when
/// the master switch is off, as in the original.
class _UsageStageCard extends StatefulWidget {
  const _UsageStageCard({
    super.key,
    required this.stage,
    required this.enabled,
    required this.onChanged,
    required this.onRemove,
  });

  final UsageWarningStage stage;
  final bool enabled;
  final ValueChanged<UsageWarningStage> onChanged;
  final VoidCallback onRemove;

  @override
  State<_UsageStageCard> createState() => _UsageStageCardState();
}

class _UsageStageCardState extends State<_UsageStageCard> {
  late final TextEditingController _minutesC;
  late final TextEditingController _vibrationC;

  static String _formatMinutes(double minutes) =>
      minutes == minutes.truncateToDouble()
      ? minutes.toInt().toString()
      : minutes.toString();

  @override
  void initState() {
    super.initState();
    _minutesC = TextEditingController(
      text: _formatMinutes(widget.stage.minutesBefore),
    );
    _vibrationC = TextEditingController(
      text: widget.stage.vibrationCount.toString(),
    );
  }

  @override
  void dispose() {
    _minutesC.dispose();
    _vibrationC.dispose();
    super.dispose();
  }

  void _onMinutesChanged(String value) {
    final parsed = double.tryParse(value.replaceAll(',', '.'));
    if (parsed != null && parsed >= 0.1 && parsed <= 180) {
      widget.onChanged(widget.stage.copyWith(minutesBefore: parsed));
    }
  }

  void _onVibrationChanged(String value) {
    final parsed = int.tryParse(value);
    if (parsed != null && parsed >= 1 && parsed <= 10) {
      widget.onChanged(widget.stage.copyWith(vibrationCount: parsed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final stage = widget.stage;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _minutesC,
                    enabled: widget.enabled,
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d{0,3}([.,]\d{0,2})?$'),
                      ),
                    ],
                    decoration: InputDecoration(
                      labelText: context.l10n.minutesBeforeLabel,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: _onMinutesChanged,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  tooltip: context.l10n.removeStageTooltip,
                  onPressed: widget.enabled ? widget.onRemove : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<UsageWarningType>(
              segments: [
                ButtonSegment(
                  value: UsageWarningType.silent,
                  label: Text(context.l10n.silent),
                ),
                ButtonSegment(
                  value: UsageWarningType.sound,
                  label: Text(context.l10n.sound),
                ),
                ButtonSegment(
                  value: UsageWarningType.vibrate,
                  label: Text(context.l10n.vibrate),
                ),
              ],
              selected: {stage.type},
              onSelectionChanged: widget.enabled
                  ? (s) => widget.onChanged(stage.copyWith(type: s.first))
                  : null,
            ),
            if (stage.type == UsageWarningType.vibrate) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text(context.l10n.vibrationCountLabel)),
                  SizedBox(
                    width: 72,
                    child: TextField(
                      controller: _vibrationC,
                      enabled: widget.enabled,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      onChanged: _onVibrationChanged,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ Suspension logs

class SuspensionLogsScreen extends StatefulWidget {
  const SuspensionLogsScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<SuspensionLogsScreen> createState() => _SuspensionLogsScreenState();
}

class _SuspensionLogsScreenState extends State<SuspensionLogsScreen> {
  List<SuspensionLogEntry>? _logs;
  Object? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final logs = await widget.controller.channel.getSuspensionLogs();
      if (mounted) setState(() => _logs = logs);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = (_logs ?? const []).where((l) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return l.appName.toLowerCase().contains(q) ||
          l.packageName.toLowerCase().contains(q) ||
          l.reason.toLowerCase().contains(q);
    }).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.suspensionLogs),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: context.l10n.clearLogsTooltip,
            onPressed: _logs == null || _logs!.isEmpty
                ? null
                : () => runLoosening(context, widget.controller, () async {
                    await widget.controller.channel.clearSuspensionLogs();
                    _load();
                  }),
          ),
        ],
      ),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : _logs == null
          ? LoadingView(message: context.l10n.loadingLogs)
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_outlined),
                      labelText: context.l10n.searchLogs,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? EmptyView(
                          icon: Icons.history_outlined,
                          message: context.l10n.noLogsYet,
                        )
                      // v1.0.5 audit C-M4 (fix-#3 completion): the log
                      // entries sit in one card like the rest of the
                      // app (the screen's AppBar carries the title).
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Card(
                            child: ListView(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                              ),
                              children: [
                                for (final l in filtered)
                                  ListTile(
                                    title: Text(l.appName),
                                    subtitle: Text(
                                      '${l.reason} · ${l.timestamp}\n${l.packageName}${l.details != null ? ' · ${l.details}' : ''}',
                                    ),
                                    isThreeLine: true,
                                  ),
                              ],
                            ),
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}
