/// Shared UI building blocks: honest loading / empty / error states and the
/// §5.4 error-code → user copy mapping. No screen in this app shows a fake
/// success or a dead button: unavailable features are labelled, failures are
/// shown with their real code and (for shell failures) the real exit code.
library;

import 'package:flutter/material.dart';

import '../data/privileged_channel.dart';

/// Human-readable copy for a channel failure. The raw code is always kept
/// visible in [ErrorView] so nothing is hidden behind vague wording.
String friendlyError(PrivilegedException e) {
  switch (e.code) {
    case 'UNAVAILABLE':
      return 'The Android service layer is not available here (this happens '
          'in tests or off-device). No operation was performed.';
    case 'SHIZUKU_NOT_INSTALLED':
      return 'Shizuku is not installed on this device.';
    case 'SHIZUKU_NOT_RUNNING':
      return 'Shizuku is installed but its server is not running. Start it '
          'from the Shizuku app, then retry.';
    case 'SHIZUKU_NO_PERMISSION':
      return 'Shizuku permission has not been granted to Dominanter.';
    case 'SHIZUKU_PRE_V11':
      return 'This Shizuku server is older than v11. Update Shizuku, then retry.';
    case 'SHIZUKU_BINDER_DEAD':
      return 'The Shizuku connection dropped during the operation. Its '
          'outcome is unknown — check the current state before retrying.';
    case 'SHELL_FAILED':
      return 'A system command failed${e.exitCode != null ? ' (exit code ${e.exitCode})' : ''}.';
    case 'PROVISIONING_FAILED':
      return 'Device Owner provisioning failed on both the direct and the '
          'fallback path. See Diagnostics on the Setup screen.';
    case 'DPM_NOT_OWNER':
      return 'Dominanter is not the Device Owner, so this operation is not '
          'available. Complete Setup first.';
    case 'DPM_FAILED':
      return 'The system refused or could not verify this change. Nothing '
          'was reported as successful.';
    case 'PACKAGE_NOT_FOUND':
      return 'That app is not installed on this device.';
    case 'PERMISSION_DENIED':
      return 'A required permission is not granted.';
    case 'UNSUPPORTED_ANDROID':
      return 'This Android version does not support this operation.';
    case 'TIMEOUT':
      return 'The operation timed out and was not reported as successful.';
    case 'INVALID_ARGUMENT':
      return 'Invalid input: ${e.message}';
    case 'NOT_IMPLEMENTED':
      return 'This is not implemented in this version.';
    default:
      return e.message;
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message = 'Loading…'});
  final String message;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message),
          ],
        ),
      );
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.message, this.action});
  final IconData icon;
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final priv = error is PrivilegedException ? error as PrivilegedException : null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text(
              priv != null ? friendlyError(priv) : error.toString(),
              textAlign: TextAlign.center,
            ),
            if (priv != null) ...[
              const SizedBox(height: 8),
              Text(
                'Error code: ${priv.code}'
                '${priv.exitCode != null ? ' · exit ${priv.exitCode}' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              if (priv.stderr != null && priv.stderr!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    priv.stderr!,
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

/// A labelled "not in this version" row — used instead of fake controls for
/// v1.1 features (ARCH §6).
class UnavailableTile extends StatelessWidget {
  const UnavailableTile({
    super.key,
    required this.icon,
    required this.title,
    required this.note,
  });
  final IconData icon;
  final String title;
  final String note;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.outline),
        title: Text(title),
        subtitle: Text(note),
        trailing: const Chip(label: Text('v1.1')),
        enabled: false,
      );
}

Future<void> showErrorSnackBar(BuildContext context, Object error) async {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        error is PrivilegedException ? friendlyError(error) : error.toString(),
      ),
      backgroundColor: Theme.of(context).colorScheme.errorContainer,
      duration: const Duration(seconds: 5),
    ),
  );
}

void showInfoSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String formatMinutes(int minutes) {
  if (minutes <= 0) return 'No limit';
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

String formatDuration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
  if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
  return '${s}s';
}

/// Minimal en/pt strings for the app chrome (F33). Full per-screen
/// translation is partial in v1 — this class covers navigation, the lock
/// screen, and primary actions; it is the single place strings live so the
/// remaining screens can be migrated incrementally.
class AppStrings {
  const AppStrings(this.language);
  final String language;
  bool get isPt => language == 'pt';

  String get appTitle => 'Dominanter';
  String get tabStatus => isPt ? 'Estado' : 'Status';
  String get tabRestrictions => isPt ? 'Restrições' : 'Restrictions';
  String get tabApps => isPt ? 'Apps' : 'Apps';
  String get tabConfig => isPt ? 'Config.' : 'Config';
  String get accessApp => isPt ? 'Aceder à app' : 'Access app';
  String get panicButton => isPt ? 'Estou com impulsos' : "I'm having impulses";
  String get sessionRemaining => isPt ? 'Sessão de recuperação' : 'Recovery session';
  String get renewSession => isPt ? 'Renovar' : 'Renew';
  String get endSession => isPt ? 'Terminar sessão' : 'End session';
}
