/// Shared UI building blocks: honest loading / empty / error states and the
/// §5.4 error-code → user copy mapping. No screen in this app shows a fake
/// success or a dead button: unavailable features are labelled.
///
/// PLAIN-LANGUAGE ERROR RULE (v1.0.6, Phase E — user order): nothing
/// user-visible may carry exception names, error codes, exit codes,
/// stack fragments, or raw technical strings. Native failures cross
/// the channel as TYPED codes; [friendlyError] is the single mapper
/// from code to localized plain language (with a next-step hint where
/// one exists). Unmapped/unexpected failures fall back to one generic
/// friendly message. The technical detail (code, message, cause) goes
/// ONLY to the local debug log via [logTechnicalError] — never the UI.
library;

import 'dart:async';
import 'package:flutter/material.dart';

import '../data/privileged_channel.dart';
import '../domain/seal_rules.dart';
import '../l10n/l10n.dart';
import '../theme.dart';

/// The local debug log for technical error detail (Phase E): code,
/// message and cause are recorded here and NEVER shown in the UI.
void logTechnicalError(Object error) {
  if (error is PrivilegedException) {
    debugPrint(
      'AzmError code=${error.code} message=${error.message} '
      'details=${error.details}',
    );
  } else {
    debugPrint('AzmError $error');
  }
}

/// Plain-language copy for a channel failure, by typed code. Every
/// code the native layer can produce has a localized message here;
/// anything else gets the generic friendly fallback.
String friendlyError(PrivilegedException e, AppLocalizations l10n) {
  logTechnicalError(e);
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
      return l10n.errShellFailed;
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
      return l10n.errInvalidArgument;
    case 'NOT_IMPLEMENTED':
      return l10n.errNotImplemented;
    case 'SEALED':
      return l10n.errSealed;
    default:
      return l10n.errGeneric;
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
                  : context.l10n.errGeneric,
              textAlign: TextAlign.center,
            ),
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

/// Hero card: ONE flat colour per brightness (deep red in dark mode,
/// white in light mode), a hairline border, and a single soft shadow.
/// v1.0.5 (user directive) retired the last colour wash: there are no
/// gradients anywhere in the app — every surface is a single flat
/// colour from the red/black/white palette.
class HeroCard extends StatelessWidget {
  const HeroCard({
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
        color: heroSurface(brightness),
        // Deeply rounded, like the reference's floating red planes.
        borderRadius: BorderRadius.circular(AzmRadius.large),
        border: Border.all(
          color: dark
              ? AzmColors.red.withValues(alpha: 0.28)
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
        borderRadius: BorderRadius.circular(AzmRadius.large),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// A titled card grouping one set of related controls (v1.0.5 UX):
/// every settings group on every screen sits in a card under a clear
/// section title, following the Status tab's grouped pattern.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          ...children,
          const SizedBox(height: 8),
        ],
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
        ? AzmColors.redDark
        : AzmColors.redBright;
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
              color: dark ? AzmColors.blackBackground : Colors.white,
              border: Border.all(
                color: AzmColors.red.withValues(alpha: 0.30),
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

/// Presents an error as a CENTERED modal Card over a dimmed scrim
/// (v1.0.6 Phase E addendum — user order, replacing the bottom
/// snackbar): plain-language message only, an explicit OK button,
/// and no auto-dismiss — an error never vanishes before it is read.
/// High-contrast pairing in both themes: a white card with near-black
/// text in light mode, a near-black card with white text in dark
/// mode, and the palette red reserved for the title/icon accent.
/// The plain-language description of the seal that refused a removal
/// (Phase D): trigger + app + remaining time, worded identically on
/// every surface that renders a SEALED refusal.
String describeSealFromDetails(
  AppLocalizations l10n,
  Map<String, dynamic> seal,
) {
  final trigger = SealTrigger.fromNative(seal['trigger'] as String? ?? '');
  final triggerText = switch (trigger) {
    SealTrigger.appBlocked => l10n.sealTriggerAppBlocked,
    SealTrigger.appSuspended => l10n.sealTriggerAppSuspended,
    SealTrigger.focusRunning => l10n.sealTriggerFocusRunning,
    SealTrigger.visualDetection => l10n.sealTriggerVisual,
    SealTrigger.bannedWord => l10n.sealTriggerWord,
    null => l10n.errSealed,
  };
  final app = seal['packageName'] as String?;
  final rule = app == null ? triggerText : '$triggerText — $app';
  final remainingMs = (seal['remainingMs'] as num?)?.toInt();
  if (remainingMs == null) {
    return l10n.sealActiveCondition(rule);
  }
  return l10n.sealActiveTimed(
    rule,
    formatDuration(Duration(milliseconds: remainingMs), l10n),
  );
}

Future<void> showErrorCard(BuildContext context, Object error) async {
  if (!context.mounted) return;
  logTechnicalError(error);
  final l10n = context.l10n;
  final seal = error is PrivilegedException && error.isSealed
      ? error.sealDetails
      : null;
  final message = seal != null
      ? describeSealFromDetails(l10n, seal)
      : error is PrivilegedException
      ? friendlyError(error, l10n)
      : l10n.errGeneric;
  final dark = Theme.of(context).brightness == Brightness.dark;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: dark ? const Color(0xFF17171A) : Colors.white,
      icon: const Icon(
        Icons.error_outline,
        color: Color(0xFFD90429),
        size: 40,
      ),
      title: Text(
        seal != null ? l10n.sealActiveTitle : l10n.errorCardTitle,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: dark ? Colors.white : const Color(0xFF0B0B0C),
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: dark ? Colors.white : const Color(0xFF0B0B0C),
          fontSize: 16,
          height: 1.45,
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.okButton),
        ),
      ],
    ),
  );
}

