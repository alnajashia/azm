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
  List<InstalledBrowser>? _browsers;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final lists = await widget.controller.config.getBlockedLists();
      List<InstalledBrowser> browsers = const [];
      Object? browserError;
      try {
        // Batch C (C1): every installed browser, with restriction
        // support, suspension state and icon — the port of DeChainer's
        // BrowserRestrictionsManager.getPossibleBrowsers.
        browsers = await widget.controller.channel.listInstalledBrowsers();
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

    // Only a loosening save is recovery-gated (user rule
    // 2026-11-22: activation never asks for the code): a list
    // deleted, or one of its sites dropped. Adding lists or sites
    // tightens and is free.
    final oldLists = _lists ?? const <BlockedList>[];
    final nextById = {for (final l in kept) l.id: l};
    final loosens = oldLists.any((old) {
      final next = nextById[old.id];
      return next == null || !next.sites.toSet().containsAll(old.sites);
    });
    if (loosens) {
      await runLoosening(context, widget.controller, save);
    } else {
      try {
        await save();
      } catch (e) {
        if (mounted) await showErrorCard(context, e);
      }
    }
  }

  /// Pushes the union of all lists' sites to every SUPPORTING browser,
  /// mirroring `BrowserRestrictionsManager.applyRestrictions`
  /// (`BrowserRestrictionsManager.kt:124-149`): bundle is exactly
  /// `{URLBlocklist: sites}` — SafeSearch is NOT forced here — and the
  /// write MERGES with each browser's existing restrictions
  /// (`merge = true`), never replacing them. Unsupported browsers are
  /// skipped: they cannot honour the blocklist, and the screen says so
  /// under each one instead of pretending the apply reached them.
  Future<void> _applyRestrictions(
    List<BlockedList> lists, {
    required bool silent,
  }) async {
    final browsers = (_browsers ?? const [])
        .where((b) => b.supportsRestrictions)
        .toList();
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

  /// The per-browser allow switch (Batch C, C1). The switch shows
  /// "allowed": ON means the browser is NOT suspended. Suspending is
  /// a tightening (direct); unsuspending is a loosening (recovery
  /// gate). The state is updated from the verified native reply, not
  /// from the requested value.
  Future<void> _toggleBrowser(InstalledBrowser browser, bool allowed) async {
    Future<void> apply() async {
      final results = await widget.controller.channel.setAppSuspended(
        [browser.packageName],
        !allowed,
        reason: 'MANUAL',
      );
      final verified = results.firstOrNull;
      if (mounted) {
        setState(() {
          _browsers = _browsers
              ?.map(
                (b) => b.packageName == browser.packageName
                    ? InstalledBrowser(
                        packageName: b.packageName,
                        label: b.label,
                        supportsRestrictions: b.supportsRestrictions,
                        isSuspended: verified?.isSuspended ?? !allowed,
                        iconBytes: b.iconBytes,
                      )
                    : b,
              )
              .toList();
        });
      }
    }

    if (allowed) {
      await runLoosening(context, widget.controller, apply);
    } else {
      try {
        await apply();
      } catch (e) {
        if (mounted) await showErrorCard(context, e);
      }
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
    final browsers = (_browsers ?? const [])
        .where((b) => b.supportsRestrictions)
        .toList();
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
    // Pushing the already-saved blocklists to the browsers is free:
    // the save itself is the gate point (user rule 2026-11-22).
    await apply();
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
                // Batch C (C1): every installed browser gets its own
                // tile with icon, allow switch and — for unsupported
                // browsers — the red warning that restrictions do not
                // work there (DeChainer's exact wording).
                SectionCard(
                  title: l10n.supportingBrowsers,
                  children: [
                    if (_browsers == null || _browsers!.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                        child: Text(l10n.noCapableBrowser),
                      )
                    else
                      for (final b in _browsers!)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ListTile(
                              leading: b.iconBytes != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.memory(
                                        Uint8List.fromList(b.iconBytes!),
                                        width: 40,
                                        height: 40,
                                      ),
                                    )
                                  : const Icon(Icons.language_outlined),
                              title: Text(b.label),
                              subtitle: Text(b.packageName),
                              trailing: Switch(
                                value: !b.isSuspended,
                                onChanged: _busy
                                    ? null
                                    : (v) => _toggleBrowser(b, v),
                              ),
                            ),
                            if (!b.supportsRestrictions)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                child: Text(
                                  l10n.browserUnsupportedWarning,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.error,
                                  ),
                                ),
                              ),
                          ],
                        ),
                  ],
                ),
                // Batch G, item 6: the torrent card moved to the
                // Config tab (Settings) — torrent clients have
                // nothing to do with browsers.
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
                            onPressed: () async {
                              final confirmed =
                                  await showDestructiveConfirmDialog(
                                context,
                                title: l10n.deleteBlocklistConfirmTitle,
                                message: l10n.deleteBlocklistConfirmMessage(
                                  l.title,
                                ),
                                confirmText: l10n.passwordRemoveConfirm,
                              );
                              if (confirmed && mounted) {
                                await _saveLists(
                                  _lists!.where((x) => x.id != l.id).toList(),
                                );
                              }
                            },
                          ),
                          onTap: () => _editList(l),
                        ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed:
                      _busy ||
                          !(_browsers?.any(
                                (b) => b.supportsRestrictions,
                              ) ??
                              false)
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

