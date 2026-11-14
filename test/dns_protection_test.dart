/// Batch DNS regression tests (fake channel — the established pattern
/// from batch_c_features_test.dart):
///
///  Model — hostname building per provider, validation mirroring the
///  native rule, JSON round-trip and corrupt-input defaults.
///  Screen — the DNS shortcut card below the browsers and the full DNS
///  card below the blocklists both render; enabling with CleanBrowsing
///  calls setPrivateDns with the Family hostname; enabling with
///  NextDNS and a blank ID is refused with the validation message and
///  no channel call; entering an ID then enabling calls setPrivateDns
///  with `<id>.dns.nextdns.io`; disabling goes through the recovery
///  gate and calls resetPrivateDns.
///
///  DNS batch (2026-11-14, unification): one card, optional provider
///  list (none = switch off, or exactly one of NextDNS / CleanBrowsing
///  / Cloudflare / AdGuard / Custom); the Config-tab dialog is retired
///  (its tile navigates to this card); the real failure reason is
///  shown inline with a Retry button; HOST_NOT_SERVING is retried
///  automatically; a live host the prefs do not know is adopted.
library;

import 'dart:convert';

import 'package:azm/app_controller.dart';
import 'package:azm/data/dns_protection.dart';
import 'package:azm/data/privileged_channel.dart';
import 'package:azm/l10n/app_localizations.dart';
import 'package:azm/theme.dart';
import 'package:azm/ui/config_screens.dart';
import 'package:azm/ui/config_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'azm/privileged';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methodChannel = MethodChannel(channelName);

  // ---- Fake channel state (reset before every test) ----------------
  late List<MethodCall> calls;
  late List<Map<String, dynamic>> fakeBrowsers;
  late String? fakeDnsJson;
  late String fakeDnsMode;
  late String? fakeDnsHostname;

  /// Upcoming setPrivateDns failures to inject (DNS batch): each
  /// decrements per failed call and throws a DPM_FAILED
  /// PlatformException carrying the DPM result code in details.
  late int setPrivateDnsFailures;
  late int setPrivateDnsFailureCode;
  final createdControllers = <AppController>[];

  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher
        .implicitView!;
    view.physicalSize = const Size(800, 4000);
    view.devicePixelRatio = 1.0;
    calls = [];
    fakeBrowsers = [
      {
        'packageName': 'com.android.chrome',
        'label': 'Chrome',
        'supportsRestrictions': true,
        'isSuspended': false,
        'icon': null,
      },
      {
        'packageName': 'com.example.browser',
        'label': 'Example Browser',
        'supportsRestrictions': false,
        'isSuspended': false,
        'icon': null,
      },
    ];
    fakeDnsJson = null;
    fakeDnsMode = 'PRIVATE_DNS_MODE_OPPORTUNISTIC';
    fakeDnsHostname = null;
    setPrivateDnsFailures = 0;
    setPrivateDnsFailureCode = 2;

    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'isDeviceOwner':
          return {
            'isDeviceOwner': true,
            'isAdminActive': true,
            'forcedRemovalDelayHours': 24,
          };
        case 'getPrivateDns':
          return {'mode': fakeDnsMode, 'hostname': fakeDnsHostname};
        case 'setPrivateDns':
          if (setPrivateDnsFailures > 0) {
            setPrivateDnsFailures--;
            throw PlatformException(
              code: 'DPM_FAILED',
              message:
                  'Private DNS was not applied (DPM result code $setPrivateDnsFailureCode)',
              details: {'verifiedState': setPrivateDnsFailureCode},
            );
          }
          final host = call.arguments['hostname'] as String;
          fakeDnsMode = 'PRIVATE_DNS_MODE_PROVIDER_HOSTNAME_SPECIFIED';
          fakeDnsHostname = host;
          return {'mode': fakeDnsMode, 'hostname': host};
        case 'resetPrivateDns':
          fakeDnsMode = 'PRIVATE_DNS_MODE_OPPORTUNISTIC';
          fakeDnsHostname = null;
          return {'mode': fakeDnsMode, 'hostname': null};
        case 'listInstalledBrowsers':
          return fakeBrowsers;
        case 'getSetting':
          final store = call.arguments['store'] as String?;
          final key = call.arguments['key'] as String?;
          if (store == 'browser_prefs' && key == 'blocked_lists_json') {
            return {'value': null};
          }
          if (store == 'browser_prefs' && key == 'dns_protection_json') {
            return {'value': fakeDnsJson};
          }
          return {'value': null};
        case 'setSetting':
          final store = call.arguments['store'] as String?;
          final key = call.arguments['key'] as String?;
          if (store == 'browser_prefs' && key == 'dns_protection_json') {
            fakeDnsJson = call.arguments['value'] as String?;
          }
          return {'value': call.arguments['value']};
        case 'isRecoveryCodeSet':
          return {'isSet': true};
        case 'verifyRecoveryCode':
          return {'matches': true};
        case 'getUserRestrictionResidue':
          return {'keys': <String>[]};
        case 'listUserRestrictions':
          return {'restrictions': <String, dynamic>{}};
        case 'getShizukuState':
          return {'isInstalled': false, 'isAuthorized': false};
      }
      throw MissingPluginException('Unhandled ${call.method} in DNS test');
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
    for (final c in createdControllers) {
      // Mirror batch_c: end the recovery session (cancels its
      // 1-second ticker) — dispose alone leaves the timer pending.
      c.session.end();
    }
    createdControllers.clear();
  });

  Widget buildTestApp({required Widget child}) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: azmLightTheme(),
      darkTheme: azmDarkTheme(),
      home: Scaffold(body: child),
    );
  }

  AppController makeController() {
    final c = AppController.test(PrivilegedChannel(methodChannel: methodChannel));
    createdControllers.add(c);
    return c;
  }

  /// Drives the recovery-gate dialog: types a 16-letter code and
  /// confirms. The fake verifies it as correct.
  Future<void> enterCodeAndConfirm(WidgetTester tester) async {
    await tester.pumpAndSettle();
    expect(find.text('Enter recovery code'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'AAAAAAAAAAAAAAAA');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();
  }

  Future<AppController> pumpScreen(WidgetTester tester) async {
    final controller = makeController();
    await tester.pumpWidget(
      buildTestApp(
        child: BrowserRestrictionsScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Future<AppController> pumpConfigTab(WidgetTester tester) async {
    final controller = makeController();
    await tester.pumpWidget(
      buildTestApp(child: ConfigTab(controller: controller)),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> tapDnsSwitch(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(SwitchListTile, 'DNS protection'),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Taps the DNS switch, then advances the fake clock past the
  /// automatic retry delays (2s/5s/8s). `pumpAndSettle` alone does
  /// NOT advance past a bare `Future.delayed` — it settles when no
  /// frame is scheduled, and the retry loop schedules none between
  /// attempts — so the clock must be moved explicitly.
  Future<void> tapDnsSwitchAndSettleRetries(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(SwitchListTile, 'DNS protection'),
        matching: find.byType(Switch),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
  }

  SwitchListTile dnsTile(WidgetTester tester) => tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'DNS protection'),
      );

  // ------------------------------------------------------------ Model

  group('DnsProtection model', () {
    test('default is off, CleanBrowsing, nothing to apply', () {
      const dns = DnsProtection();
      expect(dns.enabled, isFalse);
      expect(dns.provider, DnsProvider.cleanBrowsing);
      expect(dns.hostname, isNull);
      expect(dns.isValid, isTrue);
    });

    test('CleanBrowsing hostname is the verified Family filter host', () {
      const dns = DnsProtection(enabled: true);
      expect(dns.hostname, DnsProtection.cleanBrowsingHostname);
      expect(dns.hostname, 'family-filter-dns.cleanbrowsing.org');
      expect(dns.isValid, isTrue);
    });

    test('NextDNS hostname is built from the configuration ID', () {
      const dns = DnsProtection(
        enabled: true,
        provider: DnsProvider.nextdns,
        nextDnsConfigId: 'abc123',
      );
      expect(dns.hostname, 'abc123.dns.nextdns.io');
      expect(dns.isValid, isTrue);
    });

    test('NextDNS without an ID cannot be applied', () {
      const dns = DnsProtection(
        enabled: true,
        provider: DnsProvider.nextdns,
      );
      expect(dns.hostname, isNull);
      expect(dns.isValid, isFalse);
      expect(DnsProtection.isValidConfigId(''), isFalse);
      expect(DnsProtection.isValidConfigId('has space'), isFalse);
      expect(DnsProtection.isValidConfigId('has/slash'), isFalse);
      expect(DnsProtection.isValidConfigId('abc123'), isTrue);
    });

    test('JSON round-trip for both providers', () {
      for (final provider in DnsProvider.values) {
        final dns = DnsProtection(
          enabled: true,
          provider: provider,
          nextDnsConfigId: 'abc123',
        );
        final back = DnsProtection.fromJson(
          (jsonDecode(jsonEncode(dns.toJson())) as Map).cast<String, dynamic>(),
        );
        expect(back.enabled, isTrue);
        expect(back.provider, provider);
        expect(back.nextDnsConfigId, 'abc123');
        expect(back.hostname, dns.hostname);
      }
    });

    test('corrupt input reads as the safe default (off, CleanBrowsing)', () {
      final back = DnsProtection.fromJson({'provider': 'not-a-provider'});
      expect(back.enabled, isFalse);
      expect(back.provider, DnsProvider.cleanBrowsing);
    });

    test('Cloudflare/AdGuard hostnames are the Family filter hosts', () {
      const cloudflare = DnsProtection(
        enabled: true,
        provider: DnsProvider.cloudflare,
      );
      expect(cloudflare.hostname, 'family.cloudflare-dns.com');
      expect(cloudflare.hostname, DnsProtection.cloudflareHostname);
      const adguard = DnsProtection(
        enabled: true,
        provider: DnsProvider.adguard,
      );
      expect(adguard.hostname, 'family.adguard-dns.com');
      expect(adguard.hostname, DnsProtection.adguardHostname);
    });

    test('custom hostname validation follows the dialog rule', () {
      expect(DnsProtection.isValidCustomHostname('dns.example.com'), isTrue);
      expect(DnsProtection.isValidCustomHostname('a-b.cdef.co'), isTrue);
      expect(DnsProtection.isValidCustomHostname(''), isFalse);
      expect(DnsProtection.isValidCustomHostname('has space.com'), isFalse);
      expect(DnsProtection.isValidCustomHostname('UPPER.com'), isFalse);
      expect(DnsProtection.isValidCustomHostname('nodot'), isFalse);
      expect(DnsProtection.isValidCustomHostname('a.b'), isFalse);
      const custom = DnsProtection(
        enabled: true,
        provider: DnsProvider.custom,
        customHostname: 'dns.example.com',
      );
      expect(custom.hostname, 'dns.example.com');
      expect(custom.isValid, isTrue);
      const blank = DnsProtection(enabled: true, provider: DnsProvider.custom);
      expect(blank.hostname, isNull);
      expect(blank.isValid, isFalse);
    });

    test('fromLiveHost maps every known host and extracts a NextDNS ID',
        () {
      expect(DnsProtection.fromLiveHost(null).enabled, isFalse);
      expect(
        DnsProtection.fromLiveHost('family-filter-dns.cleanbrowsing.org')
            .provider,
        DnsProvider.cleanBrowsing,
      );
      expect(
        DnsProtection.fromLiveHost('family.cloudflare-dns.com').provider,
        DnsProvider.cloudflare,
      );
      expect(
        DnsProtection.fromLiveHost('family.adguard-dns.com').provider,
        DnsProvider.adguard,
      );
      final nextdns = DnsProtection.fromLiveHost('xyz123.dns.nextdns.io');
      expect(nextdns.provider, DnsProvider.nextdns);
      expect(nextdns.nextDnsConfigId, 'xyz123');
      expect(nextdns.hostname, 'xyz123.dns.nextdns.io');
      final custom = DnsProtection.fromLiveHost('dns.example.com');
      expect(custom.provider, DnsProvider.custom);
      expect(custom.customHostname, 'dns.example.com');
      for (final live in [
        DnsProtection.fromLiveHost('family-filter-dns.cleanbrowsing.org'),
        DnsProtection.fromLiveHost('family.cloudflare-dns.com'),
        DnsProtection.fromLiveHost('family.adguard-dns.com'),
        nextdns,
        custom,
      ]) {
        expect(live.enabled, isTrue);
      }
    });

    test('old JSON without customHostname still parses', () {
      final back = DnsProtection.fromJson({
        'enabled': true,
        'provider': 'nextdns',
        'nextDnsConfigId': 'abc',
      });
      expect(back.provider, DnsProvider.nextdns);
      expect(back.customHostname, isEmpty);
      expect(back.hostname, 'abc.dns.nextdns.io');
    });
  });

  // ------------------------------------------------------------ Screen

  group('Batch DNS — browser screen', () {
    testWidgets('DNS shortcut and full card both render', (tester) async {
      await pumpScreen(tester);

      // Three copies: shortcut title, card title, switch title.
      expect(find.text('DNS protection'), findsNWidgets(3));
      expect(find.text('NextDNS'), findsOneWidget);
      expect(find.text('CleanBrowsing (Family filter)'), findsOneWidget);
      expect(
        find.textContaining('cannot block sites from inside'),
        findsOneWidget,
      );
      expect(find.text('Private DNS is not set'), findsOneWidget);
      expect(dnsTile(tester).value, isFalse);
    });

    testWidgets('selecting NextDNS shows the in-app setup steps',
        (tester) async {
      await pumpScreen(tester);

      expect(find.text('How do I set up NextDNS?'), findsNothing);
      await tester.tap(find.text('NextDNS'));
      await tester.pumpAndSettle();

      expect(find.text('How do I set up NextDNS?'), findsOneWidget);
      expect(
        find.textContaining('Create a free account at nextdns.io'),
        findsOneWidget,
      );
      expect(find.textContaining('Denylist'), findsOneWidget);
    });

    testWidgets('enabling with CleanBrowsing sets the Family hostname',
        (tester) async {
      await pumpScreen(tester);

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(SwitchListTile, 'DNS protection'),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();

      final applied = calls.where((c) => c.method == 'setPrivateDns');
      expect(applied, hasLength(1));
      expect(
        applied.first.arguments['hostname'],
        'family-filter-dns.cleanbrowsing.org',
      );
      expect(find.text('DNS protection applied'), findsOneWidget);
      expect(dnsTile(tester).value, isTrue);
      expect(
        find.text(
          'Current host: family-filter-dns.cleanbrowsing.org',
        ),
        findsOneWidget,
      );
    });

    testWidgets('enabling with NextDNS and a blank ID is refused',
        (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('NextDNS'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(SwitchListTile, 'DNS protection'),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        calls.where((c) => c.method == 'setPrivateDns'),
        isEmpty,
      );
      expect(
        find.text('Enter a valid NextDNS configuration ID'),
        findsOneWidget,
      );
      expect(dnsTile(tester).value, isFalse);
    });

    testWidgets('NextDNS ID then enable sets <id>.dns.nextdns.io',
        (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('NextDNS'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'abc123');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(SwitchListTile, 'DNS protection'),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();

      final applied = calls.where((c) => c.method == 'setPrivateDns');
      expect(applied, hasLength(1));
      expect(applied.first.arguments['hostname'], 'abc123.dns.nextdns.io');
      expect(dnsTile(tester).value, isTrue);
    });

    testWidgets('disabling goes through the recovery gate and resets',
        (tester) async {
      fakeDnsJson = jsonEncode(
        const DnsProtection(enabled: true).toJson(),
      );
      fakeDnsMode = 'PRIVATE_DNS_MODE_PROVIDER_HOSTNAME_SPECIFIED';
      fakeDnsHostname = 'family-filter-dns.cleanbrowsing.org';
      final controller = await pumpScreen(tester);
      expect(dnsTile(tester).value, isTrue);

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(SwitchListTile, 'DNS protection'),
          matching: find.byType(Switch),
        ),
      );
      await enterCodeAndConfirm(tester);

      expect(calls.where((c) => c.method == 'resetPrivateDns'), hasLength(1));
      expect(find.text('DNS protection turned off'), findsOneWidget);
      expect(dnsTile(tester).value, isFalse);
      controller.session.end();
    });

    testWidgets('provider list shows all five options', (tester) async {
      await pumpScreen(tester);

      expect(find.text('NextDNS'), findsOneWidget);
      expect(find.text('CleanBrowsing (Family filter)'), findsOneWidget);
      expect(find.text('Cloudflare (Family filter)'), findsOneWidget);
      expect(find.text('AdGuard DNS (Family filter)'), findsOneWidget);
      expect(find.text('Custom'), findsOneWidget);
    });

    testWidgets('selecting Cloudflare while on applies its hostname',
        (tester) async {
      await pumpScreen(tester);
      await tapDnsSwitch(tester);
      expect(dnsTile(tester).value, isTrue);

      await tester.tap(find.text('Cloudflare (Family filter)'));
      await tester.pumpAndSettle();

      final applied = calls.where((c) => c.method == 'setPrivateDns');
      expect(applied, hasLength(2));
      expect(
        applied.last.arguments['hostname'],
        'family.cloudflare-dns.com',
      );
    });

    testWidgets('custom host then enable applies it', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'dns.example.com');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tapDnsSwitch(tester);

      final applied = calls.where((c) => c.method == 'setPrivateDns');
      expect(applied, hasLength(1));
      expect(applied.first.arguments['hostname'], 'dns.example.com');
      expect(dnsTile(tester).value, isTrue);
    });

    testWidgets('invalid custom hostname is refused', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'not a host');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tapDnsSwitch(tester);

      expect(calls.where((c) => c.method == 'setPrivateDns'), isEmpty);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('Invalid DNS hostname'),
        ),
        findsOneWidget,
      );
      expect(dnsTile(tester).value, isFalse);
    });

    testWidgets('HOST_NOT_SERVING is retried and then applies',
        (tester) async {
      setPrivateDnsFailures = 2;
      setPrivateDnsFailureCode = 2;
      await pumpScreen(tester);

      await tapDnsSwitchAndSettleRetries(tester);

      // Two failures, then success on the third attempt.
      final applied = calls.where((c) => c.method == 'setPrivateDns');
      expect(applied, hasLength(3));
      expect(
        applied.last.arguments['hostname'],
        'family-filter-dns.cleanbrowsing.org',
      );
      expect(find.text('DNS protection applied'), findsOneWidget);
      expect(dnsTile(tester).value, isTrue);
      expect(find.textContaining('not serving'), findsNothing);
    });

    testWidgets('HOST_NOT_SERVING exhausted shows the real reason with Retry',
        (tester) async {
      setPrivateDnsFailures = 10;
      setPrivateDnsFailureCode = 2;
      await pumpScreen(tester);

      await tapDnsSwitchAndSettleRetries(tester);

      // Four attempts (initial + 3 retries), then the inline error.
      expect(
        calls.where((c) => c.method == 'setPrivateDns'),
        hasLength(4),
      );
      expect(
        find.text('The chosen DNS host is not serving. Pick another host.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(dnsTile(tester).value, isFalse);

      // Retry re-attempts the same selection.
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();
      expect(
        calls.where((c) => c.method == 'setPrivateDns'),
        hasLength(8),
      );
      expect(
        find.text('The chosen DNS host is not serving. Pick another host.'),
        findsOneWidget,
      );
    });

    testWidgets('a non-retryable failure shows its code and tries once',
        (tester) async {
      setPrivateDnsFailures = 1;
      setPrivateDnsFailureCode = 1;
      await pumpScreen(tester);

      await tapDnsSwitch(tester);

      expect(
        calls.where((c) => c.method == 'setPrivateDns'),
        hasLength(1),
      );
      expect(
        find.text(
          'Failed to apply the private DNS host (error code 1).',
        ),
        findsOneWidget,
      );
      expect(dnsTile(tester).value, isFalse);
    });

    testWidgets('a live host the prefs do not know is adopted',
        (tester) async {
      fakeDnsJson = null;
      fakeDnsMode = 'PRIVATE_DNS_MODE_PROVIDER_HOSTNAME_SPECIFIED';
      fakeDnsHostname = 'family.adguard-dns.com';
      await pumpScreen(tester);

      // The device already enforces AdGuard; the card adopts the truth.
      expect(dnsTile(tester).value, isTrue);
      final saved =
          (jsonDecode(fakeDnsJson!) as Map).cast<String, dynamic>();
      expect(saved['enabled'], isTrue);
      expect(saved['provider'], 'adguard');
      expect(
        find.text('Enabled — AdGuard DNS (Family filter)'),
        findsOneWidget,
      );
    });

    testWidgets('Config-tab DNS tile opens the browser screen',
        (tester) async {
      final controller = await pumpConfigTab(tester);

      await tester.tap(find.widgetWithText(ListTile, 'Private DNS'));
      await tester.pumpAndSettle();

      // The retired dialog never opens; the ONE DNS card does.
      expect(find.byType(BrowserRestrictionsScreen), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      controller.session.end();
    });
  });
}
