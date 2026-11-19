/// Batch DNS regression tests (fake channel — the established pattern
/// from batch_c_features_test.dart):
///
///  Model — hostname building per provider, validation mirroring the
///  native rule, JSON round-trip and corrupt-input defaults.
///  Screen — the DNS dialog in general Settings (Config tab): the
///  browser screen has no DNS any more; the tile opens the dialog;
///  the list is Off plus exactly one of CleanBrowsing / Cloudflare /
///  AdGuard / Custom; picking Custom shows the hostname field at once
///  (the old card's deadlock — the switch was refused so the field
///  never appeared — is gone); an uppercase hostname is lowercased
///  on apply; enabling with CleanBrowsing calls setPrivateDns with
///  the Family hostname; turning off goes through the recovery gate
///  and calls resetPrivateDns.
///
///  NextDNS was removed at the user's request 2026-11-14: a saved
///  NextDNS selection falls back to CleanBrowsing, and a live
///  NextDNS hostname is adopted as a Custom hostname.
///
///  Item 5 (2026-11-14, DNS moved back to Settings): the card is
///  gone; the dialog is the ONE DNS place, with the real failure
///  reason shown inline with a Retry button; HOST_NOT_SERVING is
///  retried automatically; a live host the prefs do not know is
///  adopted.
library;

