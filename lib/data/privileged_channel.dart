/// Typed Dart client for the platform contract in `docs/ARCHITECTURE.md` §5,
/// plus the §8 enforcement-config extension methods the Kotlin handler
/// exposes (`get/setTimeLimit`, `get/setTimeWindows`, `get/setGroups`,
/// `get/setBlockedWords`, `setPassiveWords`, `get/clearSuspensionLogs`,
/// `get/setSetting`, `generateRecoveryCode`).
///
/// This is the ONLY class that touches the platform channels (ARCH §4 rule 1).
/// It never fakes a result: a platform error, a missing native side, or a
/// malformed reply is surfaced as a [PrivilegedException].
library;

import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/focus.dart';

/// A failure from the privileged channel, in the §5.4 taxonomy shape.
class PrivilegedException implements Exception {
  PrivilegedException(this.code, this.message, [this.details = const {}]);

  /// Stable machine-readable code (§5.4), or `UNAVAILABLE` when there is no
  /// native side at all (widget tests, non-Android hosts) — a Dart-side
  /// extension code, never produced by Kotlin.
  final String code;
  final String message;
  final Map<String, dynamic> details;

  int? get exitCode => (details['exitCode'] as num?)?.toInt();
  String? get command => details['command'] as String?;
  String? get stderr => details['stderr'] as String?;
  String? get cause => details['cause'] as String?;

  bool get isUnavailable => code == 'UNAVAILABLE';
  bool get isNotOwner => code == 'DPM_NOT_OWNER';
  bool get isShizukuUnavailable =>
      code.startsWith('SHIZUKU_') || code == 'SHELL_FAILED';

  @override
  String toString() => 'PrivilegedException($code: $message)';

  /// Builds an exception from a [PlatformException], preserving the details
  /// map (exitCode/command/stdout/stderr) the contract mandates.
  factory PrivilegedException.fromPlatform(PlatformException e) {
    final raw = e.details;
    final details = <String, dynamic>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        details[entry.key.toString()] = entry.value;
      }
    }
    return PrivilegedException(
      e.code,
      e.message ?? 'Platform error',
      details,
    );
  }
}

enum ShizukuState { notInstalled, notRunning, preV11, noPermission, granted, unknown }

ShizukuState parseShizukuState(String? wire) => switch (wire) {
      'notInstalled' => ShizukuState.notInstalled,
      'notRunning' => ShizukuState.notRunning,
      'preV11' => ShizukuState.preV11,
      'noPermission' => ShizukuState.noPermission,
      'granted' => ShizukuState.granted,
      _ => ShizukuState.unknown,
    };

class ShizukuStatus {
  const ShizukuStatus({
    required this.state,
    this.serverVersion,
    this.serverUid,
    this.isPreV11 = false,
    this.diagnostic,
  });

  final ShizukuState state;
  final int? serverVersion;
  final int? serverUid;
  final bool isPreV11;
  final String? diagnostic;

  factory ShizukuStatus.fromMap(Map<dynamic, dynamic> m) => ShizukuStatus(
        state: parseShizukuState(m['state'] as String?),
        serverVersion: (m['serverVersion'] as num?)?.toInt(),
        serverUid: (m['serverUid'] as num?)?.toInt(),
        isPreV11: m['isPreV11'] as bool? ?? false,
        // Kotlin's degraded path puts `diagnostic` at the top level of the
        // reply map (the doc says details.diagnostic — Kotlin wins).
        diagnostic: m['diagnostic'] as String?,
      );
}

class InstalledApp {
  const InstalledApp({
    required this.packageName,
    required this.label,
    required this.isSystem,
    required this.isHidden,
    required this.isSuspended,
    required this.isUninstallBlocked,
    this.hasExplicitContentRating,
  });

  final String packageName;
  final String label;
  final bool isSystem;
  final bool isHidden;
  final bool isSuspended;
  final bool isUninstallBlocked;
  final bool? hasExplicitContentRating;

  factory InstalledApp.fromMap(Map<dynamic, dynamic> m) => InstalledApp(
        packageName: m['packageName'] as String,
        label: m['label'] as String? ?? (m['packageName'] as String),
        isSystem: m['isSystem'] as bool? ?? false,
        isHidden: m['isHidden'] as bool? ?? false,
        isSuspended: m['isSuspended'] as bool? ?? false,
        isUninstallBlocked: m['isUninstallBlocked'] as bool? ?? false,
        hasExplicitContentRating: m['hasExplicitContentRating'] as bool?,
      );

  InstalledApp copyWith({bool? isHidden, bool? isSuspended, bool? isUninstallBlocked}) =>
      InstalledApp(
        packageName: packageName,
        label: label,
        isSystem: isSystem,
        isHidden: isHidden ?? this.isHidden,
        isSuspended: isSuspended ?? this.isSuspended,
        isUninstallBlocked: isUninstallBlocked ?? this.isUninstallBlocked,
        hasExplicitContentRating: hasExplicitContentRating,
      );
}

class UserRestriction {
  const UserRestriction({required this.key, required this.active, required this.recommended});
  final String key;
  final bool active;
  final bool recommended;

