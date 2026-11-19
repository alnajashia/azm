/// Internet blocking + VPN-based DNS filtering (user order
/// 2026-11-19). One local, no-configuration VPN serves both:
/// DNS filtering over DoH (port 443 — works where port 853 is
/// blocked) and internet blocking per app, per group, or for the
/// whole phone. The native `VpnConfigStore` is the source of
/// truth; this model is its wire shape.
library;

enum InternetBlockLevel {
  /// DNS filtering only — nothing is blocked outright.
  off('off'),

  /// Chosen apps run without internet.
  apps('apps'),

  /// Members of the chosen groups run without internet.
  groups('groups'),

  /// The whole phone has no internet (Azm itself excluded).
  phone('phone');

  const InternetBlockLevel(this.wireName);

  final String wireName;

  static InternetBlockLevel fromWire(String? value) =>
      values.firstWhere((l) => l.wireName == value, orElse: () => off);

  /// Blocking strength for the loosening gate: phone > apps/groups
  /// > DNS-only. Apps and groups rank equal (both block a chosen
  /// set), so switching between them is not a loosening by itself.
  int get rank => switch (this) {
    InternetBlockLevel.off => 1,
    InternetBlockLevel.apps => 2,
    InternetBlockLevel.groups => 2,
    InternetBlockLevel.phone => 3,
  };
}

enum DohProvider {
  cleanBrowsing('cleanBrowsing'),
  adguard('adguard'),
  cloudflare('cloudflare'),
  custom('custom');

  const DohProvider(this.wireName);

  final String wireName;

  static DohProvider fromWire(String? value) => values.firstWhere(
    (p) => p.wireName == value,
    orElse: () => DohProvider.cleanBrowsing,
  );
}

class InternetBlockConfig {
  const InternetBlockConfig({
    this.enabled = false,
    this.level = InternetBlockLevel.off,
    this.packages = const {},
    this.groupIds = const {},
    this.dohProvider = DohProvider.cleanBrowsing,
    this.customDohUrl = '',
  });

  final bool enabled;
  final InternetBlockLevel level;
  final Set<String> packages;
  final Set<String> groupIds;
  final DohProvider dohProvider;
  final String customDohUrl;

  bool get blocking => level != InternetBlockLevel.off;

  InternetBlockConfig copyWith({
    bool? enabled,
    InternetBlockLevel? level,
    Set<String>? packages,
    Set<String>? groupIds,
    DohProvider? dohProvider,
    String? customDohUrl,
  }) => InternetBlockConfig(
    enabled: enabled ?? this.enabled,
    level: level ?? this.level,
    packages: packages ?? this.packages,
    groupIds: groupIds ?? this.groupIds,
    dohProvider: dohProvider ?? this.dohProvider,
    customDohUrl: customDohUrl ?? this.customDohUrl,
  );

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'level': level.wireName,
    'packages': packages.toList(),
    'groupIds': groupIds.toList(),
    'dohProvider': dohProvider.wireName,
    'customDohUrl': customDohUrl,
  };

  factory InternetBlockConfig.fromMap(Map<dynamic, dynamic> m) =>
      InternetBlockConfig(
        enabled: m['enabled'] == true,
        level: InternetBlockLevel.fromWire(m['level'] as String?),
        packages:
            (m['packages'] as List?)?.map((e) => e.toString()).toSet() ??
            const {},
        groupIds:
            (m['groupIds'] as List?)?.map((e) => e.toString()).toSet() ??
            const {},
        dohProvider: DohProvider.fromWire(m['dohProvider'] as String?),
        customDohUrl: m['customDohUrl'] as String? ?? '',
      );

  /// True when moving from [other] to this config weakens the
  /// protection (recovery-code-gated): turning off, dropping to a
  /// weaker level, or shrinking the blocked set.
  bool isLooseningFrom(InternetBlockConfig other) {
    if (other.enabled && !enabled) return true;
    if (level.rank < other.level.rank) return true;
    if (level == InternetBlockLevel.apps &&
        other.level == InternetBlockLevel.apps &&
        !packages.containsAll(other.packages)) {
      return true;
    }
    if (level == InternetBlockLevel.groups &&
        other.level == InternetBlockLevel.groups &&
        !groupIds.containsAll(other.groupIds)) {
      return true;
    }
    return false;
  }

  @override
  bool operator ==(Object other) =>
      other is InternetBlockConfig &&
      other.enabled == enabled &&
      other.level == level &&
      other.packages.length == packages.length &&
      other.packages.containsAll(packages) &&
      other.groupIds.length == groupIds.length &&
      other.groupIds.containsAll(groupIds) &&
      other.dohProvider == dohProvider &&
      other.customDohUrl == customDohUrl;

  @override
  int get hashCode => Object.hash(
    enabled,
    level,
    Object.hashAllUnordered(packages),
    Object.hashAllUnordered(groupIds),
    dohProvider,
    customDohUrl,
  );
}
