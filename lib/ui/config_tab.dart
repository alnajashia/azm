/// Config tab: the hub mirroring the original `ConfigTab.kt` — Device
/// Owner status, Private DNS (F7), links to every sub-screen, language
/// (F33), theme, recovery-code change, and Device Owner removal (F2:
/// in-session immediate removal, or the 48-hour forced removal).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/privileged_channel.dart';
import 'common.dart';
import 'config_screens.dart';
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
    final forced = _c.forcedRemoval;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error is PrivilegedException
                ? friendlyError(_error! as PrivilegedException)
                : _error.toString()),
          ),
        ListTile(
          leading: Icon(_isOwner == true ? Icons.verified_user : Icons.shield_outlined),
          title: const Text('Setup & Device Owner'),
          subtitle: Text(_isOwner == null
              ? 'Checking…'
              : _isOwner!
                  ? 'Provisioned as Device Owner'
                  : 'Not Device Owner — open Setup'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _push(Scaffold(
            appBar: AppBar(title: const Text('Setup')),
            body: SetupScreen(controller: _c),
          )),
        ),
        ListTile(
          leading: const Icon(Icons.dns_outlined),
          title: const Text('Private DNS'),
          subtitle: Text(_dns == null
              ? (_isOwner == true ? 'Could not read current DNS state' : 'Requires Device Owner')
              : _dns!.isSpecifiedHost
                  ? 'Forced host: ${_dns!.hostname}'
                  : 'Mode: ${_dns!.mode}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _isOwner == true
              ? _editDns
              : () => showInfoSnackBar(
                    context,
                    'Private DNS requires Device Owner — finish Setup first.',
                  ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.language),
          title: const Text('Browser restrictions'),
          subtitle: const Text('URL blocklists + SafeSearch on supporting browsers'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _push(BrowserRestrictionsScreen(controller: _c)),
        ),
        ListTile(
          leading: const Icon(Icons.text_fields),
          title: const Text('Blocked words'),
          subtitle: const Text('Active and per-app on-screen word blocking'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _push(BlockedWordsScreen(controller: _c)),
        ),
        ListTile(
          leading: const Icon(Icons.emergency_outlined),
          title: const Text('Impulse lock'),
          subtitle: const Text('Panic lock, challenges, recovery keypad options'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _push(ImpulseLockScreen(controller: _c)),
        ),
        ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: const Text('Focus mode'),
          subtitle: const Text('Pomodoro sessions that suspend chosen apps'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _push(FocusModeScreen(controller: _c)),
        ),
        ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: const Text('Usage warnings'),
          subtitle: const Text('Staged warnings before a time limit expires'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _push(UsageWarningsScreen(controller: _c)),
        ),
        ListTile(
          leading: const Icon(Icons.history),
          title: const Text('Suspension logs'),
          subtitle: const Text('Audit log of every suspension'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _push(SuspensionLogsScreen(controller: _c)),
        ),
        const UnavailableTile(
          icon: Icons.palette_outlined,
          title: 'Colour modes',
          note: 'Scheduled grayscale / night light / extra dim ship in v1.1 '
              '(the WRITE_SECURE_SETTINGS grant they need is on the Setup screen).',
        ),
        const UnavailableTile(
          icon: Icons.directions_run_outlined,
          title: 'Activity blocker',
          note: 'Blocking specific activity screens ships in v1.1.',
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.translate),
          title: const Text('Language'),
          subtitle: Text(_c.language == 'pt' ? 'Português' : 'English'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _pickLanguage,
        ),
        ListTile(
          leading: const Icon(Icons.brightness_6_outlined),
          title: const Text('Theme'),
          subtitle: Text(switch (_c.themeMode) {
            ThemeMode.system => 'System default',
            ThemeMode.light => 'Light',
            ThemeMode.dark => 'Dark',
          }),
          trailing: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto)),
              ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode)),
              ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode)),
            ],
            selected: {_c.themeMode},
            onSelectionChanged: (s) => _c.setThemeMode(s.first),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.password),
          title: const Text('Change recovery code'),
          subtitle: const Text('Requires a recovery session; the old code stops working'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            if (!await ensureRecoverySession(context, _c)) return;
            if (!mounted) return;
            _push(Scaffold(
              appBar: AppBar(title: const Text('Change recovery code')),
              body: RecoveryWizard(
                controller: _c,
                isRegeneration: true,
                onDone: () {
                  Navigator.of(context).pop();
                  showInfoSnackBar(context, 'Recovery code changed.');
                },
              ),
            ));
          },
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.remove_moderator_outlined),
          title: const Text('Remove Device Owner now'),
          subtitle: const Text('Immediate, inside a recovery session'),
          onTap: _isOwner == true
              ? () => runLoosening(context, _c, () async {
                    final stillOwner = await _c.channel.removeDeviceOwner();
                    if (!stillOwner) {
                      if (mounted) {
                        setState(() => _isOwner = false);
                        showInfoSnackBar(context, 'Device Owner removed (verified).');
                      }
                    } else {
                      throw PrivilegedException(
                          'DPM_FAILED', 'Device Owner is still active after removal');
                    }
                  })
              : null,
        ),
        ListTile(
          leading: const Icon(Icons.hourglass_bottom),
          title: const Text('48-hour forced removal'),
          subtitle: Text(!forced.active
              ? 'The only code-free escape. Starts a 48-hour countdown.'
              : forced.isComplete
                  ? 'Complete — removal can now be finished without a code.'
                  : 'In progress — ${formatDuration(forced.remaining)} remaining '
                      '(advances while the app is running)'),
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
                  child: const Text('Start forced removal'),
                ),
              if (forced.active && !forced.isComplete)
                OutlinedButton(
                  onPressed: _confirmCancelForcedRemoval,
                  child: const Text('Cancel forced removal'),
                ),
              if (forced.isComplete)
                FilledButton(
                  onPressed: _finishForcedRemoval,
                  child: const Text('Finish removal'),
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
            return (
              applied: false,
              error: 'Applying the DNS host timed out. Check the current '
                  'DNS state before retrying.',
            );
          } on PrivilegedException catch (e) {
            // Native surfaces the DPM result code as `verifiedState`
            // (2 = PRIVATE_DNS_SET_ERROR_HOST_NOT_SERVING).
            final notServing = e.details['verifiedState'] == 2 ||
                e.message.contains('result code 2');
            return (
              applied: false,
              error: notServing
                  ? 'The chosen DNS host is not serving. Pick another host.'
                  : 'Failed to apply the private DNS host.',
            );
          }
        },
      ),
    );
    if (applied == true && mounted && _dns != null) {
      showInfoSnackBar(
          context, 'Private DNS forced to ${_dns!.hostname} (verified).');
    }
  }

  /// Start dialog (`ConfigTab.kt`, `showStartForcedRemovalDialog`):
  /// explanatory text + explicit Confirm before the countdown begins.
  Future<void> _confirmStartForcedRemoval() async {
    final forced = _c.forcedRemoval;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Start forced removal?'),
        content: const Text(
          'This starts a 48-hour countdown. When it finishes, Device '
          'Owner — and with it every restriction this app enforces — can '
          'be removed without the recovery code. It is the only code-free '
          'escape, and it can be cancelled at any time before it '
          'completes.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm')),
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
      builder: (_) => AlertDialog(
        title: const Text('Cancel forced removal?'),
        content: const Text(
          'The 48-hour countdown will be discarded. Device Owner removal '
          'will again require the recovery code.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Close')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm')),
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
          title: const Text('Finish forced removal?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The 48-hour wait is complete. Removing Device Owner now '
                'lifts every restriction this app enforces on this '
                'device.',
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                    'I understand this removes all protection'),
                value: confirmed,
                onChanged: (v) => setLocal(() => confirmed = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel-removal'),
              child: const Text('Cancel forced removal'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed:
                  confirmed ? () => Navigator.pop(context, 'remove') : null,
              child: const Text('Remove Device Owner'),
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
      final stillOwner = await _c.channel.removeDeviceOwner();
      if (!stillOwner) {
        await _cancelForcedRemoval();
        if (mounted) {
          setState(() => _isOwner = false);
          showInfoSnackBar(context, 'Device Owner removed (verified).');
        }
      } else {
        throw PrivilegedException(
            'DPM_FAILED', 'Device Owner is still active after removal');
      }
    } catch (e) {
      await showErrorSnackBar(context, e);
    }
  }

  Future<void> _pickLanguage() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Language / Idioma'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'en'),
            child: const Text('English'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'pt'),
            child: const Text('Português'),
          ),
        ],
      ),
    );
    if (choice != null) {
      await _c.setLanguage(choice);
      if (mounted) {
        showInfoSnackBar(
          context,
          choice == 'pt'
              ? 'Idioma guardado. A tradução completa dos ecrãs é parcial nesta versão.'
              : 'Language saved. Full per-screen translation is partial in this version.',
        );
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
      !_loading &&
      _selected != null &&
      (_selected != 'custom' || _customValid);

  Future<void> _apply() async {
    final host =
        _selected == 'custom' ? _customController.text.trim() : _selected!;
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
        title: const Text('Private DNS settings'),
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
                    title: Text(entry.key,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(entry.value),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                RadioListTile<String>(
                  value: 'custom',
                  title: const Text('Custom',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                if (_selected == 'custom')
                  TextField(
                    controller: _customController,
                    enabled: !_loading,
                    decoration: InputDecoration(
                      labelText: 'DNS hostname',
                      hintText: 'dns.example.com',
                      border: const OutlineInputBorder(),
                      errorText: _customController.text.isNotEmpty &&
                              !_customValid
                          ? 'Invalid DNS hostname'
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
                          color: Theme.of(context).colorScheme.error),
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
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _canApply ? _apply : null,
            child: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Apply'),
          ),
        ],
      ),
    );
  }
}
