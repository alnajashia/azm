/// Colour-modes screen (Batch C, C3 — GRAYSCALE_RESEARCH.md §8.2).
///
/// One screen for all four modes (grayscale first): master switch,
/// per-mode on/off, windows (empty = always on while enabled),
/// per-mode scope (whole device / all except / only these apps),
/// night-light temperature + intensity, extra-dim level, and the
/// `apply_during_focus` switch under grayscale.
///
/// The lock lives in Kotlin: a change that loosens a locked mode
/// returns `{ok: false, locked: true, lockedModes: [...]}` and writes
/// nothing. This screen answers that with a dialog offering the
/// recovery gate as the way through, then retries. Status refreshes
/// every 15 seconds while the screen is open.
///
/// Enabling the feature needs two things the app cannot grant
/// itself: the accessibility service running, and the
/// WRITE_SECURE_SETTINGS grant (via the Shizuku provisioning path).
/// Both are offered in place before the master switch turns on.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/privileged_channel.dart';
import '../domain/colour_modes.dart';
import '../l10n/l10n.dart';
import 'apps_tab.dart';
import 'common.dart';
import 'recovery_ui.dart';

class ColourModesScreen extends StatefulWidget {
  const ColourModesScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<ColourModesScreen> createState() => _ColourModesScreenState();
}

class _ColourModesScreenState extends State<ColourModesScreen> {
  ColourModesConfig? _config;
  ColourModesStatus? _status;
  List<InstalledApp>? _apps;
  Object? _error;
  bool _busy = false;
  Timer? _statusTimer;

  // Slider drafts: update locally while dragging, save on release,
  // so a drag does not hammer the channel with a save per tick.
  int? _intensityDraft;
  int? _dimDraft;

