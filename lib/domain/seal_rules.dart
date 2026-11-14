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
  lockdownRunning,
  visualDetection,
  bannedWord;

  bool get isEvent =>
      this == SealTrigger.visualDetection || this == SealTrigger.bannedWord;

  bool get needsApp =>
      this != SealTrigger.focusRunning &&
      this != SealTrigger.lockdownRunning;

  /// The native enum name (Kotlin `SealRules.Trigger`).
  String get nativeName => switch (this) {
    SealTrigger.appBlocked => 'APP_BLOCKED',
    SealTrigger.appSuspended => 'APP_SUSPENDED',
    SealTrigger.focusRunning => 'FOCUS_RUNNING',
    SealTrigger.lockdownRunning => 'LOCKDOWN_RUNNING',
    SealTrigger.visualDetection => 'VISUAL_DETECTION',
    SealTrigger.bannedWord => 'BANNED_WORD',
  };

  static SealTrigger? fromNative(String name) => switch (name) {
    'APP_BLOCKED' => SealTrigger.appBlocked,
    'APP_SUSPENDED' => SealTrigger.appSuspended,
    'FOCUS_RUNNING' => SealTrigger.focusRunning,
    'LOCKDOWN_RUNNING' => SealTrigger.lockdownRunning,
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
    this.packageNames = const [],
    this.groupId,
    this.durationMinutes,
    this.enabled = true,
  });

  final String id;
  final SealTrigger trigger;

  /// The chosen apps for app-scoped triggers (Batch H, item 12 —
  /// was a single `packageName`). Empty = none chosen yet.
  final List<String> packageNames;

  /// The chosen group for app-scoped triggers, if any. A rule
  /// watches its apps AND the group's members.
  final String? groupId;

  /// Event seals only: how long the seal holds from the event.
  final int? durationMinutes;

  final bool enabled;

  SealRule copyWith({
    SealTrigger? trigger,
    List<String>? packageNames,
    String? groupId,
    bool clearGroupId = false,
    int? durationMinutes,
    bool? enabled,
  }) => SealRule(
    id: id,
    trigger: trigger ?? this.trigger,
    packageNames: packageNames ?? this.packageNames,
    groupId: clearGroupId ? null : (groupId ?? this.groupId),
    durationMinutes: durationMinutes ?? this.durationMinutes,
    enabled: enabled ?? this.enabled,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'trigger': trigger.nativeName,
    'packageNames': packageNames,
    'groupId': groupId,
    'durationMinutes': durationMinutes,
    'enabled': enabled,
  };

  static SealRule? fromMap(Map<String, dynamic> m) {
    final trigger = SealTrigger.fromNative(m['trigger'] as String? ?? '');
    final id = m['id'] as String? ?? '';
    if (trigger == null || id.isEmpty) return null;
    // Batch H migration: a legacy `packageName` becomes a
    // one-element `packageNames`.
    final names = (m['packageNames'] as List?)
        ?.map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList();
    final legacy = (m['packageName'] as String?)?.isEmpty ?? true
        ? null
        : m['packageName'] as String;
    return SealRule(
      id: id,
      trigger: trigger,
      packageNames: names ?? (legacy == null ? const [] : [legacy]),
      groupId: (m['groupId'] as String?)?.isEmpty ?? true
          ? null
          : m['groupId'] as String,
      durationMinutes: (m['durationMinutes'] as num?)?.toInt(),
      enabled: m['enabled'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SealRule &&
      other.id == id &&
      other.trigger == trigger &&
      _listEquals(other.packageNames, packageNames) &&
      other.groupId == groupId &&
      other.durationMinutes == durationMinutes &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(
    id,
    trigger,
    // Set hash: == compares packageNames as a set (order-free).
    Object.hashAll(packageNames.toSet()),
    groupId,
    durationMinutes,
    enabled,
  );
}

bool _listEquals(List<String> a, List<String> b) =>
    a.length == b.length && a.toSet().containsAll(b);

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
/// session required): disabling a rule, shortening an event seal's
/// duration, or NARROWING its targets (losing an app, or losing the
/// group — same trigger). Adding a rule, enabling one, lengthening a
/// duration, or widening the targets tightens and is free.
/// (Group membership changes are the group's own concern — group
/// edits are gated separately.)
bool sealChangeLoosens(SealRule old, SealRule next) {
  if (old.enabled && !next.enabled) return true;
  if (old.trigger.isEvent && next.trigger.isEvent) {
    final o = old.durationMinutes ?? 0;
    final n = next.durationMinutes ?? 0;
    if (n < o) return true;
  }
  if (old.trigger == next.trigger) {
    if (!next.packageNames.toSet().containsAll(old.packageNames)) {
      return true;
    }
    if (old.groupId != null && next.groupId != old.groupId) return true;
  }
  return false;
}

/// Deleting a rule always loosens (it removes protection).
bool sealDeletionLoosens(SealRule rule) => rule.enabled;
