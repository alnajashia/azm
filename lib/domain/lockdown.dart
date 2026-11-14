/// Full-phone lockdown (Batch I-B, item 14): two tiers, user-chosen
/// in-app with a per-tier explanation.
///
///  - **Tier 1** (strict = false): suspends the lockdown's targets
///    (every user app, chosen apps, or groups), adds the
///    install/safe-boot restrictions, and locks the phone now. The
///    home screen stays, with greyed-out icons.
///  - **Tier 2** (strict = true): everything in Tier 1, plus
///    `setLockTaskPackages([Azm])` and a dedicated countdown activity
///    in lock-task mode — only Azm's countdown is visible.
///
/// This Dart model mirrors the native shape for the settings UI. The
/// authoritative store, the suspension claims, and the enforcement
/// are NATIVE (`LockdownStore` in Kotlin). A lockdown is data, not a
/// process: starting, ending, and the recurring windows all funnel
/// into the native `sync`, so a lockdown survives reboots and
/// force-stops.
///
/// Hard limits, stated in the UI: powering the phone off cannot be
/// prevented (the lockdown re-applies after reboot); the emergency
/// dialer stays reachable; the default dialer, the launcher,
/// Settings and Azm itself are never suspended.
library;

/// One-shot: a single duration from now. Recurring: a weekly window
/// (days + start/end time) that starts itself.
enum LockdownKind { oneShot, recurring }

/// What the lockdown suspends: every user app, chosen apps, or the
/// members of chosen groups.
enum LockdownScope { allApps, apps, groups }

class Lockdown {
  const Lockdown({
    required this.id,
    this.kind = LockdownKind.oneShot,
    this.durationMinutes = 180,
    this.startHour = 6,
    this.startMinute = 0,
    this.endHour = 10,
    this.endMinute = 0,
    this.daysOfWeek = const {},
    this.scope = LockdownScope.allApps,
    this.targetApps = const {},
    this.targetGroups = const {},
    this.strict = false,
    this.enabled = true,
    this.label = '',
  });

  final String id;
  final LockdownKind kind;
  final int durationMinutes; // one-shot only, 5..720
  final int startHour; // recurring only, 0..23
  final int startMinute; // recurring only, 0..59
  final int endHour; // recurring only, 0..23
  final int endMinute; // recurring only, 0..59
  final Set<int> daysOfWeek; // recurring only, 1 = Monday .. 7 = Sunday
  final LockdownScope scope;
  final Set<String> targetApps; // scope == apps
  final Set<String> targetGroups; // scope == groups
  final bool strict; // Tier 2 kiosk
  final bool enabled; // recurring only
  final String label;

