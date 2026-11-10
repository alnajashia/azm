/// SEAL rules (v1.0.6, Phase D): user-defined conditions under which
/// Azm refuses to remove itself. The authoritative store and the
/// evaluation are NATIVE (`SealRules` in Kotlin): condition seals are
/// probed live at removal-attempt time, event seals are written by
/// the accessibility service at detection time with
/// elapsedRealtime-anchored deadlines, and the channel's removal
/// operations refuse with a typed SEALED error while any seal holds.
///
/// This Dart model mirrors the native rule shape for the settings UI
/// and the Status tab. It never decides a refusal itself.
library;

/// Seal triggers. Condition triggers hold WHILE the probed state is
/// true; event triggers hold for a chosen duration from the event.
enum SealTrigger {
  appBlocked,
  appSuspended,
  focusRunning,
  visualDetection,
  bannedWord;

  bool get isEvent =>
      this == SealTrigger.visualDetection || this == SealTrigger.bannedWord;

  bool get needsApp => this != SealTrigger.focusRunning;

  /// The native enum name (Kotlin `SealRules.Trigger`).
  String get nativeName => switch (this) {
    SealTrigger.appBlocked => 'APP_BLOCKED',
    SealTrigger.appSuspended => 'APP_SUSPENDED',
    SealTrigger.focusRunning => 'FOCUS_RUNNING',
    SealTrigger.visualDetection => 'VISUAL_DETECTION',
    SealTrigger.bannedWord => 'BANNED_WORD',
  };

  static SealTrigger? fromNative(String name) => switch (name) {
    'APP_BLOCKED' => SealTrigger.appBlocked,
    'APP_SUSPENDED' => SealTrigger.appSuspended,
    'FOCUS_RUNNING' => SealTrigger.focusRunning,
    'VISUAL_DETECTION' => SealTrigger.visualDetection,
    'BANNED_WORD' => SealTrigger.bannedWord,
    _ => null,
  };
}

/// Durations offered for event seals, in minutes: 30 min, 1 h, 6 h,
/// 24 h, 7 days — mirrors the native list exactly.
const sealEventDurationsMinutes = <int>[30, 60, 360, 1440, 10080];

class SealRule {
  const SealRule({
    required this.id,
    required this.trigger,
    this.packageName,
    this.durationMinutes,
    this.enabled = true,
  });

  final String id;
  final SealTrigger trigger;

  /// The chosen app for app-scoped triggers; null for [SealTrigger.focusRunning].
  final String? packageName;

  /// Event seals only: how long the seal holds from the event.
  final int? durationMinutes;

  final bool enabled;

  SealRule copyWith({
    SealTrigger? trigger,
    String? packageName,
    int? durationMinutes,
    bool? enabled,
  }) => SealRule(
    id: id,
    trigger: trigger ?? this.trigger,
    packageName: packageName ?? this.packageName,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    enabled: enabled ?? this.enabled,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'trigger': trigger.nativeName,
    'packageName': packageName,
    'durationMinutes': durationMinutes,
    'enabled': enabled,
  };

  static SealRule? fromMap(Map<String, dynamic> m) {
    final trigger = SealTrigger.fromNative(m['trigger'] as String? ?? '');
    final id = m['id'] as String? ?? '';
    if (trigger == null || id.isEmpty) return null;
    return SealRule(
      id: id,
      trigger: trigger,
      packageName: (m['packageName'] as String?)?.isEmpty ?? true
          ? null
          : m['packageName'] as String,
      durationMinutes: (m['durationMinutes'] as num?)?.toInt(),
      enabled: m['enabled'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SealRule &&
      other.id == id &&
      other.trigger == trigger &&
      other.packageName == packageName &&
      other.durationMinutes == durationMinutes &&
      other.enabled == enabled;

  @override
  int get hashCode =>
      Object.hash(id, trigger, packageName, durationMinutes, enabled);
}

/// One seal holding right now, as reported by the native evaluation.
class ActiveSeal {
  const ActiveSeal({
    required this.ruleId,
    required this.trigger,
    this.packageName,
    this.remainingMs,
  });

  final String ruleId;
  final SealTrigger trigger;
  final String? packageName;

  /// Null = the seal holds while its condition holds (no countdown).
  final int? remainingMs;

  Duration? get remaining =>
      remainingMs == null ? null : Duration(milliseconds: remainingMs!);

  static ActiveSeal? fromMap(Map<String, dynamic> m) {
    final trigger = SealTrigger.fromNative(m['trigger'] as String? ?? '');
    if (trigger == null) return null;
    return ActiveSeal(
      ruleId: m['ruleId'] as String? ?? '',
      trigger: trigger,
      packageName: m['packageName'] as String?,
      remainingMs: (m['remainingMs'] as num?)?.toInt(),
    );
  }

  /// The native details shape, for the shared plain-language seal
  /// description (`describeSealFromDetails` in the UI layer).
  Map<String, dynamic> toDetails() => {
    'ruleId': ruleId,
    'trigger': trigger.nativeName,
    'packageName': packageName,
    'remainingMs': remainingMs,
  };
}

/// Whether replacing [old] with [next] LOOSENS protection (paper-code
/// session required): disabling a rule, or shortening an event seal's
/// duration. Adding a rule, enabling one, or lengthening a duration
/// tightens and is free.
bool sealChangeLoosens(SealRule old, SealRule next) {
  if (old.enabled && !next.enabled) return true;
  if (old.trigger.isEvent && next.trigger.isEvent) {
    final o = old.durationMinutes ?? 0;
    final n = next.durationMinutes ?? 0;
    if (n < o) return true;
  }
  return false;
}

/// Deleting a rule always loosens (it removes protection).
bool sealDeletionLoosens(SealRule rule) => rule.enabled;
