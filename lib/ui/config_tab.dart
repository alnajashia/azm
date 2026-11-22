/// Config tab: the hub mirroring the original `ConfigTab.kt` — Device
/// Owner status, Private DNS (F7), links to every sub-screen, language
/// (F33), theme, recovery-code change, and Device Owner removal (F2:
/// in-session immediate removal, or the 48-hour forced removal).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/dns_protection.dart';
import '../data/privileged_channel.dart';
import '../domain/colour_modes.dart';
import '../domain/internet_block.dart';
import '../l10n/l10n.dart';
import '../theme.dart';
import 'activity_blocker_screen.dart';
import 'colour_modes_screen.dart';
import 'common.dart';
import 'config_screens.dart';
import 'entry_password_ui.dart';
import 'impulse_focus_screens.dart';
import 'internet_block_screen.dart';
import 'recovery_ui.dart';
import 'seal_rules_screen.dart';
import 'visual_blocking_screen.dart';

class ConfigTab extends StatefulWidget {
  const ConfigTab({super.key, required this.controller});
  final AppController controller;
  @override
  State<ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends State<ConfigTab> {
  bool? _isOwner;
  bool? _isAdmin;
  PrivateDnsState? _dns;

  /// The persisted DNS-protection selection (moved back to Settings,
  /// 2026-11-14): the dialog edits this; the live [_dns] above is
  /// what the device actually enforces.
  DnsProtection? _dnsProtection;
  Object? _error;
  Timer? _ticker;

  /// Colour-modes live status for the tile subtitle (Batch C); null
  /// while loading or when the probe fails — the tile then falls back
  /// to the static note.
  ColourModesStatus? _colourModesStatus;

  /// Leftover restriction keys detected while NOT owner (residue
  /// probe in [_load]); empty when none were found.
  List<String> _residue = const [];

  /// The item-6 Settings switch: whether suspending an app also blocks
  /// its uninstall. Null while the flag is loading.
  bool? _autoBlockUninstall;

  /// True while a toggle apply is in flight (the switch is disabled).
  bool _autoBlockBusy = false;

  // Batch G, item 6: the torrent-block card moved here from the
  // browser-restrictions screen — torrent clients have nothing to
  // do with browsers. Same state, same native flag, same gates.
  List<({String packageName, String label})>? _torrentApps;
  bool? _blockTorrents;
  bool _torrentBusy = false;

  AppController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onControllerChanged);
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(ConfigTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onControllerChanged);
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final owner = await _c.channel.isDeviceOwner();
      PrivateDnsState? dns;
      DnsProtection? dnsProtection;
      var residue = const <String>[];
      if (owner.isDeviceOwner) {
        try {
          dns = await _c.channel.getPrivateDns();
        } catch (_) {
          dns = null;
        }
        // DNS (moved back to Settings, 2026-11-14): the persisted
        // selection, adopting the LIVE host when the saved prefs
        // disagree with the device — a host set from outside the
        // app (or by the retired dialog, which never persisted).
        // The device already enforces that host, so adopting only
        // records the truth; it changes no enforcement.
        try {
          dnsProtection = await _c.config.getDnsProtection();
        } catch (_) {
          dnsProtection = null;
        }
        if (dns != null && dns.isSpecifiedHost) {
          final live = DnsProtection.fromLiveHost(dns.hostname);
          // Never adopt over a VPN-mode selection: while an external
          // VPN is up Azm itself may have applied that very host
          // (ExternalVpnWatcher), and adopting would wipe viaVpn.
          if (dnsProtection == null ||
              (!dnsProtection.viaVpn &&
                  (!dnsProtection.enabled ||
                      dnsProtection.hostname != live.hostname))) {
            try {
              await _c.config.setDnsProtection(live);
              dnsProtection = live;
            } catch (_) {
              // Best-effort: the tile still shows the live host.
            }
          }
        }
      } else {
        // Not owner: probe for leftover restrictions from an earlier
        // removal (field-failure follow-up). The probe needs no admin
        // rights; a failed probe simply shows no warning.
        try {
          residue = await _c.channel.getUserRestrictionResidue();
        } catch (_) {
          residue = const <String>[];
        }
      }
      if (mounted) {
        setState(() {
          _isOwner = owner.isDeviceOwner;
          _isAdmin = owner.isAdminActive;
          _dns = dns;
          _dnsProtection = dnsProtection;
          _residue = residue;
        });
      }
      // Colour-modes tile subtitle (Batch C): best-effort probe; a
      // failed probe simply leaves the static note in place.
      try {
        final colourStatus = await _c.channel.getColourModesStatus();
        if (mounted) setState(() => _colourModesStatus = colourStatus);
      } catch (_) {
        // Leave the previous (or null) status; the tile falls back.
      }
      // Item-6 Settings switch (Batch F): best-effort; a failed probe
      // leaves the switch disabled (null) rather than guessing.
      try {
        final autoBlock = await _c.channel.isAutoBlockUninstallSuspended();
        if (mounted) setState(() => _autoBlockUninstall = autoBlock);
      } catch (_) {
        // Leave null; the switch stays disabled.
      }
      // Batch G, item 6: detected torrent clients + the native flag.
      // Best-effort, like the probes above.
      try {
        final torrentApps = await _c.channel.getTorrentApps();
        if (mounted) setState(() => _torrentApps = torrentApps);
      } catch (_) {}
      try {
        final blockTorrents = await _c.channel.isBlockTorrentsEnabled();
        if (mounted) setState(() => _blockTorrents = blockTorrents);
      } catch (_) {}
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  /// DNS selection dialog (moved back to Settings, 2026-11-14 — the
  /// browser-restrictions card is gone; this dialog is the ONE DNS
  /// place). Since 2026-11-22 it carries the "DNS via VPN" switch:
  /// switch on shows the provider list (CleanBrowsing, Cloudflare,
  /// AdGuard, Custom) and the chosen provider activates
  /// automatically whenever a VPN is on — Azm's own VPN filters over
  /// DoH with it, and while an external VPN is up Azm applies the
  /// same provider as system Private DNS (native
  /// `ExternalVpnWatcher`). Switch off hides the list and stops any
  /// running VPN DNS filtering (recovery-gated, like every
  /// deactivation). The dialog no longer applies system Private DNS
  /// directly — on the user's network port 853 is blocked, so that
  /// path could never activate; the VPN paths are the working ones.
  Future<void> _editDns() async {
    InternetBlockConfig internetBlock;
    try {
      internetBlock = await _c.channel.getInternetBlockConfig();
    } catch (_) {
      internetBlock = const InternetBlockConfig();
    }
    if (!mounted) return;
    final applied = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DnsDialog(
        current: _dnsProtection ?? const DnsProtection(),
        internetBlock: internetBlock,
        liveHostname: _dns?.hostname,
        onApply: _applyDns,
      ),
    );
    if (applied == true && mounted) {
      final dns = _dnsProtection;
      showInfoSnackBar(
        context,
        dns != null && dns.viaVpn
            ? context.l10n.dnsViaVpnSavedMsg
            : context.l10n.dnsTurnedOff,
      );
    }
  }

  /// Applies a DNS selection from the dialog: returns (applied,
  /// error). A null error with applied == false means the recovery
  /// gate was cancelled and the dialog simply stays open.
  ///
  /// The internet-block config is written FIRST (the VPN provider +
  /// the external-VPN auto host), then the dialog's own selection —
  /// if the channel write fails, nothing is saved and the dialog
  /// shows the failure. Turning the VPN switch off is a loosening
  /// (recovery-gated) and, when Azm's VPN is filtering DNS right
  /// now, stops it immediately (user request 2026-11-22); a block
  /// level keeps running — only the DNS part turns off.
  Future<({bool applied, String? error})> _applyDns(
    DnsProtection next,
  ) async {
    // Captured before the awaits below (the dialog outlives them).
    final l10n = context.l10n;

    Future<({bool applied, String? error})> doApply() async {
      try {
        final ib = await _c.channel.getInternetBlockConfig();
        final turningOff = (_dnsProtection?.viaVpn ?? false) && !next.viaVpn;
        var nextIb = ib.copyWith(
          dohProvider: dohProviderFor(next.provider),
          customDohUrl: next.customDohUrl,
          dnsAutoHost: next.viaVpn ? (next.hostname ?? '') : '',
        );
        if (turningOff &&
            ib.enabled &&
            ib.level == InternetBlockLevel.off) {
          // DNS filtering is running through Azm's VPN right now:
          // the switch-off stops it immediately.
          nextIb = nextIb.copyWith(enabled: false);
        }
        await _c.channel.setInternetBlockConfig(nextIb);
        await _c.config.setDnsProtection(next);
        if (mounted) {
          setState(() => _dnsProtection = next);
        }
        return (applied: true, error: null);
      } catch (_) {
        return (applied: false, error: l10n.dnsApplyFailed);
      }
    }

    if ((_dnsProtection?.viaVpn ?? false) && !next.viaVpn) {
      ({bool applied, String? error}) result = (applied: false, error: null);
      final ok = await runLoosening(context, _c, () async {
        result = await doApply();
      });
      return ok ? result : (applied: false, error: null);
    }
    return doApply();
  }
  /// Live subtitle for the colour-modes tile (Batch C): what is
  /// actually applied right now, or the static note while loading.
  String _colourModesSubtitle(AppLocalizations l10n) {
    final status = _colourModesStatus;
    if (status == null) return l10n.colourModesNote;
    if (!status.enabled) return l10n.colourModesSummaryOff;
    if (status.appliedModes.isEmpty) return l10n.colourModesSummaryIdle;
    final names = status.appliedModes
        .map(
          (m) => switch (m) {
            ColourMode.grayscale => l10n.colourModeGrayscale,
            ColourMode.nightLight => l10n.colourModeNightLight,
            ColourMode.extraDim => l10n.colourModeExtraDim,
            ColourMode.inversion => l10n.colourModeInversion,
          },
        )
        .join(', ');
    return l10n.colourModesSummaryActive(names);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final forced = _c.forcedRemoval;
    // Due by EITHER leg: the accumulated ticks OR both clocks
    // having advanced a full delay since filing (item 6 — the
    // controller keeps this flag live at startup and on each tick).
    final forcedDue = forced.isComplete || _c.forcedRemovalDue;
    // v1.0.5 UX (user directive): every group of controls sits in a
    // titled card, following the Status tab's grouped pattern — no
    // flat ungrouped lists. Grouping is presentation only: same
    // controls, same order, same handlers, same gates.
    return ListView(
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
        if (_isOwner == false && _residue.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SectionCard(
              title: l10n.residueTitle,
              children: [
                ListTile(
                  leading: const Icon(Icons.warning_amber_outlined),
                  title: Text(l10n.residueBody),
                  subtitle: Text(_residue.join(', ')),
                ),
              ],
            ),
          ),
        SectionCard(
          title: l10n.generalSettings,
          children: [
            ListTile(
              leading: Icon(
                _isOwner == true ? Icons.verified_user_outlined : Icons.shield_outlined,
              ),
              title: Text(l10n.setupAndOwner),
              subtitle: Text(
                _isOwner == null
                    ? l10n.checking
                    : _isOwner!
                    ? l10n.provisionedAsOwner
                    : l10n.notOwnerOpenSetup,
              ),
              trailing: const Icon(Icons.navigate_next_outlined),
              onTap: () => _c.requestTab(AppController.tabStatus),
            ),
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(l10n.privateDns),
              subtitle: Text(
                _dns == null
                    ? (_isOwner == true
                          ? l10n.dnsCouldNotRead
                          : l10n.dnsRequiresOwner)
                    : _dns!.isSpecifiedHost
                    ? l10n.dnsForcedHost(_dns!.hostname ?? '')
                    : l10n.dnsMode(_dns!.mode),
              ),
              trailing: const Icon(Icons.navigate_next_outlined),
              // DNS (moved back to Settings, 2026-11-14): the tile
              // opens the DNS dialog — the browser-restrictions
              // screen's DNS card is gone; this is the ONE DNS place.
              onTap: _isOwner == true
                  ? _editDns
                  : () => showInfoSnackBar(context, l10n.dnsNeedsOwnerMsg),
            ),
            ListTile(
              leading: const Icon(Icons.vpn_lock_outlined),
              title: Text(l10n.internetBlockTitle),
              subtitle: Text(l10n.internetBlockSub),
              trailing: const Icon(Icons.navigate_next_outlined),
              onTap: () => _push(InternetBlockScreen(controller: _c)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: l10n.protectionTools,
          children: [
            ListTile(
              leading: const Icon(Icons.language_outlined),
              title: Text(l10n.browserRestrictions),
              subtitle: Text(l10n.browserRestrictionsSub),
              trailing: const Icon(Icons.navigate_next_outlined),
              onTap: () => _push(BrowserRestrictionsScreen(controller: _c)),
            ),
            ListTile(
              leading: const Icon(Icons.text_fields_outlined),
              title: Text(l10n.blockedWords),
              subtitle: Text(l10n.blockedWordsSub),
              trailing: const Icon(Icons.navigate_next_outlined),
              onTap: () => _push(BlockedWordsScreen(controller: _c)),
            ),
            ListTile(
              leading: const Icon(Icons.image_search_outlined),
              title: Text(l10n.visualBlockingTitle),
              subtitle: Text(l10n.visualBlockingSub),
              trailing: const Icon(Icons.navigate_next_outlined),
              onTap: () => _push(VisualBlockingScreen(controller: _c)),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outlined),
              title: Text(l10n.sealRulesTitle),
              subtitle: Text(l10n.sealRulesSub),
              trailing: const Icon(Icons.navigate_next_outlined),
              onTap: () => _push(SealRulesScreen(controller: _c)),
            ),
            ListTile(
              leading: const Icon(Icons.emergency_outlined),
              title: Text(l10n.impulseLockTitle),
              subtitle: Text(l10n.impulseLockSub),
              trailing: const Icon(Icons.navigate_next_outlined),
              onTap: () => _push(ImpulseLockScreen(controller: _c)),
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text(l10n.focusMode),
              subtitle: Text(l10n.focusModeSub),
              trailing: const Icon(Icons.navigate_next_outlined),
              onTap: () => _push(FocusModeScreen(controller: _c)),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: Text(l10n.usageWarnings),
              subtitle: Text(l10n.usageWarningsSub),
              trailing: const Icon(Icons.navigate_next_outlined),
              onTap: () => _push(UsageWarningsScreen(controller: _c)),
            ),
            ListTile(
              leading: const Icon(Icons.history_outlined),
              title: Text(l10n.suspensionLogs),
              subtitle: Text(l10n.suspensionLogsSub),
              trailing: const Icon(Icons.navigate_next_outlined),
              onTap: () => _push(SuspensionLogsScreen(controller: _c)),
            ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: Text(l10n.colourModes),
              subtitle: Text(_colourModesSubtitle(l10n)),
              trailing: const Icon(Icons.navigate_next_outlined),
              onTap: () => _push(ColourModesScreen(controller: _c)),
            ),
            ListTile(
              leading: const Icon(Icons.directions_run_outlined),
              title: Text(l10n.activityBlocker),
              subtitle: Text(l10n.activityBlockerNote),
              trailing: const Icon(Icons.navigate_next_outlined),
              onTap: () => _push(ActivityBlockerScreen(controller: _c)),
            ),
            // Batch F, item 6 — the second, distinct feature: a
            // Settings switch that blocks uninstalling suspended or
            // blocked apps. Turning it ON is tightening (direct);
            // turning it OFF is loosening (recovery-gated). Disabled
            // while loading or while Azm is not the Device Owner
            // (the native setter requires owner rights).
            SwitchListTile(
              secondary: const Icon(Icons.block_outlined),
              title: Text(l10n.autoBlockUninstallTitle),
              subtitle: Text(l10n.autoBlockUninstallSub),
              value: _autoBlockUninstall ?? false,
              onChanged:
                  _autoBlockBusy ||
                          _autoBlockUninstall == null ||
                          _isOwner != true
                      ? null
                      : _toggleAutoBlockUninstall,
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Batch G, item 6: the torrent-block card is a separate card
        // in Settings — torrent clients have nothing to do with
        // browsers, so it no longer lives in the browser-restrictions
        // screen. Same switch, same gates, same native flag.
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
                  leading: const Icon(Icons.file_download_outlined),
                  title: Text(a.label),
                  subtitle: Text(a.packageName),
                ),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: l10n.preferencesSection,
          children: [
            ListTile(
              leading: const Icon(Icons.translate_outlined),
              title: Text(l10n.language),
              subtitle: Text(
                _c.language == 'ar'
                    ? l10n.languageArabic
                    : l10n.languageEnglish,
              ),
              trailing: const Icon(Icons.navigate_next_outlined),
              onTap: _pickLanguage,
            ),
            ListTile(
              leading: const Icon(Icons.brightness_6_outlined),
              title: Text(l10n.theme),
              subtitle: Text(switch (_c.themeMode) {
                ThemeMode.system => l10n.themeSystem,
                ThemeMode.light => l10n.themeLight,
                ThemeMode.dark => l10n.themeDark,
              }),
              trailing: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_outlined),
                  ),
                ],
                selected: {_c.themeMode},
                onSelectionChanged: (s) => _c.setThemeMode(s.first),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.password_outlined),
              title: Text(l10n.changeRecoveryCode),
              subtitle: Text(l10n.changeRecoveryCodeSub),
              trailing: const Icon(Icons.navigate_next_outlined),
              onTap: () async {
                if (!await ensureRecoverySession(context, _c)) return;
                if (!mounted) return;
                _push(
                  Scaffold(
                    appBar: AppBar(title: Text(l10n.changeRecoveryCode)),
                    body: RecoveryWizard(
                      controller: _c,
                      isRegeneration: true,
                      onDone: () {
                        Navigator.of(context).pop();
                        showInfoSnackBar(context, l10n.recoveryCodeChanged);
                      },
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        // App entry (v1.0.4): the optional entry password section —
        // header, plain-language explanation, status and the gated
        // set/change/remove actions live in entry_password_ui.dart.
        // It renders as its own titled card since v1.0.5.
        AppEntrySection(controller: _c),
        const SizedBox(height: 12),
        // Danger zone: removal actions in their own titled card,
        // labelled plainly, each with its one-line explanation.
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  l10n.dangerZone,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.remove_moderator_outlined),
                title: Text(
                  l10n.removeOwnerNow,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(l10n.removeOwnerNowSub),
                // User request 2026-11-19: the tile must read as a
                // tappable action, not a label.
                trailing: const Icon(Icons.navigate_next_outlined),
                onTap: ((_isOwner == true || _isAdmin == true) && !_c.isRemovingDeviceOwner)
                    ? _onRemoveOwnerTapped
                    : null,
              ),
              // In-app self-uninstall (manual-uninstall wedge fix):
              // shown only once the app is known not to be the
              // Device Owner — the system refuses while the owner
              // is active. The Settings uninstall wedged
              // system_server; this route performs the in-app
              // teardown first, which disarms the lockdown.
              if (_isOwner == false)
                ListTile(
                  leading: const Icon(Icons.delete_outline_outlined),
                  title: Text(l10n.uninstallAzm),
                  subtitle: Text(l10n.uninstallAzmSub),
                  trailing: const Icon(Icons.navigate_next_outlined),
                  onTap: _c.isRemovingDeviceOwner ? null : _onUninstallTapped,
                ),
              ListTile(
                leading: const Icon(Icons.hourglass_bottom_outlined),
                title: Text(l10n.forcedRemovalTitle),
                subtitle: Text(
                  !forced.active
                      ? l10n.forcedIdleSub
                      : forcedDue
                      ? l10n.forcedCompleteSub
                      : l10n.forcedInProgressSub(
                          formatDuration(forced.remaining, l10n),
                        ),
                ),
              ),
              if (forced.active)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: LinearProgressIndicator(value: forced.progress),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Wrap(
                  spacing: 8,
                  children: [
                    if (!forced.active)
                      OutlinedButton(
                        onPressed: _c.isRemovingDeviceOwner
                            ? null
                            : _confirmStartForcedRemoval,
                        child: Text(l10n.startForcedRemoval),
                      ),
                    if (forced.active && !forcedDue)
                      OutlinedButton(
                        onPressed: _c.isRemovingDeviceOwner
                            ? null
                            : _confirmCancelForcedRemoval,
                        child: Text(l10n.cancelForcedRemoval),
                      ),
                    if (forcedDue)
                      FilledButton(
                        onPressed: _c.isRemovingDeviceOwner
                            ? null
                            : _finishForcedRemoval,
                        child: Text(l10n.finishRemoval),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// In-app self-uninstall: opens the system uninstaller for Azm
  /// itself, after a plain confirmation card. The system always
  /// shows its own confirmation dialog, and refuses while Device
  /// Owner is still active — the tile is only shown when the app
  /// is not the owner. A failed intent start (nothing could open
  /// the uninstaller) is reported with an error card, not
  /// swallowed; the Settings path remains as a fallback.
  Future<void> _onUninstallTapped() async {
    final l10n = context.l10n;
    final proceed = await showDestructiveConfirmDialog(
      context,
      title: l10n.uninstallAzmConfirmTitle,
      message: l10n.uninstallAzmConfirmBody,
      confirmText: l10n.uninstallAzm,
      icon: Icons.delete_outline_outlined,
    );
    if (!proceed || !mounted) return;
    try {
      final result = await _c.channel.requestSelfUninstall();
      if (!result.started && mounted) {
        await showErrorCard(
          context,
          PrivilegedException(
            result.reason == 'stillOwner'
                ? 'UNINSTALL_STILL_OWNER'
                : 'UNINSTALL_NOT_STARTED',
            '',
          ),
        );
      }
    } catch (e) {
      if (mounted) await showErrorCard(context, e);
    }
  }

  /// High-warning centred confirmation card before immediate owner removal
  /// (Batch B / Audit Item 8). Lists consequences, requires explicit checkbox,
  /// and only then proceeds to the recovery gate and Batch D teardown flow.
  Future<bool> _confirmRemoveDeviceOwner() async {
    var understood = false;
    final l10n = context.l10n;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: dark ? const Color(0xFF17171A) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AzmRadius.large),
          ),
          icon: const Icon(
            Icons.warning_amber_outlined,
            color: AzmColors.red,
            size: 44,
          ),
          title: Text(
            l10n.removeOwnerConfirmTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: dark ? Colors.white : const Color(0xFF0B0B0C),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _consequenceRow(l10n.removeOwnerConsequenceRestrictions, dark),
              const SizedBox(height: 8),
              _consequenceRow(l10n.removeOwnerConsequenceDns, dark),
              const SizedBox(height: 8),
              _consequenceRow(l10n.removeOwnerConsequenceUninstall, dark),
              const SizedBox(height: 16),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  l10n.removeOwnerUnderstandCheckbox,
                  style: TextStyle(
                    color: dark ? Colors.white : const Color(0xFF0B0B0C),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                value: understood,
                onChanged: (v) => setDialogState(() => understood = v ?? false),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AzmColors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: understood
                  ? () => Navigator.of(dialogContext).pop(true)
                  : null,
              child: Text(l10n.removeOwnerConfirmButton),
            ),
          ],
        ),
      ),
    );
    return result ?? false;
  }

  static Widget _consequenceRow(String text, bool dark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, right: 8, left: 8),
          child: Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AzmColors.red,
            ),
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: dark ? Colors.white70 : const Color(0xFF2B2B2C),
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _onRemoveOwnerTapped() async {
    final confirmed = await _confirmRemoveDeviceOwner();
    if (!confirmed || !mounted) return;
    // User request 2026-11-19: removing the Device Owner always asks
    // for a FRESH recovery-code entry, even inside an active
    // recovery session — the most destructive action in the app
    // never rides on an earlier code entry.
    await runLoosening(context, _c, () async {
      await executeDeviceOwnerRemovalFlow(
        context: context,
        controller: _c,
        onRemovalSuccess: () {
          if (mounted) {
            setState(() {
              _isOwner = false;
              _isAdmin = false;
            });
          }
        },
      );
    }, forceFreshCode: true);
  }

  /// The item-6 Settings switch (Batch F). Turning it ON is tightening
  /// (direct): the native side blocks uninstall for every
  /// currently-suspended app and arms the coupling for future
  /// suspensions. Turning it OFF is loosening (recovery-gated): the
  /// native side releases exactly the AUTO-applied blocks, never a
  /// manual one.
  Future<void> _toggleAutoBlockUninstall(bool enabled) async {
    Future<void> apply() async {
      setState(() => _autoBlockBusy = true);
      try {
        final verified = await _c.channel.setAutoBlockUninstallSuspended(
          enabled,
        );
        if (mounted) {
          setState(() => _autoBlockUninstall = verified);
          showInfoSnackBar(
            context,
            verified
                ? context.l10n.autoBlockUninstallOn
                : context.l10n.autoBlockUninstallOff,
          );
        }
      } finally {
        if (mounted) setState(() => _autoBlockBusy = false);
      }
    }

    if (enabled) {
      try {
        await apply();
      } catch (e) {
        if (mounted) await showErrorCard(context, e);
      }
    } else {
      await runLoosening(context, _c, apply);
    }
  }

  /// The torrent switch (Batch F, item 4; moved here in Batch G,
  /// item 6 — same logic, new home). Enabling is a tightening
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
        final verified = await _c.channel.setBlockTorrents(enabled);
        final apps = _torrentApps ?? const [];
        if (verified) {
          final suspended = <String>{};
          if (apps.isNotEmpty) {
            final results = await _c.channel.setAppSuspended(
              apps.map((a) => a.packageName).toList(),
              true,
              reason: 'TORRENT_APP',
            );
            suspended.addAll(
              results.where((r) => r.isSuspended).map((r) => r.packageName),
            );
          }
          await _c.config.setTorrentBlockedPackages(suspended);
          if (mounted) {
            setState(() => _blockTorrents = true);
            showInfoSnackBar(
              context,
              context.l10n.torrentBlockedMsg(suspended.length),
            );
          }
        } else {
          final blocked = await _c.config.getTorrentBlockedPackages();
          if (blocked.isNotEmpty) {
            await _c.channel.setAppSuspended(blocked.toList(), false);
          }
          await _c.config.setTorrentBlockedPackages(const {});
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
      await runLoosening(context, _c, apply);
    }
  }

  /// Start dialog (`ConfigTab.kt`, `showStartForcedRemovalDialog`):
  /// explanatory text + explicit Confirm before the countdown begins.
  Future<void> _confirmStartForcedRemoval() async {
    final forced = _c.forcedRemoval;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.startForcedTitle),
        content: Text(dialogContext.l10n.startForcedBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.l10n.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // One instant, persisted and mirrored — the previous code called
    // `forced.start()` twice and stored two different start times.
    // Item 6: stamp the elapsed-realtime clock too, so the countdown
    // stays due-able even if the app is killed (the 30 s tick stalls
    // with the process; the clocks do not). A missing channel method
    // leaves the elapsed stamp null — accumulation-only, as before.
    Duration? elapsed;
    try {
      elapsed = await _c.channel.getElapsedRealtimeMs();
    } catch (_) {
      elapsed = null;
    }
    final started = forced.start(atElapsed: elapsed);
    try {
      await _c.config.setForcedRemoval(started);
    } catch (e) {
      // Batch C (C4): filing the delayed forced removal is NEVER
      // seal-refused any more — the seal exemption lives natively.
      // Any error here is a genuine failure, shown as-is.
      if (mounted) await showErrorCard(context, e);
      return;
    }
    _c.forcedRemoval = started;
    if (mounted) setState(() {});
  }

  /// Cancel dialog (`ConfigTab.kt`, `showCancelForcedRemovalDialog`).
  Future<void> _confirmCancelForcedRemoval() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.cancelForcedTitle),
        content: Text(dialogContext.l10n.cancelForcedBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.l10n.close),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.l10n.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _cancelForcedRemoval();
  }

  Future<void> _cancelForcedRemoval() async {
    final cancelled = _c.forcedRemoval.cancel();
    await _c.config.setForcedRemoval(cancelled);
    _c.forcedRemoval = cancelled;
    if (mounted) setState(() {});
  }

  /// Finish dialog (`ConfigTab.kt`, `showFinishForcedRemovalDialog`):
  /// the Confirm button stays disabled until the mandatory confirmation
  /// checkbox is ticked. As in the original, the dialog's dismiss action
  /// cancels the forced removal itself.
  Future<void> _finishForcedRemoval() async {
    var confirmed = false;
    final outcome = await showDialog<String>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(context.l10n.finishForcedTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.finishForcedBody),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(context.l10n.understandRemovesAll),
                value: confirmed,
                onChanged: (v) => setLocal(() => confirmed = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel-removal'),
              child: Text(context.l10n.cancelForcedRemoval),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.close),
            ),
            FilledButton(
              onPressed: confirmed && !_c.isRemovingDeviceOwner
                  ? () => Navigator.pop(context, 'remove')
                  : null,
              child: Text(context.l10n.removeDeviceOwnerAction),
            ),
          ],
        ),
      ),
    );
    if (outcome == 'cancel-removal') {
      await _cancelForcedRemoval();
      return;
    }
    if (outcome != 'remove' || !mounted) return;
    try {
      await executeDeviceOwnerRemovalFlow(
        context: context,
        controller: _c,
        isForcedRemoval: true,
        onRemovalSuccess: () async {
          await _cancelForcedRemoval();
          if (mounted) {
            setState(() {
              _isOwner = false;
              _isAdmin = false;
            });
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      await showErrorCard(context, e);
    }
  }

  /// Language picker (v1.0.4, amendment A): Arabic + English only —
  /// the two fully-localized UI languages. The choice persists in the
  /// config store and applies app-wide immediately (MaterialApp locale).
  Future<void> _pickLanguage() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(dialogContext.l10n.languageDialogTitle),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'en'),
            child: Text(dialogContext.l10n.languageEnglish),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'ar'),
            child: Text(dialogContext.l10n.languageArabic),
          ),
        ],
      ),
    );
    if (choice != null) {
      await _c.setLanguage(choice);
      if (mounted) {
        showInfoSnackBar(context, context.l10n.languageSaved);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Post-confirmation loading and verification for Device Owner removal
// (Batch D Addendum)
// ---------------------------------------------------------------------------

/// The shared post-confirmation loading and verification flow for Device Owner removal
/// (Batch D Addendum).
///
/// Used by both the danger-zone "Remove Device Owner now" tile and the forced-removal dialog.
/// Displays a modal, non-dismissible loading dialog, starts native teardown, and polls
/// lightweight verification every [pollInterval] until verified (with a minimum display of
/// [minDisplayDuration] ~10s and maximum of [maxDisplayDuration] ~20s).
///
/// Once loading dismisses, it presents the outcome dialog with the honest status and
/// warnings/re-check if timeout occurred.
Future<void> executeDeviceOwnerRemovalFlow({
  required BuildContext context,
  required AppController controller,
  bool isForcedRemoval = false,
  Duration minDisplayDuration = const Duration(seconds: 10),
  // 45 s (was 20 s): the native teardown is bounded by construction
  // at ~25–30 s on a several-hundred-app device (deadlock re-audit
  // fix E), so the display cap must not stop polling while a
  // legitimate teardown is still running.
  Duration maxDisplayDuration = const Duration(seconds: 45),
  Duration pollInterval = const Duration(seconds: 1),
  VoidCallback? onRemovalSuccess,
}) async {
  if (controller.isRemovingDeviceOwner) return;
  controller.isRemovingDeviceOwner = true;

  final l10n = context.l10n;

  // Pre-flight (deadlock re-audit fix D): if colour modes are currently
  // enforced but the WRITE_SECURE_SETTINGS grant is gone (Shizuku
  // stopped), the colour step could not restore the device keys — and
  // the user would discover that only after the owner is already gone.
  // Warn first; continuing anyway is the user's explicit choice.
  // Both probes fail open (a probe error never blocks the removal).
  final colourEnforced = await controller.channel
      .hasEnforcedColourModes()
      .catchError((_) => false);
  final secureSettingsGranted = await controller.channel
      .isWriteSecureSettingsGranted()
      .catchError((_) => true);
  if (colourEnforced && !secureSettingsGranted) {
    if (!context.mounted) {
      controller.isRemovingDeviceOwner = false;
      return;
    }
    final proceed = await showDestructiveConfirmDialog(
      context,
      title: l10n.removalColourPreflightTitle,
      message: l10n.removalColourPreflightBody,
      confirmText: l10n.removalColourPreflightContinue,
      icon: Icons.palette_outlined,
    );
    if (!context.mounted) {
      controller.isRemovingDeviceOwner = false;
      return;
    }
    if (!proceed) {
      controller.isRemovingDeviceOwner = false;
      return;
    }
  }
  if (!context.mounted) {
    controller.isRemovingDeviceOwner = false;
    return;
  }

  BuildContext? dialogCtx;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (dContext) {
      dialogCtx = dContext;
      return PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AzmColors.red),
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.removalLoadingTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.removalLoadingBody,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  DeviceOwnerRemovalResult? removalResult;
  Object? removalError;

  final removalFuture = controller.channel.removeDeviceOwner().then(
    (res) => removalResult = res,
    onError: (Object err) => removalError = err,
  );

  final completer = Completer<void>();
  var elapsed = Duration.zero;
  RemovalVerificationResult? lastVerification;
  bool isPolling = false;

  Timer? timer;
  try {
    timer = Timer.periodic(pollInterval, (t) async {
      elapsed += pollInterval;
      if (removalError != null) {
        t.cancel();
        if (!completer.isCompleted) completer.complete();
        return;
      }
      if (elapsed >= maxDisplayDuration) {
        t.cancel();
        if (!completer.isCompleted) completer.complete();
        return;
      }
      if (!isPolling) {
        isPolling = true;
        try {
          lastVerification = await controller.channel.verifyRemovalComplete();
        } catch (_) {}
        isPolling = false;
        if (lastVerification?.verified == true &&
            elapsed >= minDisplayDuration) {
          t.cancel();
          if (!completer.isCompleted) completer.complete();
        }
      }
    });

    await completer.future;
  } finally {
    timer?.cancel();
  }

  try {
    await removalFuture;
  } catch (_) {}

  // Dismiss the loading dialog. Prefer the builder-assigned context;
  // fall back to the root navigator when the builder has not run yet
  // (the teardown can finish before the next frame builds the dialog
  // — e.g. in tests — and the dialog would otherwise stay up forever
  // with its spinner spinning). The loading dialog is the top route
  // of the root navigator here: nothing else is pushed between
  // showDialog above and this pop.
  if (dialogCtx != null && dialogCtx!.mounted) {
    Navigator.of(dialogCtx!).pop();
  } else if (context.mounted) {
    Navigator.of(context, rootNavigator: true).pop();
  }

  controller.isRemovingDeviceOwner = false;

  if (!context.mounted) return;

  if (removalError != null) {
    await showErrorCard(context, removalError!);
    return;
  }

  if (lastVerification?.verified != true) {
    try {
      lastVerification = await controller.channel.verifyRemovalComplete();
    } catch (_) {}
    if (!context.mounted) return;
  }

  final isVerified = lastVerification?.verified == true;
  if (isVerified) {
    onRemovalSuccess?.call();
    showRemovalOutcomeDialog(
      context,
      result: removalResult,
      verification: lastVerification,
      isTimeout: false,
      onUninstall: () async { await controller.channel.requestSelfUninstall(); },
    );
  } else {
    showRemovalOutcomeDialog(
      context,
      result: removalResult,
      verification: lastVerification,
      isTimeout: true,
      onUninstall: () async { await controller.channel.requestSelfUninstall(); },
      onRecheck: () => runRemovalRecheckFlow(
        context: context,
        controller: controller,
        priorResult: removalResult,
        maxDisplayDuration: maxDisplayDuration,
        pollInterval: pollInterval,
        onRemovalSuccess: onRemovalSuccess,
      ),
    );
  }
}

/// The re-check flow when the user taps "Re-check status" from the outcome dialog.
Future<void> runRemovalRecheckFlow({
  required BuildContext context,
  required AppController controller,
  DeviceOwnerRemovalResult? priorResult,
  Duration maxDisplayDuration = const Duration(seconds: 45),
  Duration pollInterval = const Duration(seconds: 1),
  VoidCallback? onRemovalSuccess,
}) async {
  if (controller.isRemovingDeviceOwner) return;
  controller.isRemovingDeviceOwner = true;

  final l10n = context.l10n;
  BuildContext? dialogCtx;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (dContext) {
      dialogCtx = dContext;
      return PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AzmColors.red),
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.removalLoadingTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.removalLoadingBody,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  final completer = Completer<void>();
  var elapsed = Duration.zero;
  RemovalVerificationResult? lastVerification;
  bool isPolling = false;

  Timer? timer;
  try {
    timer = Timer.periodic(pollInterval, (t) async {
      elapsed += pollInterval;
      if (elapsed >= maxDisplayDuration) {
        t.cancel();
        if (!completer.isCompleted) completer.complete();
        return;
      }
      if (!isPolling) {
        isPolling = true;
        try {
          lastVerification = await controller.channel.verifyRemovalComplete();
        } catch (_) {}
        isPolling = false;
        if (lastVerification?.verified == true) {
          t.cancel();
          if (!completer.isCompleted) completer.complete();
        }
      }
    });

    await completer.future;
  } finally {
    timer?.cancel();
  }

  // Dismiss the loading dialog (same race note as the main flow:
  // the builder may not have run yet when the re-check finishes fast,
  // so fall back to the root navigator when the builder context is
  // not available).
  if (dialogCtx != null && dialogCtx!.mounted) {
    Navigator.of(dialogCtx!).pop();
  } else if (context.mounted) {
    Navigator.of(context, rootNavigator: true).pop();
  }

  controller.isRemovingDeviceOwner = false;

  if (!context.mounted) return;

  if (lastVerification?.verified != true) {
    try {
      lastVerification = await controller.channel.verifyRemovalComplete();
    } catch (_) {}
    if (!context.mounted) return;
  }

  if (lastVerification?.verified == true) {
    onRemovalSuccess?.call();
    showRemovalOutcomeDialog(
      context,
      result: priorResult,
      verification: lastVerification,
      isTimeout: false,
      onUninstall: () async { await controller.channel.requestSelfUninstall(); },
    );
  } else {
    showRemovalOutcomeDialog(
      context,
      result: priorResult,
      verification: lastVerification,
      isTimeout: true,
      onUninstall: () async { await controller.channel.requestSelfUninstall(); },
      onRecheck: () => runRemovalRecheckFlow(
        context: context,
        controller: controller,
        priorResult: priorResult,
        maxDisplayDuration: maxDisplayDuration,
        pollInterval: pollInterval,
        onRemovalSuccess: onRemovalSuccess,
      ),
    );
  }
}

/// The post-removal outcome dialog (v1.0.5 fix #6 & Batch D Addendum):
/// Displays the verified removal status or an honest accounting of uncompleted
/// steps / unverified checks. On 20s timeout, explicitly warns the user NOT to
/// uninstall yet, lists unverified items, and offers a "re-check" action.
Future<void> showRemovalOutcomeDialog(
  BuildContext context, {
  DeviceOwnerRemovalResult? result,
  RemovalVerificationResult? verification,
  bool isTimeout = false,
  VoidCallback? onRecheck,
  // In-app self-uninstall: the caller passes the channel call; the
  // dialog shows the button only on a clean removal (verified, no
  // failed steps) — the system refuses while Device Owner is
  // still active.
  Future<void> Function()? onUninstall,
}) async {
  final l10n = context.l10n;
  final failed = result?.failedSteps ?? const [];
  final skipped = result?.skippedSteps ?? const [];
  // A verify-only failure is NOT clean: the native report disagreed
  // with the Dart probe, and hiding it showed a clean success while
  // the native step said otherwise (deadlock re-audit F9 / fix F).
  final isClean = (verification?.verified == true) && failed.isEmpty;

  // A re-run in the half-torn-down state started without owner power:
  // owner-only residue can only be cleared by re-provisioning as
  // Device Owner first (deadlock re-audit F3 / fix C).
  final showReprovisionGuidance =
      (result?.startedAsOwner == false) &&
      (failed.isNotEmpty || skipped.isNotEmpty);

  final unverifiedItems = <String>[];
  if (isTimeout && verification != null) {
    if (verification.isDeviceOwner) {
      unverifiedItems.add(l10n.removalUnverifiedOwner);
    }
    if (verification.isAdminActive) {
      unverifiedItems.add(l10n.removalUnverifiedAdmin);
    }
    if (verification.restrictionsResidue.isNotEmpty) {
      unverifiedItems.add(
        l10n.removalUnverifiedRestrictions(
          verification.restrictionsResidue.join(', '),
        ),
      );
    }
    if (verification.screenCaptureDisabled) {
      unverifiedItems.add(l10n.removalUnverifiedScreenCapture);
    }
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(
        isClean ? Icons.verified_user_outlined : Icons.warning_amber_outlined,
        color: isClean ? null : AzmColors.red,
      ),
      title: Text(
        isTimeout
            ? l10n.removalTimeoutWarningTitle
            : (isClean ? l10n.removalCompleteTitle : l10n.removalPartialTitle),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isTimeout
                  ? l10n.removalTimeoutWarningBody
                  : (isClean ? l10n.removalCompleteBody : l10n.removalPartialBody),
            ),
            if (unverifiedItems.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final item in unverifiedItems)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $item'),
                ),
            ],
            if (failed.isNotEmpty && (!isClean || isTimeout)) ...[
              const SizedBox(height: 12),
              for (final s in failed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${removalStepLabel(l10n, s.id)} — ${s.detail}',
                  ),
                ),
            ],
            if (skipped.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final s in skipped)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${removalStepLabel(l10n, s.id)} '
                    '(${l10n.removalStepSkipped}) — ${s.detail}',
                  ),
                ),
            ],
            if (showReprovisionGuidance) ...[
              const SizedBox(height: 12),
              Text(l10n.removalReprovisionGuidance),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(l10n.close),
        ),
        if (isTimeout && onRecheck != null)
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              onRecheck();
            },
            child: Text(l10n.removalRecheckAction),
          ),
        // In-app self-uninstall, only on a clean removal. Popping
        // first keeps this dialog out of the way of the system
        // uninstaller that opens on top of it.
        if (isClean && onUninstall != null)
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await onUninstall();
            },
            child: Text(l10n.uninstallAzm),
          ),
      ],
    ),
  );
}