  String get formattedStart =>
      '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')}';

  String get formattedEnd =>
      '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}';

  /// Short day summary for the list: "Every day", "Weekdays",
  /// "Weekend", or the day names in order. [dayNames] is indexed
  /// 0 = Monday, supplied by the caller (localized). Same shape as
  /// FocusSchedule.daysSummary — a separate copy because the two
  /// models are independent.
  String daysSummary({
    required String everyDay,
    required String weekdays,
    required String weekend,
    required List<String> dayNames,
  }) {
    if (daysOfWeek.length == 7) return everyDay;
    if (daysOfWeek.length == 5 &&
        daysOfWeek.containsAll(const {1, 2, 3, 4, 5})) {
      return weekdays;
    }
    if (daysOfWeek.length == 2 && daysOfWeek.containsAll(const {6, 7})) {
      return weekend;
    }
    final sorted = daysOfWeek.toList()..sort();
    return sorted.map((d) => dayNames[d - 1]).join(' · ');
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'kind': kind == LockdownKind.oneShot ? 'ONE_SHOT' : 'RECURRING',
        'durationMinutes': durationMinutes,
        'startHour': startHour,
        'startMinute': startMinute,
        'endHour': endHour,
        'endMinute': endMinute,
        'days': daysOfWeek.toList()..sort(),
        'scope': switch (scope) {
          LockdownScope.allApps => 'ALL_APPS',
          LockdownScope.apps => 'APPS',
          LockdownScope.groups => 'GROUPS',
        },
        'targetApps': targetApps.toList()..sort(),
        'targetGroups': targetGroups.toList()..sort(),
        'strict': strict,
        'enabled': enabled,
        'label': label,
      };

  static Lockdown? fromMap(Map<String, dynamic> m) {
    final id = m['id'] as String?;
    if (id == null || id.isEmpty) return null;
    final days = (m['days'] as List?)
            ?.whereType<num>()
            .map((n) => n.toInt())
            .where((d) => d >= 1 && d <= 7)
            .toSet() ??
        const <int>{};
    Set<String> stringSet(String key) => (m[key] as List?)
            ?.whereType<String>()
            .where((s) => s.isNotEmpty)
            .toSet() ??
        const <String>{};
    return Lockdown(
      id: id,
      kind: m['kind'] == 'RECURRING'
          ? LockdownKind.recurring
          : LockdownKind.oneShot,
      durationMinutes:
          (m['durationMinutes'] as num?)?.toInt().clamp(5, 720) ?? 180,
      startHour: (m['startHour'] as num?)?.toInt().clamp(0, 23) ?? 6,
      startMinute: (m['startMinute'] as num?)?.toInt().clamp(0, 59) ?? 0,
      endHour: (m['endHour'] as num?)?.toInt().clamp(0, 23) ?? 10,
      endMinute: (m['endMinute'] as num?)?.toInt().clamp(0, 59) ?? 0,
      daysOfWeek: days,
      scope: switch (m['scope']) {
        'APPS' => LockdownScope.apps,
        'GROUPS' => LockdownScope.groups,
        _ => LockdownScope.allApps,
      },
      targetApps: stringSet('targetApps'),
      targetGroups: stringSet('targetGroups'),
      strict: m['strict'] as bool? ?? false,
      enabled: m['enabled'] as bool? ?? true,
      label: m['label'] as String? ?? '',
    );
  }

  Lockdown copyWith({
    LockdownKind? kind,
    int? durationMinutes,
    int? startHour,
    int? startMinute,
    int? endHour,
    int? endMinute,
    Set<int>? daysOfWeek,
    LockdownScope? scope,
    Set<String>? targetApps,
    Set<String>? targetGroups,
    bool? strict,
    bool? enabled,
    String? label,
  }) =>
      Lockdown(
        id: id,
        kind: kind ?? this.kind,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        startHour: startHour ?? this.startHour,
        startMinute: startMinute ?? this.startMinute,
        endHour: endHour ?? this.endHour,
        endMinute: endMinute ?? this.endMinute,
        daysOfWeek: daysOfWeek ?? this.daysOfWeek,
        scope: scope ?? this.scope,
        targetApps: targetApps ?? this.targetApps,
        targetGroups: targetGroups ?? this.targetGroups,
        strict: strict ?? this.strict,
        enabled: enabled ?? this.enabled,
        label: label ?? this.label,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Lockdown &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          kind == other.kind &&
          durationMinutes == other.durationMinutes &&
          startHour == other.startHour &&
          startMinute == other.startMinute &&
          endHour == other.endHour &&
          endMinute == other.endMinute &&
          daysOfWeek.length == other.daysOfWeek.length &&
          daysOfWeek.containsAll(other.daysOfWeek) &&
          scope == other.scope &&
          targetApps.length == other.targetApps.length &&
          targetApps.containsAll(other.targetApps) &&
          targetGroups.length == other.targetGroups.length &&
          targetGroups.containsAll(other.targetGroups) &&
          strict == other.strict &&
          enabled == other.enabled &&
          label == other.label;

  @override
  int get hashCode => Object.hash(
        id,
        kind,
        durationMinutes,
        startHour,
        startMinute,
        endHour,
        endMinute,
        Object.hashAll(daysOfWeek.toList()..sort()),
        scope,
        Object.hashAll(targetApps.toList()..sort()),
        Object.hashAll(targetGroups.toList()..sort()),
        strict,
        enabled,
        label,
      );
}

/// The running lockdown, if any (null when none is active).
class ActiveLockdown {
  const ActiveLockdown({
    required this.id,
    required this.label,
    required this.strict,
    required this.scope,
    required this.endWallClockMs,
    required this.remainingMs,
    required this.claimedCount,
  });

  final String id;
  final String label;
  final bool strict;
  final LockdownScope scope;
  final int endWallClockMs;
  final int remainingMs;
  final int claimedCount;

  static ActiveLockdown? fromMap(Map<String, dynamic>? m) {
    if (m == null) return null;
    final id = m['id'] as String?;
    if (id == null || id.isEmpty) return null;
    return ActiveLockdown(
      id: id,
      label: m['label'] as String? ?? '',
      strict: m['strict'] as bool? ?? false,
      scope: switch (m['scope']) {
        'APPS' => LockdownScope.apps,
        'GROUPS' => LockdownScope.groups,
        _ => LockdownScope.allApps,
      },
      endWallClockMs: (m['endWallClockMs'] as num?)?.toInt() ?? 0,
      remainingMs: (m['remainingMs'] as num?)?.toInt() ?? 0,
      claimedCount: (m['claimedCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class LockdownState {
  const LockdownState({
    required this.lockdowns,
    required this.active,
    required this.canScheduleExactAlarms,
  });

  final List<Lockdown> lockdowns; // recurring windows (one-shots are transient)
  final ActiveLockdown? active;
  final bool canScheduleExactAlarms;
}
