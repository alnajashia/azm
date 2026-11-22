/// Batch DNS regression tests (fake channel — the established pattern
/// from batch_c_features_test.dart):
///
///  Model — hostname building per provider, validation mirroring the
///  native rule, JSON round-trip and corrupt-input defaults.
///  Screen — the DNS dialog in general Settings (Config tab): the
///  browser screen has no DNS any more; the tile opens the dialog;
///  since 2026-11-22 the dialog carries the "DNS via VPN" switch —
///  the provider list (CleanBrowsing / Cloudflare / AdGuard /
///  Custom) shows only while it is on; applying syncs the provider
///  into the internet-block (VPN) config and never calls
///  setPrivateDns; turning the switch off goes through the
///  recovery gate and stops running VPN DNS filtering.
///
///  NextDNS was removed at the user's request 2026-11-14: a saved
///  NextDNS selection falls back to CleanBrowsing, and a live
///  NextDNS hostname is adopted as a Custom hostname.
///
///  Item 5 (2026-11-14, DNS moved back to Settings): the card is
///  gone; the dialog is the ONE DNS place; a live host the prefs
///  do not know is adopted (unless a VPN-mode selection exists).
library;

import 'dart:convert';
import 'dart:io';

import 'package:azm/app_controller.dart';
import 'package:azm/data/dns_protection.dart';
import 'package:azm/data/privileged_channel.dart';
import 'package:azm/domain/internet_block.dart';
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
  late Map<String, dynamic> probeResult;

  /// The fake internet-block config (the VPN provider the DNS
  /// dialog syncs into since 2026-11-22).
  late Map<String, dynamic> fakeIbConfig;
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
    // Default injected failure code: 1 = DPM HOST_NOT_SERVING.
    setPrivateDnsFailureCode = 1;
    // Default probe: port 853 reachable (transient failure).
    probeResult = {
      'port853': true,
      'port443': true,
      'reference853': true,
      'autoTime': true,
    };
    fakeIbConfig = {
      'enabled': false,
      'level': 'off',
      'packages': <String>[],
      'groupIds': <String>[],
      'dohProvider': 'cleanBrowsing',
      'customDohUrl': '',
      'dnsAutoHost': '',
    };

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
        case 'probeDnsPorts':
          return probeResult;
        case 'getInternetBlockConfig':
          return Map<String, dynamic>.from(fakeIbConfig);
        case 'setInternetBlockConfig':
          fakeIbConfig = Map<String, dynamic>.from(
            (call.arguments as Map).cast<String, dynamic>(),
          );
          return Map<String, dynamic>.from(fakeIbConfig);
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

  /// Pumps in 1-second steps until [condition] holds (bounded): the
  /// dialog's Apply button shows a spinner while loading, so
  /// `pumpAndSettle` would never settle — and the HOST_NOT_SERVING
  /// retry delays (2s/5s/8s) need the fake clock moved explicitly.
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition,
  ) async {
    for (var i = 0; i < 40 && !condition(); i++) {
      await tester.pump(const Duration(seconds: 1));
    }
  }

  /// Drives the recovery-gate dialog on top of the DNS dialog: types
  /// a 16-letter code and confirms. Scoped to the gate dialog (the
  /// DNS dialog's own fields are behind it) and uses explicit pumps
  /// — the gate opens a few microtask turns after Apply is tapped,
  /// and the DNS dialog's Apply button shows a spinner while loading,
  /// so `pumpAndSettle` would never settle.
  Future<void> enterCodeAndConfirm(WidgetTester tester) async {
    // Wait for the code stage, not just the dialog title: the gate
    // opens in a loading stage (checking the code is set) and the
    // code field only exists once it reaches the code stage.
    await pumpUntil(
      tester,
      () =>
          find.widgetWithText(FilledButton, 'Confirm').evaluate().isNotEmpty,
    );
    expect(find.text('Enter recovery code'), findsOneWidget);
    final codeField = find.descendant(
      of: find.ancestor(
        of: find.text('Enter recovery code'),
        matching: find.byType(AlertDialog),
      ),
      matching: find.byType(TextField),
    );
    await tester.enterText(codeField.first, 'AAAAAAAAAAAAAAAA');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pump();
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

  /// Opens the DNS dialog from the Config-tab tile.
  Future<void> openDnsDialog(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ListTile, 'Private DNS'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  }

  /// Taps a provider radio inside the open dialog.
  Future<void> selectProvider(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump();
  }

  FilledButton applyButton(WidgetTester tester) =>
      tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Apply'),
      );

  Future<void> tapApplyAndWait(
    WidgetTester tester,
    bool Function() condition,
  ) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pump();
    await pumpUntil(tester, condition);
  }

  bool snackbarShows(String text) =>
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text(text),
      ).evaluate().isNotEmpty;

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

    test('JSON round-trip for every provider', () {
      for (final provider in DnsProvider.values) {
        final dns = DnsProtection(
          enabled: true,
          provider: provider,
        );
        final back = DnsProtection.fromJson(
          (jsonDecode(jsonEncode(dns.toJson())) as Map).cast<String, dynamic>(),
        );
        expect(back.enabled, isTrue);
        expect(back.provider, provider);
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

    test(
        'fromLiveHost maps every known host; a legacy NextDNS host '
        'becomes Custom', () {
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
      // A live NextDNS hostname is adopted as Custom — the host
      // itself stays applied rather than being silently dropped.
      final legacy = DnsProtection.fromLiveHost('xyz123.dns.nextdns.io');
      expect(legacy.provider, DnsProvider.custom);
      expect(legacy.customHostname, 'xyz123.dns.nextdns.io');
      expect(legacy.hostname, 'xyz123.dns.nextdns.io');
      final custom = DnsProtection.fromLiveHost('dns.example.com');
      expect(custom.provider, DnsProvider.custom);
      expect(custom.customHostname, 'dns.example.com');
      for (final live in [
        DnsProtection.fromLiveHost('family-filter-dns.cleanbrowsing.org'),
        DnsProtection.fromLiveHost('family.cloudflare-dns.com'),
        DnsProtection.fromLiveHost('family.adguard-dns.com'),
        legacy,
        custom,
      ]) {
        expect(live.enabled, isTrue);
      }
    });

    test('VPN-mode fields round-trip; old saves default to off', () {
      const dns = DnsProtection(
        enabled: true,
        provider: DnsProvider.custom,
        customHostname: 'dns.example.com',
        viaVpn: true,
        customDohUrl: 'https://dns.example.com/dns-query',
      );
      final back = DnsProtection.fromJson(
        (jsonDecode(jsonEncode(dns.toJson())) as Map).cast<String, dynamic>(),
      );
      expect(back.viaVpn, isTrue);
      expect(back.customDohUrl, 'https://dns.example.com/dns-query');
      expect(back.hostname, 'dns.example.com');

      // A pre-2026-11-22 save has no viaVpn keys: switch reads off.
      final old = DnsProtection.fromJson({
        'enabled': true,
        'provider': 'adguard',
        'customHostname': '',
      });
      expect(old.viaVpn, isFalse);
      expect(old.customDohUrl, isEmpty);
    });

    test('provider mapping between DNS and internet-block enums', () {
      expect(dohProviderFor(DnsProvider.cleanBrowsing), DohProvider.cleanBrowsing);
      expect(dohProviderFor(DnsProvider.cloudflare), DohProvider.cloudflare);
      expect(dohProviderFor(DnsProvider.adguard), DohProvider.adguard);
      expect(dohProviderFor(DnsProvider.custom), DohProvider.custom);
      expect(dnsProviderFor(DohProvider.adguard), DnsProvider.adguard);
      expect(dnsProviderFor(DohProvider.custom), DnsProvider.custom);
      expect(dohUrlHost('https://DNS.Example.com/dns-query'), 'dns.example.com');
      expect(dohUrlHost('not a url'), isEmpty);
    });

    test('a stored NextDNS selection falls back to CleanBrowsing', () {
      final back = DnsProtection.fromJson({
        'enabled': true,
        'provider': 'nextdns',
        'nextDnsConfigId': 'abc',
      });
      expect(back.enabled, isTrue);
      expect(back.provider, DnsProvider.cleanBrowsing);
      expect(back.customHostname, isEmpty);
      expect(back.hostname, DnsProtection.cleanBrowsingHostname);
    });
  });

  // ------------------------------------------------------------ Screen (dialog)

  group('Batch DNS — Settings dialog', () {
    testWidgets('browser screen has no DNS anymore', (tester) async {
      await pumpScreen(tester);

      expect(find.text('DNS protection'), findsNothing);
      expect(find.text('Private DNS'), findsNothing);

      // The browser work itself is untouched.
      expect(find.text('Chrome'), findsOneWidget);
    });

    /// Toggles the "DNS via VPN" switch inside the open dialog.
    Future<void> toggleVpnSwitch(WidgetTester tester) async {
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Switch),
        ),
      );
      await tester.pump();
    }

    testWidgets('Config-tab DNS tile opens the DNS dialog', (tester) async {
      final controller = await pumpConfigTab(tester);

      await openDnsDialog(tester);

      // The dialog carries the VPN switch; the provider list is
      // hidden while it is off (user request 2026-11-22), and the
      // old Off radio is gone — the switch is the off.
      expect(find.byType(BrowserRestrictionsScreen), findsNothing);
      expect(find.text('DNS via VPN'), findsOneWidget);
      expect(find.text('CleanBrowsing (Family filter)'), findsNothing);
      expect(find.text('Off'), findsNothing);
      expect(find.text('NextDNS'), findsNothing);

      await toggleVpnSwitch(tester);
      expect(find.text('CleanBrowsing (Family filter)'), findsOneWidget);
      expect(find.text('Cloudflare (Family filter)'), findsOneWidget);
      expect(find.text('AdGuard DNS (Family filter)'), findsOneWidget);
      expect(find.text('Custom'), findsOneWidget);
      controller.session.end();
    });

    testWidgets(
      'the switch shows the list; Custom shows the URL field at once',
      (tester) async {
        await pumpConfigTab(tester);
        await openDnsDialog(tester);
        await toggleVpnSwitch(tester);
        await selectProvider(tester, 'Custom');

        // The field is there immediately — no refusal, no snackbar.
        expect(find.byType(TextField), findsOneWidget);
        expect(find.text('Invalid DNS hostname'), findsNothing);
        // Apply is disabled until the URL is a valid https endpoint.
        expect(applyButton(tester).onPressed, isNull);

        await tester.enterText(find.byType(TextField), 'dns.example.com');
        await tester.pump();
        expect(applyButton(tester).onPressed, isNull);

        await tester.enterText(
          find.byType(TextField),
          'https://dns.example.com/dns-query',
        );
        await tester.pump();
        expect(applyButton(tester).onPressed, isNotNull);
        await tapApplyAndWait(
          tester,
          () => snackbarShows(
            'DNS via VPN is set. It activates whenever a VPN is on.',
          ),
        );

        // The VPN config carries the provider, the URL, and the
        // URL's host as the external-VPN auto host. System Private
        // DNS is never touched by this dialog any more.
        expect(calls.where((c) => c.method == 'setPrivateDns'), isEmpty);
        expect(fakeIbConfig['dohProvider'], 'custom');
        expect(
          fakeIbConfig['customDohUrl'],
          'https://dns.example.com/dns-query',
        );
        expect(fakeIbConfig['dnsAutoHost'], 'dns.example.com');
        final saved = (jsonDecode(fakeDnsJson!) as Map).cast<String, dynamic>();
        expect(saved['viaVpn'], isTrue);
        expect(saved['provider'], 'custom');
        // Let the dialog's exit animation finish before asserting
        // it is gone (established lesson).
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(AlertDialog), findsNothing);
      },
    );

    testWidgets('applying with the switch on syncs the VPN provider',
        (tester) async {
      await pumpConfigTab(tester);
      await openDnsDialog(tester);
      await toggleVpnSwitch(tester);
      await selectProvider(tester, 'AdGuard DNS (Family filter)');
      await tapApplyAndWait(
        tester,
        () => snackbarShows(
          'DNS via VPN is set. It activates whenever a VPN is on.',
        ),
      );

      expect(calls.where((c) => c.method == 'setPrivateDns'), isEmpty);
      expect(fakeIbConfig['dohProvider'], 'adguard');
      expect(fakeIbConfig['dnsAutoHost'], 'family.adguard-dns.com');
      // The VPN itself was not started by the dialog — filtering
      // begins when the user turns the VPN on.
      expect(fakeIbConfig['enabled'], isFalse);
      final saved = (jsonDecode(fakeDnsJson!) as Map).cast<String, dynamic>();
      expect(saved['viaVpn'], isTrue);
      expect(saved['provider'], 'adguard');
    });

    testWidgets(
      'turning the switch off goes through the gate and stops filtering',
      (tester) async {
        fakeDnsJson = jsonEncode(
          const DnsProtection(
            enabled: true,
            provider: DnsProvider.adguard,
            viaVpn: true,
          ).toJson(),
        );
        fakeIbConfig = {
          'enabled': true,
          'level': 'off',
          'packages': <String>[],
          'groupIds': <String>[],
          'dohProvider': 'adguard',
          'customDohUrl': '',
          'dnsAutoHost': 'family.adguard-dns.com',
        };
        final controller = await pumpConfigTab(tester);
        await openDnsDialog(tester);

        // Switch is on, list visible.
        expect(find.text('AdGuard DNS (Family filter)'), findsOneWidget);
        await toggleVpnSwitch(tester);
        expect(find.text('AdGuard DNS (Family filter)'), findsNothing);

        await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
        await enterCodeAndConfirm(tester);
        await pumpUntil(
          tester,
          () => snackbarShows('DNS protection turned off'),
        );

        // Filtering through Azm's VPN stopped immediately.
        expect(fakeIbConfig['enabled'], isFalse);
        expect(fakeIbConfig['dnsAutoHost'], '');
        final saved = (jsonDecode(fakeDnsJson!) as Map).cast<String, dynamic>();
        expect(saved['viaVpn'], isFalse);
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(AlertDialog), findsNothing);
        controller.session.end();
      },
    );

    testWidgets(
      'turning the switch off at a block level keeps the VPN running',
      (tester) async {
        fakeDnsJson = jsonEncode(
          const DnsProtection(enabled: true, viaVpn: true).toJson(),
        );
        fakeIbConfig = {
          'enabled': true,
          'level': 'apps',
          'packages': <String>['com.example.app'],
          'groupIds': <String>[],
          'dohProvider': 'cleanBrowsing',
          'customDohUrl': '',
          'dnsAutoHost': 'family-filter-dns.cleanbrowsing.org',
        };
        final controller = await pumpConfigTab(tester);
        await openDnsDialog(tester);
        await toggleVpnSwitch(tester);
        await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
        await enterCodeAndConfirm(tester);
        await pumpUntil(
          tester,
          () => snackbarShows('DNS protection turned off'),
        );

        // Only the DNS part turned off; the block level stands.
        expect(fakeIbConfig['enabled'], isTrue);
        expect(fakeIbConfig['level'], 'apps');
        expect(fakeIbConfig['dnsAutoHost'], '');
        await tester.pump(const Duration(seconds: 1));
        controller.session.end();
      },
    );

    test('native port probe is wired', () {
      final handlerSrc = File(
        'android/app/src/main/kotlin/com/alnajashia/azm/channel/PrivilegedChannelHandler.kt',
      ).readAsStringSync();
      expect(handlerSrc.contains('"probeDnsPorts"'), isTrue);
      final managerSrc = File(
        'android/app/src/main/kotlin/com/alnajashia/azm/deviceowner/DeviceOwnerManager.kt',
      ).readAsStringSync();
      expect(managerSrc.contains('fun probeDnsPorts'), isTrue);
      expect(managerSrc.contains('InetSocketAddress(host, port)'), isTrue);
      expect(managerSrc.contains('Settings.Global.AUTO_TIME'), isTrue);
    });

    test('native external-VPN watcher is wired', () {
      final watcherSrc = File(
        'android/app/src/main/kotlin/com/alnajashia/azm/vpn/ExternalVpnWatcher.kt',
      ).readAsStringSync();
      expect(watcherSrc.contains('TRANSPORT_VPN'), isTrue);
      expect(watcherSrc.contains('registerNetworkCallback'), isTrue);
      expect(watcherSrc.contains('AzmVpnService.isRunning'), isTrue);
      expect(watcherSrc.contains('setPrivateDns'), isTrue);
      expect(watcherSrc.contains('resetPrivateDns'), isTrue);
      final storeSrc = File(
        'android/app/src/main/kotlin/com/alnajashia/azm/vpn/VpnConfigStore.kt',
      ).readAsStringSync();
      expect(storeSrc.contains('dnsAutoHost'), isTrue);
      expect(storeSrc.contains('ExternalVpnWatcher.sync'), isTrue);
      final a11ySrc = File(
        'android/app/src/main/kotlin/com/alnajashia/azm/accessibility/AzmAccessibilityService.kt',
      ).readAsStringSync();
      expect(a11ySrc.contains('ExternalVpnWatcher.register'), isTrue);
      expect(a11ySrc.contains('ExternalVpnWatcher.unregister'), isTrue);
    });

    testWidgets('a live host the prefs do not know is adopted',
        (tester) async {
      fakeDnsJson = null;
      fakeDnsMode = 'PRIVATE_DNS_MODE_PROVIDER_HOSTNAME_SPECIFIED';
      fakeDnsHostname = 'family.adguard-dns.com';
      await pumpConfigTab(tester);

      // The device already enforces AdGuard; the tab adopts the truth.
      final saved = (jsonDecode(fakeDnsJson!) as Map).cast<String, dynamic>();
      expect(saved['enabled'], isTrue);
      expect(saved['provider'], 'adguard');
      expect(saved['viaVpn'], isFalse);
      expect(
        find.text('Forced host: family.adguard-dns.com'),
        findsOneWidget,
      );

      // The adopted provider is the remembered choice once the
      // switch is turned on.
      await openDnsDialog(tester);
      await toggleVpnSwitch(tester);
      expect(
        tester
            .widget<RadioGroup<DnsProvider>>(
              find.byType(RadioGroup<DnsProvider>),
            )
            .groupValue,
        DnsProvider.adguard,
      );
    });
  });
}