/// DNS selection dialog (Settings). Since 2026-11-22 it carries
/// the "DNS via VPN" switch: switch on shows the provider list
/// (exactly one of CleanBrowsing / Cloudflare / AdGuard / Custom)
/// and the chosen provider activates automatically whenever a VPN
/// is on; switch off hides the list (user request). The custom
/// field holds a DoH URL (https) — the endpoint Azm's VPN filters
/// with; its host part becomes the Private DNS host applied while
/// an external VPN is up. Apply stays disabled until the custom
/// URL is valid — the choice is never refused, so the field can
/// never be unreachable (item 5's deadlock lesson). [onApply]
/// performs the gated write and reports (applied, error): a null
/// error with applied == false means the recovery gate was
/// cancelled and the dialog simply stays open.
class _DnsDialog extends StatefulWidget {
  const _DnsDialog({
    required this.current,
    required this.internetBlock,
    required this.liveHostname,
    required this.onApply,
  });

  final DnsProtection current;

  /// The live internet-block config: while the switch is on, its
  /// DoH provider is the source of truth for the selection.
  final InternetBlockConfig internetBlock;
  final String? liveHostname;
  final Future<({bool applied, String? error})> Function(DnsProtection)
  onApply;

  @override
  State<_DnsDialog> createState() => _DnsDialogState();
}

