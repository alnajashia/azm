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
import '../domain/recovery.dart';
import 'common.dart';
import 'recovery_ui.dart';

// ------------------------------------------------------------ Browser (F5)

class BrowserRestrictionsScreen extends StatefulWidget {
  const BrowserRestrictionsScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<BrowserRestrictionsScreen> createState() => _BrowserRestrictionsScreenState();
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

  Future<void> _saveLists(List<BlockedList> lists, {required bool loosening}) async {
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

    if (loosening) {
      await runLoosening(context, widget.controller, save);
    } else {
      await save();
    }
  }

  /// Pushes the union of all lists' sites to every target browser,
  /// mirroring `BrowserRestrictionsManager.applyRestrictions`
  /// (`BrowserRestrictionsManager.kt:124-149`): bundle is exactly
  /// `{URLBlocklist: sites}` — SafeSearch is NOT forced here — and the
  /// write MERGES with each browser's existing restrictions
  /// (`merge = true`), never replacing them.
  Future<void> _applyRestrictions(List<BlockedList> lists,
      {required bool silent}) async {
    final browsers = _browsers ?? const [];
    if (browsers.isEmpty) return;
    final sites = <String>{for (final l in lists) ...l.sites}.toList()..sort();
    final bundle = <String, dynamic>{'URLBlocklist': sites};
    try {
      for (final b in browsers) {
        await widget.controller.channel
            .setApplicationRestrictions(b.packageName, bundle, merge: true);
      }
      if (!silent && mounted) {
        showInfoSnackBar(
            context, 'Applied to ${browsers.length} browser(s), verified.');
      }
    } catch (e) {
      if (mounted) await showErrorSnackBar(context, e);
    }
  }

  Future<void> _editList(BlockedList? existing) async {
    final titleC = TextEditingController(text: existing?.title ?? '');
    final sitesC =
        TextEditingController(text: (existing?.sites ?? const []).join('\n'));
    final saved = await showDialog<BlockedList>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existing == null ? 'New blocklist' : 'Edit blocklist'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleC,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sitesC,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Sites, one per line (e.g. example.com)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            // A blank title discards the list, exactly as the original:
            // the dialog closes and nothing is saved or applied.
            onPressed: () => Navigator.pop(
              context,
              titleC.text.trim().isEmpty
                  ? null
                  : BlockedList(
                      id: existing?.id ??
                          DateTime.now().microsecondsSinceEpoch.toString(),
                      title: titleC.text.trim(),
                      sites: sitesC.text
                          .split('\n')
                          .map((s) => s.trim())
                          .where((s) => s.isNotEmpty)
                          .toList(),
                    ),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == null || _lists == null) return;
    final loosening = existing != null &&
        (saved.sites.length < existing.sites.length ||
            !existing.sites.every(saved.sites.contains));
    final next = [
      for (final l in _lists!)
        if (l.id == saved.id) saved else l,
      if (existing == null) saved,
    ];
    await _saveLists(next, loosening: loosening);
  }