  factory UserRestriction.fromMap(Map<dynamic, dynamic> m) => UserRestriction(
        key: m['key'] as String,
        active: m['active'] as bool? ?? false,
        recommended: m['recommended'] as bool? ?? false,
      );
}

class CapableApp {
  const CapableApp({required this.packageName, required this.label, required this.declaredKeys});
  final String packageName;
  final String label;
  final List<String> declaredKeys;

  factory CapableApp.fromMap(Map<dynamic, dynamic> m) => CapableApp(
        packageName: m['packageName'] as String,
        label: m['label'] as String? ?? (m['packageName'] as String),
        declaredKeys: (m['declaredKeys'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
}

/// One entry of a target app's own manifest-declared restrictions, as
/// returned by `getAvailableRestrictions` — the model behind the original's
/// `AppRestrictionsScreen` (its `RestrictionEntry` list from
/// `RestrictionsManager.getManifestRestrictions`).
///
/// [type] is the contract vocabulary: 'bool' | 'string' | 'stringList' |
/// 'int' | 'bundle'. [defaultValue] is the default declared in the target
/// app's restrictions XML; [currentValue] is the value currently applied via
/// Device Owner, or null when the key is not set (or this app is not owner).
/// [hidden] marks keys the original deliberately hides from the editor and
/// force-preserves on save (e.g. `URLBlocklist`, owned by the browser
/// restrictions flow) — the UI must not offer them for editing. For
/// type 'bundle', [children] carries the nested entries (for bundle arrays,
/// the per-item template entries, with defaults only).
class AvailableRestriction {
  const AvailableRestriction({
    required this.key,
    required this.type,
    required this.titleKey,
    this.defaultValue,
    this.currentValue,
    this.description,
    this.hidden = false,
    this.choices = const [],
    this.children = const [],
  });

  final String key;
  final String type;
  final Object? defaultValue;
  final Object? currentValue;
  final String titleKey;
  final String? description;
  final bool hidden;
  final List<String> choices;
  final List<AvailableRestriction> children;

  bool get isManaged => currentValue != null;

  factory AvailableRestriction.fromMap(Map<dynamic, dynamic> m) => AvailableRestriction(
        key: m['key'] as String,
        type: m['type'] as String? ?? 'string',
        titleKey: m['titleKey'] as String? ?? (m['key'] as String),
        defaultValue: m['defaultValue'],
        currentValue: m['currentValue'],
        description: m['description'] as String?,
        hidden: m['hidden'] as bool? ?? false,
        choices: (m['choices'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        children: (m['children'] as List?)
                ?.map((e) => AvailableRestriction.fromMap(e as Map<dynamic, dynamic>))
                .toList() ??
            const [],
      );
}

class ProvisioningDiagnostics {
  const ProvisioningDiagnostics({required this.accounts, required this.extraUsers, this.currentOwner});
  final List<Map<String, String>> accounts;
  final List<Map<String, dynamic>> extraUsers;
  final Map<String, String>? currentOwner;

  factory ProvisioningDiagnostics.fromMap(Map<dynamic, dynamic> m) {
    Map<String, String> stringify(Map<dynamic, dynamic> x) =>
        x.map((k, v) => MapEntry(k.toString(), v.toString()));
    return ProvisioningDiagnostics(
      accounts: (m['accounts'] as List? ?? const [])
          .map((e) => stringify(e as Map<dynamic, dynamic>))
          .toList(),
      extraUsers: (m['extraUsers'] as List? ?? const [])
          .map((e) => (e as Map<dynamic, dynamic>).map((k, v) => MapEntry(k.toString(), v)))
          .toList(),
      currentOwner: (m['currentOwner'] as Map<dynamic, dynamic>?)?.let(stringify),
    );
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

class PrivateDnsState {
  const PrivateDnsState({required this.mode, this.hostname});
  final String mode;
  final String? hostname;
  bool get isSpecifiedHost => mode.contains('PROVIDER_HOSTNAME');
  factory PrivateDnsState.fromMap(Map<dynamic, dynamic> m) => PrivateDnsState(
        mode: m['mode'] as String? ?? 'UNKNOWN',
        hostname: m['hostname'] as String?,
      );
}

class UsageToday {
  const UsageToday({required this.date, required this.packages, required this.groups});
  final String date;
  final Map<String, int> packages;
  final Map<String, int> groups;
  factory UsageToday.fromMap(Map<dynamic, dynamic> m) {
    // packages entries carry packageName, group entries carry groupId.
    return UsageToday(
      date: m['date'] as String? ?? '',
      packages: {
        for (final e in (m['packages'] as List? ?? const []))
          (e as Map<dynamic, dynamic>)['packageName'].toString():
              ((e['usedMs'] as num?)?.toInt() ?? 0),
      },
      groups: {
        for (final e in (m['groups'] as List? ?? const []))
          (e as Map<dynamic, dynamic>)['groupId'].toString():
              ((e['usedMs'] as num?)?.toInt() ?? 0),
      },
    );
  }
}

/// One allowed-usage window, minutes of day (may span midnight).
class TimeWindowModel {
  const TimeWindowModel(this.startMinute, this.endMinute);
  final int startMinute;
  final int endMinute;

  Map<String, int> toMap() => {'s': startMinute, 'e': endMinute};

  factory TimeWindowModel.fromMap(Map<dynamic, dynamic> m) =>
      TimeWindowModel((m['s'] as num).toInt(), (m['e'] as num).toInt());

  String get formatted =>
      '${_hhmm(startMinute)} – ${_hhmm(endMinute)}';
  static String _hhmm(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is TimeWindowModel && other.startMinute == startMinute && other.endMinute == endMinute;
  @override
  int get hashCode => Object.hash(startMinute, endMinute);
}

class AppEnforcement {
  const AppEnforcement({
    required this.packageName,
    this.dailyMinutes = 0,
    this.weeklyMinutes,
    this.reopenSeconds = 0,
    this.dailyWindows = const [],
    this.weeklyWindows,
  });

  final String packageName;
  final int dailyMinutes;
  final List<int>? weeklyMinutes;
  final int reopenSeconds;
  final List<TimeWindowModel> dailyWindows;
  final List<List<TimeWindowModel>>? weeklyWindows;

  bool get hasLimit => weeklyMinutes != null ? weeklyMinutes!.any((m) => m > 0) : dailyMinutes > 0;
  bool get hasWindows =>
      weeklyWindows != null ? weeklyWindows!.any((d) => d.isNotEmpty) : dailyWindows.isNotEmpty;

  int get todayLimitMinutes {
    if (weeklyMinutes != null) {
      // DateTime.weekday: Mon=1..Sun=7; Kotlin DayOfWeek ordinal: Mon=0..Sun=6.
      return weeklyMinutes![DateTime.now().weekday - 1];
    }
    return dailyMinutes;
  }
}

class AppGroupModel {
  const AppGroupModel({
    required this.id,
    required this.name,
    this.packages = const [],
    this.dailyMinutes = 0,
    this.weeklyMinutes,
    this.reopenSeconds = 0,
    this.dailyWindows = const [],
    this.weeklyWindows,
  });

  final String id;
  final String name;
  final List<String> packages;
  final int dailyMinutes;
  final List<int>? weeklyMinutes;

  /// Reopening cooldown in seconds, mirroring the per-app limit model's
  /// `reopenSeconds` (same `'reopenSeconds'` key in the groups JSON the
  /// Kotlin SettingsStore round-trips). Enforcement is F11/v1.1, as with
  /// per-app limits; the value is stored and gate-relevant (decreasing it
  /// loosens).
  final int reopenSeconds;
  final List<TimeWindowModel> dailyWindows;
  final List<List<TimeWindowModel>>? weeklyWindows;

  factory AppGroupModel.fromMap(Map<dynamic, dynamic> m) => AppGroupModel(
        id: m['id'] as String,
        name: m['name'] as String? ?? '',
        packages: (m['packages'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        dailyMinutes: (m['dailyMinutes'] as num?)?.toInt() ?? 0,
        reopenSeconds: (m['reopenSeconds'] as num?)?.toInt() ?? 0,
        weeklyMinutes:
            (m['weeklyMinutes'] as List?)?.map((e) => (e as num).toInt()).toList(),
        dailyWindows: _windows(m['dailyWindows']),
        weeklyWindows: (m['weeklyWindows'] as List?)
            ?.map((day) => _windows(day))
            .toList(),
      );

  static List<TimeWindowModel> _windows(Object? v) => (v as List? ?? const [])
      .map((e) => TimeWindowModel.fromMap(e as Map<dynamic, dynamic>))
      .toList();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'packages': packages,
        'dailyMinutes': dailyMinutes,
        'weeklyMinutes': weeklyMinutes,
        'reopenSeconds': reopenSeconds,
        'dailyWindows': dailyWindows.map((w) => w.toMap()).toList(),
        'weeklyWindows': weeklyWindows?.map((d) => d.map((w) => w.toMap()).toList()).toList(),
      };

  AppGroupModel copyWith({
    String? name,
    List<String>? packages,
    int? dailyMinutes,
    List<int>? weeklyMinutes,
    bool clearWeeklyMinutes = false,
    int? reopenSeconds,
    List<TimeWindowModel>? dailyWindows,
    List<List<TimeWindowModel>>? weeklyWindows,
    bool clearWeeklyWindows = false,
  }) =>
      AppGroupModel(
        id: id,
        name: name ?? this.name,
        packages: packages ?? this.packages,
        dailyMinutes: dailyMinutes ?? this.dailyMinutes,
        weeklyMinutes: clearWeeklyMinutes ? null : (weeklyMinutes ?? this.weeklyMinutes),
        reopenSeconds: reopenSeconds ?? this.reopenSeconds,
        dailyWindows: dailyWindows ?? this.dailyWindows,
        weeklyWindows: clearWeeklyWindows ? null : (weeklyWindows ?? this.weeklyWindows),
      );
}

class BlockedWordsState {
  const BlockedWordsState({
    this.words = const [],
    this.targetPackages = const [],
    this.passiveWords = const {},
  });
  final List<String> words;
  final List<String> targetPackages;
  final Map<String, List<String>> passiveWords;

  factory BlockedWordsState.fromMap(Map<dynamic, dynamic> m) => BlockedWordsState(
        words: (m['words'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        targetPackages:
            (m['targetPackages'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        passiveWords: (m['passiveWords'] as Map<dynamic, dynamic>? ?? const {}).map(
          (k, v) => MapEntry(
            k.toString(),
            (v as List).map((e) => e.toString()).toList(),
          ),
        ),
      );
}

class SuspensionLogEntry {
  const SuspensionLogEntry({
    required this.id,
    required this.packageName,
    required this.appName,
    required this.timestampMs,
    required this.reason,
    this.details,
  });
  final String id;
  final String packageName;
  final String appName;
  final int timestampMs;
  final String reason;
  final String? details;

  DateTime get timestamp => DateTime.fromMillisecondsSinceEpoch(timestampMs);

  factory SuspensionLogEntry.fromMap(Map<dynamic, dynamic> m) => SuspensionLogEntry(
        id: m['id'] as String? ?? '',
        packageName: m['packageName'] as String? ?? '',
        appName: m['appName'] as String? ?? (m['packageName'] as String? ?? ''),
        timestampMs: (m['timestamp'] as num?)?.toInt() ?? 0,
        reason: m['reason'] as String? ?? 'MANUAL',
        details: m['details'] as String?,
      );
}

class PrivilegedEvent {
  const PrivilegedEvent(this.type, this.payload);
  final String type;
  final Map<String, dynamic> payload;
  @override
  String toString() => 'PrivilegedEvent($type, $payload)';
}

/// The native focus session's wire state, exactly as the Kotlin
/// `FocusSessionStore.stateMap` produces it (`startFocusSession` result /
/// `getFocusSession`).
///
/// The native store is authoritative: the session is persisted natively
/// (elapsed-realtime + wall-clock anchors + boot count) and survives
/// process death; this snapshot is how Dart views it. [phase] is one of
/// `waiting | focus | shortBreak | longBreak | paused | idle` — the
/// native phases of the original `FocusMode`. When [phase] is `paused`,
/// [pausedFrom] carries the underlying phase and [deadlineElapsedMs] is
/// the nominal pre-pause deadline (the paused remaining time itself is
/// held natively and is not part of the wire shape; a restored paused
/// session therefore displays its full phase duration until resumed —
/// the native session still ends at the true deadline).
class NativeFocusSessionState {
  const NativeFocusSessionState({
    required this.phase,
    required this.phaseStartedElapsedMs,
    required this.phaseDurationMs,
    required this.completedFocusInCycle,
    required this.pausedFrom,
    required this.deadlineElapsedMs,
  });

  /// Wire phase: `waiting|focus|shortBreak|longBreak|paused|idle`.
  final String phase;

  /// `SystemClock.elapsedRealtime()` at the (re-anchored) phase start.
  final int phaseStartedElapsedMs;
  final int phaseDurationMs;
  final int completedFocusInCycle;

  /// Underlying phase when [phase] is `paused`; otherwise null.
  final String? pausedFrom;

  /// `elapsedRealtime` deadline of the current phase (nominal when paused).
  final int deadlineElapsedMs;

  bool get isPaused => phase == 'paused';
  bool get isWaiting => phase == 'waiting';
  bool get isIdle => phase == 'idle';

  factory NativeFocusSessionState.fromMap(Map<dynamic, dynamic> m) =>
      NativeFocusSessionState(
        phase: m['phase'] as String? ?? 'idle',
        phaseStartedElapsedMs: (m['phaseStartedElapsedMs'] as num?)?.toInt() ?? 0,
        phaseDurationMs: (m['phaseDurationMs'] as num?)?.toInt() ?? 0,
        completedFocusInCycle: (m['completedFocusInCycle'] as num?)?.toInt() ?? 0,
        pausedFrom: m['pausedFrom'] as String?,
        deadlineElapsedMs: (m['deadlineElapsedMs'] as num?)?.toInt() ?? 0,
      );

  static FocusPhase _phaseFor(String wire) => switch (wire) {
        'focus' => FocusPhase.focus,
        'shortBreak' => FocusPhase.breakTime,
        'longBreak' => FocusPhase.longBreak,
        'waiting' => FocusPhase.waiting,
        'paused' => FocusPhase.paused,
        'done' => FocusPhase.done,
        _ => FocusPhase.idle,
      };

  /// Rebuilds the domain [FocusSession] for [config] from this snapshot.
  ///
  /// Anchoring: when [elapsedRealtimeOffsetMs] is known (the difference
  /// between the native elapsed-realtime clock and Dart's monotonic
  /// clock, captured by [PrivilegedChannel] when this process started the
  /// session), the remaining time is computed exactly from
  /// [deadlineElapsedMs] and both of the session's clocks are re-anchored
  /// consistently. Without an offset (a session restored after a process
  /// restart) the phase is anchored at [now] with its full duration —
  /// an approximation for display only: the native alarm still ends the
  /// phase at the true deadline and the `focusPhaseChanged` event then
  /// re-syncs the UI.
  FocusSession toFocusSession(
    FocusConfig config, {
    int? elapsedRealtimeOffsetMs,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    if (phase == 'idle') return FocusSession(config: config);
    final duration = Duration(milliseconds: phaseDurationMs);
    if (isPaused) {
      return FocusSession(
        config: config,
        phase: FocusPhase.paused,
        phaseDuration: duration,
        completedFocusPeriods: completedFocusInCycle,
        pausedFrom: pausedFrom != null ? _phaseFor(pausedFrom!) : null,
        // Not carried by the wire shape; see the class doc.
        pausedRemaining: duration,
      );
    }
    final phaseEnum = _phaseFor(phase);
    Duration elapsedWithinPhase;
    if (elapsedRealtimeOffsetMs != null && phaseEnum != FocusPhase.waiting) {
      final nativeNowMs =
          FocusSession.monotonicNow.inMilliseconds + elapsedRealtimeOffsetMs;
      var remainingMs = deadlineElapsedMs - nativeNowMs;
      if (remainingMs < 0) remainingMs = 0;
      if (remainingMs > phaseDurationMs) remainingMs = phaseDurationMs;
      elapsedWithinPhase = duration - Duration(milliseconds: remainingMs);
    } else {
      elapsedWithinPhase = Duration.zero;
    }
    return FocusSession(
      config: config,
      phase: phaseEnum,
      phaseStartedAt: at.subtract(elapsedWithinPhase),
      phaseStartedElapsed: FocusSession.monotonicNow - elapsedWithinPhase,
      phaseDuration: duration,
      completedFocusPeriods: completedFocusInCycle,
    );
  }
}

/// The single Dart-side caller of `dominanter/privileged`.
class PrivilegedChannel {
  PrivilegedChannel({MethodChannel? methodChannel, EventChannel? eventChannel})
      : _methods = methodChannel ?? const MethodChannel('dominanter/privileged'),
        _events = eventChannel ?? const EventChannel('dominanter/privileged/events');

  final MethodChannel _methods;
  final EventChannel _events;

  static const int shizukuRequestCode = 911;

  Stream<PrivilegedEvent>? _eventStream;

  /// Advisory events (§5.5). Dart re-reads authoritative state on receipt.
  Stream<PrivilegedEvent> get events {
    return _eventStream ??= _events.receiveBroadcastStream().map((raw) {
      final m = (raw as Map<dynamic, dynamic>)
          .map((k, v) => MapEntry(k.toString(), v));
      final type = m.remove('type')?.toString() ?? 'unknown';
      return PrivilegedEvent(type, m);
    }).handleError((Object e) {
      // Event stream errors are advisory only; the stream must not take the
      // UI down. Authoritative state is always re-readable via methods.
    });
  }

  Future<T> _invoke<T>(String method, [Map<String, dynamic>? args]) async {
    try {
      final result = await _methods.invokeMethod<dynamic>(method, args);
      return result as T;
    } on PlatformException catch (e) {
      throw PrivilegedException.fromPlatform(e);
    } on MissingPluginException catch (e) {
      throw PrivilegedException(
        'UNAVAILABLE',
        'The Android native layer is not available in this environment.',
        {'cause': e.toString()},
      );
    }
  }

  Future<Map<String, dynamic>> _invokeMap(String method, [Map<String, dynamic>? args]) async {
    final result = await _invoke<dynamic>(method, args);
    if (result is Map) {
      return result.map((k, v) => MapEntry(k.toString(), v));
    }
    throw PrivilegedException('INTERNAL', 'Malformed reply from native layer for $method',
        {'cause': 'expected Map, got ${result.runtimeType}'});
  }

  // ---------------------------------------------------------- Shizuku

  Future<ShizukuStatus> getShizukuState() async =>
      ShizukuStatus.fromMap(await _invokeMap('getShizukuState'));

  Future<bool> requestShizukuPermission() async =>
      (await _invokeMap('requestShizukuPermission'))['requested'] as bool? ?? false;

  /// Opens Shizuku's Play Store page (market:// intent, https fallback —
  /// the original's `installShizuku`). Returns whether an intent launched.
  Future<bool> installShizuku() async =>
      (await _invokeMap('installShizuku'))['launched'] as bool? ?? false;

  // ---------------------------------------------------------- Device Owner

  Future<Map<String, dynamic>> provisionDeviceOwner() => _invokeMap('provisionDeviceOwner');

  Future<bool> removeDeviceOwner() async =>
      (await _invokeMap('removeDeviceOwner'))['isDeviceOwner'] as bool? ?? true;

  Future<({bool isDeviceOwner, bool isAdminActive})> isDeviceOwner() async {
    final m = await _invokeMap('isDeviceOwner');
    return (
      isDeviceOwner: m['isDeviceOwner'] as bool? ?? false,
      isAdminActive: m['isAdminActive'] as bool? ?? false,
    );
  }

  Future<ProvisioningDiagnostics> getProvisioningDiagnostics() async =>
      ProvisioningDiagnostics.fromMap(await _invokeMap('getProvisioningDiagnostics'));

  // ---------------------------------------------------------- Apps

  Future<List<InstalledApp>> listInstalledApps({bool includeSystem = false}) async {
    final raw = await _invoke<dynamic>('listInstalledApps', {'includeSystem': includeSystem});
    if (raw is List) {
      return raw
          .map((e) => InstalledApp.fromMap(e as Map<dynamic, dynamic>))
          .toList();
    }
    throw PrivilegedException('INTERNAL', 'Malformed reply for listInstalledApps');
  }

  Future<bool> setAppHidden(String packageName, bool hidden) async {
    final m = await _invokeMap('setAppHidden', {'packageName': packageName, 'hidden': hidden});
    return m['isHidden'] as bool? ?? !hidden;
  }

  /// Returns per-package verified results. Partial failure throws
  /// [PrivilegedException] with `details['failedPackages']` (Kotlin side).
  Future<List<({String packageName, bool isSuspended})>> setAppSuspended(
    List<String> packageNames,
    bool suspended, {
    String? reason,
  }) async {
    final m = await _invokeMap('setAppSuspended', {
      'packageNames': packageNames,
      'suspended': suspended,
      if (reason != null) 'reason': reason,
    });
    return (m['results'] as List? ?? const []).map((e) {
      final r = e as Map<dynamic, dynamic>;
      return (
        packageName: r['packageName'].toString(),
        isSuspended: r['isSuspended'] as bool? ?? false,
      );
    }).toList();
  }

  Future<bool> setUninstallBlocked(String packageName, bool blocked) async {
    final m = await _invokeMap(
        'setUninstallBlocked', {'packageName': packageName, 'blocked': blocked});
    return m['isUninstallBlocked'] as bool? ?? !blocked;
  }

  // ---------------------------------------------------------- Restrictions

  Future<List<UserRestriction>> listUserRestrictions() async {
    final m = await _invokeMap('listUserRestrictions');
    return (m['restrictions'] as List? ?? const [])
        .map((e) => UserRestriction.fromMap(e as Map<dynamic, dynamic>))
        .toList();
  }

  Future<bool> applyUserRestriction(String key) async =>
      (await _invokeMap('applyUserRestriction', {'key': key}))['active'] as bool? ?? false;

  Future<bool> clearUserRestriction(String key) async =>
      (await _invokeMap('clearUserRestriction', {'key': key}))['active'] as bool? ?? true;

  Future<Map<String, dynamic>> getApplicationRestrictions(String packageName) async {
    final m = await _invokeMap('getApplicationRestrictions', {'packageName': packageName});
    final r = m['restrictions'];
    return r is Map ? r.map((k, v) => MapEntry(k.toString(), v)) : <String, dynamic>{};
  }

  /// The target app's declared restrictions model (the original's
  /// `getAvailableRestrictions`): every restriction the app declares in its
  /// manifest, with declared defaults and currently applied values. Entries
  /// flagged [AvailableRestriction.hidden] must not be offered for editing.
  Future<List<AvailableRestriction>> getAvailableRestrictions(String packageName) async {
    final m = await _invokeMap('getAvailableRestrictions', {'packageName': packageName});
    return (m['restrictions'] as List? ?? const [])
        .map((e) => AvailableRestriction.fromMap(e as Map<dynamic, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> setApplicationRestrictions(
    String packageName,
    Map<String, dynamic> restrictions, {
    bool merge = false,
  }) async {
    final m = await _invokeMap('setApplicationRestrictions', {
      'packageName': packageName,
      'restrictions': restrictions,
      'merge': merge,
    });
    final r = m['restrictions'];
    return r is Map ? r.map((k, v) => MapEntry(k.toString(), v)) : <String, dynamic>{};
  }

  Future<List<CapableApp>> listRestrictionCapableApps({List<String> requiredKeys = const []}) async {
    final raw = await _invoke<dynamic>('listRestrictionCapableApps', {'requiredKeys': requiredKeys});
    if (raw is List) {
      return raw.map((e) => CapableApp.fromMap(e as Map<dynamic, dynamic>)).toList();
    }
    throw PrivilegedException('INTERNAL', 'Malformed reply for listRestrictionCapableApps');
  }

  // ---------------------------------------------------------- Private DNS

  Future<PrivateDnsState> getPrivateDns() async =>
      PrivateDnsState.fromMap(await _invokeMap('getPrivateDns'));

  Future<PrivateDnsState> setPrivateDns(String hostname) async =>
      PrivateDnsState.fromMap(await _invokeMap('setPrivateDns', {'hostname': hostname}));

  // ---------------------------------------------------------- Grant & Accessibility

  Future<bool> grantWriteSecureSettings() async =>
      (await _invokeMap('grantWriteSecureSettings'))['granted'] as bool? ?? false;

  /// Read-only check of the WRITE_SECURE_SETTINGS grant: the native
  /// side's verified `checkSelfPermission` re-check, without granting.
  Future<bool> isWriteSecureSettingsGranted() async =>
      (await _invokeMap('isWriteSecureSettingsGranted'))['granted'] as bool? ?? false;

  Future<bool> setAccessibilityEnabled(bool enabled) async =>
      (await _invokeMap('setAccessibilityEnabled', {'enabled': enabled}))['isEnabled'] as bool? ??
      !enabled;

  Future<({bool isEnabled, bool isServiceRunning})> isAccessibilityEnabled() async {
    final m = await _invokeMap('isAccessibilityEnabled');
    return (
      isEnabled: m['isEnabled'] as bool? ?? false,
      isServiceRunning: m['isServiceRunning'] as bool? ?? false,
    );
  }

  // ---------------------------------------------------------- Usage

  Future<UsageToday> getUsageToday({String? packageName}) async => UsageToday.fromMap(
      await _invokeMap('getUsageToday', {if (packageName != null) 'packageName': packageName}));

  // ---------------------------------------------------------- Focus (native runtime)

  /// Difference between the native elapsed-realtime clock and Dart's
  /// monotonic clock, in milliseconds, captured when this process starts
  /// a focus session (the phase start in the reply is, to within channel
  /// transit, "now" on the native clock). Used by
  /// [NativeFocusSessionState.toFocusSession] for exact remaining-time
  /// reconstruction; null for sessions this process did not start.
  int? get focusElapsedRealtimeOffsetMs => _focusElapsedRealtimeOffsetMs;
  int? _focusElapsedRealtimeOffsetMs;

  NativeFocusSessionState? _parseFocusState(dynamic result, String method) {
    if (result == null) return null;
    if (result is Map) {
      return NativeFocusSessionState.fromMap(result);
    }
    throw PrivilegedException('INTERNAL', 'Malformed reply from native layer for $method',
        {'cause': 'expected Map or null, got ${result.runtimeType}'});
  }

  /// Persists the session natively and starts its first focus phase.
  /// The native side clamps durations/cycles to the original's bounds,
  /// snapshots the config, and takes the suspension targets from the
  /// persisted focus config (`ConfigStore`).
  Future<NativeFocusSessionState> startFocusSession({
    required int focusMinutes,
    required int breakMinutes,
    required int longBreakMinutes,
    required int cycles,
    required bool autoStartFocus,
    required bool soundEnabled,
    required bool vibrationEnabled,
  }) async {
    final m = await _invokeMap('startFocusSession', {
      'focusMinutes': focusMinutes,
      'breakMinutes': breakMinutes,
      'longBreakMinutes': longBreakMinutes,
      'cycles': cycles,
      'autoStartFocus': autoStartFocus,
      'soundEnabled': soundEnabled,
      'vibrationEnabled': vibrationEnabled,
    });
    final state = NativeFocusSessionState.fromMap(m);
    // The phase has just started on the native clock: capture the offset
    // between the two monotonic clocks for later reconstruction.
    _focusElapsedRealtimeOffsetMs =
        state.phaseStartedElapsedMs - FocusSession.monotonicNow.inMilliseconds;
    return state;
  }

  /// The persisted native session, or null when no session exists. The
  /// native side advances an expired phase before replying.
  Future<NativeFocusSessionState?> getFocusSession() async =>
      _parseFocusState(await _invoke<dynamic>('getFocusSession'), 'getFocusSession');

  /// Pauses the native session. With [releaseApps] the suspended apps are
  /// released for the pause (a loosening — callers gate it behind the
  /// recovery session, as in the original); otherwise they stay suspended.
  Future<NativeFocusSessionState?> pauseFocusSession({bool releaseApps = false}) async =>
      _parseFocusState(
        await _invoke<dynamic>('pauseFocusSession', {'releaseApps': releaseApps}),
        'pauseFocusSession',
      );

  /// Resumes into the phase the session was paused from (never forces
  /// the focus phase — the original's `resume` semantics).
  Future<NativeFocusSessionState?> resumeFocusSession() async =>
      _parseFocusState(await _invoke<dynamic>('resumeFocusSession'), 'resumeFocusSession');

  /// Skips the current break, entering the next focus phase (the
  /// original's `FocusMode.skipBreak`); a no-op outside a break phase.
  Future<NativeFocusSessionState?> skipFocusSession() async =>
      _parseFocusState(await _invoke<dynamic>('skipFocusSession'), 'skipFocusSession');

  /// Stops the native session: releases its suspensions/restrictions,
  /// cancels the alarm and the status notification.
  Future<void> stopFocusSession() async {
    await _invoke<dynamic>('stopFocusSession');
    _focusElapsedRealtimeOffsetMs = null;
  }

  // ---------------------------------------------------------- Notification permission

  Future<bool> hasNotificationPermission() async =>
      (await _invokeMap('hasNotificationPermission'))['granted'] as bool? ?? false;

  /// Resolution order on the native side: already granted → device-owner
  /// policy grant (no UI) → the host Activity's runtime prompt.
  Future<bool> requestNotificationPermission() async =>
      (await _invokeMap('requestNotificationPermission'))['granted'] as bool? ?? false;

  // ---------------------------------------------------------- Recovery code

  Future<String> generateRecoveryCode() async =>
      (await _invokeMap('generateRecoveryCode'))['code'] as String;

  Future<bool> setRecoveryCode(String code) async =>
      (await _invokeMap('setRecoveryCode', {'code': code}))['isSet'] as bool? ?? false;

  Future<bool> verifyRecoveryCode(String code) async =>
      (await _invokeMap('verifyRecoveryCode', {'code': code}))['matches'] as bool? ?? false;

  Future<bool> isRecoveryCodeSet() async =>
      (await _invokeMap('isRecoveryCodeSet'))['isSet'] as bool? ?? false;

  // ------------------------------------- §8 extension: enforcement config

  Future<AppEnforcement> getAppEnforcement(String packageName) async {
    final limit = await _invokeMap('getTimeLimit', {'packageName': packageName});
    final windows = await _invokeMap('getTimeWindows', {'packageName': packageName});
    return AppEnforcement(
      packageName: packageName,
      dailyMinutes: (limit['dailyMinutes'] as num?)?.toInt() ?? 0,
      weeklyMinutes: (limit['weeklyMinutes'] as List?)?.map((e) => (e as num).toInt()).toList(),
      reopenSeconds: (limit['reopenSeconds'] as num?)?.toInt() ?? 0,
      dailyWindows: AppGroupModel._windows(windows['dailyWindows']),
      weeklyWindows:
          (windows['weeklyWindows'] as List?)?.map((d) => AppGroupModel._windows(d)).toList(),
    );
  }

  Future<AppEnforcement> setTimeLimit(
    String packageName, {
    int? dailyMinutes,
    List<int>? weeklyMinutes,
    int? reopenSeconds,
  }) async {
    await _invokeMap('setTimeLimit', {
      'packageName': packageName,
      // Dual storage: both components may ride in one call; the native side
      // persists the combined model (weekly wins when set, as in the
      // original). Sending only one component keeps the old behaviour.
      if (dailyMinutes != null) 'dailyMinutes': dailyMinutes,
      if (weeklyMinutes != null) 'weeklyMinutes': weeklyMinutes,
      if (reopenSeconds != null) 'reopenSeconds': reopenSeconds,
    });
    return getAppEnforcement(packageName);
  }

  Future<AppEnforcement> setTimeWindows(
    String packageName, {
    List<TimeWindowModel>? dailyWindows,
    List<List<TimeWindowModel>>? weeklyWindows,
  }) async {
    await _invokeMap('setTimeWindows', {
      'packageName': packageName,
      // Dual storage: both components may ride in one call (see setTimeLimit).
      if (dailyWindows != null) 'dailyWindows': dailyWindows.map((w) => w.toMap()).toList(),
      if (weeklyWindows != null)
        'weeklyWindows': weeklyWindows.map((d) => d.map((w) => w.toMap()).toList()).toList(),
    });
    return getAppEnforcement(packageName);
  }

  Future<List<AppGroupModel>> getGroups() async {
    final m = await _invokeMap('getGroups');
    return (m['groups'] as List? ?? const [])
        .map((e) => AppGroupModel.fromMap(e as Map<dynamic, dynamic>))
        .toList();
  }

  Future<List<AppGroupModel>> setGroups(List<AppGroupModel> groups) async {
    final m = await _invokeMap('setGroups', {'groups': groups.map((g) => g.toMap()).toList()});
    return (m['groups'] as List? ?? const [])
        .map((e) => AppGroupModel.fromMap(e as Map<dynamic, dynamic>))
        .toList();
  }

  Future<BlockedWordsState> getBlockedWords() async =>
      BlockedWordsState.fromMap(await _invokeMap('getBlockedWords'));

  Future<BlockedWordsState> setBlockedWords(List<String> words, List<String> targetPackages) async =>
      BlockedWordsState.fromMap(await _invokeMap(
          'setBlockedWords', {'words': words, 'targetPackages': targetPackages}));

  Future<BlockedWordsState> setPassiveWords(String packageName, List<String> words) async =>
      BlockedWordsState.fromMap(
          await _invokeMap('setPassiveWords', {'packageName': packageName, 'words': words}));

  Future<List<SuspensionLogEntry>> getSuspensionLogs() async {
    final m = await _invokeMap('getSuspensionLogs');
    return (m['logs'] as List? ?? const [])
        .map((e) => SuspensionLogEntry.fromMap(e as Map<dynamic, dynamic>))
        .toList();
  }

  Future<void> clearSuspensionLogs() async {
    await _invokeMap('clearSuspensionLogs');
  }

  // ------------------------------------- §8 extension: generic config

  /// Reads a Dart-domain config value from an allowlisted native store
  /// (security_prefs, browser_prefs, focus_prefs, focus_schedules_prefs,
  /// usage_warning_prefs, recovery_prefs). Values are JSON strings / scalars
  /// written by [setSetting]. Returns null when unset.
  Future<Object?> getSetting(String store, String key) async =>
      (await _invokeMap('getSetting', {'store': store, 'key': key}))['value'];

  Future<void> setSetting(String store, String key, Object? value) async {
    await _invokeMap('setSetting', {'store': store, 'key': key, 'value': value});
  }
}
