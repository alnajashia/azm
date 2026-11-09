import 'package:dominanter/data/privileged_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'dominanter/privileged';
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final methodChannel = const MethodChannel(channelName);

  PrivilegedChannel clientWith(Future<Object?>? Function(MethodCall call)? handler) {
    messenger.setMockMethodCallHandler(methodChannel, handler);
    return PrivilegedChannel(methodChannel: methodChannel);
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  test('getShizukuState parses the exact Kotlin payload', () async {
    final client = clientWith((call) async {
      expect(call.method, 'getShizukuState');
      return {
        'state': 'granted',
        'serverVersion': 13,
        'serverUid': 2000,
        'isPreV11': false,
      };
    });
    final status = await client.getShizukuState();
    expect(status.state, ShizukuState.granted);
    expect(status.serverVersion, 13);
    expect(status.serverUid, 2000);
    expect(status.isPreV11, isFalse);
  });

  test('all five Shizuku states parse distinctly', () async {
    for (final (wire, expected) in [
      ('notInstalled', ShizukuState.notInstalled),
      ('notRunning', ShizukuState.notRunning),
      ('preV11', ShizukuState.preV11),
      ('noPermission', ShizukuState.noPermission),
      ('granted', ShizukuState.granted),
    ]) {
      final client = clientWith((_) async => {'state': wire});
      expect((await client.getShizukuState()).state, expected, reason: wire);
    }
  });

  test('SHELL_FAILED keeps code, exitCode, command and stderr from details', () async {
    final client = clientWith((call) async {
      throw PlatformException(
        code: 'SHELL_FAILED',
        message: 'Command failed with exit code 3: dpm set-device-owner x/y',
        details: {
          'exitCode': 3,
          'command': 'dpm set-device-owner x/y',
          'stdout': '',
          'stderr': 'Error: not the owner',
        },
      );
    });
    try {
      await client.provisionDeviceOwner();
      fail('expected PrivilegedException');
    } on PrivilegedException catch (e) {
      expect(e.code, 'SHELL_FAILED');
      expect(e.exitCode, 3);
      expect(e.command, 'dpm set-device-owner x/y');
      expect(e.stderr, 'Error: not the owner');
      expect(e.isShizukuUnavailable, isTrue);
    }
  });

  test('DPM_NOT_OWNER is mapped and recognisable', () async {
    final client = clientWith((_) async {
      throw PlatformException(code: 'DPM_NOT_OWNER', message: 'not owner');
    });
    try {
      await client.listUserRestrictions();
      fail('expected PrivilegedException');
    } on PrivilegedException catch (e) {
      expect(e.code, 'DPM_NOT_OWNER');
      expect(e.isNotOwner, isTrue);
      expect(e.exitCode, isNull);
    }
  });

  test('a missing native side becomes UNAVAILABLE, never a fake result', () async {
    final client = clientWith(null); // no handler: MissingPluginException
    try {
      await client.isRecoveryCodeSet();
      fail('expected PrivilegedException');
    } on PrivilegedException catch (e) {
      expect(e.code, 'UNAVAILABLE');
      expect(e.isUnavailable, isTrue);
    }
  });

  test('listInstalledApps parses Kotlin AppInfo maps incl. null rating', () async {
    final client = clientWith((call) async {
      expect(call.method, 'listInstalledApps');
      expect((call.arguments as Map)['includeSystem'], isTrue);
      return [
        {
          'packageName': 'com.example.app',
          'label': 'Example',
          'isSystem': false,
          'isHidden': true,
          'isSuspended': false,
          'isUninstallBlocked': true,
          'hasExplicitContentRating': null,
        },
      ];
    });
    final apps = await client.listInstalledApps(includeSystem: true);
    expect(apps.single.label, 'Example');
    expect(apps.single.isHidden, isTrue);
    expect(apps.single.hasExplicitContentRating, isNull);
  });

  test('setAppSuspended returns verified per-package results', () async {
    final client = clientWith((call) async {
      final args = call.arguments as Map;
      expect(args['packageNames'], ['a.b']);
      expect(args['reason'], 'MANUAL');
      return {
        'results': [
          {'packageName': 'a.b', 'isSuspended': true},
        ],
      };
    });
    final results = await client.setAppSuspended(['a.b'], true, reason: 'MANUAL');
    expect(results.single.isSuspended, isTrue);
  });

  test('time limit / windows / groups payloads round-trip through the client', () async {
    final store = <String, Object?>{};
    final client = clientWith((call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
      switch (call.method) {
        case 'setTimeLimit':
          store['limit'] = args;
          return {
            'packageName': args['packageName'],
            'dailyMinutes': 45,
            'weeklyMinutes': null,
            'reopenSeconds': 30,
          };
        case 'getTimeLimit':
          return {
            'packageName': args['packageName'],
            'dailyMinutes': 45,
            'weeklyMinutes': null,
            'reopenSeconds': 30,
          };
        case 'getTimeWindows':
          return {
            'packageName': args['packageName'],
            'dailyWindows': [
              {'s': 420, 'e': 1260}
            ],
            'weeklyWindows': null,
          };
        case 'setGroups':
          return {'groups': args['groups']};
        default:
          fail('unexpected method ${call.method}');
      }
    });

    final enforcement = await client.setTimeLimit('a.b',
        dailyMinutes: 45, reopenSeconds: 30);
    expect(store['limit'], {
      'packageName': 'a.b',
      'dailyMinutes': 45,
      'reopenSeconds': 30,
    });
    expect(enforcement.dailyMinutes, 45);
    expect(enforcement.reopenSeconds, 30);
    expect(enforcement.dailyWindows.single.formatted, '07:00 – 21:00');

    final groups = await client.setGroups(const [
      AppGroupModel(id: 'g1', name: 'Social', packages: ['a.b'], dailyMinutes: 60),
    ]);
    expect(groups.single.name, 'Social');
    expect(groups.single.packages, ['a.b']);
  });
}
