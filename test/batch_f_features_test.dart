/// Batch F regression tests (fake channel — the established pattern
/// from dns_protection_test.dart):
///
///  Torrent (item 4) — the torrent card renders with the detected
///  clients; enabling suspends them with reason TORRENT_APP, sets the
///  native flag and saves the blocked list; disabling goes through
///  the recovery gate, clears the flag and unsuspends the saved list.
///  Uninstall block (items 5/8) — the screen lists blocked apps and
///  the empty state; adding via the picker blocks; removing goes
///  through the recovery gate.
///  Groups (items 7/9) — the Apps tab shows one filter chip per
///  group and filters the list to its members; blocking a group
///  suspends all members with reason GROUP and badges it; unblocking
///  goes through the recovery gate.
///  Item 6, Settings switch (his clarification 2026-11-13 14:54) —
///  the Config tab has a switch that blocks uninstalling suspended
///  or blocked apps; ON is tightening (direct), OFF is recovery-gated.
///  Item 10 (clarified the same day: رمز الاستيراد = رمز الاسترداد)
///  — tapping Remove Device Owner opens the recovery-code gate
///  before any removal call; the forced-removal completion path
///  calls removal directly with no gate (proven by the F-E2-1 test
///  in batch_c, which completes a due forced removal despite a seal).
library;

import 'dart:convert';

