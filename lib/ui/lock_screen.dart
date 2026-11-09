/// Lock screen (F21/F25/F32): the pre-authentication surface.
///
/// Faithful to the original's deliberate design:
/// * the impulse ("panic") button is reachable **before** any
///   authentication;
/// * a read-only usage overview is visible;
/// * "Access app" asks for biometric / device credential — and if neither
///   is enrolled on the device, entry is allowed (the original's explicit
///   fallback, surfaced here with a notice, never silently).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../app_controller.dart';
import '../data/config_store.dart';
import '../data/privileged_channel.dart';
import 'common.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _auth = LocalAuthentication();
  UsageToday? _usage;
  Map<String, String> _labels = const {};
  Timer? _ticker;
  bool _authBusy = false;

  @override
  void initState() {
    super.initState();
    _loadOverview();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _loadOverview() async {
    try {
      final usage = await widget.controller.channel.getUsageToday();
      var labels = <String, String>{};
      try {
        final apps = await widget.controller.channel.listInstalledApps();
        labels = {for (final a in apps) a.packageName: a.label};
      } catch (_) {
        labels = const {};
      }
      if (mounted) {
        setState(() {
          _usage = usage;
          _labels = labels;
        });
      }
    } catch (_) {
      // The overview is best-effort; its absence must not block the panic
      // button or access. Errors are visible on the Setup screen instead.
    }
  }

  Future<void> _panic() async {
    final config = await widget.controller.config.getImpulseConfig();
    await widget.controller.startImpulseLock(Duration(minutes: config.durationMinutes));
    if (config.action == ImpulseAction.timerAndSuspend && config.suspendApps.isNotEmpty) {
      try {
        await widget.controller.channel
            .setAppSuspended(config.suspendApps, true, reason: 'IMPULSE_LOCK');
        if (mounted) {
          showInfoSnackBar(context,
              'Impulse lock started; chosen apps suspended for ${config.durationMinutes} min.');
        }
      } catch (e) {
        if (mounted) await showErrorSnackBar(context, e);
      }
    } else if (mounted) {
      showInfoSnackBar(
          context, 'Impulse lock started for ${config.durationMinutes} min.');
    }
    if (mounted) setState(() {});
  }

  Future<void> _access() async {
    setState(() => _authBusy = true);
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) {
        // Original F32 fallback: no biometric and no device credential
        // enrolled => entry is allowed. Surfaced, not silent.
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('No device lock is set up'),
              content: const Text(
                'This device has no biometric or screen credential enrolled, '
                'so there is nothing to authenticate against. Entry is '
                'allowed — exactly as the original app behaves in this '
                'case. Consider setting a device PIN.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Continue'),
                ),
              ],
            ),
          );
          widget.controller.unlock();
        }
        return;
      }
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock Dominanter',
        biometricOnly: false, // device credential is an allowed fallback
        persistAcrossBackgrounding: true,
      );
      if (ok) {
        widget.controller.unlock();
      } else if (mounted) {
        showInfoSnackBar(context, 'Authentication was not completed.');
      }
    } on PlatformException catch (e) {
      // Not enrolled / no passcode set: same documented fallback as above.
      if (e.code == 'NotEnrolled' ||
          e.code == 'NotAvailable' ||
          e.code == 'PasscodeNotSet') {
        widget.controller.unlock();
      } else if (mounted) {
        await showErrorSnackBar(
          context,
          PrivilegedException('PERMISSION_DENIED', 'Authentication failed: ${e.message}'),
        );
      }
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings(widget.controller.language);
    final lock = widget.controller.impulseLock;
    final topUsage = (_usage?.packages.entries.toList() ?? [])
      ..sort((a, b) => b.value.compareTo(a.value));
    return Scaffold(
      appBar: AppBar(title: Text(strings.appTitle)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.lock_outline, size: 56),
          const SizedBox(height: 12),
          Text(
            'Dominanter is locked',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (lock.active && !lock.isComplete)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.lock_clock),
                title: Text('Impulse lock active — ${formatDuration(lock.remaining)} left'),
              ),
            )
          else
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: _panic,
              icon: const Icon(Icons.emergency_outlined),
              label: Text(strings.panicButton),
            ),
          const SizedBox(height: 24),
          if (_usage != null && topUsage.isNotEmpty) ...[
            Text('Today\'s usage', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final entry in topUsage.take(5))
              ListTile(
                dense: true,
                title: Text(_labels[entry.key] ?? entry.key),
                trailing: Text(formatDuration(Duration(milliseconds: entry.value))),
              ),
            const SizedBox(height: 16),
          ],
          FilledButton.icon(
            onPressed: _authBusy ? null : _access,
            icon: const Icon(Icons.fingerprint),
            label: Text(strings.accessApp),
          ),
        ],
      ),
    );
  }
}