void showInfoSnackBar(BuildContext context, String message) {
  // Same mounted guard as showErrorCard (v1.0.5 audit C-L3):
  // callers invoke this after awaits, when the context may be gone.
  // Short confirmations stay lightweight, but at the same contrast
  // bar (Phase E addendum): near-black background, white text, in
  // both themes.
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: const Color(0xFF101013),
    ),
  );
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

/// Centred confirmation card before ANY delete (Batch B / Audit Item 6):
/// displays a centred card with a red destructive action, a clear statement
/// of what will be deleted, and explicit confirm and cancel actions.
/// Always invoked BEFORE any recovery gate (runLoosening).
Future<bool> showDestructiveConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmText,
  String? cancelText,
  IconData icon = Icons.delete_outline,
}) async {
  if (!context.mounted) return false;
  final l10n = context.l10n;
  final dark = Theme.of(context).brightness == Brightness.dark;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: dark ? const Color(0xFF17171A) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AzmRadius.large),
      ),
      icon: Icon(
        icon,
        color: AzmColors.red,
        size: 40,
      ),
      title: Text(
        title,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: dark ? Colors.white : const Color(0xFF0B0B0C),
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: dark ? Colors.white : const Color(0xFF0B0B0C),
          fontSize: 16,
          height: 1.45,
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(cancelText ?? l10n.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AzmColors.red,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmText ?? l10n.deleteGroup),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Shared app picker with search + system-apps toggle (Batch B / Audit Item 10).
/// Reuses the Apps-tab pattern verbatim (apps_tab.dart ~85-100):
/// pill search field + includeSystemApps toggle as suffixIcon
/// (Icons.filter_alt filled when on, filter_alt_outlined when off),
/// ListView.builder, and debounced search by name or package.
Future<Set<String>?> showAppPicker({
  required BuildContext context,
  required PrivilegedChannel channel,
  String? title,
  Set<String> initialSelected = const {},
  bool singleSelect = false,
  List<InstalledApp>? preloadedApps,
}) async {
  if (!context.mounted) return null;
  return showDialog<Set<String>>(
    context: context,
    builder: (dialogContext) => _AppPickerDialog(
      channel: channel,
      title: title,
      initialSelected: initialSelected,
      singleSelect: singleSelect,
      preloadedApps: preloadedApps,
    ),
  );
}

class _AppPickerDialog extends StatefulWidget {
  const _AppPickerDialog({
    required this.channel,
    this.title,
    required this.initialSelected,
    required this.singleSelect,
    this.preloadedApps,
  });

  final PrivilegedChannel channel;
  final String? title;
  final Set<String> initialSelected;
  final bool singleSelect;
  final List<InstalledApp>? preloadedApps;

  @override
  State<_AppPickerDialog> createState() => _AppPickerDialogState();
}

class _AppPickerDialogState extends State<_AppPickerDialog> {
  late Set<String> _selected;
  bool _includeSystem = false;
  String _query = '';
  List<InstalledApp>? _apps;
  Object? _error;
  bool _loading = true;
  Timer? _debounce;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initialSelected);
    if (widget.preloadedApps != null && !_includeSystem) {
      _apps = widget.preloadedApps;
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final apps = await widget.channel.listInstalledApps(
        includeSystem: _includeSystem,
      );
      if (mounted) {
        setState(() {
          _apps = apps;
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

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) {
        setState(() => _query = value);
      }
    });
  }

  List<InstalledApp> get _filtered {
    final apps = (_apps ?? const [])
        .where((a) => _includeSystem || !a.isSystem);
    if (_query.trim().isEmpty) return apps.toList();
    final q = _query.trim().toLowerCase();
    return apps
        .where(
          (a) =>
              a.label.toLowerCase().contains(q) ||
              a.packageName.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filtered;

    return AlertDialog(
      backgroundColor: dark ? const Color(0xFF17171A) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AzmRadius.large),
      ),
      title: Text(
        widget.title ?? l10n.searchApps,
        style: TextStyle(
          color: dark ? Colors.white : const Color(0xFF0B0B0C),
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SizedBox(
        width: 380,
        height: 480,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_outlined),
                  suffixIcon: IconButton(
                    tooltip: l10n.includeSystemApps,
                    icon: Icon(
                      _includeSystem
                          ? Icons.filter_alt
                          : Icons.filter_alt_outlined,
                      color: _includeSystem
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    onPressed: () {
                      setState(() => _includeSystem = !_includeSystem);
                      if (widget.preloadedApps == null) {
                        _load();
                      }
                    },
                  ),
                  labelText: l10n.searchApps,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: _onQueryChanged,
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Text(
                            _error is PrivilegedException
                                ? friendlyError(_error as PrivilegedException, l10n)
                                : l10n.errGeneric,
                          ),
                        )
                      : filtered.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Text(
                                  l10n.noAppsMatch,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.outline,
                                  ),
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final app = filtered[index];
                                final isSelected = _selected.contains(app.packageName);
                                if (widget.singleSelect) {
                                  return ListTile(
                                    title: Text(app.label),
                                    subtitle: Text(app.packageName),
                                    trailing: isSelected
                                        ? const Icon(
                                            Icons.check_circle_outlined,
                                            color: AzmColors.red,
                                          )
                                        : null,
                                    onTap: () {
                                      Navigator.of(context).pop({app.packageName});
                                    },
                                  );
                                }
                                return CheckboxListTile(
                                  title: Text(app.label),
                                  subtitle: Text(app.packageName),
                                  value: isSelected,
                                  activeColor: AzmColors.red,
                                  onChanged: (v) {
                                    setState(() {
                                      if (v == true) {
                                        _selected.add(app.packageName);
                                      } else {
                                        _selected.remove(app.packageName);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(l10n.cancel),
        ),
        if (!widget.singleSelect)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_selected),
            child: Text(l10n.save),
          ),
      ],
    );
  }
}
