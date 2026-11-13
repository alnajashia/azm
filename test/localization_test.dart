// Localization (v1.0.4, amendment A): the Arabic and English ARB
// tables carry identical key sets, both locales resolve through the
// generated delegate, and the lock screen renders Arabic in RTL when
// the Arabic locale is active.
import 'dart:convert';
import 'dart:io';

import 'package:azm/app_controller.dart';
import 'package:azm/data/privileged_channel.dart';
import 'package:azm/domain/entry_password.dart';
import 'package:azm/l10n/app_localizations.dart';
import 'package:azm/l10n/app_localizations_ar.dart';
import 'package:azm/l10n/app_localizations_en.dart';
import 'package:azm/ui/lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ARB tables: identical key sets, no empty values', () {
    Map<String, dynamic> load(String path) =>
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    final en = load('lib/l10n/app_en.arb');
    final ar = load('lib/l10n/app_ar.arb');
    final enKeys = en.keys.where((k) => !k.startsWith('@')).toSet();
    final arKeys = ar.keys.where((k) => !k.startsWith('@')).toSet();
    expect(arKeys, enKeys, reason: 'ar/en ARB key sets must be identical');
    expect(enKeys.length, greaterThan(500));
    for (final key in enKeys) {
      expect((en[key] as String).trim(), isNotEmpty, reason: 'en.$key empty');
      expect((ar[key] as String).trim(), isNotEmpty, reason: 'ar.$key empty');
    }
  });

  test('Both locales resolve key strings through the generated classes', () {
    final en = AppLocalizationsEn();
    final ar = AppLocalizationsAr();
    expect(en.accessApp, 'Access app');
    expect(ar.accessApp, isNot(en.accessApp));
    expect(ar.accessApp.trim(), isNotEmpty);
    expect(en.panicButton, "I'm having impulses");
    expect(ar.gateCodeTitle.trim(), isNotEmpty);
    expect(ar.appEntrySection.trim(), isNotEmpty);
    expect(en.brandTagline, 'BREAK THE CHAIN');
    expect(ar.brandTagline, 'اكسر القيد');
    // v1.0.5 rename: the user-visible app name is Azm / عزم in both
    // locales (identifiers and asset names keep the old project name).
    expect(en.appTitle, 'Azm');
    expect(ar.appTitle, 'عزم');
    expect(en.generalSettings, 'General Settings');
    expect(ar.generalSettings, 'الإعدادات العامة');
    // Parameterised strings format in both locales.
    expect(en.stepOf(2, 4), 'Step 2 of 4');
    expect(ar.stepOf(2, 4), contains('2'));
    expect(ar.stepOf(2, 4), contains('4'));
  });

  testWidgets('Lock screen renders Arabic + RTL under the ar locale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    const methodChannel = MethodChannel('azm/privileged');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(methodChannel, null);
    });
    final record = jsonEncode(
      EntryPasswordHash.create('open sesame', iterations: 1000).toJson(),
    );
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        case 'getSetting':
          final args = (call.arguments as Map).cast<String, Object?>();
          return {'value': args['key'] == 'entry_password' ? record : null};
        case 'getUsageToday':
          return {
            'date': '2026-11-10',
            'packages': <Object?>[],
            'groups': <Object?>[],
          };
        case 'listInstalledApps':
          return <Object?>[];
        case 'getGroups':
          return {'groups': <Object?>[]};
        case 'getFocusSession':
          return null;
        default:
          throw MissingPluginException('no mock for ${call.method}');
      }
    });
    final controller = AppController.test(
      PrivilegedChannel(methodChannel: methodChannel),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LockScreen(controller: controller),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final ar = AppLocalizationsAr();
    // Arabic chrome from the AR table, not the English fallback.
    expect(find.text(ar.accessApp), findsOneWidget);
    expect(find.text(ar.usePasswordInstead), findsOneWidget);
    expect(find.text(ar.panicButton), findsOneWidget);
    expect(find.text('Access app'), findsNothing);
    // RTL directionality is active for the Arabic locale.
    final lockContext = tester.element(find.byType(LockScreen));
    expect(Directionality.of(lockContext), TextDirection.rtl);

    await tester.pumpWidget(const SizedBox());
  });
}
