/// Setup / Status screen (F30): the Shizuku state machine
/// (notInstalled → notRunning → preV11 → noPermission → granted), Device
/// Owner provisioning, diagnostics, the WRITE_SECURE_SETTINGS grant and the
/// Accessibility toggle. Every state is distinct and honest — e.g. Dominanter
/// cannot start the Shizuku server, so `notRunning` says exactly that.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/privileged_channel.dart';
import 'common.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  ShizukuStatus? _shizuku;
  bool _isOwner = false;
  bool _isAdmin = false;
  ({bool isEnabled, bool isServiceRunning})? _a11y;
  Object? _error;
  bool _loading = true;
  bool _busy = false;
  String? _provisionOutput;
  ProvisioningDiagnostics? _diagnostics;
  Object? _diagnosticsError;
  StreamSubscription<PrivilegedEvent>? _sub;

  PrivilegedChannel get _channel => widget.controller.channel;

  @override
  void initState() {
    super.initState();
    _refresh();
    _sub = _channel.events.listen((e) {
      if (e.type == 'shizukuBinderReceived' ||
          e.type == 'shizukuBinderDead' ||
          e.type == 'shizukuPermissionResult' ||
          e.type == 'deviceOwnerChanged' ||
          e.type == 'accessibilityStateChanged') {
        _refresh();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final shizuku = await _channel.getShizukuState();
      final owner = await _channel.isDeviceOwner();
      final a11y = await _channel.isAccessibilityEnabled();
      if (mounted) {
        setState(() {
          _shizuku = shizuku;
          _isOwner = owner.isDeviceOwner;
          _isAdmin = owner.isAdminActive;
          _a11y = a11y;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      await showErrorSnackBar(context, e);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _shizuku == null) return const LoadingView(message: 'Checking setup state…');
    if (_error != null && _shizuku == null) return ErrorView(error: _error!, onRetry: _refresh);
    final shizuku = _shizuku!;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ShizukuCard(
            status: shizuku,
            busy: _busy,
            onRequestPermission: () => _run(() async {
              await _channel.requestShizukuPermission();
            }),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(_isOwner ? Icons.verified_user : Icons.shield_outlined),
                  title: const Text('Device Owner'),
                  subtitle: Text(_isOwner
                      ? 'Dominanter is the Device Owner of this device.'
                      : 'Not provisioned. Most restrictions need Device Owner. '
                          'Admin active: $_isAdmin.'),
                ),
                if (!_isOwner)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: FilledButton.icon(
                      onPressed: (_busy || shizuku.state != ShizukuState.granted)
                          ? null
                          : () => _run(() async {
                                final r = await _channel.provisionDeviceOwner();
                                if (mounted) {
                                  setState(() {
                                    _provisionOutput =
                                        'Path used: ${r['pathUsed']}\n${r['commandOutput'] ?? ''}';
                                  });
                                }
                              }),
                      icon: const Icon(Icons.admin_panel_settings),
                      label: const Text('Become Device Owner via Shizuku'),
                    ),
                  ),
                if (shizuku.state != ShizukuState.granted && !_isOwner)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text(
                      'Provisioning unlocks when Shizuku is running and permission is granted.',
                    ),
                  ),
                if (_provisionOutput != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: SelectableText(_provisionOutput!),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.accessibility_new),
                  title: const Text('Accessibility Service'),
                  subtitle: Text(_a11y == null
                      ? 'Unknown'
                      : _a11y!.isEnabled
                          ? (_a11y!.isServiceRunning
                              ? 'Enabled and running — enforcement is live.'
                              : 'Enabled but not yet running (binding).')
                          : 'Off. Turning it off later suspends every controlled app (anti-bypass lockdown).'),
                  value: _a11y?.isEnabled ?? false,
                  onChanged: _busy
                      ? null
                      : (v) => _run(() async {
                            await _channel.setAccessibilityEnabled(v);
                          }),
                ),
                ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: const Text('Grant WRITE_SECURE_SETTINGS'),
                  subtitle: const Text(
                      'Needed for colour modes (v1.1). Granted via Shizuku; '
                      'the check is re-read after granting.'),
                  trailing: FilledButton.tonal(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                              final ok = await _channel.grantWriteSecureSettings();
                              if (mounted && ok) {
                                showInfoSnackBar(context, 'WRITE_SECURE_SETTINGS is granted.');
                              }
                            }),
                    child: const Text('Grant'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ListTile(
                  leading: Icon(Icons.medical_information_outlined),
                  title: Text('Provisioning diagnostics'),
                  subtitle: Text(
                      'Accounts, extra users and the current Device Owner — '
                      'these can block provisioning.'),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                              try {
                                final d = await _channel.getProvisioningDiagnostics();
                                if (mounted) {
                                  setState(() {
                                    _diagnostics = d;
                                    _diagnosticsError = null;
                                  });
                                }
                              } catch (e) {
                                if (mounted) setState(() => _diagnosticsError = e);
                              }
                            }),
                    child: const Text('Run diagnostics'),
                  ),
                ),
                if (_diagnosticsError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text(
                      _diagnosticsError is PrivilegedException
                          ? friendlyError(_diagnosticsError! as PrivilegedException)
                          : _diagnosticsError.toString(),
                    ),
                  ),
                if (_diagnostics != null) _DiagnosticsView(d: _diagnostics!),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShizukuCard extends StatelessWidget {
  const _ShizukuCard({required this.status, required this.busy, required this.onRequestPermission});
  final ShizukuStatus status;
  final bool busy;
  final VoidCallback onRequestPermission;

  @override
  Widget build(BuildContext context) {
    final (icon, title, body) = switch (status.state) {
      ShizukuState.notInstalled => (
          Icons.block,
          'Shizuku: not installed',
          'Install Shizuku (moe.shizuku.privileged.api) from the Play Store '
              'or its official site, then return here.',
        ),
      ShizukuState.notRunning => (
          Icons.power_off,
          'Shizuku: not running',
          'Shizuku is installed, but its server is not running. Dominanter '
              'cannot start it — open the Shizuku app and start the server '
              '(via wireless debugging or ADB), then pull to refresh.',
        ),
      ShizukuState.preV11 => (
          Icons.update,
          'Shizuku: too old (pre-v11)',
          'This Shizuku server predates v11 and cannot run commands. '
              'Update Shizuku, restart its server, then refresh.',
        ),
      ShizukuState.noPermission => (
          Icons.lock_outline,
          'Shizuku: permission needed',
          'The server is running. Grant Dominanter permission in Shizuku to '
              'continue setup.',
        ),
      ShizukuState.granted => (
          Icons.check_circle,
          'Shizuku: connected & granted',
          'Setup operations are available. Day-to-day enforcement does not '
              'need Shizuku after provisioning.',
        ),
      ShizukuState.unknown => (
          Icons.help_outline,
          'Shizuku: unknown state',
          'The native layer returned an unrecognised state.',
        ),
    };
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Icon(icon),
            title: Text(title),
            subtitle: Text(body),
          ),
          if (status.serverVersion != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                'Server version ${status.serverVersion}, UID ${status.serverUid}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (status.diagnostic != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text('Diagnostic: ${status.diagnostic}',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          if (status.state == ShizukuState.noPermission)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: FilledButton.icon(
                onPressed: busy ? null : onRequestPermission,
                icon: const Icon(Icons.key),
                label: const Text('Request Shizuku permission'),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _DiagnosticsView extends StatelessWidget {
  const _DiagnosticsView({required this.d});
  final ProvisioningDiagnostics d;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Accounts (${d.accounts.length})',
              style: Theme.of(context).textTheme.titleSmall),
          if (d.accounts.isEmpty) const Text('No accounts found — good for provisioning.'),
          for (final a in d.accounts) Text('• ${a['name']} (${a['type']})'),
          const SizedBox(height: 8),
          Text('Users (${d.extraUsers.length})',
              style: Theme.of(context).textTheme.titleSmall),
          if (d.extraUsers.isEmpty) const Text('Only the primary user.'),
          for (final u in d.extraUsers) Text('• ${u['name']} (id ${u['id']})'),
          const SizedBox(height: 8),
          Text('Current Device Owner', style: Theme.of(context).textTheme.titleSmall),
          Text(d.currentOwner == null
              ? 'None'
              : '${d.currentOwner!['packageName']} / ${d.currentOwner!['receiver']}'),
        ],
      ),
    );
  }
}
