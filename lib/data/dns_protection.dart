/// DNS filtering for browsers that cannot honour URL restrictions
/// (Batch DNS, 2026-11-13; unified into ONE card 2026-11-14).
///
/// Android's Private DNS is a single device-wide setting: it cannot be
/// scoped to one browser. Enabling it for any unsupported browser
/// filters the whole device — every browser and every app that uses
/// system DNS. That is the honest trade-off the screen states: no
/// per-page blocking, domain-level only, and bypassable from inside a
/// browser (in-browser secure DNS, in-app VPNs).
///
/// The card offers ONE optional list: the switch off means "none", and
/// the radio choice means exactly one provider — Android accepts a
/// single Private DNS hostname at a time, so "more than one at once"
/// is impossible, and the UI says so by construction (radio, not
/// checkboxes). The providers are the union of the two pre-unification
/// UIs (the Batch DNS card's NextDNS/CleanBrowsing and the Config-tab
/// dialog's Cloudflare/AdGuard/CleanBrowsing/custom):
///
/// * [DnsProvider.cleanBrowsing] — the free Family filter, no account,
///   blocks adult content + proxies/VPNs and enforces SafeSearch, but
///   cannot apply the user's own blocklists.
/// * [DnsProvider.nextdns] — applies the user's own denylist (managed
///   in the NextDNS dashboard) via the profile's configuration ID;
///   free up to 300,000 queries/month, after which filtering stops
///   silently until the month resets (fail-open).
/// * [DnsProvider.cloudflare] — the free Cloudflare Family filter, no
///   account: blocks malware and adult content.
/// * [DnsProvider.adguard] — the free AdGuard Family filter, no
///   account: blocks adult content.
/// * [DnsProvider.custom] — the user's own DNS hostname.
library;

/// The filtering DNS provider behind DNS protection.
enum DnsProvider {
  nextdns,
  cleanBrowsing,
  cloudflare,
  adguard,
  custom;

  /// Unknown or absent names fall back to CleanBrowsing — the provider
  /// that works with no setup — matching the constructor default.
  static DnsProvider fromName(String? name) => switch (name) {
    'nextdns' => nextdns,
    'cloudflare' => cloudflare,
    'adguard' => adguard,
    'custom' => custom,
    _ => cleanBrowsing,
  };
}

/// Persisted DNS-protection selection for the browser screen.
class DnsProtection {
  const DnsProtection({
    this.enabled = false,
    this.provider = DnsProvider.cleanBrowsing,
    this.nextDnsConfigId = '',
    this.customHostname = '',
  });

  final bool enabled;
  final DnsProvider provider;

  /// The NextDNS configuration ID (the part before `.dns.nextdns.io`),
  /// e.g. `abc123`. Ignored unless [provider] is [DnsProvider.nextdns].
  final String nextDnsConfigId;

  /// The user-entered hostname for [DnsProvider.custom]. Ignored
  /// unless [provider] is [DnsProvider.custom].
  final String customHostname;

  /// The CleanBrowsing Family filter DoT hostname (free, no account).
  /// Verified against cleanbrowsing.org 2026-11-13.
  static const cleanBrowsingHostname =
      'family-filter-dns.cleanbrowsing.org';

  /// The Cloudflare Family filter DoT hostname (free, no account).
  /// From the original Config-tab dialog presets (v1.0.6).
  static const cloudflareHostname = 'family.cloudflare-dns.com';

  /// The AdGuard Family filter DoT hostname (free, no account).
  /// From the original Config-tab dialog presets (v1.0.6).
  static const adguardHostname = 'family.adguard-dns.com';

  /// The hostname to set as the device's Private DNS provider, or null
  /// when nothing can be applied (disabled, or NextDNS without an ID,
  /// or custom without a valid hostname).
  String? get hostname {
    if (!enabled) return null;
    return switch (provider) {
      DnsProvider.cleanBrowsing => cleanBrowsingHostname,
      DnsProvider.nextdns => isValidConfigId(nextDnsConfigId)
          ? '${nextDnsConfigId.trim()}.dns.nextdns.io'
          : null,
      DnsProvider.cloudflare => cloudflareHostname,
      DnsProvider.adguard => adguardHostname,
      DnsProvider.custom => isValidCustomHostname(customHostname)
          ? customHostname.trim()
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

  /// A custom hostname must be lowercase dot-separated labels with a
  /// TLD of at least two letters (the original dialog's rule,
  /// `ConfigTab.kt:538-540`, moved here with the unification).
  static bool isValidCustomHostname(String host) => RegExp(
    r'^([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}$',
  ).hasMatch(host.trim());

  /// Maps a live device hostname back to the selection that produces
  /// it — used when the saved prefs disagree with the live DPM state
  /// (e.g. a host set by the retired Config-tab dialog, which never
  /// persisted). Known hostnames map to their provider; any other
  /// non-empty hostname is a custom one. Null means "nothing live".
  static DnsProtection fromLiveHost(String? hostname) {
    final host = hostname?.trim() ?? '';
    if (host.isEmpty) return const DnsProtection();
    return switch (host) {
      cleanBrowsingHostname => const DnsProtection(
        enabled: true,
        provider: DnsProvider.cleanBrowsing,
      ),
      cloudflareHostname => const DnsProtection(
        enabled: true,
        provider: DnsProvider.cloudflare,
      ),
      adguardHostname => const DnsProtection(
        enabled: true,
        provider: DnsProvider.adguard,
      ),
      _ => host.endsWith('.dns.nextdns.io')
          ? DnsProtection(
              enabled: true,
              provider: DnsProvider.nextdns,
              nextDnsConfigId: host.substring(
                0,
                host.length - '.dns.nextdns.io'.length,
              ),
            )
          : DnsProtection(
              enabled: true,
              provider: DnsProvider.custom,
              customHostname: host,
            ),
    };
  }

  DnsProtection copyWith({
    bool? enabled,
    DnsProvider? provider,
    String? nextDnsConfigId,
    String? customHostname,
  }) =>
      DnsProtection(
        enabled: enabled ?? this.enabled,
        provider: provider ?? this.provider,
        nextDnsConfigId: nextDnsConfigId ?? this.nextDnsConfigId,
        customHostname: customHostname ?? this.customHostname,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'provider': provider.name,
        'nextDnsConfigId': nextDnsConfigId,
        'customHostname': customHostname,
      };

  factory DnsProtection.fromJson(Map<String, dynamic> json) =>
      DnsProtection(
        enabled: json['enabled'] as bool? ?? false,
        provider: DnsProvider.fromName(json['provider'] as String?),
        nextDnsConfigId: json['nextDnsConfigId'] as String? ?? '',
        customHostname: json['customHostname'] as String? ?? '',
      );
}