import 'dart:convert';
import 'dart:io';

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
  late Map<String, dynamic> probeResult;
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

    testWidgets('Config-tab DNS tile opens the DNS dialog', (tester) async {
      final controller = await pumpConfigTab(tester);

      await openDnsDialog(tester);

      // The dialog, not the browser screen, and not the retired dialog.
      expect(find.byType(BrowserRestrictionsScreen), findsNothing);
      expect(find.text('Off'), findsOneWidget);
      expect(find.text('NextDNS'), findsNothing);
      expect(find.text('CleanBrowsing (Family filter)'), findsOneWidget);
      expect(find.text('Cloudflare (Family filter)'), findsOneWidget);
      expect(find.text('AdGuard DNS (Family filter)'), findsOneWidget);
      expect(find.text('Custom'), findsOneWidget);
      controller.session.end();
    });

    testWidgets(
      'the custom-DNS deadlock is fixed: picking Custom shows the '
      'field at once',
      (tester) async {
        // Protection ON with CleanBrowsing — the exact state where
        // the old card refused the switch and the field never appeared.
        fakeDnsJson = jsonEncode(const DnsProtection(enabled: true).toJson());
        fakeDnsMode = 'PRIVATE_DNS_MODE_PROVIDER_HOSTNAME_SPECIFIED';
        fakeDnsHostname = 'family-filter-dns.cleanbrowsing.org';
        await pumpConfigTab(tester);
        await openDnsDialog(tester);

        await selectProvider(tester, 'Custom');

        // The field is there immediately — no refusal, no snackbar.
        expect(find.byType(TextField), findsOneWidget);
        expect(calls.where((c) => c.method == 'setPrivateDns'), isEmpty);
        expect(find.text('Invalid DNS hostname'), findsNothing);
        // Apply is disabled until the hostname is valid.
        expect(applyButton(tester).onPressed, isNull);

        await tester.enterText(find.byType(TextField), 'dns.example.com');
        await tester.pump();
        expect(applyButton(tester).onPressed, isNotNull);
        await tapApplyAndWait(
          tester,
          () => snackbarShows('DNS protection applied'),
        );

        final applied = calls.where((c) => c.method == 'setPrivateDns');
        expect(applied, hasLength(1));
        expect(applied.first.arguments['hostname'], 'dns.example.com');
        expect(find.byType(AlertDialog), findsNothing);
      },
    );

    testWidgets('an uppercase custom hostname is lowercased on apply',
        (tester) async {
      await pumpConfigTab(tester);
      await openDnsDialog(tester);
      await selectProvider(tester, 'Custom');

      // Uppercase is valid input here, not an error — it is
      // normalised on apply (the model only accepts lowercase).
      // (The normalised host also shows as the field's helper text,
      // next to its identical hint — so no text assertion here.)
      await tester.enterText(find.byType(TextField), 'DNS.Example.COM');
      await tester.pump();
      expect(find.text('Invalid DNS hostname'), findsNothing);
      expect(applyButton(tester).onPressed, isNotNull);
      await tapApplyAndWait(
        tester,
        () => snackbarShows('DNS protection applied'),
      );

      final applied = calls.where((c) => c.method == 'setPrivateDns');
      expect(applied, hasLength(1));
      expect(applied.first.arguments['hostname'], 'dns.example.com');
    });

    testWidgets('enabling with CleanBrowsing sets the Family hostname',
        (tester) async {
      await pumpConfigTab(tester);
      await openDnsDialog(tester);
      await selectProvider(tester, 'CleanBrowsing (Family filter)');
      await tapApplyAndWait(
        tester,
        () => snackbarShows('DNS protection applied'),
      );

      final applied = calls.where((c) => c.method == 'setPrivateDns');
      expect(applied, hasLength(1));
      expect(
        applied.first.arguments['hostname'],
        'family-filter-dns.cleanbrowsing.org',
      );
      final saved = (jsonDecode(fakeDnsJson!) as Map).cast<String, dynamic>();
      expect(saved['enabled'], isTrue);
      expect(saved['provider'], 'cleanBrowsing');
    });

    testWidgets('turning off goes through the recovery gate and resets',
        (tester) async {
      fakeDnsJson = jsonEncode(
        const DnsProtection(enabled: true).toJson(),
      );
      fakeDnsMode = 'PRIVATE_DNS_MODE_PROVIDER_HOSTNAME_SPECIFIED';
      fakeDnsHostname = 'family-filter-dns.cleanbrowsing.org';
      final controller = await pumpConfigTab(tester);
      await openDnsDialog(tester);

      await selectProvider(tester, 'Off');
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await enterCodeAndConfirm(tester);
      await pumpUntil(
        tester,
        () => snackbarShows('DNS protection turned off'),
      );

      expect(calls.where((c) => c.method == 'resetPrivateDns'), hasLength(1));
      final saved = (jsonDecode(fakeDnsJson!) as Map).cast<String, dynamic>();
      expect(saved['enabled'], isFalse);
      // Let both dialogs' exit animations finish (explicit pump, not
      // pumpAndSettle: the recovery session's ticker is now running).
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(AlertDialog), findsNothing);
      controller.session.end();
    });

    testWidgets('HOST_NOT_SERVING is retried and then applies',
        (tester) async {
      setPrivateDnsFailures = 2;
      setPrivateDnsFailureCode = 1;
      await pumpConfigTab(tester);
      await openDnsDialog(tester);
      await selectProvider(tester, 'CleanBrowsing (Family filter)');
      await tapApplyAndWait(
        tester,
        () => snackbarShows('DNS protection applied'),
      );

      // Two failures, then success on the third attempt.
      final applied = calls.where((c) => c.method == 'setPrivateDns');
      expect(applied, hasLength(3));
      expect(
        applied.last.arguments['hostname'],
        'family-filter-dns.cleanbrowsing.org',
      );
      expect(find.textContaining('not serving'), findsNothing);
    });

    testWidgets('HOST_NOT_SERVING exhausted shows the real reason with Retry',
        (tester) async {
      setPrivateDnsFailures = 10;
      setPrivateDnsFailureCode = 1;
      await pumpConfigTab(tester);
      await openDnsDialog(tester);
      await selectProvider(tester, 'CleanBrowsing (Family filter)');
      await tapApplyAndWait(
        tester,
        () =>
            find.text(
              'The chosen DNS host is not answering yet. Wait a bit, then retry.',
            ).evaluate().isNotEmpty,
      );

      // Four attempts (initial + 3 retries), then the inline error.
      expect(
        calls.where((c) => c.method == 'setPrivateDns'),
        hasLength(4),
      );
      expect(find.text('Retry'), findsOneWidget);

      // Retry re-attempts the same selection.
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await pumpUntil(
        tester,
        () => calls.where((c) => c.method == 'setPrivateDns').length == 8,
      );
      expect(
        find.text('The chosen DNS host is not answering yet. Wait a bit, then retry.'),
        findsOneWidget,
      );
    });

    testWidgets('port 853 blocked shows the network diagnosis', (tester) async {
      // User report 2026-11-19: all providers fail with code 1 —
      // the network blocks port 853. The probe must name it.
      setPrivateDnsFailures = 10;
      setPrivateDnsFailureCode = 1;
      probeResult = {
        'port853': false,
        'port443': true,
        'reference853': false,
        'autoTime': true,
      };
      await pumpConfigTab(tester);
      await openDnsDialog(tester);
      await selectProvider(tester, 'CleanBrowsing (Family filter)');
      await tapApplyAndWait(
        tester,
        () => find
            .textContaining('Your network blocks encrypted DNS')
            .evaluate()
            .isNotEmpty,
      );
      expect(
        find.textContaining('Your network blocks encrypted DNS'),
        findsOneWidget,
      );
      expect(calls.where((c) => c.method == 'probeDnsPorts'), hasLength(1));
    });

    testWidgets('host unreachable shows the connection diagnosis',
        (tester) async {
      setPrivateDnsFailures = 10;
      setPrivateDnsFailureCode = 1;
      probeResult = {
        'port853': false,
        'port443': false,
        'reference853': false,
        'autoTime': true,
      };
      await pumpConfigTab(tester);
      await openDnsDialog(tester);
      await selectProvider(tester, 'CleanBrowsing (Family filter)');
      await tapApplyAndWait(
        tester,
        () => find
            .textContaining('could not be reached at all')
            .evaluate()
            .isNotEmpty,
      );
      expect(
        find.textContaining('could not be reached at all'),
        findsOneWidget,
      );
    });

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

    testWidgets('a non-retryable failure shows its code and tries once',
        (tester) async {
      setPrivateDnsFailures = 1;
      // 2 = DPM FAILURE_SETTING: a hard failure, never retried.
      setPrivateDnsFailureCode = 2;
      await pumpConfigTab(tester);
      await openDnsDialog(tester);
      await selectProvider(tester, 'CleanBrowsing (Family filter)');
      await tapApplyAndWait(
        tester,
        () =>
            find.text(
              'Failed to apply the private DNS host (error code 2).',
            ).evaluate().isNotEmpty,
      );

      expect(
        calls.where((c) => c.method == 'setPrivateDns'),
        hasLength(1),
      );
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
      expect(
        find.text('Forced host: family.adguard-dns.com'),
        findsOneWidget,
      );

      await openDnsDialog(tester);
      expect(
        tester
            .widget<RadioGroup<DnsProvider?>>(
              find.byType(RadioGroup<DnsProvider?>),
            )
            .groupValue,
        DnsProvider.adguard,
      );
    });
  });
}
