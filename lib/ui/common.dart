/// Shared UI building blocks: honest loading / empty / error states and the
/// §5.4 error-code → user copy mapping. No screen in this app shows a fake
/// success or a dead button: unavailable features are labelled, failures are
/// shown with their real code and (for shell failures) the real exit code.
library;

import 'package:flutter/material.dart';

import '../data/privileged_channel.dart';
import '../l10n/l10n.dart';
import '../theme.dart';

/// Human-readable copy for a channel failure. The raw code is always kept
/// visible in [ErrorView] so nothing is hidden behind vague wording.
String friendlyError(PrivilegedException e, AppLocalizations l10n) {
  switch (e.code) {
    case 'UNAVAILABLE':
      return l10n.errUnavailable;
    case 'SHIZUKU_NOT_INSTALLED':
      return l10n.errShizukuNotInstalled;
    case 'SHIZUKU_NOT_RUNNING':
      return l10n.errShizukuNotRunning;
    case 'SHIZUKU_NO_PERMISSION':
      return l10n.errShizukuNoPermission;
    case 'SHIZUKU_PRE_V11':
      return l10n.errShizukuPreV11;
    case 'SHIZUKU_BINDER_DEAD':
      return l10n.errShizukuBinderDead;
    case 'SHELL_FAILED':
      return e.exitCode != null
          ? l10n.errShellFailedExit(e.exitCode!)
          : l10n.errShellFailed;
    case 'PROVISIONING_FAILED':
      return l10n.errProvisioningFailed;
    case 'DPM_NOT_OWNER':
      return l10n.errDpmNotOwner;
    case 'DPM_FAILED':
      return l10n.errDpmFailed;
    case 'PACKAGE_NOT_FOUND':
      return l10n.errPackageNotFound;
    case 'PERMISSION_DENIED':
      return l10n.errPermissionDenied;
    case 'UNSUPPORTED_ANDROID':
      return l10n.errUnsupportedAndroid;
    case 'TIMEOUT':
      return l10n.errTimeout;
    case 'INVALID_ARGUMENT':
      return l10n.errInvalidArgument(e.message);
    case 'NOT_IMPLEMENTED':
      return l10n.errNotImplemented;
    default:
      return e.message;
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});
  final String? message;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(message ?? context.l10n.loadingDefault),
      ],
    ),
  );
}

class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.icon,
    required this.message,
    this.action,
  });
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
    final priv = error is PrivilegedException
        ? error as PrivilegedException
        : null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text(
              priv != null
                  ? friendlyError(priv, context.l10n)
                  : error.toString(),
              textAlign: TextAlign.center,
            ),
            if (priv != null) ...[
              const SizedBox(height: 8),
              Text(
                priv.exitCode != null
                    ? context.l10n.errorCodeExitLine(priv.code, priv.exitCode!)
                    : context.l10n.errorCodeLine(priv.code),
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
              FilledButton.tonal(
                onPressed: onRetry,
                child: Text(context.l10n.retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Hero card (redesign v2 identity, premium-minimal finish in v1.0.4):
/// one refined deep-red → black gradient in dark mode, a flat white
/// surface in light mode, a hairline border, and a single soft shadow.
/// The v2 build's glossy top highlight and red under-glow were retired
/// in the v1.0.4 polish pass — calm, flat surfaces over effects.
/// Content is unchanged; this only replaces the surface it sits on.
class GradientCard extends StatelessWidget {
  const GradientCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: heroGradient(brightness),
        // Deeply rounded, like the reference's floating red planes.
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: dark
              ? DominanterColors.red.withValues(alpha: 0.28)
              : Colors.black.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.35 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// mm:ss (or h:mm:ss) clock text for timer rings.
String formatClock(Duration d) {
  final total = d.isNegative ? Duration.zero : d;
  final h = total.inHours;
  final m = (total.inMinutes % 60).toString().padLeft(2, '0');
  final s = (total.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Large circular timer in the reference style: a thick rounded RED
/// ring (red & black only — focus burns bright red, a break dims to
/// dark red; the old blue break ring is gone) around a flat black disc
/// with a red hairline rim (the v1.0.4 polish pass removed the glow),
/// big centre numerals like the reference's «05», phase label above
/// the digits and a cycle label below. Presentation only — callers
/// drive it from the existing models.
class FocusTimerRing extends StatelessWidget {
  const FocusTimerRing({
    super.key,
    required this.progress,
    required this.remainingText,
    required this.phaseLabel,
    this.cycleLabel,
    this.isBreak = false,
    this.size = 232,
  });

  /// Fraction of the phase remaining, 0..1 (ring depletes with time).
  final double progress;
  final String remainingText;
  final String phaseLabel;
  final String? cycleLabel;
  final bool isBreak;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ringColor = isBreak
        ? DominanterColors.redDark
        : DominanterColors.redBright;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The reference's dark disc inside the chunky red ring —
          // flat fill, hairline red rim, no glow (v1.0.4 polish).
          Container(
            width: size - 26,
            height: size - 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dark ? DominanterColors.blackBackground : Colors.white,
              border: Border.all(
                color: DominanterColors.red.withValues(alpha: 0.30),
              ),
            ),
          ),
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              strokeWidth: 16,
              strokeCap: StrokeCap.round,
              color: ringColor,
              backgroundColor: scheme.surfaceContainerHighest.withValues(
                alpha: 0.55,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  phaseLabel,
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    remainingText,
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                ),
                if (cycleLabel != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    cycleLabel!,
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ],
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
    trailing: Chip(label: Text(context.l10n.chipV11)),
    enabled: false,
  );
}

Future<void> showErrorSnackBar(BuildContext context, Object error) async {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        error is PrivilegedException
            ? friendlyError(error, context.l10n)
            : error.toString(),
      ),
      backgroundColor: Theme.of(context).colorScheme.errorContainer,
      duration: const Duration(seconds: 5),
    ),
  );
}

void showInfoSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String formatMinutes(int minutes, AppLocalizations l10n) {
  if (minutes <= 0) return l10n.noLimit;
  if (minutes < 60) return l10n.minutesOnly(minutes);
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? l10n.hoursOnly(h) : l10n.hoursMinutes(h, m);
}

String formatDuration(Duration d, AppLocalizations l10n) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  if (h > 0) {
    return l10n.durationHoursMinutes(
      h.toString(),
      m.toString().padLeft(2, '0'),
    );
  }
  if (m > 0) {
    return l10n.durationMinutesSeconds(
      m.toString(),
      s.toString().padLeft(2, '0'),
    );
  }
  return l10n.durationSecondsOnly(s.toString());
}
