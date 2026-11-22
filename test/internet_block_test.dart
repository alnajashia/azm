/// Internet blocking + VPN DNS filtering (2026-11-19): model
/// round-trip and loosening rules, the screen's gating behaviour,
/// and source pins for the native VPN wiring.
library;

import 'dart:io';

import 'package:azm/app_controller.dart';
import 'package:azm/data/privileged_channel.dart';
import 'package:azm/domain/internet_block.dart';
import 'package:azm/l10n/app_localizations.dart';
import 'package:azm/theme.dart';
import 'package:azm/ui/internet_block_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'azm/privileged';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methodChannel = MethodChannel(channelName);

  late List<MethodCall> calls;
  late Map<String, dynamic> fakeConfig;
  final createdControllers = <AppController>[];

  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher
        .implicitView!;
    view.physicalSize = const Size(800, 4000);
    view.devicePixelRatio = 1.0;
    calls = [];
    fakeConfig = const InternetBlockConfig().toMap();

    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getInternetBlockConfig':
          return fakeConfig;
        case 'setInternetBlockConfig':
          fakeConfig = Map<String, dynamic>.from(
            call.arguments as Map<dynamic, dynamic>,
          );
          return fakeConfig;
        case 'getVpnStatus':
          return {'running': fakeConfig['enabled'] == true, 'enabled': fakeConfig['enabled'] == true};
        case 'getGroups':
          return {
            'groups': [
              {
                'id': 'g1',
                'name': 'Social',
                'packages': ['com.example.social'],
                'dailyMinutes': 0,
                'reopenSeconds': 0,
                'dailyWindows': <dynamic>[],
              },
            ],
          };
        case 'isRecoveryCodeSet':
          return {'isSet': true};
        case 'verifyRecoveryCode':
          return {'matches': true};
        case 'listInstalledApps':
          return <Map<String, dynamic>>[];
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
    for (final c in createdControllers) {
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

  Future<void> pumpScreen(WidgetTester tester) async {
    final controller = makeController();
    await tester.pumpWidget(
      buildTestApp(child: InternetBlockScreen(controller: controller)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('InternetBlockConfig model', () {
    test('round-trips through the wire map', () {
      const config = InternetBlockConfig(
        enabled: true,
        level: InternetBlockLevel.groups,
        packages: {'com.a', 'com.b'},
        groupIds: {'g1'},
        dohProvider: DohProvider.adguard,
        customDohUrl: 'https://example.com/dns-query',
        dnsAutoHost: 'family.adguard-dns.com',
      );
      final back = InternetBlockConfig.fromMap(config.toMap());
      expect(back, config);
    });

    test('a wire map without dnsAutoHost reads as feature off', () {
      final config = InternetBlockConfig.fromMap({'enabled': true});
      expect(config.dnsAutoHost, isEmpty);
    });

    test('corrupt input reads as the safe default', () {
      final config = InternetBlockConfig.fromMap({
        'enabled': 'yes',
        'level': 'bogus',
        'dohProvider': 'bogus',
      });
      expect(config.enabled, isFalse);
      expect(config.level, InternetBlockLevel.off);
      expect(config.dohProvider, DohProvider.cleanBrowsing);
    });

    test('loosening rules', () {
      const on = InternetBlockConfig(enabled: true);
      expect(on.copyWith(enabled: false).isLooseningFrom(on), isTrue);

      const phone = InternetBlockConfig(
        enabled: true,
        level: InternetBlockLevel.phone,
      );
      expect(
        phone.copyWith(level: InternetBlockLevel.apps).isLooseningFrom(phone),
        isTrue,
      );
      expect(
        on.copyWith(level: InternetBlockLevel.phone).isLooseningFrom(on),
        isFalse,
      );

      const apps = InternetBlockConfig(
        enabled: true,
        level: InternetBlockLevel.apps,
        packages: {'com.a', 'com.b'},
      );
      expect(
        apps.copyWith(packages: {'com.a'}).isLooseningFrom(apps),
        isTrue,
      );
      expect(
        apps.copyWith(packages: {'com.a', 'com.b', 'com.c'}).isLooseningFrom(apps),
        isFalse,
      );
      expect(
        apps.copyWith(level: InternetBlockLevel.groups).isLooseningFrom(apps),
        isFalse,
      );
    });
  });

  group('InternetBlockScreen', () {
    testWidgets('enabling applies at once, without a code gate',
        (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final sets = calls.where((c) => c.method == 'setInternetBlockConfig');
      expect(sets, hasLength(1));
      expect((sets.single.arguments as Map)['enabled'], isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('disabling asks for the recovery code first',
        (tester) async {
      fakeConfig = const InternetBlockConfig(enabled: true).toMap();
      await pumpScreen(tester);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The gate dialog is up and nothing was applied yet.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        calls.where((c) => c.method == 'setInternetBlockConfig'),
        isEmpty,
      );
    });

    testWidgets('apps level shows the app picker tile', (tester) async {
      fakeConfig = const InternetBlockConfig(
        enabled: true,
        level: InternetBlockLevel.apps,
        packages: {'com.a'},
      ).toMap();
      await pumpScreen(tester);
      expect(find.text('Choose apps'), findsOneWidget);
      expect(find.text('1 apps blocked'), findsOneWidget);
    });

    testWidgets('DNS level shows the provider choices', (tester) async {
      await pumpScreen(tester);
      expect(find.text('CleanBrowsing (Family filter)'), findsOneWidget);
      expect(find.text('AdGuard DNS (Family filter)'), findsOneWidget);
    });
  });

  group('native wiring pins', () {
    test('manifest declares the VPN service and consent activity', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(manifest.contains('.vpn.AzmVpnService'), isTrue);
      expect(manifest.contains('android.permission.BIND_VPN_SERVICE'), isTrue);
      expect(manifest.contains('.vpn.VpnConsentActivity'), isTrue);
    });

    test('handler exposes the three internet-block cases', () {
      final src = File(
        'android/app/src/main/kotlin/com/alnajashia/azm/channel/PrivilegedChannelHandler.kt',
      ).readAsStringSync();
      expect(src.contains('"getInternetBlockConfig"'), isTrue);
      expect(src.contains('"setInternetBlockConfig"'), isTrue);
      expect(src.contains('"getVpnStatus"'), isTrue);
    });

    test('teardown stops the VPN while still owner', () {
      final src = File(
        'android/app/src/main/kotlin/com/alnajashia/azm/deviceowner/DeviceOwnerManager.kt',
      ).readAsStringSync();
      expect(src.contains('step("vpn")'), isTrue);
      expect(src.contains('VpnConfigStore.stopAndClear(context)'), isTrue);
    });

    test('DoH endpoints are the verified provider URLs', () {
      final src = File(
        'android/app/src/main/kotlin/com/alnajashia/azm/vpn/DohClient.kt',
      ).readAsStringSync();
      expect(
        src.contains('https://doh.cleanbrowsing.org/doh/family-filter/'),
        isTrue,
      );
      expect(src.contains('https://family.adguard-dns.com/dns-query'), isTrue);
      expect(
        src.contains('https://family.cloudflare-dns.com/dns-query'),
        isTrue,
      );
    });

    test('VPN service routes per mode and protects DoH sockets', () {
      final src = File(
        'android/app/src/main/kotlin/com/alnajashia/azm/vpn/AzmVpnService.kt',
      ).readAsStringSync();
      expect(src.contains('addAllowedApplication'), isTrue);
      expect(src.contains('addDisallowedApplication'), isTrue);
      expect(src.contains('protect(socket)'), isTrue);
    });

    test('always-on pin is set and cleared by the store', () {
      final src = File(
        'android/app/src/main/kotlin/com/alnajashia/azm/vpn/VpnConfigStore.kt',
      ).readAsStringSync();
      expect(src.contains('setAlwaysOnVpnPackage'), isTrue);
      expect(src.contains('DISALLOW_CONFIG_VPN'), isTrue);
    });
  });
}
