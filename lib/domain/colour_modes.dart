/// Colour-modes domain model (Batch C, C3 — GRAYSCALE_RESEARCH.md §6.1).
///
/// The wire shape matches `ColourModesSettings.configToMap` /
/// `configFromMap` in Kotlin exactly: mode and scope names are the
/// Kotlin enum names (`GRAYSCALE`, `DEVICE`, ...), windows are `{s, e}`
/// minute maps, app lists are plain string lists.
///
/// The lock lives in Kotlin: `ColourModesSettings.lockedModesForChange`
/// decides whether a change may be written, and the channel returns
/// `{ok, locked, lockedModes}`. The pure-Dart [ColourScope.isLoosening]
/// below mirrors that rule for display only — the UI may use it to hint
/// that a change will need the recovery gate, but it never authorises
/// or refuses a save.
library;

import '../data/privileged_channel.dart';

enum ColourMode {
  grayscale,
  nightLight,
  extraDim,
  inversion;

  String get wireName => switch (this) {
    ColourMode.grayscale => 'GRAYSCALE',
    ColourMode.nightLight => 'NIGHT_LIGHT',
    ColourMode.extraDim => 'EXTRA_DIM',
    ColourMode.inversion => 'INVERSION',
  };

  static ColourMode? fromWire(String? name) => switch (name) {
    'GRAYSCALE' => ColourMode.grayscale,
    'NIGHT_LIGHT' => ColourMode.nightLight,
    'EXTRA_DIM' => ColourMode.extraDim,
    'INVERSION' => ColourMode.inversion,
    _ => null,
  };
}

enum ColourScope {
  device,
  exceptApps,
  onlyApps;

  String get wireName => switch (this) {
    ColourScope.device => 'DEVICE',
    ColourScope.exceptApps => 'EXCEPT_APPS',
    ColourScope.onlyApps => 'ONLY_APPS',
  };

  static ColourScope fromWire(String? name) => switch (name) {
    'EXCEPT_APPS' => ColourScope.exceptApps,
    'ONLY_APPS' => ColourScope.onlyApps,
    _ => ColourScope.device,
  };

  /// Whether going from [from] to [to] leaves the mode off somewhere it
  /// used to apply. Mirrors `ColourScope.isLoosening` in Kotlin; the
  /// native result is authoritative.
  static bool isLoosening(ColourCoverage from, ColourCoverage to) {
    switch (to.scope) {
      case ColourScope.device:
        return false;
      case ColourScope.exceptApps:
        switch (from.scope) {
          case ColourScope.device:
            return to.excludedApps.isNotEmpty;
          case ColourScope.exceptApps:
            return !from.excludedApps.containsAll(to.excludedApps);
          case ColourScope.onlyApps:
            return from.onlyApps.any(to.excludedApps.contains);
        }
      case ColourScope.onlyApps:
        switch (from.scope) {
          case ColourScope.device:
          case ColourScope.exceptApps:
            return true;
          case ColourScope.onlyApps:
            return !to.onlyApps.containsAll(from.onlyApps);
        }
    }
  }
}

class ColourCoverage {
  const ColourCoverage({
    required this.scope,
    this.excludedApps = const {},
    this.onlyApps = const {},
  });

  final ColourScope scope;
  final Set<String> excludedApps;
  final Set<String> onlyApps;
}

class ColourModesConfig {
  const ColourModesConfig({
    this.enabled = false,
    this.modes = const {ColourMode.grayscale},
    this.windows = const {},
    this.scopes = const {},
    this.excludedApps = const {},
    this.onlyApps = const {},
    this.nightLightTemperature = 3200,
    this.nightLightIntensity = 5,
    this.extraDimLevel = 50,
    // Batch G, item 4: on devices whose framework ignores the
    // platform extra-dim keys (the user's Android 12 Transsion
    // phone), Azm dims with its own overlay instead of the system
    // setting. Default off — the platform path is preferred where
    // it works.
    this.extraDimUseOverlay = false,
    this.applyDuringFocus = false,
  });

  static const nightLightTemperatures = [1800, 2000, 2500, 2700, 3200, 4000];
  static const maxNightLightIntensity = 60;

  final bool enabled;
  final Set<ColourMode> modes;
  final Map<ColourMode, List<TimeWindowModel>> windows;
  final Map<ColourMode, ColourScope> scopes;
  final Map<ColourMode, Set<String>> excludedApps;
  final Map<ColourMode, Set<String>> onlyApps;
  final int nightLightTemperature;
  final int nightLightIntensity;
  final int extraDimLevel;
  final bool extraDimUseOverlay;
  final bool applyDuringFocus;