enum _BlockedWordsView { byApp, byWord }

class _BlockedWordsScreenState extends State<BlockedWordsScreen> {
  BlockedWordsState? _state;
  List<InstalledApp>? _apps;
  List<AppGroupModel>? _groups;
  Object? _error;
  var _view = _BlockedWordsView.byApp;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final state = await widget.controller.channel.getBlockedWords();
      final apps = await widget.controller.channel.listInstalledApps();
      // Groups are nice-to-have here (names + expansion): a failure
      // to load them must not break the whole screen.
      List<AppGroupModel> groups = const [];
      try {
        groups = await widget.controller.channel.getGroups();
      } catch (_) {
        groups = const [];
      }
      if (mounted) {
        setState(() {
          _state = state;
          _apps = apps;
          _groups = groups;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String _labelFor(String pkg) =>
      _apps?.where((a) => a.packageName == pkg).firstOrNull?.label ?? pkg;

  String _groupName(String id) =>
      _groups?.where((g) => g.id == id).firstOrNull?.name ?? id;

  /// Persists a whole new assignment table. [loosens] follows the
  /// standing gates: removing coverage or activating blocking in a
  /// new place goes through the paper-code session; tightening is
  /// direct (but a channel error still surfaces, never swallowed).
  Future<void> _saveAssignments(
    List<WordAssignment> next, {
    required bool loosens,
  }) async {
    Future<void> save() async {
      final s = await widget.controller.channel.setWordAssignments(next);
      if (mounted) setState(() => _state = s);
    }

    if (!mounted) return;
    if (loosens) {
      await runLoosening(context, widget.controller, save);
    } else {
      try {
        await save();
      } catch (e) {
        if (mounted) await showErrorCard(context, e);
      }
    }
  }

  /// One word row in the app dialog: the word, its Typed / On-screen
  /// mode chips, and a delete button. [subtitle] names the word's
  /// other targets when it also applies elsewhere — the chips edit
  /// the word's modes everywhere, so the row must say so.
  Widget _modeRow({
    required AppLocalizations l10n,
    required String title,
    String? subtitle,
    required Set<WordBlockMode> modes,
    required void Function(WordBlockMode mode, bool selected) onMode,
    required VoidCallback onDelete,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title)),
            IconButton(
              icon: const Icon(Icons.delete_outlined),
              onPressed: onDelete,
            ),
          ],
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Wrap(
          spacing: 8,
          children: [
            for (final mode in WordBlockMode.values)
              FilterChip(
                label: Text(
                  mode == WordBlockMode.active
                      ? l10n.wordModeActive
                      : l10n.wordModePassive,
                ),
                selected: modes.contains(mode),
                onSelected: (v) => onMode(mode, v),
              ),
          ],
        ),
        const Divider(),
      ],
    );
  }

  /// Edits one app's words (words-per-app direction). A newly added
  /// word starts with BOTH modes on — "block this word in this app"
  /// — and the chips let the user narrow it down.
  ///
  /// Batch J: the modes are per WORD, not per app, so the chips edit
  /// the word's modes everywhere it applies. A word that also
  /// targets other apps or groups says so under its row. A word that
  /// covers this app only through a group is shown read-only with
  /// the group named; tapping it jumps to the word editor.
  Future<void> _editAppWords(String packageName) async {
    final l10n = context.l10n;
    final s = _state!;
    final groups = _groups ?? const [];
    final oldCoverage = appWordCoverage(s.assignments, packageName, groups);
    // Direct words (editable chips) and words covering this app only
    // through a group (read-only rows with the group named).
    final modes = <String, Set<WordBlockMode>>{};
    final viaGroups = <String, List<String>>{};
    for (final a in s.assignments) {
      final direct = a.packageNames.contains(packageName);
      final names = a.coveringGroupNames(packageName, groups);
      if (direct) {
        (modes[a.word] ??= {}).addAll(a.modes);
      }
      if (names.isNotEmpty) {
        viaGroups[a.word] = names;
      }
    }
    String? jumpToWord;
    final addController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          void addWord() {
            final word = addController.text.trim();
            if (word.isEmpty || modes.containsKey(word)) return;
            setDialogState(() {
              modes[word] = {
                WordBlockMode.active,
                WordBlockMode.passive,
              };
              addController.clear();
            });
          }

          // Other apps a word targets, for the honest subtitle under
          // its row (groups are shown by the via-note instead).
          String? otherTargets(String word) {
            final entry = s.forWord(word).firstOrNull;
            if (entry == null) return null;
            final names = [
              for (final p in entry.packageNames)
                if (p != packageName) _labelFor(p),
            ];
            if (names.isEmpty) return null;
            return l10n.blockedWordsAlsoTargets(names.join(', '));
          }

          String? subtitleFor(String word) {
            final parts = <String>[];
            final via = viaGroups[word];
            if (via != null) {
              parts.add(l10n.blockedWordsViaGroup(via.join(', ')));
            }
            final other = otherTargets(word);
            if (other != null) parts.add(other);
            return parts.isEmpty ? null : parts.join(' · ');
          }

          return AlertDialog(
            // Dechainer parity: the per-app dialog is titled with the
            // app's name alone, exactly like the original.
            title: Text(_labelFor(packageName)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.blockedWordsIntro),
                  const SizedBox(height: 12),
                  for (final word in modes.keys.toList()..sort())
                    _modeRow(
                      l10n: l10n,
                      title: word,
                      subtitle: subtitleFor(word),
                      modes: modes[word]!,
                      onMode: (mode, selected) => setDialogState(() {
                        if (selected) {
                          modes[word]!.add(mode);
                        } else {
                          modes[word]!.remove(mode);
                        }
                      }),
                      onDelete: () =>
                          setDialogState(() => modes.remove(word)),
                    ),
                  for (final word in (viaGroups.keys.toList()..sort())
                      .where((w) => !modes.containsKey(w)))
                    ListTile(
                      title: Text(word),
                      subtitle: Text(
                        l10n.blockedWordsViaGroup(
                          viaGroups[word]!.join(', '),
                        ),
                      ),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () {
                        jumpToWord = word;
                        Navigator.pop(dialogContext, false);
                      },
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: addController,
                          decoration: InputDecoration(
                            hintText: l10n.wordHint,
                            labelText: l10n.blockedWordsAddWord,
                            border: const OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => addWord(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_outlined),
                        onPressed: addWord,
                      ),
                    ],
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
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(l10n.save),
              ),
            ],
          );
        },
      ),
    );
    // NOTE: intentionally not disposed here — disposing while the
    // dialog route is still animating out re-attaches listeners to a
    // dead controller ("used after being disposed"). The old
    // per-dialog controllers were never disposed either.
    if (!mounted) return;
    if (jumpToWord != null) {
      await _editWordTargets(jumpToWord!);
      return;
    }
    if (saved != true) return;
    // Rebuild the table: this app's direct coverage follows the
    // dialog; every other row is untouched. Removing the app from a
    // row keeps the row when groups still cover it.
    final next = <WordAssignment>[];
    final handled = <String>{};
    for (final a in s.assignments) {
      final dialogModes = modes[a.word];
      final isDirect = a.packageNames.contains(packageName);
      if (!isDirect && dialogModes == null) {
        next.add(a);
        continue;
      }
      handled.add(a.word);
      final remainingPkgs =
          a.packageNames.where((p) => p != packageName).toList();
      if (dialogModes == null || dialogModes.isEmpty) {
        // Direct coverage removed (word deleted in the dialog).
        if (a.groupIds.isNotEmpty) {
          next.add(
            WordAssignment(
              word: a.word,
              packageNames: remainingPkgs,
              groupIds: a.groupIds,
              modes: a.modes,
            ),
          );
        }
        // Else the row is gone entirely.
      } else {
        next.add(
          WordAssignment(
            word: a.word,
            packageNames: [...remainingPkgs, packageName],
            groupIds: a.groupIds,
            modes: dialogModes,
          ),
        );
      }
    }
    // Words added in the dialog are new rows for this app alone.
    for (final word in modes.keys) {
      if (!handled.contains(word)) {
        next.add(
          WordAssignment(
            word: word,
            packageNames: [packageName],
            modes: modes[word]!,
          ),
        );
      }
    }
    await _saveAssignments(
      next,
      loosens: appCoverageChangeLoosens(
        oldCoverage,
        appWordCoverage(next, packageName, groups),
      ),
    );
  }

  /// Edits one word's targets (apps-per-word direction, Batch J):
  /// one word, any mix of apps and groups, and its modes. The mode
  /// chips sit at the top because they apply to ALL of the word's
  /// targets. Removing every target drops the word entirely.
  Future<void> _editWordTargets(String word) async {
    final l10n = context.l10n;
    final s = _state!;
    final oldRow = s.forWord(word).firstOrNull;
    final oldForWord = oldRow == null ? const <WordAssignment>[] : [oldRow];
    var modes = {...?oldRow?.modes};
    var packageNames = [...?oldRow?.packageNames];
    var groupIds = [...?oldRow?.groupIds];
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(l10n.blockedWordsTargetsForWord(word)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.blockedWordsIntro),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final mode in WordBlockMode.values)
                      FilterChip(
                        label: Text(
                          mode == WordBlockMode.active
                              ? l10n.wordModeActive
                              : l10n.wordModePassive,
                        ),
                        selected: modes.contains(mode),
                        onSelected: (v) => setDialogState(() {
                          if (v) {
                            modes.add(mode);
                          } else {
                            modes.remove(mode);
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.blockedWordsAppsTitle,
                  style: Theme.of(dialogContext).textTheme.titleSmall,
                ),
                for (final pkg in packageNames.toList()
                  ..sort((a, b) => _labelFor(a).compareTo(_labelFor(b))))
                  ListTile(
                    title: Text(_labelFor(pkg)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outlined),
                      onPressed: () => setDialogState(
                        () => packageNames.remove(pkg),
                      ),
                    ),
                  ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () async {
                      final picked = await showAppPicker(
                        context: dialogContext,
                        channel: widget.controller.channel,
                        title: l10n.blockedWordsAddApp,
                        initialSelected: packageNames.toSet(),
                        preloadedApps: _apps,
                      );
                      if (picked == null) return;
                      setDialogState(
                        () => packageNames = picked.toList()
                          ..sort(
                            (a, b) => _labelFor(a).compareTo(_labelFor(b)),
                          ),
                      );
                    },
                    icon: const Icon(Icons.add_outlined),
                    label: Text(l10n.blockedWordsAddApp),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.blockedWordsGroupsTitle,
                  style: Theme.of(dialogContext).textTheme.titleSmall,
                ),
                for (final id in groupIds.toList()
                  ..sort((a, b) => _groupName(a).compareTo(_groupName(b))))
                  ListTile(
                    title: Text(_groupName(id)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outlined),
                      onPressed: () =>
                          setDialogState(() => groupIds.remove(id)),
                    ),
                  ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () async {
                      final picked = await _pickWordGroups(
                        dialogContext,
                        groupIds.toSet(),
                      );
                      if (picked == null) return;
                      setDialogState(() => groupIds = picked.toList());
                    },
                    icon: const Icon(Icons.add_outlined),
                    label: Text(l10n.blockedWordsAddGroup),
                  ),
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
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final nextRow = (packageNames.isEmpty && groupIds.isEmpty) ||
            modes.isEmpty
        ? null
        : WordAssignment(
            word: word,
            packageNames: packageNames,
            groupIds: groupIds,
            modes: modes,
          );
    final next = [
      for (final a in s.assignments)
        if (a.word != word) a,
      if (nextRow != null) nextRow,
    ];
    await _saveAssignments(
      next,
      loosens: wordAssignmentsChangeLoosens(
        oldForWord,
        nextRow == null ? const [] : [nextRow],
      ),
    );
  }

  /// Multi-select group picker for the word editor, with select-all
  /// (Batch J). Returns the full selected set, or null on cancel.
  Future<Set<String>?> _pickWordGroups(
    BuildContext dialogContext,
    Set<String> initialSelected,
  ) async {
    final l10n = context.l10n;
    final groups = _groups ?? const [];
    var selected = Set<String>.from(initialSelected);
    return showDialog<Set<String>>(
      context: dialogContext,
      builder: (groupDialogContext) => StatefulBuilder(
        builder: (groupDialogContext, setGroupState) => AlertDialog(
          title: Text(l10n.blockedWordsGroupsTitle),
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
              onPressed: () => Navigator.of(groupDialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            selectAllAction(
              l10n: l10n,
              allSelected:
                  groups.isNotEmpty &&
                  groups.every((g) => selected.contains(g.id)),
              enabled: groups.isNotEmpty,
              onPressed: () => setGroupState(() {
                if (groups.every((g) => selected.contains(g.id))) {
                  selected.clear();
                } else {
                  selected.addAll(groups.map((g) => g.id));
                }
              }),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(groupDialogContext).pop(selected),
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addApp() async {
    final groups = _groups ?? const [];
    final listed = {
      for (final a in _state!.assignments) ...a.expandedPackages(groups),
    };
    final candidates = (_apps ?? const [])
        .where((a) => !listed.contains(a.packageName))
        .toList();
    if (candidates.isEmpty) {
      showInfoSnackBar(context, context.l10n.blockedWordsNoMoreApps);
      return;
    }
    final picked = await showAppPicker(
      context: context,
      channel: widget.controller.channel,
      title: context.l10n.blockedWordsAddApp,
      singleSelect: true,
      preloadedApps: candidates,
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    await _editAppWords(picked.first);
  }

  String _appSubtitle(AppLocalizations l10n, List<WordAssignment> forApp) {
    final words = {for (final a in forApp) a.word}.length;
    final modes = {for (final a in forApp) ...a.modes};
    if (modes.isEmpty) return l10n.wordsCount(words);
    final modeLabel = modes.length == 2
        ? '${l10n.wordModeActive} + ${l10n.wordModePassive}'
        : modes.first == WordBlockMode.active
        ? l10n.wordModeActive
        : l10n.wordModePassive;
    return '${l10n.wordsCount(words)} · $modeLabel';
  }

  /// By-word row subtitle: how many apps and groups the word targets.
  String _wordSubtitle(AppLocalizations l10n, WordAssignment a) {
    final parts = <String>[l10n.targetAppsCount(a.packageNames.length)];
    if (a.groupIds.isNotEmpty) {
      parts.add(l10n.targetGroupsCount(a.groupIds.length));
    }
    return parts.join(' · ');
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
    final groups = _groups ?? const [];
    final appsWithWords = {
      for (final a in s.assignments) ...a.expandedPackages(groups),
    }.toList()..sort((a, b) => _labelFor(a).compareTo(_labelFor(b)));
    final words = {
      for (final a in s.assignments) a.word,
    }.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.blockedWords)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // v1.0.5 UX (user directive): titled card groups.
          SectionCard(
            title: l10n.blockedWords,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(l10n.blockedWordsIntro),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SegmentedButton<_BlockedWordsView>(
                  segments: [
                    ButtonSegment(
                      value: _BlockedWordsView.byApp,
                      label: Text(l10n.blockedWordsByApp),
                    ),
                    ButtonSegment(
                      value: _BlockedWordsView.byWord,
                      label: Text(l10n.blockedWordsByWord),
                    ),
                  ],
                  selected: {_view},
                  onSelectionChanged: (v) =>
                      setState(() => _view = v.first),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_view == _BlockedWordsView.byApp)
            SectionCard(
              title: l10n.blockedWordsByApp,
              children: [
                if (appsWithWords.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Text(l10n.blockedWordsNoApps),
                  )
                else
                  for (final pkg in appsWithWords)
                    ListTile(
                      leading: const Icon(Icons.android_outlined),
                      title: Text(_labelFor(pkg)),
                      subtitle: Text(
                        _appSubtitle(
                          l10n,
                          s.forApp(pkg, groups: groups),
                        ),
                      ),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _editAppWords(pkg),
                    ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: _addApp,
                    icon: const Icon(Icons.add_outlined),
                    label: Text(l10n.blockedWordsAddApp),
                  ),
                ),
              ],
            )
          else
            SectionCard(
              title: l10n.blockedWordsByWord,
              children: [
                if (words.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Text(l10n.blockedWordsNoWords),
                  )
                else
                  for (final word in words)
                    ListTile(
                      title: Text(word),
                      subtitle: Text(
                        _wordSubtitle(l10n, s.forWord(word).first),
                      ),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _editWordTargets(word),
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

  Future<void> _removeStage(UsageWarningStage stage) async {
    final minutesStr = stage.minutesBefore.toStringAsFixed(
      stage.minutesBefore.truncateToDouble() == stage.minutesBefore ? 0 : 1,
    );
    final confirmed = await showDestructiveConfirmDialog(
      context,
      title: context.l10n.deleteStageConfirmTitle,
      message: context.l10n.deleteStageConfirmMessage(minutesStr),
      confirmText: context.l10n.passwordRemoveConfirm,
    );
    if (confirmed && mounted) {
      _save(_enabled ?? false, _stages!.where((s) => s.id != stage.id).toList());
    }
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
