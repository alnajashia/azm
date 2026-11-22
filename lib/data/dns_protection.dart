/// DNS filtering for browsers that cannot honour URL restrictions
/// (Batch DNS, 2026-11-13; unified into ONE card 2026-11-14; moved
/// back to a list in general Settings as a dialog 2026-11-14, item 5).
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
/// checkboxes). The dialog in Settings offers the same list with an
/// explicit Off choice. NextDNS was removed at the user's request
/// 2026-11-14: a saved NextDNS selection falls back to CleanBrowsing,
/// and a live NextDNS hostname is adopted as a Custom hostname (the
/// host itself stays applied — nothing is silently turned off).
/// The dialog never refuses a provider choice: picking Custom shows
/// the hostname field at once, and Apply stays disabled until the
/// (lowercase-normalised) hostname is valid — the old card refused
/// the switch itself, so the field could never be reached (item 5).
///
/// * [DnsProvider.cleanBrowsing] — the free Family filter, no account,
///   blocks adult content + proxies/VPNs and enforces SafeSearch, but
///   cannot apply the user's own blocklists.
/// * [DnsProvider.cloudflare] — the free Cloudflare Family filter, no
///   account: blocks malware and adult content.
/// * [DnsProvider.adguard] — the free AdGuard Family filter, no
///   account: blocks adult content.
/// * [DnsProvider.custom] — the user's own DNS hostname.
///
/// VPN mode (user request 2026-11-22): [DnsProtection.viaVpn] is the
/// "DNS via VPN" switch in the Settings dialog. When it is on, the
/// provider list is shown and the chosen provider activates
/// automatically whenever a VPN is on — Azm's own VPN (DoH filtering
/// over port 443, via the internet-block config) or any external VPN
/// (Azm applies the same provider as system Private DNS while the
/// external VPN is up; see the native `ExternalVpnWatcher`). When it
/// is off, the list is hidden and any running VPN DNS filtering
/// stops (recovery-gated, like every deactivation).
library;

import '../domain/internet_block.dart';

/// The filtering DNS provider behind DNS protection.
enum DnsProvider {
  cleanBrowsing,
  cloudflare,
  adguard,
  custom;

  /// Unknown or absent names fall back to CleanBrowsing — the provider
  /// that works with no setup — matching the constructor default.
  /// (A saved 'nextdns' name lands here too — NextDNS was removed
  /// 2026-11-14 at the user's request.)
  static DnsProvider fromName(String? name) => switch (name) {
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
    this.customHostname = '',
    this.viaVpn = false,
    this.customDohUrl = '',
  });

  final bool enabled;
  final DnsProvider provider;

  /// The user-entered hostname for [DnsProvider.custom]. Ignored
  /// unless [provider] is [DnsProvider.custom]. In VPN mode this is
  /// the host part of [customDohUrl] — the Private DNS host Azm
  /// applies while an external VPN is up.
  final String customHostname;

  /// The "DNS via VPN" switch (user request 2026-11-22): the chosen
  /// provider activates automatically whenever a VPN is on. The
  /// Settings dialog shows the provider list only while this is on.
  final bool viaVpn;

  /// The user-entered DoH endpoint for [DnsProvider.custom] in VPN
  /// mode (https URL). Ignored unless [provider] is
  /// [DnsProvider.custom].
  final String customDohUrl;

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
  /// when nothing can be applied (disabled, or custom without a valid
  /// hostname).
  String? get hostname {
    if (!enabled) return null;
    return switch (provider) {
      DnsProvider.cleanBrowsing => cleanBrowsingHostname,
      DnsProvider.cloudflare => cloudflareHostname,
      DnsProvider.adguard => adguardHostname,
      DnsProvider.custom => isValidCustomHostname(customHostname)
          ? customHostname.trim()
          : null,
    };
  }

  /// True when the current selection can be applied as-is.
  bool get isValid => !enabled || hostname != null;

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
  /// non-empty hostname is a custom one — including a legacy NextDNS
  /// hostname (`<id>.dns.nextdns.io`): it stays applied as Custom
  /// rather than being silently dropped. Null means "nothing live".
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
      _ => DnsProtection(
        enabled: true,
        provider: DnsProvider.custom,
        customHostname: host,
      ),
    };
  }

  DnsProtection copyWith({
    bool? enabled,
    DnsProvider? provider,
    String? customHostname,
    bool? viaVpn,
    String? customDohUrl,
  }) =>
      DnsProtection(
        enabled: enabled ?? this.enabled,
        provider: provider ?? this.provider,
        customHostname: customHostname ?? this.customHostname,
        viaVpn: viaVpn ?? this.viaVpn,
        customDohUrl: customDohUrl ?? this.customDohUrl,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'provider': provider.name,
        'customHostname': customHostname,
        'viaVpn': viaVpn,
        'customDohUrl': customDohUrl,
      };

  factory DnsProtection.fromJson(Map<String, dynamic> json) =>
      DnsProtection(
        enabled: json['enabled'] as bool? ?? false,
        provider: DnsProvider.fromName(json['provider'] as String?),
        customHostname: json['customHostname'] as String? ?? '',
        // Absent in pre-2026-11-22 saves: the switch reads as off.
        viaVpn: json['viaVpn'] as bool? ?? false,
        customDohUrl: json['customDohUrl'] as String? ?? '',
      );
}

/// The internet-block DoH provider matching a [DnsProvider] (the two
/// enums name the same four providers; the DNS dialog and the
/// internet-block screen edit one shared choice).
DohProvider dohProviderFor(DnsProvider provider) => switch (provider) {
      DnsProvider.cleanBrowsing => DohProvider.cleanBrowsing,
      DnsProvider.cloudflare => DohProvider.cloudflare,
      DnsProvider.adguard => DohProvider.adguard,
      DnsProvider.custom => DohProvider.custom,
    };

/// The [DnsProvider] matching an internet-block DoH provider.
DnsProvider dnsProviderFor(DohProvider provider) => switch (provider) {
      DohProvider.cleanBrowsing => DnsProvider.cleanBrowsing,
      DohProvider.cloudflare => DnsProvider.cloudflare,
      DohProvider.adguard => DnsProvider.adguard,
      DohProvider.custom => DnsProvider.custom,
    };

/// The host part of a DoH URL, lowercased — the Private DNS host
/// Azm applies for a custom provider while an external VPN is up.
/// Empty when [url] does not parse to a host.
String dohUrlHost(String url) =>
    Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