  List<TimeWindowModel> windowsFor(ColourMode mode) => windows[mode] ?? const [];
  ColourScope scopeFor(ColourMode mode) => scopes[mode] ?? ColourScope.device;
  ColourCoverage coverageFor(ColourMode mode) => ColourCoverage(
    scope: scopeFor(mode),
    excludedApps: excludedApps[mode] ?? const {},
    onlyApps: onlyApps[mode] ?? const {},
  );

  factory ColourModesConfig.fromMap(Map<dynamic, dynamic> m) {
    Map<ColourMode, List<TimeWindowModel>> parseWindows(dynamic raw) {
      final out = <ColourMode, List<TimeWindowModel>>{};
      if (raw is Map) {
        for (final entry in raw.entries) {
          final mode = ColourMode.fromWire(entry.key.toString());
          if (mode == null || entry.value is! List) continue;
          out[mode] = (entry.value as List)
              .whereType<Map>()
              .map(TimeWindowModel.fromMap)
              .toList();
        }
      }
      return out;
    }

    Map<ColourMode, T> parsePerMode<T>(dynamic raw, T Function(dynamic) parse) {
      final out = <ColourMode, T>{};
      if (raw is Map) {
        for (final entry in raw.entries) {
          final mode = ColourMode.fromWire(entry.key.toString());
          if (mode == null) continue;
          out[mode] = parse(entry.value);
        }
      }
      return out;
    }

    return ColourModesConfig(
      enabled: m['enabled'] as bool? ?? false,
      modes:
          (m['modes'] as List?)
              ?.map((e) => ColourMode.fromWire(e.toString()))
              .whereType<ColourMode>()
              .toSet() ??
          const {ColourMode.grayscale},
      windows: parseWindows(m['windows']),
      scopes: parsePerMode(
        m['scopes'],
        (v) => ColourScope.fromWire(v as String?),
      ),
      excludedApps: parsePerMode(
        m['excludedApps'],
        (v) => (v as List?)
                ?.map((e) => e.toString())
                .toSet() ??
            const <String>{},
      ),
      onlyApps: parsePerMode(
        m['onlyApps'],
        (v) => (v as List?)
                ?.map((e) => e.toString())
                .toSet() ??
            const <String>{},
      ),
      nightLightTemperature:
          (m['nightLightTemperature'] as num?)?.toInt() ?? 3200,
      nightLightIntensity: (m['nightLightIntensity'] as num?)?.toInt() ?? 5,
      extraDimLevel: (m['extraDimLevel'] as num?)?.toInt() ?? 50,
      extraDimUseOverlay: m['extraDimUseOverlay'] as bool? ?? false,
      applyDuringFocus: m['applyDuringFocus'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'modes': modes.map((m) => m.wireName).toList(),
    'windows': {
      for (final mode in ColourMode.values)
        mode.wireName: windowsFor(mode).map((w) => w.toMap()).toList(),
    },
    'scopes': {
      for (final mode in ColourMode.values)
        mode.wireName: scopeFor(mode).wireName,
    },
    'excludedApps': {
      for (final mode in ColourMode.values)
        mode.wireName: (excludedApps[mode] ?? const <String>{}).toList(),
    },
    'onlyApps': {
      for (final mode in ColourMode.values)
        mode.wireName: (onlyApps[mode] ?? const <String>{}).toList(),
    },
    'nightLightTemperature': nightLightTemperature,
    'nightLightIntensity': nightLightIntensity,
    'extraDimLevel': extraDimLevel,
    'extraDimUseOverlay': extraDimUseOverlay,
    'applyDuringFocus': applyDuringFocus,
  };

  ColourModesConfig copyWith({
    bool? enabled,
    Set<ColourMode>? modes,
    Map<ColourMode, List<TimeWindowModel>>? windows,
    Map<ColourMode, ColourScope>? scopes,
    Map<ColourMode, Set<String>>? excludedApps,
    Map<ColourMode, Set<String>>? onlyApps,
    int? nightLightTemperature,
    int? nightLightIntensity,
    int? extraDimLevel,
    bool? extraDimUseOverlay,
    bool? applyDuringFocus,
  }) => ColourModesConfig(
    enabled: enabled ?? this.enabled,
    modes: modes ?? this.modes,
    windows: windows ?? this.windows,
    scopes: scopes ?? this.scopes,
    excludedApps: excludedApps ?? this.excludedApps,
    onlyApps: onlyApps ?? this.onlyApps,
    nightLightTemperature: nightLightTemperature ?? this.nightLightTemperature,
    nightLightIntensity: nightLightIntensity ?? this.nightLightIntensity,
    extraDimLevel: extraDimLevel ?? this.extraDimLevel,
    extraDimUseOverlay: extraDimUseOverlay ?? this.extraDimUseOverlay,
    applyDuringFocus: applyDuringFocus ?? this.applyDuringFocus,
  );
}

/// One window currently active for a mode, from `getColourModesStatus`.
class ActiveColourWindow {
  const ActiveColourWindow({required this.mode, required this.window});

  final ColourMode mode;
  final TimeWindowModel window;
}

class ColourModesStatus {
  const ColourModesStatus({
    required this.enabled,
    required this.appliedModes,
    required this.writeSecureSettingsGranted,
    required this.accessibilityServiceEnabled,
    required this.locked,
    required this.activeWindows,
    required this.platformNightLight,
    required this.extraDimAvailable,
    required this.grayscaleSupported,
    // Batch G, item 4: the secure keys the last enforce could not
    // verify as written (empty = everything applied). Surfaced in
    // the status card so a rejected write is visible instead of
    // the toggle showing ON while nothing changed.
    this.failedKeys = const {},
  });

  final bool enabled;
  final Set<ColourMode> appliedModes;
  final bool writeSecureSettingsGranted;
  final bool accessibilityServiceEnabled;
  final Map<ColourMode, bool> locked;
  final List<ActiveColourWindow> activeWindows;
  final bool platformNightLight;
  final bool extraDimAvailable;
  final bool grayscaleSupported;
  final Set<String> failedKeys;

  /// The colour modes whose secure keys failed to apply, derived
  /// from [failedKeys] by secure-setting name prefix.
  Set<ColourMode> get failedModes {
    final modes = <ColourMode>{};
    for (final key in failedKeys) {
      if (key.startsWith('reduce_bright_colors')) {
        modes.add(ColourMode.extraDim);
      } else if (key.startsWith('accessibility_display_daltonizer')) {
        modes.add(ColourMode.grayscale);
      } else if (key.startsWith('night_display')) {
        modes.add(ColourMode.nightLight);
      } else if (key == 'accessibility_display_inversion_enabled') {
        modes.add(ColourMode.inversion);
      }
    }
    return modes;
  }

  bool isLocked(ColourMode mode) => locked[mode] ?? false;

  /// The window currently active for [mode], or null when the mode is
  /// on with no windows (always on while enabled) or off.
  ActiveColourWindow? activeWindowFor(ColourMode mode) {
    for (final w in activeWindows) {
      if (w.mode == mode) return w;
    }
    return null;
  }

  factory ColourModesStatus.fromMap(Map<dynamic, dynamic> m) {
    final lockedRaw = m['locked'];
    final locked = <ColourMode, bool>{};
    if (lockedRaw is Map) {
      for (final entry in lockedRaw.entries) {
        final mode = ColourMode.fromWire(entry.key.toString());
        if (mode != null) locked[mode] = entry.value as bool? ?? false;
      }
    }
    return ColourModesStatus(
      enabled: m['enabled'] as bool? ?? false,
      appliedModes:
          (m['appliedModes'] as List?)
              ?.map((e) => ColourMode.fromWire(e.toString()))
              .whereType<ColourMode>()
              .toSet() ??
          const {},
      writeSecureSettingsGranted:
          m['writeSecureSettingsGranted'] as bool? ?? false,
      accessibilityServiceEnabled:
          m['accessibilityServiceEnabled'] as bool? ?? false,
      locked: locked,
      activeWindows:
          (m['activeWindows'] as List?)
              ?.whereType<Map>()
              .map((w) {
                final mode = ColourMode.fromWire(w['mode'] as String?);
                if (mode == null) return null;
                return ActiveColourWindow(
                  mode: mode,
                  window: TimeWindowModel.fromMap(w),
                );
              })
              .whereType<ActiveColourWindow>()
              .toList() ??
          const [],
      platformNightLight: m['platformNightLight'] as bool? ?? true,
      extraDimAvailable: m['extraDimAvailable'] as bool? ?? false,
      grayscaleSupported: m['grayscaleSupported'] as bool? ?? false,
      failedKeys:
          (m['failedKeys'] as List?)
              ?.map((e) => e.toString())
              .toSet() ??
          const {},
    );
  }
}

/// The result of `setColourModesConfig`: a refused (locked) change is
/// not an exception — it returns `ok: false` with the locked modes, so
/// the UI can offer the recovery gate as the way through.
class ColourModesSetResult {
  const ColourModesSetResult({
    required this.ok,
    required this.locked,
    required this.lockedModes,
  });

  final bool ok;
  final bool locked;
  final Set<ColourMode> lockedModes;

  factory ColourModesSetResult.fromMap(Map<dynamic, dynamic> m) =>
      ColourModesSetResult(
        ok: m['ok'] as bool? ?? false,
        locked: m['locked'] as bool? ?? false,
        lockedModes:
            (m['lockedModes'] as List?)
                ?.map((e) => ColourMode.fromWire(e.toString()))
                .whereType<ColourMode>()
                .toSet() ??
            const {},
      );
}
