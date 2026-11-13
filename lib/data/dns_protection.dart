/// DNS filtering for browsers that cannot honour URL restrictions
/// (Batch DNS, 2026-11-13).
///
/// Android's Private DNS is a single device-wide setting: it cannot be
/// scoped to one browser. Enabling it for any unsupported browser
/// filters the whole device — every browser and every app that uses
/// system DNS. That is the honest trade-off the screen states: no
/// per-page blocking, domain-level only, and bypassable from inside a
/// browser (in-browser secure DNS, in-app VPNs). The two providers
/// below are both selectable inside the app:
///
/// * [DnsProvider.cleanBrowsing] — the free Family filter, no account,
///   blocks adult content + proxies/VPNs and enforces SafeSearch, but
///   cannot apply the user's own blocklists.
/// * [DnsProvider.nextdns] — applies the user's own denylist (managed
///   in the NextDNS dashboard) via the profile's configuration ID;
///   free up to 300,000 queries/month, after which filtering stops
///   silently until the month resets (fail-open).
library;

/// The filtering DNS provider behind DNS protection.
enum DnsProvider {
  nextdns,
  cleanBrowsing;

  /// Unknown or absent names fall back to CleanBrowsing — the provider
  /// that works with no setup — matching the constructor default.
  static DnsProvider fromName(String? name) => switch (name) {
    'nextdns' => nextdns,
    _ => cleanBrowsing,
  };
}

/// Persisted DNS-protection selection for the browser screen.
class DnsProtection {
  const DnsProtection({
    this.enabled = false,
    this.provider = DnsProvider.cleanBrowsing,
    this.nextDnsConfigId = '',
  });

  final bool enabled;
  final DnsProvider provider;

  /// The NextDNS configuration ID (the part before `.dns.nextdns.io`),
  /// e.g. `abc123`. Ignored unless [provider] is [DnsProvider.nextdns].
  final String nextDnsConfigId;

  /// The CleanBrowsing Family filter DoT hostname (free, no account).
  /// Verified against cleanbrowsing.org 2026-11-13.
  static const cleanBrowsingHostname =
      'family-filter-dns.cleanbrowsing.org';

  /// The hostname to set as the device's Private DNS provider, or null
  /// when nothing can be applied (disabled, or NextDNS without an ID).
  String? get hostname {
    if (!enabled) return null;
    return switch (provider) {
      DnsProvider.cleanBrowsing => cleanBrowsingHostname,
      DnsProvider.nextdns => isValidConfigId(nextDnsConfigId)
          ? '${nextDnsConfigId.trim()}.dns.nextdns.io'
          : null,
    };
  }

  /// True when the current selection can be applied as-is.
  bool get isValid => !enabled || hostname != null;

  /// The native side rejects blank hostnames and any hostname with a
  /// space or a slash (`DeviceOwnerManager.setPrivateDns`); mirror that
  /// rule here so the UI refuses an ID early instead of surfacing a
  /// native error.
  static bool isValidConfigId(String id) {
    final v = id.trim();
    return v.isNotEmpty && !v.contains(' ') && !v.contains('/');
  }

  DnsProtection copyWith({
    bool? enabled,
    DnsProvider? provider,
    String? nextDnsConfigId,
  }) =>
      DnsProtection(
        enabled: enabled ?? this.enabled,
        provider: provider ?? this.provider,
        nextDnsConfigId: nextDnsConfigId ?? this.nextDnsConfigId,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'provider': provider.name,
        'nextDnsConfigId': nextDnsConfigId,
      };

  factory DnsProtection.fromJson(Map<String, dynamic> json) =>
      DnsProtection(
        enabled: json['enabled'] as bool? ?? false,
        provider: DnsProvider.fromName(json['provider'] as String?),
        nextDnsConfigId: json['nextDnsConfigId'] as String? ?? '',
      );
}