  Future<void> _applyToBrowsers() async {
    final browsers = _browsers ?? const [];
    if (browsers.isEmpty || _lists == null) return;
    final sites = <String>{for (final l in _lists!) ...l.sites}.toList()..sort();
    final bundle = <String, dynamic>{'URLBlocklist': sites};
    // Loosening check against the first browser's current bundle. The
    // write merges, so the effective new state is the current bundle
    // with URLBlocklist replaced — other keys are preserved and must
    // not count as loosened.
    var loosening = false;
    try {
      final current = await widget.controller.channel
          .getApplicationRestrictions(browsers.first.packageName);
      loosening = Loosening.isLooserRestrictions(
        oldRestrictions: current,
        newRestrictions: {...current, ...bundle},
      );
    } catch (_) {
      loosening = false;
    }
    Future<void> apply() async {
      setState(() => _busy = true);
      try {
        await _applyRestrictions(_lists!, silent: false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Browser restrictions'),
        actions: [
          IconButton(
            onPressed: () => _editList(null),
            icon: const Icon(Icons.add),
            tooltip: 'New blocklist',
          ),
        ],
      ),
      body: _lists == null
          ? const LoadingView(message: 'Loading blocklists…')
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error is PrivilegedException
                        ? friendlyError(_error! as PrivilegedException)
                        : _error.toString()),
                  ),
                Text('Supporting browsers', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                if (_browsers == null || _browsers!.isEmpty)
                  const Text(
                    'No installed browser declares URLBlocklist in its '
                    'managed restrictions, so there is nothing to push '
                    'policy to. Browsers without support are handled by '
                    'suspension rules (v1.1 auto-suspension).',
                  )
                else
                  for (final b in _browsers!) Text('• ${b.label} (${b.packageName})'),
                const SizedBox(height: 16),
                Text('Blocklists', style: Theme.of(context).textTheme.titleMedium),
                if (_lists!.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('No blocklists yet. Create one to start blocking sites.'),
                  )
                else
                  for (final l in _lists!)
                    ListTile(
                      title: Text(l.title),
                      subtitle: Text('${l.sites.length} site(s)'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _saveLists(
                          _lists!.where((x) => x.id != l.id).toList(),
                          loosening: true,
                        ),
                      ),
                      onTap: () => _editList(l),
                    ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy || (_browsers?.isEmpty ?? true) ? null : _applyToBrowsers,
                  icon: const Icon(Icons.upload_outlined),
                  label: const Text('Apply blocklists to browsers'),
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
      builder: (_) => AlertDialog(
        title: const Text('Active blocking words'),
        content: TextField(
          controller: controller,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'One word or phrase per line',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              controller.text
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
    final loosening = saved.length < _state!.words.length ||
        !_state!.words.every(saved.contains);
    Future<void> save() async {
      final s = await widget.controller.channel
          .setBlockedWords(saved, _state!.targetPackages);
      if (mounted) setState(() => _state = s);
    }

    if (loosening) {
      await runLoosening(context, widget.controller, save);
    } else {
      await save();
    }
  }

  Future<void> _pickTargets() async {
    final selected = {..._state!.targetPackages};
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Apps where active words block'),
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
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected.toList()),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final loosening = result.length < _state!.targetPackages.length;
    Future<void> save() async {
      final s = await widget.controller.channel.setBlockedWords(_state!.words, result);
      if (mounted) setState(() => _state = s);
    }

    if (loosening) {
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
      builder: (_) => AlertDialog(
        title: Text('On-screen words for ${_labelFor(packageName)}'),
        content: TextField(
          controller: controller,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'One word or phrase per line',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              controller.text
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
    final loosening = saved.length < current.length || !current.every(saved.contains);
    Future<void> save() async {
      final s = await widget.controller.channel.setPassiveWords(packageName, saved);
      if (mounted) setState(() => _state = s);
    }

    if (loosening) {
      await runLoosening(context, widget.controller, save);
    } else {
      await save();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Scaffold(appBar: AppBar(title: const Text('Blocked words')), body: ErrorView(error: _error!, onRetry: _load));
    if (_state == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Blocked words')),
        body: const LoadingView(message: 'Loading blocked words…'),
      );
    }
    final s = _state!;
    return Scaffold(
      appBar: AppBar(title: const Text('Blocked words')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Active blocking (F14)', style: Theme.of(context).textTheme.titleMedium),
          const Text(
            'When a word is present in the text field of a chosen app and '
            'typing ends, the app is backed out of and a block screen shows.',
          ),
          ListTile(
            title: Text('${s.words.length} word(s)'),
            subtitle: Text(s.words.take(5).join(', ')),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _editWords,
          ),
          ListTile(
            title: Text('${s.targetPackages.length} target app(s)'),
            subtitle: Text(s.targetPackages.map(_labelFor).take(3).join(', ')),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _pickTargets,
          ),
          const Divider(),
          Text('Passive blocking (F15)', style: Theme.of(context).textTheme.titleMedium),
          const Text('Words appearing anywhere on screen in a specific app.'),
          if (s.passiveWords.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No per-app lists yet.'),
            )
          else
            for (final entry in s.passiveWords.entries)
              ListTile(
                title: Text(_labelFor(entry.key)),
                subtitle: Text('${entry.value.length} word(s)'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _editPassive(entry.key),
              ),
          TextButton.icon(
            onPressed: () async {
              // Add a passive list for one of the target apps not yet listed.
              final candidates = s.targetPackages
                  .where((p) => !s.passiveWords.containsKey(p))
                  .toList();
              if (candidates.isEmpty) {
                showInfoSnackBar(context,
                    'Add target apps above first — passive lists attach to them in v1.');
                return;
              }
              await _editPassive(candidates.first);
            },
            icon: const Icon(Icons.add),
            label: const Text('Add per-app list'),
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
    final loosening = (_enabled == true && !enabled) ||
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
      await save();
    }
  }

  void _updateStage(UsageWarningStage updated) {
    _save(_enabled ?? false, [
      for (final s in _stages!)
        if (s.id == updated.id) updated else s,
    ]);
  }

  void _removeStage(UsageWarningStage stage) {
    _save(_enabled ?? false,
        _stages!.where((s) => s.id != stage.id).toList());
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
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Usage warnings')),
        body: ErrorView(error: _error!, onRetry: _load),
      );
    }
    if (_stages == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Usage warnings')),
        body: const LoadingView(message: 'Loading warning stages…'),
      );
    }
    final enabled = _enabled ?? false;
    // Display order mirrors the original: descending by minutes.
    final sorted = [..._stages!]
      ..sort((a, b) => b.minutesBefore.compareTo(a.minutesBefore));
    return Scaffold(
      appBar: AppBar(title: const Text('Usage warnings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('Staged warnings before a limit expires'),
            value: enabled,
            onChanged: (v) => _save(v, _stages!),
          ),
          const Text(
            'Each stage warns once, the configured number of minutes '
            'before an app\'s daily limit runs out. Stages are stored '
            'for the Accessibility Service to fire; notification '
            'delivery depends on the native notifier.',
          ),
          const SizedBox(height: 8),
          if (sorted.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No warning stages. Add at least one stage or no '
                'warnings will be shown.',
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
            icon: const Icon(Icons.add),
            label: const Text('Add stage'),
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
    _minutesC =
        TextEditingController(text: _formatMinutes(widget.stage.minutesBefore));
    _vibrationC =
        TextEditingController(text: widget.stage.vibrationCount.toString());
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
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d{0,3}([.,]\d{0,2})?$')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Minutes before',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: _onMinutesChanged,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error),
                  tooltip: 'Remove stage',
                  onPressed: widget.enabled ? widget.onRemove : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<UsageWarningType>(
              segments: const [
                ButtonSegment(
                    value: UsageWarningType.silent, label: Text('Silent')),
                ButtonSegment(
                    value: UsageWarningType.sound, label: Text('Sound')),
                ButtonSegment(
                    value: UsageWarningType.vibrate, label: Text('Vibrate')),
              ],
              selected: {stage.type},
              onSelectionChanged: widget.enabled
                  ? (s) => widget
                      .onChanged(stage.copyWith(type: s.first))
                  : null,
            ),
            if (stage.type == UsageWarningType.vibrate) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(child: Text('Vibration count')),
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
        title: const Text('Suspension logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear logs (recovery session required)',
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
              ? const LoadingView(message: 'Loading logs…')
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          labelText: 'Search logs',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                    Expanded(
                      child: filtered.isEmpty
                          ? const EmptyView(
                              icon: Icons.history,
                              message: 'No suspensions have been logged.',
                            )
                          : ListView(
                              children: [
                                for (final l in filtered)
                                  ListTile(
                                    title: Text(l.appName),
                                    subtitle: Text(
                                        '${l.reason} · ${l.timestamp}\n${l.packageName}${l.details != null ? ' · ${l.details}' : ''}'),
                                    isThreeLine: true,
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
    );
  }
}