import 'package:azm/app_controller.dart';
import 'package:azm/data/privileged_channel.dart';
import 'package:azm/l10n/app_localizations.dart';
import 'package:azm/theme.dart';
import 'package:azm/ui/apps_tab.dart';
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

  late List<MethodCall> calls;
  late List<Map<String, dynamic>> fakeApps;
  late List<Map<String, dynamic>> fakeGroups;
  late List<Map<String, dynamic>> fakeBrowsers;
  late List<Map<String, dynamic>> fakeTorrentApps;
  late bool fakeBlockTorrents;
  late bool fakeAutoBlockUninstall;
  late String? fakeTorrentBlockedJson;
  late String? fakeBlockedGroupsJson;
  late String? fakeDnsJson;
  late String? fakeBlocklistsJson;
  final createdControllers = <AppController>[];

  Map<String, dynamic> app(
    String packageName,
    String label, {
    bool suspended = false,
    bool uninstallBlocked = false,
  }) =>
      {
        'packageName': packageName,
        'label': label,
        'isSystem': false,
        'isHidden': false,
        'isSuspended': suspended,
        'isUninstallBlocked': uninstallBlocked,
      };

  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher
        .implicitView!;
    view.physicalSize = const Size(800, 4000);
    view.devicePixelRatio = 1.0;
    calls = [];
    fakeApps = [
      app('com.example.app', 'Example'),
      app('com.example.social', 'Social App'),
      app('com.example.notes', 'Notes', uninstallBlocked: true),
    ];
    fakeGroups = [
      {
        'id': 'g1',
        'name': 'Social',
        'packages': ['com.example.social'],
        'dailyMinutes': 0,
      },
    ];
    fakeBrowsers = [
      {
        'packageName': 'com.android.chrome',
        'label': 'Chrome',
        'supportsRestrictions': true,
        'isSuspended': false,
        'icon': null,
      },
    ];
    fakeTorrentApps = [
      {'packageName': 'com.example.torrent', 'label': 'Torrent Client'},
    ];
    fakeBlockTorrents = false;
    fakeAutoBlockUninstall = true;
    fakeTorrentBlockedJson = null;
    fakeBlockedGroupsJson = null;
    fakeDnsJson = null;
    fakeBlocklistsJson = null;

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
          return {'mode': 'PRIVATE_DNS_MODE_OPPORTUNISTIC', 'hostname': null};
        case 'listInstalledBrowsers':
          return fakeBrowsers;
        case 'getTorrentApps':
          return fakeTorrentApps;
        case 'isBlockTorrentsEnabled':
          return fakeBlockTorrents;
        case 'setBlockTorrents':
          fakeBlockTorrents = call.arguments['enabled'] as bool;
          return fakeBlockTorrents;
        case 'isAutoBlockUninstallSuspended':
          return fakeAutoBlockUninstall;
        case 'setAutoBlockUninstallSuspended':
          fakeAutoBlockUninstall = call.arguments['enabled'] as bool;
          return fakeAutoBlockUninstall;
        case 'listInstalledApps':
          return fakeApps;
        case 'getGroups':
          return {'groups': fakeGroups};
        case 'setGroups':
          fakeGroups = (call.arguments['groups'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          return {'groups': fakeGroups};
        case 'setAppSuspended':
          final packages =
              (call.arguments['packageNames'] as List).cast<String>();
          final suspended = call.arguments['suspended'] as bool;
          for (final a in fakeApps) {
            if (packages.contains(a['packageName'])) {
              a['isSuspended'] = suspended;
            }
          }
          return {
            'results': packages
                .map(
                  (p) => {'packageName': p, 'isSuspended': suspended},
                )
                .toList(),
          };
        case 'setUninstallBlocked':
          final pkg = call.arguments['packageName'] as String;
          final blocked = call.arguments['blocked'] as bool;
          for (final a in fakeApps) {
            if (a['packageName'] == pkg) a['isUninstallBlocked'] = blocked;
          }
          return {'packageName': pkg, 'isUninstallBlocked': blocked};
        case 'getSetting':
          final store = call.arguments['store'] as String?;
          final key = call.arguments['key'] as String?;
          if (store == 'browser_prefs' && key == 'blocked_lists_json') {
            return {'value': fakeBlocklistsJson};
          }
          if (store == 'browser_prefs' && key == 'dns_protection_json') {
            return {'value': fakeDnsJson};
          }
          if (store == 'browser_prefs' && key == 'torrent_blocked_json') {
            return {'value': fakeTorrentBlockedJson};
          }
          if (store == 'browser_prefs' && key == 'blocked_groups_json') {
            return {'value': fakeBlockedGroupsJson};
          }
          return {'value': null};
        case 'setSetting':
          final store = call.arguments['store'] as String?;
          final key = call.arguments['key'] as String?;
          final value = call.arguments['value'] as String?;
          if (store == 'browser_prefs' && key == 'torrent_blocked_json') {
            fakeTorrentBlockedJson = value;
          }
          if (store == 'browser_prefs' && key == 'blocked_groups_json') {
            fakeBlockedGroupsJson = value;
          }
          if (store == 'browser_prefs' && key == 'dns_protection_json') {
            fakeDnsJson = value;
          }
          return {'value': value};
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
      throw MissingPluginException('Unhandled ${call.method} in Batch F test');
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

  Future<void> enterCodeAndConfirm(WidgetTester tester) async {
    await tester.pumpAndSettle();
    expect(find.text('Enter recovery code'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'AAAAAAAAAAAAAAAA');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();
  }

  List<InstalledApp> installedApps() => fakeApps
      .map((e) => InstalledApp.fromMap(e as Map<dynamic, dynamic>))
      .toList();

  SwitchListTile torrentTile(WidgetTester tester) => tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Block torrent apps'),
      );

  // ------------------------------------------------------------ Torrent

  group('Batch F — torrent apps (item 4)', () {
    testWidgets('torrent card renders with detected clients',
        (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(
          child: BrowserRestrictionsScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      // Two copies: the card title and the switch title.
      expect(find.text('Block torrent apps'), findsNWidgets(2));
      expect(find.text('Torrent Client'), findsOneWidget);
      expect(find.text('Detected torrent apps: 1'), findsOneWidget);
      expect(torrentTile(tester).value, isFalse);
    });

    testWidgets('enabling suspends detected clients and saves the list',
        (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(
          child: BrowserRestrictionsScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(SwitchListTile, 'Block torrent apps'),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();

      final flag = calls.where((c) => c.method == 'setBlockTorrents');
      expect(flag, hasLength(1));
      expect(flag.first.arguments['enabled'], isTrue);
      final suspended = calls.where((c) => c.method == 'setAppSuspended');
      expect(suspended, hasLength(1));
      expect(
        suspended.first.arguments['packageNames'],
        ['com.example.torrent'],
      );
      expect(suspended.first.arguments['suspended'], isTrue);
      expect(suspended.first.arguments['reason'], 'TORRENT_APP');
      expect(
        jsonDecode(fakeTorrentBlockedJson!),
        ['com.example.torrent'],
      );
      expect(find.text('Suspended 1 torrent app(s)'), findsOneWidget);
      expect(torrentTile(tester).value, isTrue);
    });

    testWidgets('disabling goes through the gate and unsuspends the list',
        (tester) async {
      fakeBlockTorrents = true;
      fakeTorrentBlockedJson = jsonEncode(['com.example.torrent']);
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(
          child: BrowserRestrictionsScreen(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      expect(torrentTile(tester).value, isTrue);

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(SwitchListTile, 'Block torrent apps'),
          matching: find.byType(Switch),
        ),
      );
      await enterCodeAndConfirm(tester);

      final flag = calls.where((c) => c.method == 'setBlockTorrents');
      expect(flag, hasLength(1));
      expect(flag.first.arguments['enabled'], isFalse);
      final unsuspended = calls.where(
        (c) =>
            c.method == 'setAppSuspended' &&
            c.arguments['suspended'] == false,
      );
      expect(unsuspended, hasLength(1));
      expect(
        unsuspended.first.arguments['packageNames'],
        ['com.example.torrent'],
      );
      expect(fakeTorrentBlockedJson, '[]');
      expect(find.text('Torrent apps unsuspended'), findsOneWidget);
      expect(torrentTile(tester).value, isFalse);
      controller.session.end();
    });
  });

  // ------------------------------------------------------------ Uninstall block

  group('Batch F — uninstall block screen (items 5/8)', () {
    testWidgets('lists blocked apps and the add action', (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(
          child: UninstallBlockScreen(
            controller: controller,
            apps: installedApps(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Block uninstallation'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('Example'), findsNothing);
    });

    testWidgets('adding via the picker blocks the app', (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(
          child: UninstallBlockScreen(
            controller: controller,
            apps: installedApps(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Example'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final blocked = calls.where(
        (c) =>
            c.method == 'setUninstallBlocked' &&
            c.arguments['packageName'] == 'com.example.app',
      );
      expect(blocked, hasLength(1));
      expect(blocked.first.arguments['blocked'], isTrue);
      expect(find.text('Example'), findsOneWidget);
    });

    testWidgets('removing goes through the recovery gate', (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(
          child: UninstallBlockScreen(
            controller: controller,
            apps: installedApps(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await enterCodeAndConfirm(tester);

      final removed = calls.where(
        (c) =>
            c.method == 'setUninstallBlocked' &&
            c.arguments['packageName'] == 'com.example.notes',
      );
      expect(removed, hasLength(1));
      expect(removed.first.arguments['blocked'], isFalse);
      expect(find.text('Uninstall allowed for Notes'), findsOneWidget);
      expect(find.text('Notes'), findsNothing);
      controller.session.end();
    });
  });

  // ------------------------------------------------------------ Groups

  group('Batch F — groups (items 7/9)', () {
    testWidgets('Apps tab shows a filter chip per group and filters',
        (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(child: AppsTab(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Example'), findsOneWidget);
      expect(find.text('Social App'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'Social'));
      await tester.pumpAndSettle();

      expect(find.text('Social App'), findsOneWidget);
      expect(find.text('Example'), findsNothing);
      expect(find.text('Notes'), findsNothing);

      await tester.tap(find.widgetWithText(FilterChip, 'All'));
      await tester.pumpAndSettle();
      expect(find.text('Example'), findsOneWidget);
    });

    testWidgets('blocking a group suspends all members and badges it',
        (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(
          child: GroupsScreen(
            controller: controller,
            apps: installedApps(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Social'), findsOneWidget);
      expect(find.textContaining('Blocked'), findsNothing);

      await tester.tap(
        find.byWidgetPredicate((w) => w is PopupMenuButton<String>).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block group'));
      await tester.pumpAndSettle();

      final suspended = calls.where((c) => c.method == 'setAppSuspended');
      expect(suspended, hasLength(1));
      expect(
        suspended.first.arguments['packageNames'],
        ['com.example.social'],
      );
      expect(suspended.first.arguments['suspended'], isTrue);
      expect(suspended.first.arguments['reason'], 'GROUP');
      expect(jsonDecode(fakeBlockedGroupsJson!), ['g1']);
      expect(find.text('Group Social blocked'), findsOneWidget);
      expect(find.textContaining('Blocked'), findsOneWidget);
    });

    testWidgets('unblocking a group goes through the recovery gate',
        (tester) async {
      fakeBlockedGroupsJson = jsonEncode(['g1']);
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(
          child: GroupsScreen(
            controller: controller,
            apps: installedApps(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byWidgetPredicate((w) => w is PopupMenuButton<String>).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unblock group'));
      await enterCodeAndConfirm(tester);

      final unsuspended = calls.where(
        (c) =>
            c.method == 'setAppSuspended' &&
            c.arguments['suspended'] == false,
      );
      expect(unsuspended, hasLength(1));
      expect(
        unsuspended.first.arguments['packageNames'],
        ['com.example.social'],
      );
      expect(fakeBlockedGroupsJson, '[]');
      expect(find.text('Group Social unblocked'), findsOneWidget);
      controller.session.end();
    });
  });

  // --------------------------------- Item 6: the Settings switch

  group('Batch F — item 6 Settings switch (block uninstall of suspended apps)', () {
    SwitchListTile autoBlockTile(WidgetTester tester) =>
        tester.widget<SwitchListTile>(
          find.widgetWithText(
            SwitchListTile,
            'Block uninstalling suspended or blocked apps',
          ),
        );

    Future<AppController> pumpConfigTab(WidgetTester tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(child: ConfigTab(controller: controller)),
      );
      await tester.pumpAndSettle();
      return controller;
    }

    testWidgets('the switch renders with the native flag value',
        (tester) async {
      await pumpConfigTab(tester);
      await tester.scrollUntilVisible(
        find.text('Block uninstalling suspended or blocked apps'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(autoBlockTile(tester).value, isTrue);
    });

    testWidgets('turning it ON calls the channel directly (tightening)',
        (tester) async {
      fakeAutoBlockUninstall = false;
      await pumpConfigTab(tester);
      await tester.scrollUntilVisible(
        find.text('Block uninstalling suspended or blocked apps'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(autoBlockTile(tester).value, isFalse);

      await tester.tap(
        find.widgetWithText(
          SwitchListTile,
          'Block uninstalling suspended or blocked apps',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        calls.any(
          (c) =>
              c.method == 'setAutoBlockUninstallSuspended' &&
              c.arguments['enabled'] == true,
        ),
        isTrue,
      );
      expect(autoBlockTile(tester).value, isTrue);
      expect(find.text('Enter recovery code'), findsNothing);
    });

    testWidgets(
        'turning it OFF goes through the recovery gate (loosening)',
        (tester) async {
      final controller = await pumpConfigTab(tester);
      await tester.scrollUntilVisible(
        find.text('Block uninstalling suspended or blocked apps'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(autoBlockTile(tester).value, isTrue);

      await tester.tap(
        find.widgetWithText(
          SwitchListTile,
          'Block uninstalling suspended or blocked apps',
        ),
      );
      await tester.pumpAndSettle();

      // The code gate appears and nothing is applied yet.
      expect(find.text('Enter recovery code'), findsOneWidget);
      expect(
        calls.any((c) => c.method == 'setAutoBlockUninstallSuspended'),
        isFalse,
      );

      await enterCodeAndConfirm(tester);
      expect(
        calls.any(
          (c) =>
              c.method == 'setAutoBlockUninstallSuspended' &&
              c.arguments['enabled'] == false,
        ),
        isTrue,
      );
      expect(autoBlockTile(tester).value, isFalse);
      // The recovery session runs a 1s ticker: end it before the
      // test body finishes, or the pending-timer check fails.
      controller.session.end();
    });
  });

  // --------------------------------- Item 10: the recovery code at removal

  group('Batch F — item 10 (removal asks for the recovery code)', () {
    testWidgets('Remove Device Owner opens the code gate before removal',
        (tester) async {
      final controller = makeController();
      await tester.pumpWidget(
        buildTestApp(child: ConfigTab(controller: controller)),
      );
      await tester.pumpAndSettle();

      final removeTile = find.text('Remove Device Owner now');
      await tester.scrollUntilVisible(
        removeTile,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(removeTile);
      await tester.pumpAndSettle();

      expect(
        find.text('Remove Device Owner and end protection?'),
        findsOneWidget,
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove protection'));
      await tester.pumpAndSettle();

      // The 16-character paper recovery code is required before the
      // removal runs: the code gate appears and no removal call fired.
      expect(find.text('Enter recovery code'), findsOneWidget);
      expect(
        calls.any((c) => c.method == 'removeDeviceOwner'),
        isFalse,
      );
      controller.session.end();
    });
  });
}
