/// Config tab: the hub mirroring the original `ConfigTab.kt` — Device
/// Owner status, Private DNS (F7), links to every sub-screen, language
/// (F33), theme, recovery-code change, and Device Owner removal (F2:
/// in-session immediate removal, or the 48-hour forced removal).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/privileged_channel.dart';
import '../l10n/l10n.dart';
import 'common.dart';
import 'config_screens.dart';
import 'entry_password_ui.dart';
import 'impulse_focus_screens.dart';
import 'recovery_ui.dart';
import 'setup_screen.dart';

/// The original's preset hosts, verbatim (`ConfigTab.kt:522-524`).
const dnsPresets = <String, String>{
  'Cloudflare': 'family.cloudflare-dns.com',
  'AdGuard DNS': 'family.adguard-dns.com',
  'CleanBrowsing': 'adult-filter-dns.cleanbrowsing.org',
};

/// The original's custom-host validation (`ConfigTab.kt:538-540`):
/// lowercase dot-separated labels and a TLD of at least two letters.
bool isValidHostname(String host) =>
    RegExp(r'^([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}$').hasMatch(host);

class ConfigTab extends StatefulWidget {
  const ConfigTab({super.key, required this.controller});
  final AppController controller;
  @override
  State<ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends State<ConfigTab> {
  bool? _isOwner;
  PrivateDnsState? _dns;
  Object? _error;
  Timer? _ticker;

  AppController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final owner = await _c.channel.isDeviceOwner();
      PrivateDnsState? dns;
      if (owner.isDeviceOwner) {
        try {
          dns = await _c.channel.getPrivateDns();
        } catch (_) {
          dns = null;
        }
      }
      if (mounted) {
        setState(() {
          _isOwner = owner.isDeviceOwner;
          _dns = dns;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
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
                  : _error.toString(),
            ),
          ),
        SectionCard(
          title: l10n.generalSettings,
          children: [
            ListTile(
              leading: Icon(
                _isOwner == true ? Icons.verified_user : Icons.shield_outlined,
              ),
              title: Text(l10n.setupAndOwner),
              subtitle: Text(
                _isOwner == null
                    ? l10n.checking
                    : _isOwner!
                    ? l10n.provisionedAsOwner
                    : l10n.notOwnerOpenSetup,
              ),
              trailing: const Icon(Icons.navigate_next),
              onTap: () => _push(
                Scaffold(
                  appBar: AppBar(title: Text(l10n.setupTitle)),
                  body: SetupScreen(controller: _c),
                ),
              ),
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
              trailing: const Icon(Icons.navigate_next),
              onTap: _isOwner == true
                  ? _editDns
                  : () => showInfoSnackBar(context, l10n.dnsNeedsOwnerMsg),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: l10n.protectionTools,
          children: [
            ListTile(
              leading: const Icon(Icons.language),
              title: Text(l10n.browserRestrictions),
              subtitle: Text(l10n.browserRestrictionsSub),
              trailing: const Icon(Icons.navigate_next),
              onTap: () => _push(BrowserRestrictionsScreen(controller: _c)),
            ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: Text(l10n.blockedWords),
              subtitle: Text(l10n.blockedWordsSub),
              trailing: const Icon(Icons.navigate_next),
              onTap: () => _push(BlockedWordsScreen(controller: _c)),
            ),
            ListTile(
              leading: const Icon(Icons.emergency_outlined),
              title: Text(l10n.impulseLockTitle),
              subtitle: Text(l10n.impulseLockSub),
              trailing: const Icon(Icons.navigate_next),
              onTap: () => _push(ImpulseLockScreen(controller: _c)),
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text(l10n.focusMode),
              subtitle: Text(l10n.focusModeSub),
              trailing: const Icon(Icons.navigate_next),
              onTap: () => _push(FocusModeScreen(controller: _c)),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: Text(l10n.usageWarnings),
              subtitle: Text(l10n.usageWarningsSub),
              trailing: const Icon(Icons.navigate_next),
              onTap: () => _push(UsageWarningsScreen(controller: _c)),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(l10n.suspensionLogs),
              subtitle: Text(l10n.suspensionLogsSub),
              trailing: const Icon(Icons.navigate_next),
              onTap: () => _push(SuspensionLogsScreen(controller: _c)),
            ),
            UnavailableTile(
              icon: Icons.palette_outlined,
              title: l10n.colourModes,
              note: l10n.colourModesNote,
            ),
            UnavailableTile(
              icon: Icons.directions_run_outlined,
              title: l10n.activityBlocker,
              note: l10n.activityBlockerNote,
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: l10n.preferencesSection,
          children: [
            ListTile(
              leading: const Icon(Icons.translate),
              title: Text(l10n.language),
              subtitle: Text(
                _c.language == 'ar'
                    ? l10n.languageArabic
                    : l10n.languageEnglish,
              ),
              trailing: const Icon(Icons.navigate_next),
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
                    icon: Icon(Icons.brightness_auto),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode),
                  ),
                ],
                selected: {_c.themeMode},
                onSelectionChanged: (s) => _c.setThemeMode(s.first),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.password),
              title: Text(l10n.changeRecoveryCode),
              subtitle: Text(l10n.changeRecoveryCodeSub),
              trailing: const Icon(Icons.navigate_next),
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
                onTap: _isOwner == true
                    ? () async {
                        // v1.0.5 fix #6: removal runs the ordered native
                        // teardown; the outcome dialog reports honestly
                        // whether every cleanup step completed.
                        DeviceOwnerRemovalResult? result;
                        await runLoosening(context, _c, () async {
                          result = await _c.channel.removeDeviceOwner();
                          if (result!.isDeviceOwner) {
                            throw PrivilegedException(
                              'DPM_FAILED',
                              l10n.ownerStillActiveMsg,
                            );
                          }
                          // Guarded by context.mounted (not State.mounted): this
                          // closure runs through runLoosening, where the analyzer
                          // treats the State check as unrelated to this context.
                          if (!context.mounted) return;
                          setState(() => _isOwner = false);
                        });
                        if (result != null &&
                            !result!.isDeviceOwner &&
                            context.mounted) {
                          await _showRemovalOutcome(context, result!);
                        }
                      }
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.hourglass_bottom),
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
                        onPressed: _confirmStartForcedRemoval,
                        child: Text(l10n.startForcedRemoval),
                      ),
                    if (forced.active && !forced.isComplete)
                      OutlinedButton(
                        onPressed: _confirmCancelForcedRemoval,
                        child: Text(l10n.cancelForcedRemoval),
                      ),
                    if (forced.isComplete)
                      FilledButton(
                        onPressed: _finishForcedRemoval,
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

  /// DNS selection dialog, mirroring the original's `DnsSelectionDialog`
  /// (`ConfigTab.kt:514-630`) and its apply path (`:443-475`): radio
  /// presets + custom host with inline validation, Apply disabled until
  /// the selection is valid, the apply wrapped in the recovery gate,
  /// a 15-second timeout, and result-code error mapping
  /// (`PRIVATE_DNS_SET_ERROR_HOST_NOT_SERVING` gets its own message).
  Future<void> _editDns() async {
    final applied = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DnsDialog(
        currentHost: _dns?.isSpecifiedHost == true ? _dns!.hostname : null,
        onApply: (host) async {
          // Captured before the awaits below (the dialog outlives them).
          final l10n = context.l10n;
          // The original wraps the apply in `recoveryGate.run` — a full
          // recovery session, not just the loosening path.
          if (!await ensureRecoverySession(context, _c)) {
            return (applied: false, error: null);
          }
          try {
            final state = await _c.channel
                .setPrivateDns(host)
                .timeout(const Duration(seconds: 15));
            if (mounted) setState(() => _dns = state);
            return (applied: true, error: null);
          } on TimeoutException {
            return (applied: false, error: l10n.dnsApplyTimeout);
          } on PrivilegedException catch (e) {
            // Native surfaces the DPM result code as `verifiedState`
            // (2 = PRIVATE_DNS_SET_ERROR_HOST_NOT_SERVING).
            final notServing =
                e.details['verifiedState'] == 2 ||
                e.message.contains('result code 2');
            return (
              applied: false,
              error: notServing ? l10n.dnsNotServing : l10n.dnsApplyFailed,
            );
          }
        },
      ),
    );
    if (applied == true && mounted && _dns != null) {
      showInfoSnackBar(
        context,
        context.l10n.dnsAppliedMsg(_dns!.hostname ?? ''),
      );
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
    await _c.config.setForcedRemoval(started);
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
              onPressed: confirmed
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
    final l10n = context.l10n;
    try {
      final result = await _c.channel.removeDeviceOwner();
      if (!result.isDeviceOwner) {
        await _cancelForcedRemoval();
        if (mounted) {
          setState(() => _isOwner = false);
          await _showRemovalOutcome(context, result);
        }
      } else {
        throw PrivilegedException('DPM_FAILED', l10n.ownerStillActiveMsg);
      }
    } catch (e) {
      if (!mounted) return;
      await showErrorSnackBar(context, e);
    }
  }

  /// The post-removal state (v1.0.5, fix #6): after a verified removal
  /// the user is told plainly that protection is fully removed and the
  /// app can now be uninstalled normally — or, when some teardown steps
  /// did not complete, exactly which ones, instead of a blanket success
  /// message.
  Future<void> _showRemovalOutcome(
    BuildContext context,
    DeviceOwnerRemovalResult result,
  ) async {
    final l10n = context.l10n;
    final failed = result.failedSteps;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          failed.isEmpty
              ? Icons.verified_user_outlined
              : Icons.warning_amber_outlined,
        ),
        title: Text(
          failed.isEmpty ? l10n.removalCompleteTitle : l10n.removalPartialTitle,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              failed.isEmpty
                  ? l10n.removalCompleteBody
                  : l10n.removalPartialBody,
            ),
            if (failed.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final s in failed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${_removalStepLabel(l10n, s.id)} — ${s.detail}',
                  ),
                ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  /// Localized names for the native teardown step ids (fix #6).
  String _removalStepLabel(AppLocalizations l10n, String id) => switch (id) {
    'flag' || 'flagClear' => l10n.removalStepDisarm,
    'focus' => l10n.removalStepFocus,
    'unsuspend' => l10n.removalStepUnsuspend,
    'restrictions' => l10n.removalStepRestrictions,
    'unhide' => l10n.removalStepUnhide,
    'uninstallBlocks' => l10n.removalStepUninstallBlocks,
    'appRestrictions' => l10n.removalStepAppRestrictions,
    'clearOwner' => l10n.removalStepClearOwner,
    _ => id,
  };

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

/// The original's `DnsSelectionDialog` (`ConfigTab.kt:514-630`): preset
/// radios, a Custom radio revealing the host field with inline validation,
/// an inline error line for apply failures, a spinner while applying, and
/// Apply disabled until there is a valid selection. [onApply] performs
/// the gated native call and reports `(applied, error)`: a null error
/// with `applied == false` means the recovery gate was cancelled and the
/// dialog simply stays open, as in the original.
class _DnsDialog extends StatefulWidget {
  const _DnsDialog({required this.currentHost, required this.onApply});

  final String? currentHost;
  final Future<({bool applied, String? error})> Function(String host) onApply;

  @override
  State<_DnsDialog> createState() => _DnsDialogState();
}

class _DnsDialogState extends State<_DnsDialog> {
  /// Selected preset host, `'custom'`, or null (nothing selected yet).
  String? _selected;
  final _customController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final current = widget.currentHost;
    if (current != null && dnsPresets.values.contains(current)) {
      _selected = current;
    } else if (current != null) {
      _selected = 'custom';
      _customController.text = current;
    }
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  bool get _customValid => isValidHostname(_customController.text.trim());

  bool get _canApply =>
      !_loading && _selected != null && (_selected != 'custom' || _customValid);

  Future<void> _apply() async {
    final host = _selected == 'custom'
        ? _customController.text.trim()
        : _selected!;
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.onApply(host);
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
    return PopScope(
      canPop: !_loading,
      child: AlertDialog(
        title: Text(context.l10n.dnsSettingsTitle),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: RadioGroup<String>(
              groupValue: _selected,
              onChanged: _loading
                  ? (_) {}
                  : (v) => setState(() => _selected = v),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in dnsPresets.entries)
                    RadioListTile<String>(
                      value: entry.value,
                      title: Text(
                        entry.key,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(entry.value),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  RadioListTile<String>(
                    value: 'custom',
                    title: Text(
                      context.l10n.dnsCustom,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_selected == 'custom')
                    TextField(
                      controller: _customController,
                      enabled: !_loading,
                      decoration: InputDecoration(
                        labelText: context.l10n.dnsHostnameLabel,
                        hintText: 'dns.example.com',
                        border: const OutlineInputBorder(),
                        errorText:
                            _customController.text.isNotEmpty && !_customValid
                            ? context.l10n.dnsInvalidHostname
                            : null,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _loading ? null : () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: _canApply ? _apply : null,
            child: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(context.l10n.apply),
          ),
        ],
      ),
    );
  }
}
