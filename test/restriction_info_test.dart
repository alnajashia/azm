/// Item 12 coverage pin (v1.0.6): EVERY restriction key in the
/// catalog has a plain-language explanation in BOTH locales — none
/// left unexplained — and unknown keys still get the generic
/// explanation rather than a blank.
library;

import 'package:dominanter/l10n/app_localizations_ar.dart';
import 'package:dominanter/l10n/app_localizations_en.dart';
import 'package:dominanter/ui/restriction_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every catalog restriction has an explanation in en AND ar', () {
    final en = AppLocalizationsEn();
    final ar = AppLocalizationsAr();
    expect(restrictionCatalogKeys.length, 74);
    for (final key in restrictionCatalogKeys) {
      final enText = restrictionExplanation(en, key);
      final arText = restrictionExplanation(ar, key);
      expect(
        enText,
        isNot(en.restrictionInfoGeneric),
        reason: '$key falls back to generic in English',
      );
      expect(
        arText,
        isNot(ar.restrictionInfoGeneric),
        reason: '$key falls back to generic in Arabic',
      );
      expect(enText.trim().length, greaterThan(40), reason: '$key en too short');
      expect(arText.trim().length, greaterThan(40), reason: '$key ar too short');
    }
  });

  test('an unknown future key gets the generic explanation, never blank', () {
    final en = AppLocalizationsEn();
    expect(
      restrictionExplanation(en, 'no_some_future_restriction'),
      en.restrictionInfoGeneric,
    );
  });
}
