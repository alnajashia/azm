/// v1.0.6 feature pins: visual blocking (Phase B), seal rules
/// (Phase D), app-lock timing (Phase C), the plain-language error
/// layer (Phase E), the outlined-icon language (item 9 + the single
/// sanctioned exception from item 10), and the 24-hour forced
/// removal (user directive).
library;

import 'dart:io';

import 'package:azm/data/privileged_channel.dart';
import 'package:azm/domain/entry_grace.dart';
import 'package:azm/domain/seal_rules.dart';
import 'package:azm/domain/visual_blocking.dart';
import 'package:azm/l10n/app_localizations.dart';
import 'package:azm/l10n/app_localizations_ar.dart';
import 'package:azm/l10n/app_localizations_en.dart';
import 'package:azm/ui/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase B — VisualBlockingConfig', () {
    test('defaults mirror the original exactly', () {
      const c = VisualBlockingConfig();
      expect(c.enabled, isFalse);
      expect(c.targetPackages, {'com.reddit.frontpage'});
      expect(c.categories, {'hentai', 'porn', 'sexy'});
      expect(c.threshold, 0.5);
      expect(c.suspendEnabled, isFalse);
      expect(c.suspendBlockCount, 5);
      expect(c.suspendWindowMinutes, 15);
      expect(c.suspendDurationMinutes, 30);
    });

    test('map round-trip preserves every field', () {
      const c = VisualBlockingConfig(
        enabled: true,
        targetPackages: {'com.a', 'com.b'},
        categories: {'porn', 'drawings'},
        threshold: 0.7,
        suspendEnabled: true,
        suspendBlockCount: 3,
        suspendWindowMinutes: 10,
        suspendDurationMinutes: 45,
      );
      expect(VisualBlockingConfig.fromMap(c.toMap()), c);
    });

    test('fromMap clamps out-of-range values and drops neutral', () {
      final c = VisualBlockingConfig.fromMap({
        'enabled': true,
        'targetPackages': ['com.a'],
        'categories': ['neutral', 'porn'],
        'threshold': 5.0,
        'suspendEnabled': true,
        'suspendBlockCount': 0,
        'suspendWindowMinutes': 99999,
        'suspendDurationMinutes': -3,
      });
      expect(c.categories, {'porn'});
      expect(c.threshold, 0.99);
      expect(c.suspendBlockCount, 1);
      expect(c.suspendWindowMinutes, 1440);
      expect(c.suspendDurationMinutes, 1);
    });

    test('loosenedBy: disabling, dropping, or raising loosens; the '
        'reverse tightens', () {
      const base = VisualBlockingConfig(enabled: true);
      expect(base.loosenedBy(base.copyWith(enabled: false)), isTrue);
      expect(
        base.loosenedBy(base.copyWith(targetPackages: <String>{})),
        isTrue,
      );
      expect(
        base.loosenedBy(base.copyWith(categories: {'porn'})),
        isTrue,
      );
      expect(base.loosenedBy(base.copyWith(threshold: 0.6)), isTrue);
      expect(base.loosenedBy(base.copyWith(threshold: 0.4)), isFalse);
      expect(
        base.loosenedBy(
          base.copyWith(targetPackages: {'com.reddit.frontpage', 'com.x'}),
        ),
        isFalse,
      );
      const off = VisualBlockingConfig();
      expect(off.loosenedBy(off.copyWith(enabled: true)), isFalse);
    });
  });

  group('Phase D — seal rules (Dart model)', () {
    test('rule map round-trip for every trigger', () {
      for (final t in SealTrigger.values) {
        final rule = SealRule(
          id: 'r1',
          trigger: t,
          packageName: t.needsApp ? 'com.example.app' : null,
          durationMinutes: t.isEvent ? 360 : null,
        );
        expect(SealRule.fromMap(rule.toMap()), rule);
      }
    });

    test('native names match the Kotlin enum', () {
      expect(SealTrigger.appBlocked.nativeName, 'APP_BLOCKED');
      expect(SealTrigger.appSuspended.nativeName, 'APP_SUSPENDED');
      expect(SealTrigger.focusRunning.nativeName, 'FOCUS_RUNNING');
      expect(SealTrigger.visualDetection.nativeName, 'VISUAL_DETECTION');
      expect(SealTrigger.bannedWord.nativeName, 'BANNED_WORD');
      for (final t in SealTrigger.values) {
        expect(SealTrigger.fromNative(t.nativeName), t);
      }
    });

    test('event durations mirror the native list', () {
      expect(sealEventDurationsMinutes, [30, 60, 360, 1440, 10080]);
    });

    test('gate classification: disable/shorten/delete loosen; '
        'enable/lengthen/add tighten', () {
      const rule = SealRule(
        id: 'r',
        trigger: SealTrigger.visualDetection,
        packageName: 'com.a',
        durationMinutes: 360,
      );
      expect(sealChangeLoosens(rule, rule.copyWith(enabled: false)), isTrue);
      expect(
        sealChangeLoosens(rule, rule.copyWith(durationMinutes: 60)),
        isTrue,
      );
      expect(
        sealChangeLoosens(rule, rule.copyWith(durationMinutes: 1440)),
        isFalse,
      );
      expect(sealChangeLoosens(rule, rule), isFalse);
      expect(sealDeletionLoosens(rule), isTrue);
      expect(
        sealDeletionLoosens(rule.copyWith(enabled: false)),
        isFalse,
      );
    });

    test('ActiveSeal parses the native details shape', () {
      final seal = ActiveSeal.fromMap({
        'ruleId': 'r9',
        'trigger': 'BANNED_WORD',
        'packageName': 'com.chat',
        'remainingMs': 1800000,
      })!;
      expect(seal.remaining, const Duration(minutes: 30));
      expect(seal.toDetails()['trigger'], 'BANNED_WORD');
    });
  });

  group('Phase C — entry grace decision', () {
    final t0 = DateTime(2026, 11, 10, 12, 0);

    test('Immediately relocks after a real absence, never for a '
        'transient surface', () {
      expect(
        entryShouldRelock(
          now: t0.add(const Duration(seconds: 30)),
          lastUnlockAt: t0,
          period: EntryGracePeriod.immediately,
          backgroundedFor: const Duration(seconds: 30),
        ),
        isTrue,
      );
      // The biometric prompt itself backgrounds the app briefly.
      expect(
        entryShouldRelock(
          now: t0.add(const Duration(seconds: 1)),
          lastUnlockAt: t0,
          period: EntryGracePeriod.immediately,
          backgroundedFor: const Duration(seconds: 1),
        ),
        isFalse,
      );
    });

    test('grace windows: inside stays open, at/after the limit relocks',
        () {
      for (final (period, within, beyond) in [
        (EntryGracePeriod.oneMinute, 59, 60),
        (EntryGracePeriod.fifteenMinutes, 14 * 60 + 59, 15 * 60),
        (EntryGracePeriod.oneHour, 59 * 60 + 59, 60 * 60),
      ]) {
        expect(
          entryShouldRelock(
            now: t0.add(Duration(seconds: within)),
            lastUnlockAt: t0,
            period: period,
            backgroundedFor: Duration(seconds: within),
          ),
          isFalse,
          reason: '$period within',
        );
        expect(
          entryShouldRelock(
            now: t0.add(Duration(seconds: beyond)),
            lastUnlockAt: t0,
            period: period,
            backgroundedFor: Duration(seconds: beyond),
          ),
          isTrue,
          reason: '$period beyond',
        );
      }
    });

    test('no recorded unlock relocks; a FUTURE timestamp is clamped '
        'to expired (process death / clock moves cannot extend grace)',
        () {
      expect(
        entryShouldRelock(
          now: t0,
          lastUnlockAt: null,
          period: EntryGracePeriod.oneHour,
          backgroundedFor: const Duration(minutes: 5),
        ),
        isTrue,
      );
      expect(
        entryShouldRelock(
          now: t0,
          lastUnlockAt: t0.add(const Duration(hours: 2)),
          period: EntryGracePeriod.oneHour,
          backgroundedFor: const Duration(minutes: 5),
        ),
        isTrue,
      );
    });

    test('default is Immediately; lengthening loosens, shortening '
        'tightens', () {
      expect(
        EntryGracePeriod.fromName(null),
        EntryGracePeriod.immediately,
      );
      expect(
        EntryGracePeriod.immediately.loosenedBy(EntryGracePeriod.oneHour),
        isTrue,
      );
      expect(
        EntryGracePeriod.oneHour.loosenedBy(EntryGracePeriod.immediately),
        isFalse,
      );
    });
  });

  group('Phase E — plain-language error mapper', () {
    final locales = <AppLocalizations>[AppLocalizationsEn(), AppLocalizationsAr()];
    const typedCodes = [
      'UNAVAILABLE',
      'SHIZUKU_NOT_INSTALLED',
      'SHIZUKU_NOT_RUNNING',
      'SHIZUKU_NO_PERMISSION',
      'SHIZUKU_PRE_V11',
      'SHIZUKU_BINDER_DEAD',
      'SHELL_FAILED',
      'PROVISIONING_FAILED',
      'DPM_NOT_OWNER',
      'DPM_FAILED',
      'PACKAGE_NOT_FOUND',
      'PERMISSION_DENIED',
      'UNSUPPORTED_ANDROID',
      'TIMEOUT',
      'INVALID_ARGUMENT',
      'NOT_IMPLEMENTED',
      'SEALED',
      'INTERNAL',
      'SOME_FUTURE_CODE',
    ];
    const technicalTokens = [
      'Exception',
      'PlatformException',
      'DPM_',
      'SHIZUKU_',
      'exit code',
      'stack',
      'null',
      'RAW_TECHNICAL_DETAIL',
      '{',
      '}',
    ];

    test('every typed code maps to plain language in BOTH locales, '
        'with no technical tokens and no raw message leakage', () {
      for (final l10n in locales) {
        for (final code in typedCodes) {
          final out = friendlyError(
            PrivilegedException(code, 'RAW_TECHNICAL_DETAIL', const {
              'exitCode': 17,
              'stderr': 'RAW_TECHNICAL_DETAIL',
            }),
            l10n,
          );
          expect(out.trim(), isNotEmpty, reason: '$code empty');
          for (final token in technicalTokens) {
            expect(
              out.contains(token),
              isFalse,
              reason: '$code leaked "$token": $out',
            );
          }
        }
        // Unknown and internal codes get the one generic fallback.
        expect(
          friendlyError(PrivilegedException('SOME_FUTURE_CODE', 'x'), l10n),
          l10n.errGeneric,
        );
        expect(
          friendlyError(PrivilegedException('INTERNAL', 'x'), l10n),
          l10n.errGeneric,
        );
      }
    });

    testWidgets('errors present as a centered Card dialog — never a '
        'snackbar — and dismiss only via the OK button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showErrorCard(
                    context,
                    PrivilegedException('DPM_FAILED', 'technical xyz'),
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      // The plain-language message, not the technical detail.
      expect(find.text('technical xyz'), findsNothing);
      // It does not auto-vanish.
      await tester.pump(const Duration(seconds: 10));
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('source scans (v1.0.6)', () {
    List<File> dartSources() => Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) =>
              f.path.endsWith('.dart') &&
              !f.path.contains('app_localizations'),
        )
        .toList();

    test('item 9: every icon reference is an outlined variant, except '
        'the ONE sanctioned exception (item 10)', () {
      // Sanctioned exception (user item 10, explicit): the Apps
      // search field's "include system apps" trailing toggle renders
      // FILLED while the filter is active. That single control, in
      // that single file, may reference the filled filter icon.
      const sanctionedFiles = ['lib/ui/apps_tab.dart', 'lib/ui/common.dart'];
      const sanctionedIcon = 'Icons.filter_alt';
      final iconRef = RegExp(r'Icons\.([a-z0-9_]+)');
      for (final f in dartSources()) {
        final src = f.readAsStringSync();
        for (final m in iconRef.allMatches(src)) {
          final name = m.group(1)!;
          if (name.endsWith('_outlined') || name.endsWith('_outline')) {
            continue;
          }
          final isSanctioned =
              sanctionedFiles.any((file) => f.path.endsWith(file)) &&
              'Icons.$name' == sanctionedIcon;
          expect(
            isSanctioned,
            isTrue,
            reason: '${f.path}: Icons.$name is not an outlined variant',
          );
        }
      }
    });

    test('Phase E: no raw error interpolation into UI text anywhere '
        'in lib/ui', () {
      const banned = [
        'error.toString()',
        '_error.toString()',
        '_enforcementError.toString()',
        // NB: a bare `e.toString()` is NOT banned — data conversions
        // like `source.map((e) => e.toString())` are legitimate; what
        // is banned is interpolating a caught error into UI text.
        r"'$e'",
        r'"$e"',
        'errShellFailedExit',
        'errorCodeLine',
        'errorCodeExitLine',
      ];
      for (final f in dartSources().where(
        (f) => f.path.contains('lib/ui/'),
      )) {
        final src = f.readAsStringSync();
        for (final b in banned) {
          expect(
            src.contains(b),
            isFalse,
            reason: '${f.path} contains banned raw-error pattern: $b',
          );
        }
      }
    });

    test('item 13: the Restrictions not-owner card switches to the '
        'Config tab — no pop-up page push remains', () {
      final src = File(
        'lib/ui/restrictions_tab.dart',
      ).readAsStringSync();
      expect(src.contains('requestTab(AppController.tabConfig)'), isTrue);
      expect(src.contains('MaterialPageRoute'), isFalse);
      expect(src.contains('SetupScreen('), isFalse);
    });

    test('24-hour directive: no forced-removal "48" remains in the '
        'ARB strings', () {
      for (final path in ['lib/l10n/app_en.arb', 'lib/l10n/app_ar.arb']) {
        final src = File(path).readAsStringSync();
        for (final line in src.split('\n')) {
          if (line.contains('forced') || line.contains('Forced')) {
            expect(
              line.contains('48'),
              isFalse,
              reason: '$path: $line',
            );
          }
        }
      }
    });
  });
}