class _DnsDialogState extends State<_DnsDialog> {
  bool _viaVpn = false;
  DnsProvider _selected = DnsProvider.cleanBrowsing;
  final _customController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final current = widget.current;
    _viaVpn = current.viaVpn;
    if (current.viaVpn) {
      // The internet-block config is what the VPN actually uses.
      _selected = dnsProviderFor(widget.internetBlock.dohProvider);
      _customController.text = widget.internetBlock.customDohUrl;
    } else {
      _selected = current.provider;
      _customController.text = current.customDohUrl;
    }
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  /// The custom DoH URL as it will be applied (trimmed).
  String get _customUrl => _customController.text.trim();

  bool get _customValid {
    final uri = Uri.tryParse(_customUrl);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  bool get _canApply {
    if (_loading) return false;
    if (!_viaVpn) return true;
    if (_selected == DnsProvider.custom) return _customValid;
    return true;
  }

  Future<void> _apply() async {
    final current = widget.current;
    final isCustom = _selected == DnsProvider.custom;
    final next = DnsProtection(
      enabled: _viaVpn,
      provider: _selected,
      customHostname: isCustom
          ? dohUrlHost(_customUrl)
          : current.customHostname,
      viaVpn: _viaVpn,
      customDohUrl: isCustom ? _customUrl : current.customDohUrl,
    );
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.onApply(next);
    if (!mounted) return;
    if (result.applied) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _loading = false;
        _error = result.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopScope(
      canPop: !_loading,
      child: AlertDialog(
        title: Text(l10n.privateDns),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.liveHostname != null
                      ? l10n.dnsCurrentHost(widget.liveHostname!)
                      : l10n.dnsNotSet,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: Text(l10n.dnsViaVpnTitle),
                  subtitle: Text(l10n.dnsViaVpnSub),
                  value: _viaVpn,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: _loading
                      ? null
                      : (v) => setState(() => _viaVpn = v),
                ),
                // The provider list exists only while the switch is
                // on (user request 2026-11-22).
                if (_viaVpn)
                  RadioGroup<DnsProvider>(
                    groupValue: _selected,
                    onChanged: _loading
                        ? (_) {}
                        : (v) =>
                              setState(() => _selected = v ?? _selected),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RadioListTile<DnsProvider>(
                          title: Text(l10n.dnsProviderCleanbrowsing),
                          subtitle: Text(l10n.dnsProviderCleanbrowsingNote),
                          value: DnsProvider.cleanBrowsing,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile<DnsProvider>(
                          title: Text(l10n.dnsProviderCloudflare),
                          subtitle: Text(l10n.dnsProviderCloudflareNote),
                          value: DnsProvider.cloudflare,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile<DnsProvider>(
                          title: Text(l10n.dnsProviderAdguard),
                          subtitle: Text(l10n.dnsProviderAdguardNote),
                          value: DnsProvider.adguard,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile<DnsProvider>(
                          title: Text(l10n.dnsCustom),
                          subtitle: Text(l10n.dnsProviderCustomNote),
                          value: DnsProvider.custom,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        if (_selected == DnsProvider.custom)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: TextField(
                              controller: _customController,
                              decoration: InputDecoration(
                                labelText: l10n.internetBlockCustomUrl,
                                errorText:
                                    _customController.text.isNotEmpty &&
                                        !_customValid
                                    ? l10n.dnsInvalidHostname
                                    : null,
                              ),
                              enabled: !_loading,
                              keyboardType: TextInputType.url,
                              onChanged: (_) => setState(() {}),
                              onSubmitted: (_) => _apply(),
                            ),
                          ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(l10n.dnsProtectionNote),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _loading ? null : _apply,
                          child: Text(l10n.dnsRetryApply),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _loading ? null : () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: _canApply ? _apply : null,
            child: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.apply),
          ),
        ],
      ),
    );
  }
}

/// Localized names for native teardown step ids.
String removalStepLabel(AppLocalizations l10n, String id) => switch (id) {
  'flag' || 'flagClear' || 'tornDown' => l10n.removalStepDisarm,
  'focus' => l10n.removalStepFocus,
  'lockdown' => l10n.removalStepLockdown,
  'vpn' => l10n.removalStepVpn,
  'policies' => l10n.removalStepPolicies,
  'privateDns' => l10n.removalStepPrivateDns,
  'unsuspend' => l10n.removalStepUnsuspend,
  'restrictions' => l10n.removalStepRestrictions,
  'unhide' => l10n.removalStepUnhide,
  'uninstallBlocks' => l10n.removalStepUninstallBlocks,
  'appRestrictions' => l10n.removalStepAppRestrictions,
  'notifications' => l10n.removalStepNotifications,
  'clearOwner' => l10n.removalStepClearOwner,
  'removeAdmin' => l10n.removalStepRemoveAdmin,
  'stopAccessibility' => l10n.removalStepStopAccessibility,
  'colourModes' => l10n.removalStepColourModes,
  'verify' => l10n.removalStepVerify,
  _ => id,
};
