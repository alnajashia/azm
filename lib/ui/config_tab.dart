/// Config tab: the hub mirroring the original `ConfigTab.kt` — Device
/// Owner status, Private DNS (F7), links to every sub-screen, language
/// (F33), theme, recovery-code change, and Device Owner removal (F2:
/// in-session immediate removal, or the 48-hour forced removal).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/privileged_channel.dart';
import '../domain/colour_modes.dart';
import '../l10n/l10n.dart';
import '../theme.dart';
import 'activity_blocker_screen.dart';
import 'colour_modes_screen.dart';
import 'common.dart';
import 'config_screens.dart';
import 'entry_password_ui.dart';
import 'impulse_focus_screens.dart';
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
      var residue = const <String>[];
      if (owner.isDeviceOwner) {
        try {
          dns = await _c.channel.getPrivateDns();
        } catch (_) {
          dns = null;
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
              // DNS batch: this tile used to open a SECOND, separate
              // DNS dialog (presets + custom host, its own apply path
              // that never persisted). The browser-restrictions
              // screen's DNS card is now the ONE DNS place, so the
              // tile navigates there instead.
              onTap: _isOwner == true
                  ? () => _push(BrowserRestrictionsScreen(controller: _c))
                  : () => showInfoSnackBar(context, l10n.dnsNeedsOwnerMsg),
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
                title: Text(l10n.removeOwnerNow),
                subtitle: Text(l10n.removeOwnerNowSub),
                onTap: ((_isOwner == true || _isAdmin == true) && !_c.isRemovingDeviceOwner)
                    ? _onRemoveOwnerTapped
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.hourglass_bottom_outlined),
                title: Text(l10n.forcedRemovalTitle),
                subtitle: Text(
                  !forced.active
                      ? l10n.forcedIdleSub
                      : forced.isComplete
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
                    if (forced.active && !forced.isComplete)
                      OutlinedButton(
                        onPressed: _c.isRemovingDeviceOwner
                            ? null
                            : _confirmCancelForcedRemoval,
                        child: Text(l10n.cancelForcedRemoval),
                      ),
                    if (forced.isComplete)
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
    });
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
    final started = forced.start();
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
  Duration maxDisplayDuration = const Duration(seconds: 20),
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

  if (dialogCtx != null && dialogCtx!.mounted) {
    Navigator.of(dialogCtx!).pop();
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
    );
  } else {
    showRemovalOutcomeDialog(
      context,
      result: removalResult,
      verification: lastVerification,
      isTimeout: true,
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
  Duration maxDisplayDuration = const Duration(seconds: 20),
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

  if (dialogCtx != null && dialogCtx!.mounted) {
    Navigator.of(dialogCtx!).pop();
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
    );
  } else {
    showRemovalOutcomeDialog(
      context,
      result: priorResult,
      verification: lastVerification,
      isTimeout: true,
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
}) async {
  final l10n = context.l10n;
  final failed = result?.failedSteps ?? const [];
  final isClean = (verification?.verified == true) &&
      (failed.isEmpty || (failed.length == 1 && failed.first.id == 'verify'));

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
      ],
    ),
  );
}

/// Localized names for native teardown step ids.
String removalStepLabel(AppLocalizations l10n, String id) => switch (id) {
  'flag' || 'flagClear' => l10n.removalStepDisarm,
  'focus' => l10n.removalStepFocus,
  'policies' => l10n.removalStepPolicies,
  'privateDns' => l10n.removalStepPrivateDns,
  'unsuspend' => l10n.removalStepUnsuspend,
  'restrictions' => l10n.removalStepRestrictions,
  'unhide' => l10n.removalStepUnhide,
  'uninstallBlocks' => l10n.removalStepUninstallBlocks,
  'appRestrictions' => l10n.removalStepAppRestrictions,
  'notifications' => l10n.removalStepNotifications,
  'clearOwner' => l10n.removalStepClearOwner,
  'colourModes' => l10n.removalStepColourModes,
  'verify' => l10n.removalStepVerify,
  _ => id,
};
