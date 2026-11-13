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
library;

import 'dart:convert';

import 'package:azm/app_controller.dart';
import 'package:azm/data/dns_protection.dart';
import 'package:azm/data/privileged_channel.dart';
import 'package:azm/l10n/app_localizations.dart';
import 'package:azm/theme.dart';
import 'package:azm/ui/config_screens.dart';
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
  });
}
