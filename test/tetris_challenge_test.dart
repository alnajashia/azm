/// Batch I-C, item 2 — Tetris: the view renders, starts on input,
/// pauses when idle, completes after the configured active-play time,
/// and the sound toggle reports back; the config keys round-trip
/// through the channel (minutes 1–15, default 3; sound default on).
///
/// NOTE: the view runs a frame ticker, so these tests use explicit
/// `tester.pump()` calls instead of `pumpAndSettle` (which would time
/// out on the periodic ticker). The completion test pumps 600 frames
/// of 100ms — the ticker caps each frame delta at 100ms, like the
/// original's `MAX_FRAME_DELTA_MS`.
library;

import 'package:azm/data/config_store.dart';
import 'package:azm/data/privileged_channel.dart';
import 'package:azm/data/tetris_sounds.dart';
import 'package:azm/l10n/app_localizations.dart';
import 'package:azm/theme.dart';
import 'package:azm/ui/tetris_challenge.dart';
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
  late Map<String, Object?> fakeSettings;

  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher
        .implicitView!;
    view.physicalSize = const Size(800, 4000);
    view.devicePixelRatio = 1.0;
    calls = [];
    fakeSettings = {
      'tetris_minutes': 5,
      'tetris_sound': false,
    };

    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getSetting':
          return {'value': fakeSettings[call.arguments['key']]};
        case 'setSetting':
          fakeSettings[call.arguments['key'] as String] =
              call.arguments['value'];
          return <String, dynamic>{};
        case 'loadTetrisSounds':
          return {'loaded': true};
        case 'playTetrisSound':
          return {'played': true};
        case 'releaseTetrisSounds':
          return {'released': true};
      }
      throw MissingPluginException('Unhandled ${call.method} in tetris test');
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher
        .implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  Widget buildTestApp({required Widget child}) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: azmLightTheme(),
      darkTheme: azmDarkTheme(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );
  }

  Future<void> pumpView(
    WidgetTester tester, {
    int minutes = 1,
    bool soundOn = false,
    required VoidCallback onComplete,
    ValueChanged<bool>? onSoundChanged,
  }) async {
    await tester.pumpWidget(
      buildTestApp(
        child: TetrisChallengeView(
          minutes: minutes,
          soundOn: soundOn,
          onSoundChanged: onSoundChanged ?? (_) {},
          sounds: TetrisSounds(PrivilegedChannel(methodChannel: methodChannel)),
          onComplete: onComplete,
        ),
      ),
    );
    await tester.pump();
  }

  group('ConfigStore tetris keys', () {
    test('minutes round-trip and clamp; sound round-trips', () async {
      final config = ConfigStore(PrivilegedChannel(methodChannel: methodChannel));
      expect(await config.getTetrisMinutes(), 5);
      await config.setTetrisMinutes(99);
      expect(fakeSettings['tetris_minutes'], 15);
      expect(await config.getTetrisMinutes(), 15);
      await config.setTetrisMinutes(0);
      expect(await config.getTetrisMinutes(), 1);
      expect(await config.isTetrisSoundEnabled(), isFalse);
      await config.setTetrisSoundEnabled(true);
      expect(fakeSettings['tetris_sound'], isTrue);
    });

    test('defaults apply when nothing is stored', () async {
      fakeSettings.clear();
      final config = ConfigStore(PrivilegedChannel(methodChannel: methodChannel));
      expect(await config.getTetrisMinutes(), 3);
      expect(await config.isTetrisSoundEnabled(), isTrue);
    });
  });

  group('TetrisChallengeView', () {
    testWidgets('renders the board, timer, next preview and buttons',
        (tester) async {
      var completed = false;
      await pumpView(tester, onComplete: () => completed = true);
      expect(find.text('01:00'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Lines: 0'), findsOneWidget);
      expect(find.text('Level 1'), findsOneWidget);
      for (final tooltip in [
        'Move left',
        'Rotate',
        'Move right',
        'Move down',
        'Drop',
      ]) {
        expect(find.byTooltip(tooltip), findsOneWidget);
      }
      expect(calls.any((c) => c.method == 'loadTetrisSounds'), isTrue);
      expect(completed, isFalse);
    });

    testWidgets('starts paused; the first input starts play', (tester) async {
      await pumpView(tester, onComplete: () {});
      // The game starts paused (Dechainer: lastInputAt = -8s).
      expect(
        find.text(
          'Paused — touch the board or a button to play. Time only counts while you play.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Rotate'));
      await tester.pump();
      expect(
        find.text(
          'Paused — touch the board or a button to play. Time only counts while you play.',
        ),
        findsNothing,
      );
    });

    testWidgets('idles back to paused after 8s without input',
        (tester) async {
      await pumpView(tester, onComplete: () {});
      await tester.tap(find.byTooltip('Rotate'));
      await tester.pump();
      // 9 seconds of frames without input: the idle rule pauses.
      for (var i = 0; i < 90; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        find.text(
          'Paused — touch the board or a button to play. Time only counts while you play.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('playing 1 minute shows Continue and completes',
        (tester) async {
      var completed = false;
      await pumpView(tester, onComplete: () => completed = true);
      // 600 frames of 100ms = 60s of active play; re-input every
      // 5s so the 8s idle rule never pauses the game.
      for (var i = 0; i < 600; i++) {
        if (i % 50 == 0) {
          await tester.tap(find.byTooltip('Rotate'));
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Continue'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(completed, isTrue);
    });

    testWidgets('the sound toggle reports back', (tester) async {
      var reported = true;
      await pumpView(
        tester,
        soundOn: true,
        onComplete: () {},
        onSoundChanged: (v) => reported = v,
      );
      await tester.tap(find.byIcon(Icons.volume_up_outlined));
      await tester.pump();
      expect(reported, isFalse);
    });
  });
}