  @override
  void initState() {
    super.initState();
    _load();
    _statusTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshStatus(),
    );
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final config = await widget.controller.channel.getColourModesConfig();
      final status = await widget.controller.channel.getColourModesStatus();
      List<InstalledApp> apps = const [];
      try {
        apps = await widget.controller.channel.listInstalledApps();
      } catch (_) {
        // App labels degrade to package names in the scope pickers.
      }
      if (mounted) {
        setState(() {
          _config = config;
          _status = status;
          _apps = apps;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<ColourModesStatus?> _refreshStatus() async {
    try {
      final status = await widget.controller.channel.getColourModesStatus();
      if (mounted) setState(() => _status = status);
      return status;
    } catch (_) {
      // Keep the last known status; a transient failure must not
      // clobber the screen every 15 seconds.
      return _status;
    }
  }

  String _modeName(ColourMode mode, AppLocalizations l10n) => switch (mode) {
    ColourMode.grayscale => l10n.colourModeGrayscale,
    ColourMode.nightLight => l10n.colourModeNightLight,
    ColourMode.extraDim => l10n.colourModeExtraDim,
    ColourMode.inversion => l10n.colourModeInversion,
  };

  String _modeDescription(ColourMode mode, AppLocalizations l10n) =>
      switch (mode) {
        ColourMode.grayscale => l10n.colourModeGrayscaleDesc,
        ColourMode.nightLight => l10n.colourModeNightLightDesc,
        ColourMode.extraDim => l10n.colourModeExtraDimDesc,
        ColourMode.inversion => l10n.colourModeInversionDesc,
      };

  String _scopeName(ColourScope scope, AppLocalizations l10n) =>
      switch (scope) {
        ColourScope.device => l10n.colourScopeDevice,
        ColourScope.exceptApps => l10n.colourScopeExceptApps,
        ColourScope.onlyApps => l10n.colourScopeOnlyApps,
      };

  Future<void> _save(ColourModesConfig next) async {
    // v1.0.1: a change that ADDS enforcement (enabling the feature
    // or switching a mode on) first makes sure the accessibility
    // service is running and WRITE_SECURE_SETTINGS is granted —
    // per-mode toggles used to save with no such check, and the
    // sync below then failed silently, leaving the toggle on with
    // nothing applied on the device.
    final current = _config;
    final addsEnforcement = next.enabled &&
        (current == null ||
            !current.enabled ||
            next.modes.difference(current.modes).isNotEmpty);
    if (addsEnforcement && !await _ensurePrerequisites()) return;
    setState(() => _busy = true);
    try {
      final result = await widget.controller.channel.setColourModesConfig(next);
      if (!mounted) return;
      if (!result.ok) {
        await _showLockedDialog(next, result.lockedModes);
        return;
      }
      setState(() => _config = next);
      // v1.0.1: the sync result used to be ignored — when the
      // service is not running it returns false and nothing is
      // applied. Say so honestly instead of showing the toggle on.
      final synced = await widget.controller.channel.syncColourModes();
      if (!synced && next.enabled && next.modes.isNotEmpty && mounted) {
        showInfoSnackBar(
          context,
          context.l10n.colourModesStatusNoAccessibility,
        );
      }
      await _refreshStatus();
    } catch (e) {
      if (mounted) await showErrorCard(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Makes sure the accessibility service is running and
  /// WRITE_SECURE_SETTINGS is granted before anything is enforced.
  /// Returns false when the user declines or the prerequisites
  /// still are not met. Shared by the master toggle and [_save].
  Future<bool> _ensurePrerequisites() async {
    var status = await _refreshStatus();
    if (status == null || !mounted) return false;
    if (!status.accessibilityServiceEnabled) {
      final enable = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(dialogContext.l10n.colourModesNeedAccessibilityTitle),
          content: Text(
            dialogContext.l10n.colourModesNeedAccessibility,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(dialogContext.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(dialogContext.l10n.enableAccessibility),
            ),
          ],
        ),
      );
      if (enable != true || !mounted) return false;
      try {
        await widget.controller.channel.setAccessibilityEnabled(true);
      } catch (e) {
        if (mounted) await showErrorCard(context, e);
        return false;
      }
      status = await _refreshStatus();
      if (status == null || !status.accessibilityServiceEnabled) {
        if (mounted) {
          showInfoSnackBar(context, context.l10n.accessibilityStillDisabled);
        }
        return false;
      }
    }
    if (!status.writeSecureSettingsGranted) {
      try {
        final granted =
            await widget.controller.channel.grantWriteSecureSettings();
        if (!granted) {
          if (mounted) {
            showInfoSnackBar(
              context,
              context.l10n.secureSettingsGrantFailed,
            );
          }
          return false;
        }
      } catch (e) {
        if (mounted) await showErrorCard(context, e);
        return false;
      }
      await _refreshStatus();
    }
    return true;
  }

  /// A locked change: explain, offer the recovery gate, retry after
  /// it. The native session opens every lock for 10 minutes.
  Future<void> _showLockedDialog(
    ColourModesConfig next,
    Set<ColourMode> lockedModes,
  ) async {
    final l10n = context.l10n;
    final names = lockedModes.map((m) => _modeName(m, l10n)).join(', ');
    final openGate = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.lock_outline),
        title: Text(dialogContext.l10n.colourModesLockedTitle),
        content: Text(
          dialogContext.l10n.colourModesLockedMessage(names),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.l10n.openRecoveryGate),
          ),
        ],
      ),
    );
    if (openGate != true || !mounted) return;
    if (await ensureRecoverySession(context, widget.controller)) {
      await _save(next);
    }
  }

  Future<void> _toggleEnabled(bool value) async {
    final config = _config;
    if (config == null) return;
    // Turning on is gated inside _save (prerequisites); turning
    // off must always work, even with the service down.
    await _save(config.copyWith(enabled: value));
  }

  Future<void> _toggleMode(ColourMode mode, bool selected) async {
    final config = _config;
    if (config == null) return;
    final modes = {...config.modes};
    if (selected) {
      modes.add(mode);
    } else {
      modes.remove(mode);
    }
    await _save(config.copyWith(modes: modes));
  }

  Future<void> _editWindows(ColourMode mode) async {
    final config = _config;
    if (config == null) return;
    final result = await showDialog<List<TimeWindowModel>>(
      context: context,
      builder: (_) => TimeWindowsEditor(windows: config.windowsFor(mode)),
    );
    if (result == null || !mounted) return;
    final windows = Map<ColourMode, List<TimeWindowModel>>.of(config.windows);
    windows[mode] = result;
    await _save(config.copyWith(windows: windows));
  }

  Future<void> _changeScope(ColourMode mode, ColourScope scope) async {
    final config = _config;
    if (config == null) return;
    final scopes = Map<ColourMode, ColourScope>.of(config.scopes);
    scopes[mode] = scope;
    await _save(config.copyWith(scopes: scopes));
  }

  Future<void> _pickScopeApps(ColourMode mode) async {
    final config = _config;
    if (config == null) return;
    final scope = config.scopeFor(mode);
    if (scope == ColourScope.device) return;
    final initial = scope == ColourScope.exceptApps
        ? (config.excludedApps[mode] ?? const <String>{})
        : (config.onlyApps[mode] ?? const <String>{});
    final picked = await showAppPicker(
      context: context,
      channel: widget.controller.channel,
      title: context.l10n.colourScopeAppsTitle(_modeName(mode, context.l10n)),
      initialSelected: initial,
      preloadedApps: _apps,
    );
    if (picked == null || !mounted) return;
    if (scope == ColourScope.exceptApps) {
      final excluded = Map<ColourMode, Set<String>>.of(config.excludedApps);
      excluded[mode] = picked;
      await _save(config.copyWith(excludedApps: excluded));
    } else {
      final only = Map<ColourMode, Set<String>>.of(config.onlyApps);
      only[mode] = picked;
      await _save(config.copyWith(onlyApps: only));
    }
  }

  String _formatMinute(int minute) {
    final h = minute ~/ 60;
    final m = minute % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String _windowsSummary(ColourMode mode, AppLocalizations l10n) {
    final windows = _config?.windowsFor(mode) ?? const [];
    if (windows.isEmpty) return l10n.colourWindowsAlways;
    return windows.map((w) => w.formatted).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final config = _config;
    final status = _status;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.colourModes)),
      body: config == null || status == null
          ? (_error != null
                ? ErrorView(error: _error!, onRetry: _load)
                : LoadingView(message: l10n.loading))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(l10n.colourModesDescription),
                const SizedBox(height: 12),
                _buildStatusCard(l10n, config, status),
                const SizedBox(height: 12),
                SectionCard(
                  title: l10n.colourModesEnableTitle,
                  children: [
                    SwitchListTile(
                      title: Text(l10n.colourModesEnable),
                      value: config.enabled,
                      onChanged: _busy ? null : _toggleEnabled,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final mode in ColourMode.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildModeCard(l10n, config, status, mode),
                  ),
              ],
            ),
    );
  }

  Widget _buildStatusCard(
    AppLocalizations l10n,
    ColourModesConfig config,
    ColourModesStatus status,
  ) {
    final scheme = Theme.of(context).colorScheme;
    Widget row(IconData icon, String text, {bool warn = false}) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: warn ? scheme.error : scheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
    return SectionCard(
      title: l10n.colourModesStatusTitle,
      children: [
        if (!status.accessibilityServiceEnabled)
          row(
            Icons.accessibility_new_outlined,
            l10n.colourModesStatusNoAccessibility,
            warn: true,
          )
        else if (!status.writeSecureSettingsGranted)
          row(
            Icons.security_outlined,
            l10n.colourModesStatusNoGrant,
            warn: true,
          )
        else if (!status.grayscaleSupported)
          row(
            Icons.warning_amber_outlined,
            l10n.colourModesStatusUnsupported,
            warn: true,
          )
        else if (config.enabled && status.appliedModes.isNotEmpty)
          row(
            Icons.check_circle_outline,
            l10n.colourModesStatusActive(
              status.appliedModes.map((m) => _modeName(m, l10n)).join(', '),
            ),
          )
        else if (config.enabled)
          row(Icons.schedule_outlined, l10n.colourModesStatusIdle)
        else
          row(Icons.circle_outlined, l10n.colourModesStatusOff),
        // Batch G, item 4: a rejected write must be visible, not
        // hidden behind a toggle that shows ON.
        if (status.failedKeys.isNotEmpty)
          row(
            Icons.warning_amber_outlined,
            l10n.colourModesStatusVerifyFailed(
              status.failedModes.map((m) => _modeName(m, l10n)).join(', '),
            ),
            warn: true,
          ),
      ],
    );
  }

  Widget _buildModeCard(
    AppLocalizations l10n,
    ColourModesConfig config,
    ColourModesStatus status,
    ColourMode mode,
  ) {
    final unavailable =
        mode == ColourMode.extraDim && !status.extraDimAvailable;
    final selected = config.modes.contains(mode);
    final locked = status.isLocked(mode);
    final activeWindow = status.activeWindowFor(mode);
    final scope = config.scopeFor(mode);
    final scopeApps = scope == ColourScope.exceptApps
        ? (config.excludedApps[mode] ?? const <String>{})
        : scope == ColourScope.onlyApps
        ? (config.onlyApps[mode] ?? const <String>{})
        : const <String>{};
    return SectionCard(
      title: _modeName(mode, l10n),
      children: [
        SwitchListTile(
          title: Text(_modeDescription(mode, l10n)),
          value: selected,
          onChanged: _busy || unavailable || !config.enabled
              ? null
              : (v) => _toggleMode(mode, v),
        ),
        if (unavailable)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              l10n.colourModeExtraDimUnavailable,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (locked)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.lock_outline, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    activeWindow != null
                        ? l10n.colourModeLockedUntil(
                            _formatMinute(activeWindow.window.endMinute),
                          )
                        : l10n.colourModeLockedActive,
                  ),
                ),
              ],
            ),
          ),
        if (selected && config.enabled) ...[
          if (mode == ColourMode.nightLight) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(l10n.nightLightTemperature),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final t in ColourModesConfig.nightLightTemperatures)
                    ChoiceChip(
                      label: Text('$t K'),
                      selected: config.nightLightTemperature == t,
                      onSelected: _busy
                          ? null
                          : (v) {
                              if (v) {
                                _save(
                                  config.copyWith(nightLightTemperature: t),
                                );
                              }
                            },
                    ),
                ],
              ),
            ),
            if (!status.platformNightLight) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  l10n.nightLightIntensity(
                    _intensityDraft ?? config.nightLightIntensity,
                  ),
                ),
              ),
              // v1.0.1: sliders are LTR even in the Arabic UI, so the
              // value always rises left-to-right with the number above
              // it. (In RTL the slider mirrors and the right end is
              // the minimum — the user dragged it right expecting
              // maximum and got level 0, i.e. no dimming at all.)
              Directionality(
                textDirection: TextDirection.ltr,
                child: Slider(
                  min: 0,
                  max: ColourModesConfig.maxNightLightIntensity.toDouble(),
                  divisions: ColourModesConfig.maxNightLightIntensity,
                  value: (_intensityDraft ?? config.nightLightIntensity)
                      .toDouble(),
                  onChanged: _busy
                      ? null
                      : (v) => setState(
                          () => _intensityDraft = v.round(),
                        ),
                  onChangeEnd: (v) {
                    final intensity = v.round();
                    setState(() => _intensityDraft = null);
                    _save(config.copyWith(nightLightIntensity: intensity));
                  },
                ),
              ),
            ],
          ],
          if (mode == ColourMode.extraDim) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                l10n.extraDimLevel(_dimDraft ?? config.extraDimLevel),
              ),
            ),
            // v1.0.1: LTR slider — see the night-light slider above.
            Directionality(
              textDirection: TextDirection.ltr,
              child: Slider(
                min: 0,
                max: 100,
                divisions: 100,
                value: (_dimDraft ?? config.extraDimLevel).toDouble(),
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _dimDraft = v.round()),
                onChangeEnd: (v) {
                  final level = v.round();
                  setState(() => _dimDraft = null);
                  _save(config.copyWith(extraDimLevel: level));
                },
              ),
            ),
            // Batch G, item 4: the overlay fallback. Shown only when
            // the mode itself is on — it replaces the platform keys
            // with Azm's own dimming on devices whose framework
            // ignores them. Switching it on is a config save like the
            // level slider; the service picks the overlay up on sync.
            SwitchListTile(
              title: Text(l10n.extraDimUseOverlayTitle),
              subtitle: Text(l10n.extraDimUseOverlaySub),
              value: config.extraDimUseOverlay,
              onChanged: _busy
                  ? null
                  : (v) =>
                      _save(config.copyWith(extraDimUseOverlay: v)),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(l10n.colourWindowsLabel(_windowsSummary(mode, l10n))),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: _busy ? null : () => _editWindows(mode),
                  icon: const Icon(Icons.schedule_outlined),
                  label: Text(l10n.editWindows),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: DropdownButton<ColourScope>(
              value: scope,
              isExpanded: true,
              items: [
                for (final s in ColourScope.values)
                  DropdownMenuItem(
                    value: s,
                    child: Text(_scopeName(s, l10n)),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (v) {
                      if (v != null) _changeScope(mode, v);
                    },
            ),
          ),
          if (scope != ColourScope.device)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _busy ? null : () => _pickScopeApps(mode),
                    icon: const Icon(Icons.apps_outlined),
                    label: Text(l10n.colourScopeAppsCount(scopeApps.length)),
                  ),
                ],
              ),
            ),
        ],
        if (mode == ColourMode.grayscale &&
            selected &&
            config.enabled) ...[
          SwitchListTile(
            title: Text(l10n.applyDuringFocus),
            subtitle: Text(l10n.applyDuringFocusDesc),
            value: config.applyDuringFocus,
            onChanged: _busy
                ? null
                : (v) => _save(config.copyWith(applyDuringFocus: v)),
          ),
        ],
      ],
    );
  }
}
