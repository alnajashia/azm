/// Setup / Status screen (F30): the Shizuku state machine
/// (notInstalled → notRunning → preV11 → noPermission → granted), Device
/// Owner provisioning, diagnostics, the WRITE_SECURE_SETTINGS grant and the
/// Accessibility toggle. Every state is distinct and honest — e.g. Dominanter
/// cannot start the Shizuku server, so `notRunning` says exactly that.
///
/// Permission flow (the original's polling design): requesting Shizuku
/// permission only *opens* Shizuku's dialog — the answer arrives later.
/// Like the original (which re-checks binder/permission state every
/// 500 ms), this screen polls `getShizukuState` every 500 ms after a
/// request until the grant is observed (then everything refreshes and the
/// Provision button enables with no manual step) or a 30 s timeout, and it
/// also refreshes on privileged-channel events. The same poll-after-action
/// pattern drives the Install Shizuku return trip and the
/// WRITE_SECURE_SETTINGS grant tile.
///
/// Provisioning blockers (D-08): mirroring the original's
/// `SetupDeviceOwnerPrivileges`, extra users or a *different* app already
/// being Device Owner replace the provisioning path entirely — the button
/// is disabled and an explanatory dialog is shown once when the blocker is
/// first detected.
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

/// This app's own package name, for telling "we are the current owner"
/// apart from "*another* app is the current owner" in diagnostics.
const String _ownPackage = 'io.github.alnajashia.dominanter';

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

  // --- Shizuku permission / install polling (500 ms, like the original) ---
  Timer? _shizukuPoll;
  bool _pollTickInFlight = false;
  int _pollTicks = 0;

  /// True while waiting for the user to answer Shizuku's permission dialog.
  bool _awaitingPermission = false;

  /// True while waiting for Shizuku to appear after an install tap.
  bool _awaitingInstall = false;

  // --- WRITE_SECURE_SETTINGS grant state ---------------------------------
  /// null = not verified yet; true = verified granted; false = verified
  /// not granted. Seeded by the passive read on every refresh and updated
  /// by grant attempts.
  bool? _wssGranted;
  Timer? _wssPoll;
  bool _wssTickInFlight = false;
  int _wssTicks = 0;
  bool _wssBusy = false;

  /// The blocker key the explanatory dialog was last shown for, so the
  /// dialog appears once per distinct blocker (and again if it clears and
  /// a different one appears).
  String? _blockerDialogShownFor;

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
          e.type == 'accessibilityStateChanged' ||
          e.type == 'accessibilityStatus') {
        _refresh();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _shizukuPoll?.cancel();
    _wssPoll?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------ blockers

  /// The active provisioning blocker, mirroring the original's grant
  /// content: extra users block first, then a different app as owner.
  /// Accounts never block (the original only warns about them in text).
  ({String key, String title, String body})? get _blocker {
    final d = _diagnostics;
    if (_isOwner || d == null) return null;
    if (d.extraUsers.isNotEmpty) {
      final names = d.extraUsers
          .map((u) => '${u['name']} (id ${u['id']})')
          .join(', ');
      return (
        key: 'users:${d.extraUsers.map((u) => u['id']).join('/')}',
        title: 'Provisioning blocked: extra users',
        body:
            'This device has additional users or profiles: $names.\n\n'
            'Android cannot provision a Device Owner while other users '
            'exist. Remove the extra users/profiles (Settings → Users), '
            'then return here and refresh. This matches the original '
            'app, which replaces the provisioning button with this '
            'warning.',
      );
    }
    final owner = d.currentOwner;
    if (owner != null && owner['packageName'] != _ownPackage) {
      return (
        key: 'owner:${owner['packageName']}',
        title: 'Provisioning blocked: another Device Owner',
        body:
            '${owner['packageName']} is already the Device Owner of this '
            'device (${owner['receiver']}).\n\n'
            'A device can have only one Device Owner. That app must '
            'relinquish ownership (or the device must be factory-reset) '
            'before Dominanter can be provisioned. This matches the '
            'original app, which replaces the provisioning button with '
            'this warning.',
      );
    }
    return null;
  }

  void _maybeShowBlockerDialog() {
    final blocker = _blocker;
    if (blocker == null) {
      _blockerDialogShownFor = null;
      return;
    }
    if (_blockerDialogShownFor == blocker.key) return;
    _blockerDialogShownFor = blocker.key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _blocker != null) _showBlockerDialog();
    });
  }

  Future<void> _showBlockerDialog() async {
    final blocker = _blocker;
    if (blocker == null) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.block),
        title: Text(blocker.title),
        content: Text(blocker.body),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('I understand'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ refreshing

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final shizuku = await _channel.getShizukuState();
      final owner = await _channel.isDeviceOwner();
      final a11y = await _channel.isAccessibilityEnabled();
      // Diagnostics ride along with every refresh so provisioning
      // blockers are detected live, not only on demand (the manual
      // "Run diagnostics" button below refreshes the same state).
      ProvisioningDiagnostics? diagnostics = _diagnostics;
      Object? diagnosticsError;
      try {
        diagnostics = await _channel.getProvisioningDiagnostics();
      } catch (e) {
        diagnosticsError = e;
      }
      // The WRITE_SECURE_SETTINGS grant state is read passively on
      // every refresh (the native side's verified re-check, without
      // granting), so the tile reflects reality even before any Grant
      // tap this session. A failed read keeps the last verified state.
      var wssGranted = _wssGranted;
      try {
        wssGranted = await _channel.isWriteSecureSettingsGranted();
      } catch (_) {
        // Keep the last verified state.
      }
      if (mounted) {
        setState(() {
          _shizuku = shizuku;
          _isOwner = owner.isDeviceOwner;
          _isAdmin = owner.isAdminActive;
          _a11y = a11y;
          _diagnostics = diagnostics;
          _wssGranted = wssGranted;
          if (diagnosticsError != null) _diagnosticsError = diagnosticsError;
          _loading = false;
        });
        _maybeShowBlockerDialog();
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
      if (mounted) await showErrorSnackBar(context, e);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refresh();
      }
    }
  }

  // ------------------------------------------------- Shizuku polling core

  /// Polls `getShizukuState` every 500 ms — the original's cadence — until
  /// [until] accepts a state (then [onReached] runs with it) or the tick
  /// budget runs out (then a full refresh runs and [onTimeout] fires).
  void _pollShizuku({
    required bool Function(ShizukuStatus status) until,
    required void Function(ShizukuStatus status) onReached,
    required VoidCallback onTimeout,
    int maxTicks = 60,
  }) {
    _shizukuPoll?.cancel();
    _pollTicks = 0;
    _pollTickInFlight = false;
    _shizukuPoll = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_pollTickInFlight) return;
      _pollTickInFlight = true;
      _pollTicks++;
      try {
        final status = await _channel.getShizukuState();
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (until(status)) {
          timer.cancel();
          if (identical(_shizukuPoll, timer)) _shizukuPoll = null;
          onReached(status);
          return;
        }
      } catch (_) {
        // Transient channel errors while Shizuku's dialog is up must not
        // kill the wait; the tick budget still bounds it.
      } finally {
        _pollTickInFlight = false;
      }
      if (_pollTicks >= maxTicks) {
        timer.cancel();
        if (identical(_shizukuPoll, timer)) _shizukuPoll = null;
        if (mounted) {
          _refresh();
          onTimeout();
        }
      }
    });
  }

  /// The Grant fix: requesting permission only opens Shizuku's dialog.
  /// The answer is observed by polling — when the grant lands, the whole
  /// screen refreshes and provisioning unlocks with no manual step.
  Future<void> _requestPermission() async {
    setState(() => _busy = true);
    try {
      await _channel.requestShizukuPermission();
    } catch (e) {
      if (mounted) await showErrorSnackBar(context, e);
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    setState(() => _awaitingPermission = true);
    _pollShizuku(
      until: (s) => s.state == ShizukuState.granted,
      onReached: (_) {
        if (!mounted) return;
        setState(() => _awaitingPermission = false);
        showInfoSnackBar(
          context,
          'Shizuku permission granted — provisioning is unlocked.',
        );
        _refresh();
      },
      onTimeout: () {
        if (!mounted) return;
        setState(() => _awaitingPermission = false);
        showInfoSnackBar(
          context,
          'Permission not granted yet. Approve Dominanter in Shizuku, '
          'then tap Request again.',
        );
      },
    );
  }

  /// Install Shizuku, then watch for it to appear (the user returns from
  /// the store page) with the same 500 ms polling.
  Future<void> _installShizuku() async {
    setState(() => _busy = true);
    try {
      final launched = await _channel.installShizuku();
      if (mounted && !launched) {
        showInfoSnackBar(
          context,
          'No store or browser could be opened for the Shizuku page.',
        );
      }
    } catch (e) {
      if (mounted) await showErrorSnackBar(context, e);
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    setState(() => _awaitingInstall = true);
    _pollShizuku(
      until: (s) => s.state != ShizukuState.notInstalled,
      onReached: (_) {
        if (!mounted) return;
        setState(() => _awaitingInstall = false);
        showInfoSnackBar(context, 'Shizuku detected.');
        _refresh();
      },
      onTimeout: () {
        if (!mounted) return;
        setState(() => _awaitingInstall = false);
      },
    );
  }

  // ------------------------------------------- WRITE_SECURE_SETTINGS tile

  /// Grants WRITE_SECURE_SETTINGS and then keeps re-reading the verified
  /// state until it flips or a ~10 s budget runs out.
  ///
  /// Note: the poll below re-invokes `grantWriteSecureSettings` itself —
  /// the native side runs `pm grant` and verifies by re-checking
  /// `checkSelfPermission`, so re-invoking it is an idempotent re-read,
  /// not a blind repeat. (The passive display state comes from
  /// `isWriteSecureSettingsGranted`, read on every refresh.)
  Future<void> _grantWriteSecureSettings() async {
    setState(() => _wssBusy = true);
    try {
      final granted = await _channel.grantWriteSecureSettings();
      if (!mounted) return;
      if (granted) {
        setState(() {
          _wssGranted = true;
          _wssBusy = false;
        });
        showInfoSnackBar(context, 'WRITE_SECURE_SETTINGS is granted.');
        return;
      }
    } catch (e) {
      if (mounted) {
        setState(() => _wssBusy = false);
        await showErrorSnackBar(context, e);
      }
      return;
    }
    // Not granted yet (e.g. Shizuku answered slowly): poll the verified
    // re-read every 500 ms for up to ~10 s.
    _wssPoll?.cancel();
    _wssTicks = 0;
    _wssTickInFlight = false;
    _wssPoll = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_wssTickInFlight) return;
      _wssTickInFlight = true;
      _wssTicks++;
      var granted = false;
      try {
        granted = await _channel.grantWriteSecureSettings();
      } catch (_) {
        // Still unavailable (e.g. binder not ready): keep waiting within
        // the budget.
      } finally {
        _wssTickInFlight = false;
      }
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (granted) {
        timer.cancel();
        if (identical(_wssPoll, timer)) _wssPoll = null;
        setState(() {
          _wssGranted = true;
          _wssBusy = false;
        });
        showInfoSnackBar(context, 'WRITE_SECURE_SETTINGS is granted.');
        return;
      }
      if (_wssTicks >= 20) {
        timer.cancel();
        if (identical(_wssPoll, timer)) _wssPoll = null;
        setState(() {
          _wssGranted = false;
          _wssBusy = false;
        });
        showInfoSnackBar(
          context,
          'WRITE_SECURE_SETTINGS is still not granted. Shizuku must be '
          'running with permission granted first.',
        );
      }
    });
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    if (_loading && _shizuku == null) {
      return const LoadingView(message: 'Checking setup state…');
    }
    if (_error != null && _shizuku == null) {
      return ErrorView(error: _error!, onRetry: _refresh);
    }
    final shizuku = _shizuku!;
    final blocker = _blocker;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ShizukuCard(
            status: shizuku,
            busy: _busy,
            awaitingPermission: _awaitingPermission,
            awaitingInstall: _awaitingInstall,
            onRequestPermission: _requestPermission,
            onInstallShizuku: _installShizuku,
          ),
          const SizedBox(height: 12),
          GradientCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    _isOwner ? Icons.verified_user : Icons.shield_outlined,
                  ),
                  title: const Text('Device Owner'),
                  subtitle: Text(
                    _isOwner
                        ? 'Dominanter is the Device Owner of this device.'
                        : 'Not provisioned. Most restrictions need Device Owner. '
                              'Admin active: $_isAdmin.',
                  ),
                ),
                if (!_isOwner && blocker != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.block, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(blocker.title)),
                        TextButton(
                          onPressed: _showBlockerDialog,
                          child: const Text('Details'),
                        ),
                      ],
                    ),
                  ),
                if (!_isOwner &&
                    blocker == null &&
                    _diagnostics != null &&
                    _diagnostics!.accounts.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'Note: ${_diagnostics!.accounts.length} account(s) '
                      'detected. Provisioning usually still works via '
                      'Shizuku, but removing accounts first is the '
                      'original app\'s recommended path.',
                    ),
                  ),
                if (!_isOwner)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: FilledButton.icon(
                      onPressed:
                          (_busy ||
                              blocker != null ||
                              shizuku.state != ShizukuState.granted)
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
                if (blocker == null &&
                    shizuku.state != ShizukuState.granted &&
                    !_isOwner)
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
                  subtitle: Text(
                    _a11y == null
                        ? 'Unknown'
                        : _a11y!.isEnabled
                        ? (_a11y!.isServiceRunning
                              ? 'Enabled and running — enforcement is live.'
                              : 'Enabled but not yet running (binding).')
                        : 'Off. Turning it off later suspends every controlled app (anti-bypass lockdown).',
                  ),
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
                  subtitle: Text(
                    _wssGranted == true
                        ? 'Granted (verified by re-check).'
                        : 'Needed for colour modes (v1.1). Granted via '
                              'Shizuku and verified by re-check; the '
                              'state shown here is read on every refresh.',
                  ),
                  trailing: _wssGranted == true
                      ? const FilledButton.tonal(
                          onPressed: null,
                          child: Text('Granted'),
                        )
                      : FilledButton.tonal(
                          onPressed: (_busy || _wssBusy)
                              ? null
                              : _grantWriteSecureSettings,
                          child: Text(_wssBusy ? 'Granting…' : 'Grant'),
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
                    'these can block provisioning.',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            try {
                              final d = await _channel
                                  .getProvisioningDiagnostics();
                              if (mounted) {
                                setState(() {
                                  _diagnostics = d;
                                  _diagnosticsError = null;
                                });
                                _maybeShowBlockerDialog();
                              }
                            } catch (e) {
                              if (mounted) {
                                setState(() => _diagnosticsError = e);
                              }
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
                          ? friendlyError(
                              _diagnosticsError! as PrivilegedException,
                            )
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
  const _ShizukuCard({
    required this.status,
    required this.busy,
    required this.awaitingPermission,
    required this.awaitingInstall,
    required this.onRequestPermission,
    required this.onInstallShizuku,
  });
  final ShizukuStatus status;
  final bool busy;
  final bool awaitingPermission;
  final bool awaitingInstall;
  final VoidCallback onRequestPermission;
  final VoidCallback onInstallShizuku;

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
    return GradientCard(
      padding: const EdgeInsets.symmetric(vertical: 8),
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
              child: Text(
                'Diagnostic: ${status.diagnostic}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (status.state == ShizukuState.notInstalled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: FilledButton.icon(
                onPressed: (busy || awaitingInstall)
                    ? null
                    : onInstallShizuku,
                icon: const Icon(Icons.install_mobile),
                label: Text(
                  awaitingInstall
                      ? 'Waiting for Shizuku to appear…'
                      : 'Install Shizuku',
                ),
              ),
            ),
          if (status.state == ShizukuState.noPermission)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: FilledButton.icon(
                onPressed: (busy || awaitingPermission)
                    ? null
                    : onRequestPermission,
                icon: const Icon(Icons.key),
                label: Text(
                  awaitingPermission
                      ? 'Waiting for Shizuku\'s answer…'
                      : 'Request Shizuku permission',
                ),
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
          Text(
            'Accounts (${d.accounts.length})',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (d.accounts.isEmpty)
            const Text('No accounts found — good for provisioning.'),
          for (final a in d.accounts) Text('• ${a['name']} (${a['type']})'),
          const SizedBox(height: 8),
          Text(
            'Users (${d.extraUsers.length})',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (d.extraUsers.isEmpty) const Text('Only the primary user.'),
          for (final u in d.extraUsers) Text('• ${u['name']} (id ${u['id']})'),
          const SizedBox(height: 8),
          Text(
            'Current Device Owner',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            d.currentOwner == null
                ? 'None'
                : '${d.currentOwner!['packageName']} / ${d.currentOwner!['receiver']}',
          ),
        ],
      ),
    );
  }
}
