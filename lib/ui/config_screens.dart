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
  // DNS card below the blocklists. (DNS batch, 2026-11-14: the card
  // is now the ONE DNS place — the Config-tab dialog is retired —
  // with an optional provider list, the real failure reason, and
  // automatic retry on HOST_NOT_SERVING.)
  DnsProtection? _dns;
  PrivateDnsState? _dnsState;
  bool _dnsBusy = false;
  final _dnsCardKey = GlobalKey();
  final _dnsIdController = TextEditingController();
  final _dnsCustomController = TextEditingController();

  /// The last selection an apply was attempted with (it may differ
  /// from [_dns] when the apply failed — [_dns] only ever holds a
  /// verified state). The inline Retry button re-applies this one.
  DnsProtection? _dnsPending;

  /// The mapped failure message of the last DNS apply, shown inline
  /// under the provider list with a Retry button; null when the last
  /// apply succeeded (or none was attempted).
  String? _dnsError;

  /// True while an apply is inside its automatic retry loop.
  bool _dnsRetrying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _dnsIdController.dispose();
    _dnsCustomController.dispose();
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
      if (mounted) {
        setState(() {
          _lists = lists;
          _browsers = browsers;
          _error = browserError;
          _dns = dns;
          _dnsState = dnsState;
          if (dns != null) {
            _dnsIdController.text = dns.nextDnsConfigId;
            _dnsCustomController.text = dns.customHostname;
          }
        });
      }
      // DNS batch: adopt the LIVE host when the saved prefs disagree
      // with the device — a host set by the retired Config-tab dialog
      // (which never persisted) or from outside the app. The device
      // already enforces that host, so adopting only records the
      // truth; it changes no enforcement and needs no gate.
      if (dnsState != null && dnsState.isSpecifiedHost) {
        final live = DnsProtection.fromLiveHost(dnsState.hostname);
        if (dns == null || !dns.enabled || dns.hostname != live.hostname) {
          try {
            await widget.controller.config.setDnsProtection(live);
            if (mounted) {
              setState(() {
                _dns = live;
                _dnsIdController.text = live.nextDnsConfigId;
                _dnsCustomController.text = live.customHostname;
              });
            }
          } catch (_) {
            // Best-effort: the card still shows the live host below.
          }
        }
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

  /// Maps a DNS-apply failure to the message the user sees: the REAL
  /// reason, not a generic "failed". The native side surfaces the DPM
  /// result code as `verifiedState` (2 = HOST_NOT_SERVING, 1 =
  /// FAILURE); a timeout is its own message; anything else carries
  /// the numeric code so the failure is never anonymous.
  String _dnsFailureMessage(Object e, AppLocalizations l10n) {
    if (e is TimeoutException) return l10n.dnsApplyTimeout;
    if (e is PrivilegedException) {
      final code = e.details['verifiedState'];
      if (code == 2 || e.message.contains('result code 2')) {
        return l10n.dnsNotServing;
      }
      if (code is num) return l10n.dnsApplyFailedCode(code.toInt());
      return l10n.dnsApplyFailed;
    }
    return l10n.dnsApplyFailed;
  }

  /// True when the failure is the DPM "host not serving" result — the
  /// retryable one (the system often reports it for a while after
  /// provisioning, then the same host applies fine).
  bool _isHostNotServing(Object e) {
    if (e is PrivilegedException) {
      return e.details['verifiedState'] == 2 ||
          e.message.contains('result code 2');
    }
    return false;
  }

  /// One channel apply with automatic retry on HOST_NOT_SERVING: up to
  /// 4 attempts (delays 2s/5s/8s, 20s timeout each) — the "fails at
  /// first, works after a while" case from item 3. Disabling (reset
  /// to opportunistic) never retries: it sets no host, so the code
  /// cannot apply to it. Any other failure returns at once. Throws
  /// the last failure.
  Future<PrivateDnsState> _applyDnsWithRetry(DnsProtection next) async {
    if (!next.enabled) {
      return widget.controller.channel
          .resetPrivateDns()
          .timeout(const Duration(seconds: 20));
    }
    const delays = [
      Duration.zero,
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 8),
    ];
    Object? lastError;
    for (var i = 0; i < delays.length; i++) {
      if (i > 0) {
        if (mounted) setState(() => _dnsRetrying = true);
        await Future.delayed(delays[i]);
      }
      try {
        return await widget.controller.channel
            .setPrivateDns(next.hostname!)
            .timeout(const Duration(seconds: 20));
      } catch (e) {
        lastError = e;
        if (!_isHostNotServing(e)) rethrow;
      }
    }
    throw lastError!;
  }

  /// Applies a DNS-protection selection: the channel call runs FIRST
  /// and the preference is saved only after the verified native reply,
  /// so the saved flag can never claim a state the device is not in.
  /// Enabling is a tightening (direct); disabling is a loosening
  /// (recovery-gated, like unsuspending a browser).
  ///
  /// On failure the mapped reason is shown INLINE under the provider
  /// list (with a Retry button) instead of a one-shot error dialog —
  /// the dialog's generic message is what hid the cause in item 3.
  Future<void> _applyDns(DnsProtection next) async {
    if (_dnsBusy) return;
    if (next.enabled && !next.isValid) {
      if (mounted) {
        showInfoSnackBar(
          context,
          next.provider == DnsProvider.custom
              ? context.l10n.dnsInvalidHostname
              : context.l10n.dnsInvalidConfigId,
        );
      }
      return;
    }

    Future<void> apply() async {
      if (!mounted) return;
      _dnsPending = next;
      setState(() {
        _dnsBusy = true;
        _dnsError = null;
        _dnsRetrying = false;
      });
      try {
        final state = await _applyDnsWithRetry(next);
        await widget.controller.config.setDnsProtection(next);
        if (mounted) {
          setState(() {
            _dns = next;
            _dnsState = state;
            _dnsPending = null;
            _dnsError = null;
            _dnsRetrying = false;
          });
          showInfoSnackBar(
            context,
            next.enabled
                ? context.l10n.dnsApplied
                : context.l10n.dnsTurnedOff,
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _dnsError = _dnsFailureMessage(e, context.l10n);
            _dnsRetrying = false;
          });
        }
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

  /// Re-applies the selection the last apply attempted (the inline
  /// Retry button). Falls back to the current verified selection.
  Future<void> _retryDns() async {
    final pending = _dnsPending ?? _dns ?? const DnsProtection();
    await _applyDns(pending);
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

  /// Custom DNS hostname, applied on submit: while protection is on
  /// with Custom it re-applies at once; otherwise it only persists.
  /// An invalid hostname is refused (with the reason) so the saved
  /// selection can never name a hostname that does not exist.
  Future<void> _submitDnsCustomHost(String value) async {
    final current = _dns ?? const DnsProtection();
    final next = current.copyWith(customHostname: value.trim());
    if (next.enabled && next.provider == DnsProvider.custom) {
      await _applyDns(next);
    } else {
      await widget.controller.config.setDnsProtection(next);
      if (mounted) setState(() => _dns = next);
    }
  }

  /// The display name of a provider for the shortcut-card subtitle.
  String _dnsProviderName(DnsProvider provider, AppLocalizations l10n) =>
      switch (provider) {
        DnsProvider.nextdns => l10n.dnsProviderNextdns,
        DnsProvider.cleanBrowsing => l10n.dnsProviderCleanbrowsing,
        DnsProvider.cloudflare => l10n.dnsProviderCloudflare,
        DnsProvider.adguard => l10n.dnsProviderAdguard,
        DnsProvider.custom => l10n.dnsCustom,
      };

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
                // Batch G, item 6: the torrent card moved to the
                // Config tab (Settings) — torrent clients have
                // nothing to do with browsers.
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
                              ? '${l10n.dnsProtectionEnabled} — ${_dnsProviderName(_dns!.provider, l10n)}'
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
                          RadioListTile<DnsProvider>(
                            title: Text(l10n.dnsProviderCloudflare),
                            subtitle:
                                Text(l10n.dnsProviderCloudflareNote),
                            value: DnsProvider.cloudflare,
                          ),
                          RadioListTile<DnsProvider>(
                            title: Text(l10n.dnsProviderAdguard),
                            subtitle: Text(l10n.dnsProviderAdguardNote),
                            value: DnsProvider.adguard,
                          ),
                          RadioListTile<DnsProvider>(
                            title: Text(l10n.dnsCustom),
                            subtitle: Text(l10n.dnsProviderCustomNote),
                            value: DnsProvider.custom,
                          ),
                          if ((_dns?.provider ??
                                      DnsProvider.cleanBrowsing) ==
                                  DnsProvider.custom)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                0,
                                16,
                                8,
                              ),
                              child: TextField(
                                controller: _dnsCustomController,
                                decoration: InputDecoration(
                                  labelText: l10n.dnsHostnameLabel,
                                  hintText: l10n.dnsHostnameHint,
                                  helperText:
                                      _dnsCustomController.text.trim().isEmpty
                                      ? null
                                      : _dnsCustomController.text.trim(),
                                  errorText:
                                      _dnsCustomController.text.isNotEmpty &&
                                          !DnsProtection.isValidCustomHostname(
                                            _dnsCustomController.text.trim(),
                                          )
                                      ? l10n.dnsInvalidHostname
                                      : null,
                                ),
                                enabled: !_dnsBusy,
                                onChanged: (_) => setState(() {}),
                                onSubmitted: _submitDnsCustomHost,
                              ),
                            ),
                        ],
                      ),
                    ),
                    // The last apply's real failure reason, with a
                    // Retry button (the one-shot error dialog's generic
                    // message is what hid the cause in item 3).
                    if (_dnsRetrying)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(l10n.dnsRetrying),
                      ),
                    if (_dnsError != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                _dnsError!,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.error,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _dnsBusy ? null : _retryDns,
                              child: Text(l10n.dnsRetryApply),
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
