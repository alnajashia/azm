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
import '../domain/seal_rules.dart';
import '../l10n/l10n.dart';
import 'common.dart';
import 'recovery_ui.dart';

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

  /// Currently-holding SEAL rules (Phase D), refreshed with the tab.
  List<ActiveSeal> _activeSeals = const [];

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
    // context.l10n never throws (it falls back to English strings when
    // no localization delegate is installed, e.g. in bare widget tests).
    final l10n = context.l10n;
    if (d.extraUsers.isNotEmpty) {
      final names = d.extraUsers
          .map((u) => '${u['name']} (id ${u['id']})')
          .join(', ');
      return (
        key: 'users:${d.extraUsers.map((u) => u['id']).join('/')}',
        title: l10n.blockerExtraUsersTitle,
        body: l10n.blockerExtraUsersBody(names),
      );
    }
    final owner = d.currentOwner;
    if (owner != null && owner['packageName'] != _ownPackage) {
      return (
        key: 'owner:${owner['packageName']}',
        title: l10n.blockerOtherOwnerTitle,
        body: l10n.blockerOtherOwnerBody(
          '${owner['packageName']}',
          '${owner['receiver']}',
        ),
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
        icon: const Icon(Icons.block_outlined),
        title: Text(blocker.title),
        content: Text(blocker.body),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.iUnderstand),
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
      // Active SEAL rules ride along with every refresh (Phase D):
      // the Status tab surfaces a holding seal with its remaining
      // time. A failed probe keeps the last known state.
      var activeSeals = _activeSeals;
      try {
        activeSeals = [
          for (final m in await _channel.getActiveSeals())
            if (ActiveSeal.fromMap(m) case final s?) s,
        ];
      } catch (_) {
        // Keep the last known state.
      }
      if (mounted) {
        setState(() {
          _shizuku = shizuku;
          _isOwner = owner.isDeviceOwner;
          _isAdmin = owner.isAdminActive;
          _a11y = a11y;
          _diagnostics = diagnostics;
          _wssGranted = wssGranted;
          _activeSeals = activeSeals;
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
      if (mounted) await showErrorCard(context, e);
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
      if (mounted) await showErrorCard(context, e);
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
          context.l10n.shizukuPermissionGrantedMsg,
        );
        _refresh();
      },
      onTimeout: () {
        if (!mounted) return;
        setState(() => _awaitingPermission = false);
        showInfoSnackBar(
          context,
          context.l10n.permissionNotGrantedYetMsg,
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
          context.l10n.noStoreMsg,
        );
      }
    } catch (e) {
      if (mounted) await showErrorCard(context, e);
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
        showInfoSnackBar(context, context.l10n.shizukuDetectedMsg);
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
    // Granting a privilege is recovery-gated (user security directive,
    // v1.0.4 audit): the paper code session must be active first. The
    // poll below re-invokes the channel method directly, so this gate
    // runs exactly once per user tap.
    if (!await ensureRecoverySession(context, widget.controller)) return;
    if (!mounted) return;
    setState(() => _wssBusy = true);
    try {
      final granted = await _channel.grantWriteSecureSettings();
      if (!mounted) return;
      if (granted) {
        setState(() {
          _wssGranted = true;
          _wssBusy = false;
        });
        showInfoSnackBar(context, context.l10n.wssGrantedMsg);
        return;
      }
    } catch (e) {
      if (mounted) {
        setState(() => _wssBusy = false);
        await showErrorCard(context, e);
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
        showInfoSnackBar(context, context.l10n.wssGrantedMsg);
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
          context.l10n.wssStillNotGrantedMsg,
        );
      }
    });
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    if (_loading && _shizuku == null) {
      return LoadingView(message: context.l10n.checkingSetupState);
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
          if (_activeSeals.isNotEmpty) ...[
            SectionCard(
              title: context.l10n.sealActiveTitle,
              children: [
                for (final seal in _activeSeals)
                  ListTile(
                    leading: const Icon(Icons.lock_outlined),
                    title: Text(
                      describeSealFromDetails(
                        context.l10n,
                        seal.toDetails(),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          HeroCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    _isOwner ? Icons.verified_user_outlined : Icons.shield_outlined,
                  ),
                  title: Text(context.l10n.deviceOwnerTitle),
                  subtitle: Text(
                    _isOwner
                        ? context.l10n.deviceOwnerYes
                        : context.l10n.deviceOwnerNo('$_isAdmin'),
                  ),
                ),
                if (!_isOwner && blocker != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.block_outlined, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(blocker.title)),
                        TextButton(
                          onPressed: _showBlockerDialog,
                          child: Text(context.l10n.details),
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
                      context.l10n.accountsNote(_diagnostics!.accounts.length),
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
                          : () async {
                              // Granting Device Owner is the app's
                              // biggest privilege grant — recovery-gated
                              // (user security directive, v1.0.4 audit).
                              // The setup wizard has already issued and
                              // confirmed the paper code by the time this
                              // screen is reachable, so the code exists
                              // before the privilege does.
                              if (!await ensureRecoverySession(
                                  context, widget.controller)) {
                                return;
                              }
                              if (!mounted) return;
                              await _run(() async {
                              final r = await _channel.provisionDeviceOwner();
                              if (mounted) {
                                setState(() {
                                  _provisionOutput = context.l10n
                                      .provisionOutput(
                                        '${r['pathUsed']}',
                                        '${r['commandOutput'] ?? ''}',
                                      );
                                });
                              }
                              });
                            },
                      icon: const Icon(Icons.admin_panel_settings_outlined),
                      label: Text(context.l10n.becomeDeviceOwner),
                    ),
                  ),
                if (blocker == null &&
                    shizuku.state != ShizukuState.granted &&
                    !_isOwner)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text(context.l10n.provisioningUnlocksNote),
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
          // v1.0.5 audit C-M4 (fix-#3 completion): titled card, like
          // every other group in the app.
          SectionCard(
            title: context.l10n.setupServicesSection,
            children: [
                SwitchListTile(
                  secondary: const Icon(Icons.accessibility_new_outlined),
                  title: Text(context.l10n.accessibilityService),
                  subtitle: Text(
                    _a11y == null
                        ? context.l10n.a11yUnknown
                        : _a11y!.isEnabled
                        ? (_a11y!.isServiceRunning
                              ? context.l10n.a11yRunning
                              : context.l10n.a11yBinding)
                        : context.l10n.a11yOff,
                  ),
                  value: _a11y?.isEnabled ?? false,
                  onChanged: _busy
                      ? null
                      : (v) => _run(() async {
                          // ENABLING the service grants a privilege —
                          // recovery-gated (user security directive,
                          // v1.0.4 audit). DISABLING stays ungated: it
                          // triggers the F28 lockdown, the protective
                          // direction.
                          if (v &&
                              !await ensureRecoverySession(
                                  context, widget.controller)) {
                            return;
                          }
                          await _channel.setAccessibilityEnabled(v);
                        }),
                ),
                ListTile(
                  leading: const Icon(Icons.key_outlined),
                  // Plain-language title (v1.0.4 UX pass): what the
                  // permission is FOR, with the technical name kept in
                  // the subtitle (wssPurpose names WRITE_SECURE_SETTINGS).
                  title: Text(context.l10n.wssTitle),
                  subtitle: Text(
                    _wssGranted == true
                        ? context.l10n.wssGrantedText
                        : context.l10n.wssPurpose,
                  ),
                  trailing: _wssGranted == true
                      ? FilledButton.tonal(
                          onPressed: null,
                          child: Text(context.l10n.granted),
                        )
                      : FilledButton.tonal(
                          onPressed: (_busy || _wssBusy)
                              ? null
                              : _grantWriteSecureSettings,
                          child: Text(
                            _wssBusy
                                ? context.l10n.granting
                                : context.l10n.grant,
                          ),
                        ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Titled card (audit C-M4): the section title moves into the
          // card header; the subtitle stays as body text.
          SectionCard(
            title: context.l10n.diagnosticsTitle,
            children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(context.l10n.diagnosticsSubtitle),
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
                    child: Text(context.l10n.runDiagnostics),
                  ),
                ),
                if (_diagnosticsError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text(
                      _diagnosticsError is PrivilegedException
                          ? friendlyError(
                              _diagnosticsError! as PrivilegedException,
                              context.l10n,
                            )
                          : _diagnosticsError.toString(),
                    ),
                  ),
                if (_diagnostics != null) _DiagnosticsView(d: _diagnostics!),
            ],
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
    final l10n = context.l10n;
    final (icon, title, body) = switch (status.state) {
      ShizukuState.notInstalled => (
        Icons.block_outlined,
        l10n.shizukuNotInstalledTitle,
        l10n.shizukuNotInstalledBody,
      ),
      ShizukuState.notRunning => (
        Icons.power_off_outlined,
        l10n.shizukuNotRunningTitle,
        l10n.shizukuNotRunningBody,
      ),
      ShizukuState.preV11 => (
        Icons.update_outlined,
        l10n.shizukuPreV11Title,
        l10n.shizukuPreV11Body,
      ),
      ShizukuState.noPermission => (
        Icons.lock_outline,
        l10n.shizukuNoPermissionTitle,
        l10n.shizukuNoPermissionBody,
      ),
      ShizukuState.granted => (
        Icons.check_circle_outlined,
        l10n.shizukuGrantedTitle,
        l10n.shizukuGrantedBody,
      ),
      ShizukuState.unknown => (
        Icons.help_outline,
        l10n.shizukuUnknownTitle,
        l10n.shizukuUnknownBody,
      ),
    };
    return HeroCard(
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
                l10n.serverVersionLine(
                  status.serverVersion!,
                  status.serverUid ?? 0,
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (status.diagnostic != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                l10n.diagnosticLine(status.diagnostic!),
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
                icon: const Icon(Icons.install_mobile_outlined),
                label: Text(
                  awaitingInstall
                      ? l10n.waitingShizukuAppear
                      : l10n.installShizuku,
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
                icon: const Icon(Icons.key_outlined),
                label: Text(
                  awaitingPermission
                      ? l10n.waitingShizukuAnswer
                      : l10n.requestShizukuPermission,
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
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.diagAccounts(d.accounts.length),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (d.accounts.isEmpty) Text(l10n.diagNoAccounts),
          for (final a in d.accounts) Text('• ${a['name']} (${a['type']})'),
          const SizedBox(height: 8),
          Text(
            l10n.diagUsers(d.extraUsers.length),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (d.extraUsers.isEmpty) Text(l10n.diagOnlyPrimaryUser),
          for (final u in d.extraUsers) Text('• ${u['name']} (id ${u['id']})'),
          const SizedBox(height: 8),
          Text(
            l10n.diagCurrentOwner,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            d.currentOwner == null
                ? l10n.diagNone
                : '${d.currentOwner!['packageName']} / ${d.currentOwner!['receiver']}',
          ),
        ],
      ),
    );
  }
}
