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

const dnsPresets = <String, String>{
  'Cloudflare Family': 'security.cloudflare-dns.com',
  'AdGuard Family': 'family.adguard-dns.com',
  'CleanBrowsing (family filter)': 'security-filter-dns.cleanbrowsing.org',
};

bool isValidHostname(String host) {
  if (host.isEmpty || host.length > 253 || host.contains(' ') || host.contains('/')) {
    return false;
  }
  final label = RegExp(r'^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$');
  return host.split('.').every((p) => p.isNotEmpty && label.hasMatch(p));
}

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
          onTap: _isOwner == true ? _editDns : null,
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
                  onPressed: () async {
                    await _c.config.setForcedRemoval(forced.start());
                    // Reload the controller's copy.
                    _c.forcedRemoval = forced.start();
                    if (mounted) setState(() {});
                  },
                  child: const Text('Start forced removal'),
                ),
              if (forced.active && !forced.isComplete)
                OutlinedButton(
                  onPressed: () async {
                    final cancelled = forced.cancel();
                    await _c.config.setForcedRemoval(cancelled);
                    _c.forcedRemoval = cancelled;
                    if (mounted) setState(() {});
                  },
                  child: const Text('Cancel forced removal'),
                ),
              if (forced.isComplete)
                FilledButton(
                  onPressed: () async {
                    final stillOwner = await _c.channel.removeDeviceOwner();
                    if (!stillOwner) {
                      final cleared = forced.cancel();
                      await _c.config.setForcedRemoval(cleared);
                      _c.forcedRemoval = cleared;
                      if (mounted) {
                        setState(() => _isOwner = false);
                        showInfoSnackBar(context, 'Device Owner removed (verified).');
                      }
                    }
                  },
                  child: const Text('Finish removal'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _editDns() async {
    final customController = TextEditingController();
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Force family private DNS'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in dnsPresets.entries)
                ListTile(
                  title: Text(entry.key),
                  subtitle: Text(entry.value),
                  onTap: () => Navigator.pop(context, entry.value),
                ),
              const Divider(),
              TextField(
                controller: customController,
                decoration: const InputDecoration(
                  labelText: 'Custom hostname',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, customController.text.trim()),
            child: const Text('Use custom'),
          ),
        ],
      ),
    );
    if (choice == null || choice.isEmpty) return;
    if (!isValidHostname(choice)) {
      await showErrorSnackBar(
        context,
        PrivilegedException('INVALID_ARGUMENT', 'Malformed private DNS hostname: $choice'),
      );
      return;
    }
    try {
      final state = await _c.channel.setPrivateDns(choice);
      if (mounted) {
        setState(() => _dns = state);
        showInfoSnackBar(context, 'Private DNS forced to ${state.hostname} (verified).');
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
