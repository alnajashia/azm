/// Config sub-screens: Browser restrictions (F5), Blocked words (F14/F15),
/// Usage warnings (F12), Suspension logs (F27), Impulse lock (F21) +
/// challenge settings (F22), Focus mode (F25).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../data/config_store.dart';
import '../data/dns_protection.dart';
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

  // DNS protection (Batch DNS): persisted selection + verified native
  // state. The shortcut card below the browsers scrolls to the full
  // DNS card below the blocklists.
  DnsProtection? _dns;
  PrivateDnsState? _dnsState;
  bool _dnsBusy = false;
  final _dnsCardKey = GlobalKey();
  final _dnsIdController = TextEditingController();

  // Torrent apps (Batch F, item 4): detected clients + the native
  // block-torrents flag. The flag lives natively (SettingsStore) so
  // the install hook (AzmApplication) can read it with the UI closed.
  List<({String packageName, String label})>? _torrentApps;
  bool? _blockTorrents;
  bool _torrentBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _dnsIdController.dispose();
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
      // Batch DNS: persisted selection + the verified native state
      // (never trust the saved flag alone — read the device).
      DnsProtection? dns;
      PrivateDnsState? dnsState;
      try {
        dns = await widget.controller.config.getDnsProtection();
      } catch (_) {}
      try {
        dnsState = await widget.controller.channel.getPrivateDns();
      } catch (_) {}
      // Batch F, item 4: detected torrent clients + the native flag.
      List<({String packageName, String label})>? torrentApps;
      bool? blockTorrents;
      try {
        torrentApps = await widget.controller.channel.getTorrentApps();
      } catch (_) {}
      try {
        blockTorrents = await widget.controller.channel.isBlockTorrentsEnabled();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _lists = lists;
          _browsers = browsers;
          _error = browserError;
          _dns = dns;
          _dnsState = dnsState;
          if (dns != null) _dnsIdController.text = dns.nextDnsConfigId;
          _torrentApps = torrentApps;
          _blockTorrents = blockTorrents;
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

  /// The torrent switch (Batch F, item 4). Enabling is a tightening
  /// (direct): the native flag is set first, then every detected
  /// torrent client is suspended with reason TORRENT_APP and the
  /// suspended set is saved — so disabling later unsuspends exactly
  /// the apps this toggle blocked. Disabling is a loosening
  /// (recovery-gated). New installs while enabled are suspended by
  /// the AzmApplication install hook, not here.
  Future<void> _toggleTorrents(bool enabled) async {
    Future<void> apply() async {
      setState(() => _torrentBusy = true);
      try {
        // Channel first, prefs only after the verified native reply.
        final verified =
            await widget.controller.channel.setBlockTorrents(enabled);
        final apps = _torrentApps ?? const [];
        if (verified) {
          final suspended = <String>{};
          if (apps.isNotEmpty) {
            final results = await widget.controller.channel.setAppSuspended(
              apps.map((a) => a.packageName).toList(),
              true,
              reason: 'TORRENT_APP',
            );
            suspended.addAll(
              results.where((r) => r.isSuspended).map((r) => r.packageName),
            );
          }
          await widget.controller.config.setTorrentBlockedPackages(suspended);
          if (mounted) {
            setState(() => _blockTorrents = true);
            showInfoSnackBar(
              context,
              context.l10n.torrentBlockedMsg(suspended.length),
            );
          }
        } else {
          final blocked =
              await widget.controller.config.getTorrentBlockedPackages();
          if (blocked.isNotEmpty) {
            await widget.controller.channel.setAppSuspended(
              blocked.toList(),
              false,
            );
          }
          await widget.controller.config.setTorrentBlockedPackages(const {});
          if (mounted) {
            setState(() => _blockTorrents = false);
            showInfoSnackBar(context, context.l10n.torrentUnblockedMsg);
          }
        }
      } finally {
        if (mounted) setState(() => _torrentBusy = false);
      }
    }

    if (enabled) {
      try {
        await apply();
      } catch (e) {
        if (mounted) await showErrorCard(context, e);
      }
    } else {
      await runLoosening(context, widget.controller, apply);
    }
  }

  /// Applies a DNS-protection selection: the channel call runs FIRST
  /// and the preference is saved only after the verified native reply,
  /// so the saved flag can never claim a state the device is not in.
  /// Enabling is a tightening (direct); disabling is a loosening
  /// (recovery-gated, like unsuspending a browser).
  Future<void> _applyDns(DnsProtection next) async {
    if (_dnsBusy) return;
    if (next.enabled && !next.isValid) {
      if (mounted) {
        showInfoSnackBar(context, context.l10n.dnsInvalidConfigId);
      }
      return;
    }

    Future<void> apply() async {
      setState(() => _dnsBusy = true);
      try {
        final PrivateDnsState state;
        if (!next.enabled) {
          state = await widget.controller.channel.resetPrivateDns();
        } else {
          state = await widget.controller.channel.setPrivateDns(
            next.hostname!,
          );
        }
        await widget.controller.config.setDnsProtection(next);
        if (mounted) {
          setState(() {
            _dns = next;
            _dnsState = state;
          });
          showInfoSnackBar(
            context,
            next.enabled
                ? context.l10n.dnsApplied
                : context.l10n.dnsTurnedOff,
          );
        }
      } catch (e) {
        if (mounted) await showErrorCard(context, e);
      } finally {
        if (mounted) setState(() => _dnsBusy = false);
      }
    }

    if (!next.enabled && (_dns?.enabled ?? false)) {
      await runLoosening(context, widget.controller, apply);
    } else {
      await apply();
    }
  }

  Future<void> _toggleDns(bool value) async {
    final current = _dns ?? const DnsProtection();
    await _applyDns(current.copyWith(enabled: value));
  }

  /// Provider switch: while protection is on it re-applies at once
  /// with the new provider's hostname; while off it only persists the
  /// choice. A switch to NextDNS without an ID is refused, so the
  /// saved selection can never name a hostname that does not exist.
  Future<void> _selectDnsProvider(DnsProvider provider) async {
    final current = _dns ?? const DnsProtection();
    if (current.provider == provider) return;
    final next = current.copyWith(provider: provider);
    if (next.enabled) {
      await _applyDns(next);
    } else {
      await widget.controller.config.setDnsProtection(next);
      if (mounted) setState(() => _dns = next);
    }
  }

  /// NextDNS configuration ID, applied on submit: while protection is
  /// on with NextDNS it re-applies at once; otherwise it only persists.
  Future<void> _submitDnsConfigId(String value) async {
    final current = _dns ?? const DnsProtection();
    final next = current.copyWith(nextDnsConfigId: value.trim());
    if (next.enabled && next.provider == DnsProvider.nextdns) {
      await _applyDns(next);
    } else {
      await widget.controller.config.setDnsProtection(next);
      if (mounted) setState(() => _dns = next);
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
                // Batch F, item 4: block torrent apps — one switch
                // suspends every detected torrent client now and arms
                // the install hook for later ones (AzmApplication).
                const SizedBox(height: 12),
                SectionCard(
                  title: l10n.torrentTitle,
                  children: [
                    SwitchListTile(
                      title: Text(l10n.torrentTitle),
                      subtitle: Text(l10n.torrentSub),
                      value: _blockTorrents ?? false,
                      onChanged: _torrentBusy || _blockTorrents == null
                          ? null
                          : _toggleTorrents,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: _torrentApps == null
                          ? Text(l10n.loadingShort)
                          : _torrentApps!.isEmpty
                              ? Text(l10n.torrentDetectedNone)
                              : Text(
                                  l10n.torrentDetectedCount(
                                    _torrentApps!.length,
                                  ),
                                ),
                    ),
                    if (_torrentApps != null)
                      for (final a in _torrentApps!)
                        ListTile(
                          leading:
                              const Icon(Icons.file_download_outlined),
                          title: Text(a.label),
                          subtitle: Text(a.packageName),
                        ),
                  ],
                ),
                // Batch DNS: compact shortcut to the full DNS card
                // below the blocklists — the state at a glance, one
                // tap scrolls to the controls.
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.shield_outlined),
                    title: Text(l10n.dnsProtectionTitle),
                    subtitle: Text(
                      _dns == null
                          ? ''
                          : _dns!.enabled
                              ? '${l10n.dnsProtectionEnabled} — ${_dns!.provider == DnsProvider.nextdns ? l10n.dnsProviderNextdns : l10n.dnsProviderCleanbrowsing}'
                              : l10n.dnsProtectionDisabled,
                    ),
                    trailing: TextButton(
                      onPressed: () {
                        final ctx = _dnsCardKey.currentContext;
                        if (ctx != null) {
                          Scrollable.ensureVisible(
                            ctx,
                            duration: const Duration(milliseconds: 300),
                          );
                        }
                      },
                      child: Text(l10n.dnsSettings),
                    ),
                  ),
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
                // Batch DNS: the full DNS-protection card — switch,
                // provider choice (both inside the app), NextDNS ID,
                // verified native state and the honest note that
                // filtering is domain-level and device-wide.
                const SizedBox(height: 12),
                SectionCard(
                  key: _dnsCardKey,
                  title: l10n.dnsProtectionTitle,
                  children: [
                    SwitchListTile(
                      title: Text(l10n.dnsProtectionTitle),
                      subtitle: Text(
                        _dnsState?.hostname != null
                            ? l10n.dnsCurrentHost(_dnsState!.hostname!)
                            : l10n.dnsNotSet,
                      ),
                      value: _dns?.enabled ?? false,
                      onChanged:
                          _dnsBusy || _dns == null ? null : _toggleDns,
                    ),
                    RadioGroup<DnsProvider>(
                      groupValue:
                          _dns?.provider ?? DnsProvider.cleanBrowsing,
                      onChanged: (v) {
                        if (_dnsBusy || _dns == null || v == null) return;
                        _selectDnsProvider(v);
                      },
                      child: Column(
                        children: [
                          RadioListTile<DnsProvider>(
                            title: Text(l10n.dnsProviderNextdns),
                            subtitle: Text(l10n.dnsProviderNextdnsNote),
                            value: DnsProvider.nextdns,
                          ),
                          if ((_dns?.provider ??
                                      DnsProvider.cleanBrowsing) ==
                                  DnsProvider.nextdns)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    8,
                                  ),
                                  child: TextField(
                                    controller: _dnsIdController,
                                    decoration: InputDecoration(
                                      labelText: l10n.dnsConfigIdLabel,
                                      hintText: l10n.dnsConfigIdHint,
                                      helperText: _dnsIdController.text
                                              .trim()
                                              .isEmpty
                                          ? null
                                          : l10n.dnsConfigIdHostname(
                                              _dnsIdController.text.trim(),
                                            ),
                                    ),
                                    enabled: !_dnsBusy,
                                    onChanged: (_) => setState(() {}),
                                    onSubmitted: _submitDnsConfigId,
                                  ),
                                ),
                                // In-app NextDNS setup guide (user
                                // request 14:30): the steps live in
                                // the app itself, next to the ID field.
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    8,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        l10n.dnsNextdnsHowTitle,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(l10n.dnsNextdnsStep1),
                                      Text(l10n.dnsNextdnsStep2),
                                      Text(l10n.dnsNextdnsStep3),
                                      Text(l10n.dnsNextdnsStep4),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          RadioListTile<DnsProvider>(
                            title: Text(l10n.dnsProviderCleanbrowsing),
                            subtitle:
                                Text(l10n.dnsProviderCleanbrowsingNote),
                            value: DnsProvider.cleanBrowsing,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(l10n.dnsProtectionNote),
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

class _BlockedWordsScreenState extends State<BlockedWordsScreen> {
  BlockedWordsState? _state;
  List<InstalledApp>? _apps;
  Object? _error;

  /// The active list's read-only field (Dechainer parity): one
  /// controller owned by the state, re-synced in build — never a fresh
  /// controller per build (that would leak one per rebuild).
  final _activeWordsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _activeWordsController.dispose();
    super.dispose();
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
            hintText: dialogContext.l10n.wordHint,
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
    final result = await showAppPicker(
      context: context,
      channel: widget.controller.channel,
      title: context.l10n.appsWhereWordsBlock,
      initialSelected: _state!.targetPackages.toSet(),
      preloadedApps: _apps,
    );
    if (result == null || !mounted) return;
    final list = result.toList();
    // ANY change to the target set is recovery-gated: removing a target
    // loosens (F23), and ADDING one ACTIVATES word blocking inside an
    // app that did not have it (user directive, v1.0.4 audit).
    final changed =
        list.length != _state!.targetPackages.length ||
        !_state!.targetPackages.every(list.contains);
    Future<void> save() async {
      final s = await widget.controller.channel.setBlockedWords(
        _state!.words,
        list,
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
        // Dechainer parity (item 3): the per-app dialog is titled
        // with the app's name alone, exactly like the original.
        title: Text(_labelFor(packageName)),
        content: TextField(
          controller: controller,
          maxLines: 8,
          decoration: InputDecoration(
            hintText: dialogContext.l10n.wordHint,
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

  /// Deletes a per-app (passive) word list — Dechainer's trash icon on
  /// each passive row. Clearing the list removes the entry natively
  /// (an empty set is deleted, not stored), so the row disappears.
  /// Removing blocking is a loosening, so the delete is recovery-gated.
  Future<void> _deletePassive(String packageName) async {
    Future<void> apply() async {
      final s = await widget.controller.channel.setPassiveWords(
        packageName,
        const [],
      );
      if (mounted) setState(() => _state = s);
    }

    if (!mounted) return;
    await runLoosening(context, widget.controller, apply);
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
              // Dechainer parity (item 3): the active list itself is
              // shown as a read-only multi-line field (placeholder +
              // "one word per line"), not only as a count.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _activeWordsController
                    ..text = s.words.join('\n'),
                  readOnly: true,
                  maxLines: 6,
                  decoration: InputDecoration(
                    hintText: l10n.wordHint,
                    helperText: l10n.oneWordPerLine,
                    border: const OutlineInputBorder(),
                  ),
                ),
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
                    leading: const Icon(Icons.android_outlined),
                    title: Text(_labelFor(entry.key)),
                    subtitle: Text(l10n.wordsCount(entry.value.length)),
                    // Dechainer parity (item 3): each passive row has
                    // an edit pencil AND a delete trash icon.
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _editPassive(entry.key),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outlined),
                          onPressed: () => _deletePassive(entry.key),
                        ),
                      ],
                    ),
                    onTap: () => _editPassive(entry.key),
                  ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () async {
                    // Dechainer parity (item 3): a passive list can be
                    // created for ANY installed app — not only the
                    // active targets. The v1 restriction ("add target
                    // apps first") is gone: the original's Passive
                    // section works with "No apps selected" in Active.
                    final listed = s.passiveWords.keys.toSet();
                    final candidates = (_apps ?? const [])
                        .where((a) => !listed.contains(a.packageName))
                        .toList();
                    if (candidates.isEmpty) {
                      showInfoSnackBar(
                        context,
                        l10n.noMoreAppsForPassive,
                      );
                      return;
                    }
                    final picked = await showAppPicker(
                      context: context,
                      channel: widget.controller.channel,
                      title: l10n.addPerAppList,
                      singleSelect: true,
                      preloadedApps: candidates,
                    );
                    if (picked == null || picked.isEmpty) return;
                    await _editPassive(picked.first);
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
