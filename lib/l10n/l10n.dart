/// Localization access for the whole UI (v1.0.4: Arabic + English).
///
/// `context.l10n` resolves the generated [AppLocalizations] for the
/// ambient locale. When no localization delegate is installed — bare
/// widget tests pump screens inside a plain MaterialApp — it falls back
/// to the English strings, so a missing delegate degrades the language,
/// never the function.
library;

import 'package:flutter/widgets.dart';

import 'app_localizations.dart';
import 'app_localizations_en.dart';

export 'app_localizations.dart';

extension AppL10n on BuildContext {
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      AppLocalizationsEn();
}
