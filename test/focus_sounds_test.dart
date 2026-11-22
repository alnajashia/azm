// Focus sounds (user request 2026-11-22): Start_relax plays when a
// break starts (short or long); one of two pre-focus sounds — the
// user's pick — plays to completion BEFORE every focus phase, and
// the phase begins only after it ends.
library;

import 'dart:convert';
import 'dart:io';

import 'package:azm/app_controller.dart';
import 'package:azm/data/privileged_channel.dart';
import 'package:azm/domain/focus.dart';
import 'package:azm/theme.dart';
import 'package:azm/ui/impulse_focus_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'azm/privileged';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methodChannel = MethodChannel(channelName);

  group('FocusConfig.preFocusSound', () {
    test('round-trips through JSON', () {
      const c = FocusConfig(preFocusSound: 1);
      expect(FocusConfig.fromJson(c.toJson()).preFocusSound, 1);
    });

    test('old stored configs without the key default to the first sound', () {
      expect(FocusConfig.fromJson(const {}).preFocusSound, 0);
    });

    test('clamps to 0..1', () {
      expect(FocusConfig.fromJson(const {'preFocusSound': 7}).preFocusSound, 1);
      expect(FocusConfig.fromJson(const {'preFocusSound': -2}).preFocusSound, 0);
    });
  });

  group('FocusModeScreen sound picker', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'getSetting':
            return {'value': null};
          case 'listInstalledApps':
            return <Object?>[];
          case 'getGroups':
            return {'groups': <Object?>[]};
          case 'getFocusSession':
            return null;
          case 'setSetting':
            return <String, Object?>{};
          case 'previewFocusSound':
            return {'played': true};
          case 'hasNotificationPermission':
            return {'granted': true};
          default:
            throw MissingPluginException('no mock for ${call.method}');
        }
      });
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(methodChannel, null);
    });

    Map<String, dynamic>? lastSavedConfig() {
      for (final call in calls.reversed) {
        if (call.method != 'setSetting') continue;
        final args = call.arguments as Map<dynamic, dynamic>;
        if (args['key'] != 'config') continue;
        return (jsonDecode(args['value'] as String) as Map)
            .cast<String, dynamic>();
      }
      return null;
    }

    testWidgets('picking Sound 2 persists and previews it', (tester) async {
      final controller = AppController.test(
        PrivilegedChannel(methodChannel: methodChannel),
      );
      addTearDown(controller.dispose);
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: azmDarkTheme(),
          home: FocusModeScreen(controller: controller),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Sound before focus'), findsOneWidget);
      expect(find.text('Sound 1'), findsWidgets);
      expect(find.text('Sound 2'), findsWidgets);

      await tester.tap(find.text('Sound 2').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(lastSavedConfig()?['preFocusSound'], 1);
      final preview = calls.where((c) => c.method == 'previewFocusSound');
      expect(preview, hasLength(1));
      expect((preview.first.arguments as Map)['choice'], 1);

      await tester.pumpWidget(const SizedBox()); // dispose tickers
    });
  });

  group('native wiring pins', () {
    final store = File(
      'android/app/src/main/kotlin/com/alnajashia/azm/focus/'
      'FocusSessionStore.kt',
    ).readAsStringSync();
    final sounds = File(
      'android/app/src/main/kotlin/com/alnajashia/azm/focus/FocusSounds.kt',
    ).readAsStringSync();
    final handler = File(
      'android/app/src/main/kotlin/com/alnajashia/azm/channel/'
      'PrivilegedChannelHandler.kt',
    ).readAsStringSync();

    test('the four sound assets are bundled', () {
      for (final name in [
        'start_relax.mp3',
        'long_relax.mp3',
        'before_focus_start.mp3',
        'before_focus_start2.mp3',
      ]) {
        final f = File('android/app/src/main/assets/sounds/focus/$name');
        expect(f.existsSync(), isTrue, reason: name);
        expect(f.lengthSync(), greaterThan(10000), reason: name);
      }
      expect(sounds.contains('sounds/focus/start_relax.mp3'), isTrue);
      expect(sounds.contains('sounds/focus/long_relax.mp3'), isTrue);
      expect(sounds.contains('sounds/focus/before_focus_start.mp3'), isTrue);
      expect(sounds.contains('sounds/focus/before_focus_start2.mp3'), isTrue);
    });

    test('the sound choice is snapshotted from the Dart JSON', () {
      expect(store.contains('KEY_PRE_FOCUS_SOUND = "pre_focus_sound"'), isTrue);
      expect(store.contains('dartConfigPreFocusSound()'), isTrue);
      expect(store.contains('putInt(KEY_PRE_FOCUS_SOUND'), isTrue);
    });

    test('focus entry waits for the sound; stop invalidates it', () {
      expect(store.contains('private fun beginFocusPhase'), isTrue);
      expect(store.contains('FocusSounds.playPreFocus'), isTrue);
      expect(store.contains('sessionGeneration++'), isTrue);
      expect(store.contains('phaseStartPending'), isTrue);
    });

    test('break entry waits for its sound (short vs long)', () {
      expect(
        store.contains(
          'FocusSounds.playBreakStart(ctx, long = next == Phase.LONG_BREAK)',
        ),
        isTrue,
      );
      expect(sounds.contains('if (long) SOUND_LONG_BREAK else SOUND_BREAK'), isTrue);
    });

    test('the preview channel case exists', () {
      expect(handler.contains('"previewFocusSound"'), isTrue);
      expect(handler.contains('FocusSounds.preview'), isTrue);
    });
  });
}
