import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Azm'**
  String get appTitle;

  /// No description provided for @loadingDefault.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loadingDefault;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @continueAction.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueAction;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @errUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The Android service layer is not available here (this happens in tests or off-device). No operation was performed.'**
  String get errUnavailable;

  /// No description provided for @errShizukuNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'Shizuku is not installed on this device.'**
  String get errShizukuNotInstalled;

  /// No description provided for @errShizukuNotRunning.
  ///
  /// In en, this message translates to:
  /// **'Shizuku is installed but its server is not running. Start it from the Shizuku app, then retry.'**
  String get errShizukuNotRunning;

  /// No description provided for @errShizukuNoPermission.
  ///
  /// In en, this message translates to:
  /// **'Shizuku permission has not been granted to Azm.'**
  String get errShizukuNoPermission;

  /// No description provided for @errShizukuPreV11.
  ///
  /// In en, this message translates to:
  /// **'This Shizuku server is older than v11. Update Shizuku, then retry.'**
  String get errShizukuPreV11;

  /// No description provided for @errShizukuBinderDead.
  ///
  /// In en, this message translates to:
  /// **'The Shizuku connection dropped during the operation. Its outcome is unknown — check the current state before retrying.'**
  String get errShizukuBinderDead;

  /// No description provided for @errShellFailed.
  ///
  /// In en, this message translates to:
  /// **'A system command failed.'**
  String get errShellFailed;

  /// No description provided for @errProvisioningFailed.
  ///
  /// In en, this message translates to:
  /// **'Device Owner provisioning failed on both the direct and the fallback path. See Diagnostics on the Setup screen.'**
  String get errProvisioningFailed;

  /// No description provided for @errDpmNotOwner.
  ///
  /// In en, this message translates to:
  /// **'Azm is not the Device Owner, so this operation is not available. Complete Setup first.'**
  String get errDpmNotOwner;

  /// No description provided for @errDpmFailed.
  ///
  /// In en, this message translates to:
  /// **'The system refused or could not verify this change. Nothing was reported as successful.'**
  String get errDpmFailed;

  /// No description provided for @errPackageNotFound.
  ///
  /// In en, this message translates to:
  /// **'That app is not installed on this device.'**
  String get errPackageNotFound;

  /// No description provided for @errPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'A required permission is not granted.'**
  String get errPermissionDenied;

  /// No description provided for @errUnsupportedAndroid.
  ///
  /// In en, this message translates to:
  /// **'This Android version does not support this operation.'**
  String get errUnsupportedAndroid;

  /// No description provided for @errTimeout.
  ///
  /// In en, this message translates to:
  /// **'The operation timed out and was not reported as successful.'**
  String get errTimeout;

  /// No description provided for @errInvalidArgument.
  ///
  /// In en, this message translates to:
  /// **'Some of the information entered is not valid. Please check it and try again.'**
  String get errInvalidArgument;

  /// No description provided for @errNotImplemented.
  ///
  /// In en, this message translates to:
  /// **'This is not implemented in this version.'**
  String get errNotImplemented;

  /// No description provided for @noLimit.
  ///
  /// In en, this message translates to:
  /// **'No limit'**
  String get noLimit;

  /// No description provided for @minutesOnly.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String minutesOnly(int count);

  /// No description provided for @hoursOnly.
  ///
  /// In en, this message translates to:
  /// **'{count} h'**
  String hoursOnly(int count);

  /// No description provided for @hoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours} h {minutes} min'**
  String hoursMinutes(int hours, int minutes);

  /// No description provided for @durationHoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m'**
  String durationHoursMinutes(String hours, String minutes);

  /// No description provided for @durationMinutesSeconds.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m {seconds}s'**
  String durationMinutesSeconds(String minutes, String seconds);

  /// No description provided for @durationSecondsOnly.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s'**
  String durationSecondsOnly(String seconds);

  /// No description provided for @chipV11.
  ///
  /// In en, this message translates to:
  /// **'v1.1'**
  String get chipV11;

  /// No description provided for @sessionRemaining.
  ///
  /// In en, this message translates to:
  /// **'Recovery session'**
  String get sessionRemaining;

  /// No description provided for @renewSession.
  ///
  /// In en, this message translates to:
  /// **'Renew'**
  String get renewSession;

  /// No description provided for @endSession.
  ///
  /// In en, this message translates to:
  /// **'End session'**
  String get endSession;

  /// No description provided for @wordYes.
  ///
  /// In en, this message translates to:
  /// **'yes'**
  String get wordYes;

  /// No description provided for @wordNo.
  ///
  /// In en, this message translates to:
  /// **'no'**
  String get wordNo;

  /// No description provided for @startingAzm.
  ///
  /// In en, this message translates to:
  /// **'Starting Azm…'**
  String get startingAzm;

  /// No description provided for @unknownStartupError.
  ///
  /// In en, this message translates to:
  /// **'Unknown startup error'**
  String get unknownStartupError;

  /// No description provided for @tabStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get tabStatus;

  /// No description provided for @tabRestrictions.
  ///
  /// In en, this message translates to:
  /// **'Restrictions'**
  String get tabRestrictions;

  /// No description provided for @tabApps.
  ///
  /// In en, this message translates to:
  /// **'Apps'**
  String get tabApps;

  /// No description provided for @tabConfig.
  ///
  /// In en, this message translates to:
  /// **'Config'**
  String get tabConfig;

  /// No description provided for @lockTitle.
  ///
  /// In en, this message translates to:
  /// **'Azm is locked'**
  String get lockTitle;

  /// No description provided for @panicButton.
  ///
  /// In en, this message translates to:
  /// **'I\'m having impulses'**
  String get panicButton;

  /// No description provided for @accessApp.
  ///
  /// In en, this message translates to:
  /// **'Access app'**
  String get accessApp;

  /// No description provided for @viewLimits.
  ///
  /// In en, this message translates to:
  /// **'View limits'**
  String get viewLimits;

  /// No description provided for @lockHelperBiometric.
  ///
  /// In en, this message translates to:
  /// **'Use your fingerprint, face or device PIN to open the app.'**
  String get lockHelperBiometric;

  /// No description provided for @lockHelperWithPassword.
  ///
  /// In en, this message translates to:
  /// **'Use your fingerprint, face or device PIN — or your app password.'**
  String get lockHelperWithPassword;

  /// No description provided for @usePasswordInstead.
  ///
  /// In en, this message translates to:
  /// **'Use password instead'**
  String get usePasswordInstead;

  /// No description provided for @versionFooter.
  ///
  /// In en, this message translates to:
  /// **'Azm {version}'**
  String versionFooter(String version);

  /// No description provided for @impulseBlockActive.
  ///
  /// In en, this message translates to:
  /// **'Impulse block active'**
  String get impulseBlockActive;

  /// No description provided for @impulseStartedSuspended.
  ///
  /// In en, this message translates to:
  /// **'Impulse lock started; chosen apps suspended for {minutes} min.'**
  String impulseStartedSuspended(int minutes);

  /// No description provided for @impulseStarted.
  ///
  /// In en, this message translates to:
  /// **'Impulse lock started for {minutes} min.'**
  String impulseStarted(int minutes);

  /// No description provided for @focusPhaseFocusOf.
  ///
  /// In en, this message translates to:
  /// **'Focus {current}/{total}'**
  String focusPhaseFocusOf(int current, int total);

  /// No description provided for @focusPhaseShortBreak.
  ///
  /// In en, this message translates to:
  /// **'Short break'**
  String get focusPhaseShortBreak;

  /// No description provided for @focusPhaseLongBreak.
  ///
  /// In en, this message translates to:
  /// **'Long break'**
  String get focusPhaseLongBreak;

  /// No description provided for @focusPhaseBreakOver.
  ///
  /// In en, this message translates to:
  /// **'Break over'**
  String get focusPhaseBreakOver;

  /// No description provided for @focusPhaseMode.
  ///
  /// In en, this message translates to:
  /// **'Focus mode'**
  String get focusPhaseMode;

  /// No description provided for @focusPausedTitle.
  ///
  /// In en, this message translates to:
  /// **'{title} · paused'**
  String focusPausedTitle(String title);

  /// No description provided for @focusConfigSummary.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min of focus, suspending the selected apps'**
  String focusConfigSummary(int minutes);

  /// No description provided for @focusPeriodsCompleted.
  ///
  /// In en, this message translates to:
  /// **'Focus periods completed: {done}/{total}'**
  String focusPeriodsCompleted(int done, int total);

  /// No description provided for @focusStart.
  ///
  /// In en, this message translates to:
  /// **'Start focus'**
  String get focusStart;

  /// No description provided for @focusResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get focusResume;

  /// No description provided for @focusSkipBreak.
  ///
  /// In en, this message translates to:
  /// **'Skip break'**
  String get focusSkipBreak;

  /// No description provided for @focusPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get focusPause;

  /// No description provided for @focusEndSession.
  ///
  /// In en, this message translates to:
  /// **'End session'**
  String get focusEndSession;

  /// No description provided for @todaysUsage.
  ///
  /// In en, this message translates to:
  /// **'Today\'s usage'**
  String get todaysUsage;

  /// No description provided for @loadingUsageLimits.
  ///
  /// In en, this message translates to:
  /// **'Loading usage limits…'**
  String get loadingUsageLimits;

  /// No description provided for @noLimitsSet.
  ///
  /// In en, this message translates to:
  /// **'No time limit set for apps or groups.'**
  String get noLimitsSet;

  /// No description provided for @sectionGroups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get sectionGroups;

  /// No description provided for @sectionApps.
  ///
  /// In en, this message translates to:
  /// **'Apps'**
  String get sectionApps;

  /// No description provided for @groupPrefix.
  ///
  /// In en, this message translates to:
  /// **'Group: {name}'**
  String groupPrefix(String name);

  /// No description provided for @usageOf.
  ///
  /// In en, this message translates to:
  /// **'{used} of {limit}'**
  String usageOf(String used, String limit);

  /// No description provided for @limitReached.
  ///
  /// In en, this message translates to:
  /// **'Limit reached'**
  String get limitReached;

  /// No description provided for @timeLeft.
  ///
  /// In en, this message translates to:
  /// **'{time} left'**
  String timeLeft(String time);

  /// No description provided for @overviewMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count}min'**
  String overviewMinutes(int count);

  /// No description provided for @overviewHours.
  ///
  /// In en, this message translates to:
  /// **'{count}h'**
  String overviewHours(int count);

  /// No description provided for @overviewHoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}min'**
  String overviewHoursMinutes(int hours, int minutes);

  /// No description provided for @noDeviceLockTitle.
  ///
  /// In en, this message translates to:
  /// **'No device lock is set up'**
  String get noDeviceLockTitle;

  /// No description provided for @noDeviceLockBody.
  ///
  /// In en, this message translates to:
  /// **'This device has no biometric or screen credential enrolled, so there is nothing to authenticate against. Entry is allowed — exactly as the original app behaves in this case. Consider setting a device PIN.'**
  String get noDeviceLockBody;

  /// No description provided for @unlockReason.
  ///
  /// In en, this message translates to:
  /// **'Unlock Azm'**
  String get unlockReason;

  /// No description provided for @authNotCompleted.
  ///
  /// In en, this message translates to:
  /// **'Authentication was not completed.'**
  String get authNotCompleted;

  /// No description provided for @authFailed.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed: {message}'**
  String authFailed(String message);

  /// No description provided for @authCouldNotStart.
  ///
  /// In en, this message translates to:
  /// **'Authentication could not start. Please try again.'**
  String get authCouldNotStart;

  /// No description provided for @passwordPromptTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter app password'**
  String get passwordPromptTitle;

  /// No description provided for @passwordFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'App password'**
  String get passwordFieldLabel;

  /// No description provided for @passwordUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get passwordUnlock;

  /// No description provided for @passwordWrong.
  ///
  /// In en, this message translates to:
  /// **'That password is not correct.'**
  String get passwordWrong;

  /// No description provided for @passwordRetryIn.
  ///
  /// In en, this message translates to:
  /// **'Try again in {seconds}s'**
  String passwordRetryIn(int seconds);

  /// No description provided for @passwordChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get passwordChecking;

  /// No description provided for @appEntrySection.
  ///
  /// In en, this message translates to:
  /// **'App entry'**
  String get appEntrySection;

  /// No description provided for @appEntryExplanation.
  ///
  /// In en, this message translates to:
  /// **'Set an app password as another way to open Azm from the lock screen. The password only opens the app — loosening restrictions or removing Device Owner still needs the recovery code.'**
  String get appEntryExplanation;

  /// No description provided for @appEntryStatusSet.
  ///
  /// In en, this message translates to:
  /// **'An app password is set.'**
  String get appEntryStatusSet;

  /// No description provided for @appEntryStatusUnset.
  ///
  /// In en, this message translates to:
  /// **'No app password is set.'**
  String get appEntryStatusUnset;

  /// No description provided for @appEntrySet.
  ///
  /// In en, this message translates to:
  /// **'Set password'**
  String get appEntrySet;

  /// No description provided for @appEntryChange.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get appEntryChange;

  /// No description provided for @appEntryRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove password'**
  String get appEntryRemove;

  /// No description provided for @passwordNewLabel.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get passwordNewLabel;

  /// No description provided for @passwordConfirmLabel.
  ///
  /// In en, this message translates to:
  /// **'Repeat password'**
  String get passwordConfirmLabel;

  /// No description provided for @passwordMinLength.
  ///
  /// In en, this message translates to:
  /// **'Use at least {count} characters.'**
  String passwordMinLength(int count);

  /// No description provided for @passwordMismatch.
  ///
  /// In en, this message translates to:
  /// **'The two passwords do not match.'**
  String get passwordMismatch;

  /// No description provided for @passwordSetDone.
  ///
  /// In en, this message translates to:
  /// **'App password set.'**
  String get passwordSetDone;

  /// No description provided for @passwordRemovedDone.
  ///
  /// In en, this message translates to:
  /// **'App password removed.'**
  String get passwordRemovedDone;

  /// No description provided for @passwordRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove app password?'**
  String get passwordRemoveTitle;

  /// No description provided for @passwordRemoveBody.
  ///
  /// In en, this message translates to:
  /// **'You will open the app with your fingerprint or device credential again. This does not change the recovery code.'**
  String get passwordRemoveBody;

  /// No description provided for @passwordRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get passwordRemoveConfirm;

  /// No description provided for @passwordShow.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get passwordShow;

  /// No description provided for @passwordHide.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get passwordHide;

  /// No description provided for @recoveryCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Recovery code'**
  String get recoveryCodeLabel;

  /// No description provided for @wizardSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Set up your recovery code'**
  String get wizardSetupTitle;

  /// No description provided for @wizardChangeTitle.
  ///
  /// In en, this message translates to:
  /// **'Change recovery code'**
  String get wizardChangeTitle;

  /// No description provided for @stepOf.
  ///
  /// In en, this message translates to:
  /// **'Step {step} of {total}'**
  String stepOf(int step, int total);

  /// No description provided for @grabPaper.
  ///
  /// In en, this message translates to:
  /// **'Grab a pen and paper before continuing.'**
  String get grabPaper;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @finish.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get finish;

  /// No description provided for @wizardIntroTitle.
  ///
  /// In en, this message translates to:
  /// **'Your recovery code'**
  String get wizardIntroTitle;

  /// No description provided for @howItWorks.
  ///
  /// In en, this message translates to:
  /// **'How it works'**
  String get howItWorks;

  /// No description provided for @tipGenerates.
  ///
  /// In en, this message translates to:
  /// **'Azm generates a 16-letter code'**
  String get tipGenerates;

  /// No description provided for @tipWrite.
  ///
  /// In en, this message translates to:
  /// **'Write the code down on a piece of paper'**
  String get tipWrite;

  /// No description provided for @tipTypeBack.
  ///
  /// In en, this message translates to:
  /// **'Type it back to make sure it\'s correct'**
  String get tipTypeBack;

  /// No description provided for @tipStorePaper.
  ///
  /// In en, this message translates to:
  /// **'Store the paper in a safe place'**
  String get tipStorePaper;

  /// No description provided for @wizardIntroBody.
  ///
  /// In en, this message translates to:
  /// **'The code will be asked for whenever you change Azm\'s settings. Without it, you could be locked out of the blocked features. It is stored only as a salted hash on this device — it cannot be shown again after this wizard, and there is no account or cloud copy.'**
  String get wizardIntroBody;

  /// No description provided for @writeTitle.
  ///
  /// In en, this message translates to:
  /// **'Write it on paper'**
  String get writeTitle;

  /// No description provided for @writeBody.
  ///
  /// In en, this message translates to:
  /// **'Copy the 16 letters exactly as shown. Don\'t take a screenshot or save it on your phone — a copy within reach is easy to use in a moment of impulse.'**
  String get writeBody;

  /// No description provided for @generatingCode.
  ///
  /// In en, this message translates to:
  /// **'Generating your code…'**
  String get generatingCode;

  /// No description provided for @showCode.
  ///
  /// In en, this message translates to:
  /// **'Show code'**
  String get showCode;

  /// No description provided for @wroteOnPaper.
  ///
  /// In en, this message translates to:
  /// **'I wrote the code on paper'**
  String get wroteOnPaper;

  /// No description provided for @confirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Check what you wrote'**
  String get confirmTitle;

  /// No description provided for @confirmBody.
  ///
  /// In en, this message translates to:
  /// **'The code is hidden now. Type it from your paper to make sure every letter is right.'**
  String get confirmBody;

  /// No description provided for @codeCorrect.
  ///
  /// In en, this message translates to:
  /// **'The code is correct'**
  String get codeCorrect;

  /// No description provided for @codeMismatchBack.
  ///
  /// In en, this message translates to:
  /// **'It doesn\'t match. Go back and compare it with your paper.'**
  String get codeMismatchBack;

  /// No description provided for @codeCountOf.
  ///
  /// In en, this message translates to:
  /// **'{count}/16'**
  String codeCountOf(int count);

  /// No description provided for @storeTitle.
  ///
  /// In en, this message translates to:
  /// **'Store it in a safe place'**
  String get storeTitle;

  /// No description provided for @storeBody.
  ///
  /// In en, this message translates to:
  /// **'The paper is now the only copy of your code. Choose carefully where to keep it.'**
  String get storeBody;

  /// No description provided for @tipAway.
  ///
  /// In en, this message translates to:
  /// **'Away from your phone, somewhere you won\'t reach on impulse'**
  String get tipAway;

  /// No description provided for @tipEasyFind.
  ///
  /// In en, this message translates to:
  /// **'Easy to find when you really need it — a drawer, a folder or with someone you trust'**
  String get tipEasyFind;

  /// No description provided for @tipNoPhotos.
  ///
  /// In en, this message translates to:
  /// **'No photos or digital copies'**
  String get tipNoPhotos;

  /// No description provided for @tipThrowOld.
  ///
  /// In en, this message translates to:
  /// **'Throw away the paper with the old code'**
  String get tipThrowOld;

  /// No description provided for @storedPaperCheckbox.
  ///
  /// In en, this message translates to:
  /// **'I stored the paper in a safe place'**
  String get storedPaperCheckbox;

  /// No description provided for @codeMismatchStore.
  ///
  /// In en, this message translates to:
  /// **'That does not match the code shown. Check your paper copy and try again.'**
  String get codeMismatchStore;

  /// No description provided for @codeNotStored.
  ///
  /// In en, this message translates to:
  /// **'The code was not stored. Nothing was changed.'**
  String get codeNotStored;

  /// No description provided for @firstRunTitle.
  ///
  /// In en, this message translates to:
  /// **'Azm — first run'**
  String get firstRunTitle;

  /// No description provided for @gateCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter recovery code'**
  String get gateCodeTitle;

  /// No description provided for @gateIntroText.
  ///
  /// In en, this message translates to:
  /// **'Enter your recovery code to open a 10-minute session.'**
  String get gateIntroText;

  /// No description provided for @gateEnterCodeError.
  ///
  /// In en, this message translates to:
  /// **'Enter the 16-letter code from your paper copy.'**
  String get gateEnterCodeError;

  /// No description provided for @gateWrongCode.
  ///
  /// In en, this message translates to:
  /// **'That code does not match. Nothing was unlocked.'**
  String get gateWrongCode;

  /// No description provided for @preparingGate.
  ///
  /// In en, this message translates to:
  /// **'Preparing the gate…'**
  String get preparingGate;

  /// No description provided for @undoWindowPassed.
  ///
  /// In en, this message translates to:
  /// **'The undo window has passed; the change stands.'**
  String get undoWindowPassed;

  /// No description provided for @mathSolveTitle.
  ///
  /// In en, this message translates to:
  /// **'Solve {count} problems'**
  String mathSolveTitle(int count);

  /// No description provided for @mathNotQuite.
  ///
  /// In en, this message translates to:
  /// **'Not quite — try again.'**
  String get mathNotQuite;

  /// No description provided for @answerLabel.
  ///
  /// In en, this message translates to:
  /// **'Answer'**
  String get answerLabel;

  /// No description provided for @check.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get check;

  /// No description provided for @wordsTypeTitle.
  ///
  /// In en, this message translates to:
  /// **'Type the words'**
  String get wordsTypeTitle;

  /// No description provided for @wordsCounter.
  ///
  /// In en, this message translates to:
  /// **'{current} / {total}'**
  String wordsCounter(int current, int total);

  /// No description provided for @typeWordLabel.
  ///
  /// In en, this message translates to:
  /// **'Type the word'**
  String get typeWordLabel;

  /// No description provided for @readingTitle.
  ///
  /// In en, this message translates to:
  /// **'Read slowly — passage {current} of {total}: {title}'**
  String readingTitle(int current, int total, String title);

  /// No description provided for @readingFinish.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get readingFinish;

  /// No description provided for @readingNextPassage.
  ///
  /// In en, this message translates to:
  /// **'Next passage'**
  String get readingNextPassage;

  /// No description provided for @tetrisSkippedNote.
  ///
  /// In en, this message translates to:
  /// **'Note: the Tetris challenge is not available in this version (v1.1) and was skipped — it was not simulated.'**
  String get tetrisSkippedNote;

  /// No description provided for @passageOnWaiting.
  ///
  /// In en, this message translates to:
  /// **'On waiting'**
  String get passageOnWaiting;

  /// No description provided for @passageOnFutureSelf.
  ///
  /// In en, this message translates to:
  /// **'On the future self'**
  String get passageOnFutureSelf;

  /// No description provided for @passageOnAttention.
  ///
  /// In en, this message translates to:
  /// **'On attention'**
  String get passageOnAttention;

  /// No description provided for @passageOnBeginningAgain.
  ///
  /// In en, this message translates to:
  /// **'On beginning again'**
  String get passageOnBeginningAgain;

  /// No description provided for @passageOnPatience.
  ///
  /// In en, this message translates to:
  /// **'On patience'**
  String get passageOnPatience;

  /// No description provided for @yourPhrase.
  ///
  /// In en, this message translates to:
  /// **'Your phrase'**
  String get yourPhrase;

  /// No description provided for @challengeMath.
  ///
  /// In en, this message translates to:
  /// **'Math problems'**
  String get challengeMath;

  /// No description provided for @challengeWords.
  ///
  /// In en, this message translates to:
  /// **'Typing words'**
  String get challengeWords;

  /// No description provided for @challengeTetris.
  ///
  /// In en, this message translates to:
  /// **'Tetris'**
  String get challengeTetris;

  /// No description provided for @challengeReading.
  ///
  /// In en, this message translates to:
  /// **'Reflective reading'**
  String get challengeReading;

  /// No description provided for @checkingSetupState.
  ///
  /// In en, this message translates to:
  /// **'Checking setup state…'**
  String get checkingSetupState;

  /// No description provided for @iUnderstand.
  ///
  /// In en, this message translates to:
  /// **'I understand'**
  String get iUnderstand;

  /// No description provided for @details.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get details;

  /// No description provided for @shizukuNotInstalledTitle.
  ///
  /// In en, this message translates to:
  /// **'Shizuku: not installed'**
  String get shizukuNotInstalledTitle;

  /// No description provided for @shizukuNotInstalledBody.
  ///
  /// In en, this message translates to:
  /// **'Install Shizuku (moe.shizuku.privileged.api) from the Play Store or its official site, then return here.'**
  String get shizukuNotInstalledBody;

  /// No description provided for @shizukuNotRunningTitle.
  ///
  /// In en, this message translates to:
  /// **'Shizuku: not running'**
  String get shizukuNotRunningTitle;

  /// No description provided for @shizukuNotRunningBody.
  ///
  /// In en, this message translates to:
  /// **'Shizuku is installed, but its server is not running. Azm cannot start it — open the Shizuku app and start the server (via wireless debugging or ADB), then pull to refresh.'**
  String get shizukuNotRunningBody;

  /// No description provided for @shizukuPreV11Title.
  ///
  /// In en, this message translates to:
  /// **'Shizuku: too old (pre-v11)'**
  String get shizukuPreV11Title;

  /// No description provided for @shizukuPreV11Body.
  ///
  /// In en, this message translates to:
  /// **'This Shizuku server predates v11 and cannot run commands. Update Shizuku, restart its server, then refresh.'**
  String get shizukuPreV11Body;

  /// No description provided for @shizukuNoPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Shizuku: permission needed'**
  String get shizukuNoPermissionTitle;

  /// No description provided for @shizukuNoPermissionBody.
  ///
  /// In en, this message translates to:
  /// **'The server is running. Grant Azm permission in Shizuku to continue setup.'**
  String get shizukuNoPermissionBody;

  /// No description provided for @shizukuGrantedTitle.
  ///
  /// In en, this message translates to:
  /// **'Shizuku: connected & granted'**
  String get shizukuGrantedTitle;

  /// No description provided for @shizukuGrantedBody.
  ///
  /// In en, this message translates to:
  /// **'Setup operations are available. Day-to-day enforcement does not need Shizuku after provisioning.'**
  String get shizukuGrantedBody;

  /// No description provided for @shizukuUnknownTitle.
  ///
  /// In en, this message translates to:
  /// **'Shizuku: unknown state'**
  String get shizukuUnknownTitle;

  /// No description provided for @shizukuUnknownBody.
  ///
  /// In en, this message translates to:
  /// **'The native layer returned an unrecognised state.'**
  String get shizukuUnknownBody;

  /// No description provided for @serverVersionLine.
  ///
  /// In en, this message translates to:
  /// **'Server version {version}, UID {uid}'**
  String serverVersionLine(int version, int uid);

  /// No description provided for @diagnosticLine.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic: {text}'**
  String diagnosticLine(String text);

  /// No description provided for @installShizuku.
  ///
  /// In en, this message translates to:
  /// **'Install Shizuku'**
  String get installShizuku;

  /// No description provided for @waitingShizukuAppear.
  ///
  /// In en, this message translates to:
  /// **'Waiting for Shizuku to appear…'**
  String get waitingShizukuAppear;

  /// No description provided for @requestShizukuPermission.
  ///
  /// In en, this message translates to:
  /// **'Request Shizuku permission'**
  String get requestShizukuPermission;

  /// No description provided for @waitingShizukuAnswer.
  ///
  /// In en, this message translates to:
  /// **'Waiting for Shizuku\'s answer…'**
  String get waitingShizukuAnswer;

  /// No description provided for @shizukuPermissionGrantedMsg.
  ///
  /// In en, this message translates to:
  /// **'Shizuku permission granted — provisioning is unlocked.'**
  String get shizukuPermissionGrantedMsg;

  /// No description provided for @permissionNotGrantedYetMsg.
  ///
  /// In en, this message translates to:
  /// **'Permission not granted yet. Approve Azm in Shizuku, then tap Request again.'**
  String get permissionNotGrantedYetMsg;

  /// No description provided for @noStoreOpenedMsg.
  ///
  /// In en, this message translates to:
  /// **'No store or browser could be opened for the Shizuku page.'**
  String get noStoreOpenedMsg;

  /// No description provided for @shizukuDetectedMsg.
  ///
  /// In en, this message translates to:
  /// **'Shizuku detected.'**
  String get shizukuDetectedMsg;

  /// No description provided for @deviceOwnerTitle.
  ///
  /// In en, this message translates to:
  /// **'Device Owner'**
  String get deviceOwnerTitle;

  /// No description provided for @deviceOwnerYes.
  ///
  /// In en, this message translates to:
  /// **'Azm is the Device Owner of this device.'**
  String get deviceOwnerYes;

  /// No description provided for @deviceOwnerNo.
  ///
  /// In en, this message translates to:
  /// **'Not provisioned. Most restrictions need Device Owner. Admin active: {admin}.'**
  String deviceOwnerNo(String admin);

  /// No description provided for @accountsNote.
  ///
  /// In en, this message translates to:
  /// **'Note: {count} account(s) detected. Provisioning usually still works via Shizuku, but removing accounts first is the original app\'s recommended path.'**
  String accountsNote(int count);

  /// No description provided for @becomeDeviceOwner.
  ///
  /// In en, this message translates to:
  /// **'Become Device Owner via Shizuku'**
  String get becomeDeviceOwner;

  /// No description provided for @provisioningUnlocksNote.
  ///
  /// In en, this message translates to:
  /// **'Provisioning unlocks when Shizuku is running and permission is granted.'**
  String get provisioningUnlocksNote;

  /// No description provided for @pathUsed.
  ///
  /// In en, this message translates to:
  /// **'Path used: {path}'**
  String pathUsed(String path);

  /// No description provided for @accessibilityService.
  ///
  /// In en, this message translates to:
  /// **'Accessibility Service'**
  String get accessibilityService;

  /// No description provided for @a11yUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get a11yUnknown;

  /// No description provided for @a11yRunning.
  ///
  /// In en, this message translates to:
  /// **'Enabled and running — enforcement is live.'**
  String get a11yRunning;

  /// No description provided for @a11yBinding.
  ///
  /// In en, this message translates to:
  /// **'Enabled but not yet running (binding).'**
  String get a11yBinding;

  /// No description provided for @a11yOff.
  ///
  /// In en, this message translates to:
  /// **'Off. Turning it off later suspends every controlled app (anti-bypass lockdown).'**
  String get a11yOff;

  /// No description provided for @wssTitle.
  ///
  /// In en, this message translates to:
  /// **'Extra system permission'**
  String get wssTitle;

  /// No description provided for @wssGrantedText.
  ///
  /// In en, this message translates to:
  /// **'Granted (verified by re-check).'**
  String get wssGrantedText;

  /// No description provided for @wssPurpose.
  ///
  /// In en, this message translates to:
  /// **'Grants the WRITE_SECURE_SETTINGS permission, needed for colour modes (v1.1). Granted via Shizuku and verified by re-check; the state shown here is read on every refresh.'**
  String get wssPurpose;

  /// No description provided for @granted.
  ///
  /// In en, this message translates to:
  /// **'Granted'**
  String get granted;

  /// No description provided for @granting.
  ///
  /// In en, this message translates to:
  /// **'Granting…'**
  String get granting;

  /// No description provided for @grant.
  ///
  /// In en, this message translates to:
  /// **'Grant'**
  String get grant;

  /// No description provided for @wssGrantedMsg.
  ///
  /// In en, this message translates to:
  /// **'WRITE_SECURE_SETTINGS is granted.'**
  String get wssGrantedMsg;

  /// No description provided for @wssStillNotGrantedMsg.
  ///
  /// In en, this message translates to:
  /// **'WRITE_SECURE_SETTINGS is still not granted. Shizuku must be running with permission granted first.'**
  String get wssStillNotGrantedMsg;

  /// No description provided for @diagnosticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Provisioning diagnostics'**
  String get diagnosticsTitle;

  /// No description provided for @diagnosticsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Accounts, extra users and the current Device Owner — these can block provisioning.'**
  String get diagnosticsSubtitle;

  /// No description provided for @runDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Run diagnostics'**
  String get runDiagnostics;

  /// No description provided for @diagAccounts.
  ///
  /// In en, this message translates to:
  /// **'Accounts ({count})'**
  String diagAccounts(int count);

  /// No description provided for @diagNoAccounts.
  ///
  /// In en, this message translates to:
  /// **'No accounts found — good for provisioning.'**
  String get diagNoAccounts;

  /// No description provided for @diagUsers.
  ///
  /// In en, this message translates to:
  /// **'Users ({count})'**
  String diagUsers(int count);

  /// No description provided for @diagOnlyPrimaryUser.
  ///
  /// In en, this message translates to:
  /// **'Only the primary user.'**
  String get diagOnlyPrimaryUser;

  /// No description provided for @diagCurrentOwner.
  ///
  /// In en, this message translates to:
  /// **'Current Device Owner'**
  String get diagCurrentOwner;

  /// No description provided for @diagNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get diagNone;

  /// No description provided for @blockerExtraUsersTitle.
  ///
  /// In en, this message translates to:
  /// **'Provisioning blocked: extra users'**
  String get blockerExtraUsersTitle;

  /// No description provided for @blockerExtraUsersBody.
  ///
  /// In en, this message translates to:
  /// **'This device has additional users or profiles: {names}.\n\nAndroid cannot provision a Device Owner while other users exist. Remove the extra users/profiles (Settings → Users), then return here and refresh. This matches the original app, which replaces the provisioning button with this warning.'**
  String blockerExtraUsersBody(String names);

  /// No description provided for @blockerOtherOwnerTitle.
  ///
  /// In en, this message translates to:
  /// **'Provisioning blocked: another Device Owner'**
  String get blockerOtherOwnerTitle;

  /// No description provided for @blockerOtherOwnerBody.
  ///
  /// In en, this message translates to:
  /// **'{packageName} is already the Device Owner of this device ({receiver}).\n\nA device can have only one Device Owner. That app must relinquish ownership (or the device must be factory-reset) before Azm can be provisioned. This matches the original app, which replaces the provisioning button with this warning.'**
  String blockerOtherOwnerBody(String packageName, String receiver);

  /// No description provided for @userIdSuffix.
  ///
  /// In en, this message translates to:
  /// **'{name} (id {id})'**
  String userIdSuffix(String name, int id);

  /// No description provided for @setupAppBarTitle.
  ///
  /// In en, this message translates to:
  /// **'Setup'**
  String get setupAppBarTitle;

  /// No description provided for @setupTileTitle.
  ///
  /// In en, this message translates to:
  /// **'Setup & Device Owner'**
  String get setupTileTitle;

  /// No description provided for @checking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get checking;

  /// No description provided for @provisionedAsOwner.
  ///
  /// In en, this message translates to:
  /// **'Provisioned as Device Owner'**
  String get provisionedAsOwner;

  /// No description provided for @notOwnerOpenSetup.
  ///
  /// In en, this message translates to:
  /// **'Not Device Owner — open Setup'**
  String get notOwnerOpenSetup;

  /// No description provided for @privateDns.
  ///
  /// In en, this message translates to:
  /// **'Private DNS'**
  String get privateDns;

  /// No description provided for @dnsCouldNotRead.
  ///
  /// In en, this message translates to:
  /// **'Could not read current DNS state'**
  String get dnsCouldNotRead;

  /// No description provided for @dnsRequiresOwner.
  ///
  /// In en, this message translates to:
  /// **'Requires Device Owner'**
  String get dnsRequiresOwner;

  /// No description provided for @dnsForcedHost.
  ///
  /// In en, this message translates to:
  /// **'Forced host: {host}'**
  String dnsForcedHost(String host);

  /// No description provided for @dnsMode.
  ///
  /// In en, this message translates to:
  /// **'Mode: {mode}'**
  String dnsMode(String mode);

  /// No description provided for @dnsRequiresOwnerSnack.
  ///
  /// In en, this message translates to:
  /// **'Private DNS requires Device Owner — finish Setup first.'**
  String get dnsRequiresOwnerSnack;

  /// No description provided for @browserRestrictions.
  ///
  /// In en, this message translates to:
  /// **'Browser restrictions'**
  String get browserRestrictions;

  /// No description provided for @browserRestrictionsSub.
  ///
  /// In en, this message translates to:
  /// **'URL blocklists + SafeSearch on supporting browsers'**
  String get browserRestrictionsSub;

  /// No description provided for @blockedWords.
  ///
  /// In en, this message translates to:
  /// **'Blocked words'**
  String get blockedWords;

  /// No description provided for @blockedWordsSub.
  ///
  /// In en, this message translates to:
  /// **'Active and per-app on-screen word blocking'**
  String get blockedWordsSub;

  /// No description provided for @impulseLock.
  ///
  /// In en, this message translates to:
  /// **'Impulse lock'**
  String get impulseLock;

  /// No description provided for @impulseLockSub.
  ///
  /// In en, this message translates to:
  /// **'Panic lock, challenges, recovery keypad options'**
  String get impulseLockSub;

  /// No description provided for @focusMode.
  ///
  /// In en, this message translates to:
  /// **'Focus mode'**
  String get focusMode;

  /// No description provided for @focusModeSub.
  ///
  /// In en, this message translates to:
  /// **'Pomodoro sessions that suspend chosen apps'**
  String get focusModeSub;

  /// No description provided for @usageWarnings.
  ///
  /// In en, this message translates to:
  /// **'Usage warnings'**
  String get usageWarnings;

  /// No description provided for @usageWarningsSub.
  ///
  /// In en, this message translates to:
  /// **'Staged warnings before a time limit expires'**
  String get usageWarningsSub;

  /// No description provided for @suspensionLogs.
  ///
  /// In en, this message translates to:
  /// **'Suspension logs'**
  String get suspensionLogs;

  /// No description provided for @suspensionLogsSub.
  ///
  /// In en, this message translates to:
  /// **'Audit log of every suspension'**
  String get suspensionLogsSub;

  /// No description provided for @colourModes.
  ///
  /// In en, this message translates to:
  /// **'Colour modes'**
  String get colourModes;

  /// No description provided for @colourModesNote.
  ///
  /// In en, this message translates to:
  /// **'Grayscale, night light, extra dim and colour inversion — scheduled and per app.'**
  String get colourModesNote;

  /// No description provided for @activityBlocker.
  ///
  /// In en, this message translates to:
  /// **'Activity blocker'**
  String get activityBlocker;

  /// No description provided for @activityBlockerNote.
  ///
  /// In en, this message translates to:
  /// **'Block specific activity screens; the launcher and system apps can never be blocked.'**
  String get activityBlockerNote;

  /// No description provided for @removalStepColourModes.
  ///
  /// In en, this message translates to:
  /// **'Colour modes released'**
  String get removalStepColourModes;

  /// No description provided for @browserUnsupportedWarning.
  ///
  /// In en, this message translates to:
  /// **'Restrictions do not work in this browser, it is recommended to disable it.'**
  String get browserUnsupportedWarning;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @block.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get block;

  /// No description provided for @blocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get blocked;

  /// No description provided for @unblock.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get unblock;

  /// No description provided for @activityBlockerDescription.
  ///
  /// In en, this message translates to:
  /// **'When a blocked activity opens, Azm sends it back. The launcher, system UI, Settings, calls and Azm itself can never be blocked.'**
  String get activityBlockerDescription;

  /// No description provided for @blockedActivities.
  ///
  /// In en, this message translates to:
  /// **'Blocked activities'**
  String get blockedActivities;

  /// No description provided for @noBlockedActivities.
  ///
  /// In en, this message translates to:
  /// **'No activities blocked yet.'**
  String get noBlockedActivities;

  /// No description provided for @recentlyAccessedActivities.
  ///
  /// In en, this message translates to:
  /// **'Recently accessed'**
  String get recentlyAccessedActivities;

  /// No description provided for @noAccessedActivities.
  ///
  /// In en, this message translates to:
  /// **'No activities seen yet — open some apps and come back.'**
  String get noAccessedActivities;

  /// No description provided for @activitiesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} activities'**
  String activitiesCount(int count);

  /// No description provided for @unblockActivityConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Unblock this activity?'**
  String get unblockActivityConfirmTitle;

  /// No description provided for @unblockActivityConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'“{activity}” will be allowed to open again.'**
  String unblockActivityConfirmMessage(String activity);

  /// No description provided for @addActivityTitle.
  ///
  /// In en, this message translates to:
  /// **'Block an activity'**
  String get addActivityTitle;

  /// No description provided for @addActivityBody.
  ///
  /// In en, this message translates to:
  /// **'Enter the full activity class name, as shown in the recently accessed list.'**
  String get addActivityBody;

  /// No description provided for @activityClassNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Activity class name'**
  String get activityClassNameLabel;

  /// No description provided for @addActivityInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a full class name, e.g. com.example.app.MainActivity.'**
  String get addActivityInvalid;

  /// No description provided for @addActivityProtected.
  ///
  /// In en, this message translates to:
  /// **'This activity is protected and can never be blocked.'**
  String get addActivityProtected;

  /// No description provided for @addActivityAlreadyBlocked.
  ///
  /// In en, this message translates to:
  /// **'This activity is already blocked.'**
  String get addActivityAlreadyBlocked;

  /// No description provided for @colourModesDescription.
  ///
  /// In en, this message translates to:
  /// **'Make the screen less stimulating: grayscale, night light, extra dim and colour inversion, on schedules and per app. A mode that is on right now cannot be loosened without the recovery code.'**
  String get colourModesDescription;

  /// No description provided for @colourModesStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get colourModesStatusTitle;

  /// No description provided for @colourModesStatusNoAccessibility.
  ///
  /// In en, this message translates to:
  /// **'Accessibility service is off — colour modes cannot apply. Turn it on below.'**
  String get colourModesStatusNoAccessibility;

  /// No description provided for @colourModesStatusNoGrant.
  ///
  /// In en, this message translates to:
  /// **'WRITE_SECURE_SETTINGS is not granted — enable the feature below to grant it via Shizuku.'**
  String get colourModesStatusNoGrant;

  /// No description provided for @colourModesStatusUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This device could not apply the grayscale keys — the feature may not work here.'**
  String get colourModesStatusUnsupported;

  /// No description provided for @colourModesStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active now: {modes}'**
  String colourModesStatusActive(String modes);

  /// No description provided for @colourModesStatusIdle.
  ///
  /// In en, this message translates to:
  /// **'Enabled — no mode is active right now.'**
  String get colourModesStatusIdle;

  /// No description provided for @colourModesStatusOff.
  ///
  /// In en, this message translates to:
  /// **'Off.'**
  String get colourModesStatusOff;

  /// No description provided for @colourModesEnableTitle.
  ///
  /// In en, this message translates to:
  /// **'Colour modes'**
  String get colourModesEnableTitle;

  /// No description provided for @colourModesEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable colour modes'**
  String get colourModesEnable;

  /// No description provided for @colourModesSummaryActive.
  ///
  /// In en, this message translates to:
  /// **'Active: {modes}'**
  String colourModesSummaryActive(String modes);

  /// No description provided for @colourModesSummaryIdle.
  ///
  /// In en, this message translates to:
  /// **'Enabled — nothing active right now'**
  String get colourModesSummaryIdle;

  /// No description provided for @colourModesSummaryOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get colourModesSummaryOff;

  /// No description provided for @colourModeGrayscale.
  ///
  /// In en, this message translates to:
  /// **'Grayscale'**
  String get colourModeGrayscale;

  /// No description provided for @colourModeGrayscaleDesc.
  ///
  /// In en, this message translates to:
  /// **'Removes all colour from the screen.'**
  String get colourModeGrayscaleDesc;

  /// No description provided for @colourModeNightLight.
  ///
  /// In en, this message translates to:
  /// **'Night light'**
  String get colourModeNightLight;

  /// No description provided for @colourModeNightLightDesc.
  ///
  /// In en, this message translates to:
  /// **'Warms the screen colours at night.'**
  String get colourModeNightLightDesc;

  /// No description provided for @colourModeExtraDim.
  ///
  /// In en, this message translates to:
  /// **'Extra dim'**
  String get colourModeExtraDim;

  /// No description provided for @colourModeExtraDimDesc.
  ///
  /// In en, this message translates to:
  /// **'Dims the screen below its lowest brightness.'**
  String get colourModeExtraDimDesc;

  /// No description provided for @colourModeInversion.
  ///
  /// In en, this message translates to:
  /// **'Colour inversion'**
  String get colourModeInversion;

  /// No description provided for @colourModeInversionDesc.
  ///
  /// In en, this message translates to:
  /// **'Inverts all colours on screen.'**
  String get colourModeInversionDesc;

  /// No description provided for @colourModeExtraDimUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Extra dim is not available on this device.'**
  String get colourModeExtraDimUnavailable;

  /// No description provided for @colourModeLockedUntil.
  ///
  /// In en, this message translates to:
  /// **'Locked until {time} — the recovery code opens it.'**
  String colourModeLockedUntil(String time);

  /// No description provided for @colourModeLockedActive.
  ///
  /// In en, this message translates to:
  /// **'Locked while active — the recovery code opens it.'**
  String get colourModeLockedActive;

  /// No description provided for @colourModesLockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Locked right now'**
  String get colourModesLockedTitle;

  /// No description provided for @colourModesLockedMessage.
  ///
  /// In en, this message translates to:
  /// **'{modes} is on right now, so it cannot be loosened without the recovery code.'**
  String colourModesLockedMessage(String modes);

  /// No description provided for @openRecoveryGate.
  ///
  /// In en, this message translates to:
  /// **'Open recovery gate'**
  String get openRecoveryGate;

  /// No description provided for @colourModesNeedAccessibilityTitle.
  ///
  /// In en, this message translates to:
  /// **'Accessibility service is off'**
  String get colourModesNeedAccessibilityTitle;

  /// No description provided for @colourModesNeedAccessibility.
  ///
  /// In en, this message translates to:
  /// **'Colour modes are enforced by the accessibility service. Enable it now?'**
  String get colourModesNeedAccessibility;

  /// No description provided for @enableAccessibility.
  ///
  /// In en, this message translates to:
  /// **'Enable accessibility'**
  String get enableAccessibility;

  /// No description provided for @accessibilityStillDisabled.
  ///
  /// In en, this message translates to:
  /// **'Accessibility is still off.'**
  String get accessibilityStillDisabled;

  /// No description provided for @secureSettingsGrantFailed.
  ///
  /// In en, this message translates to:
  /// **'The WRITE_SECURE_SETTINGS grant failed.'**
  String get secureSettingsGrantFailed;

  /// No description provided for @nightLightTemperature.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get nightLightTemperature;

  /// No description provided for @nightLightIntensity.
  ///
  /// In en, this message translates to:
  /// **'Intensity: {value}'**
  String nightLightIntensity(int value);

  /// No description provided for @extraDimLevel.
  ///
  /// In en, this message translates to:
  /// **'Dim level: {value}'**
  String extraDimLevel(int value);

  /// No description provided for @colourWindowsLabel.
  ///
  /// In en, this message translates to:
  /// **'Windows: {windows}'**
  String colourWindowsLabel(String windows);

  /// No description provided for @colourWindowsAlways.
  ///
  /// In en, this message translates to:
  /// **'Always, while enabled'**
  String get colourWindowsAlways;

  /// No description provided for @editWindows.
  ///
  /// In en, this message translates to:
  /// **'Edit windows'**
  String get editWindows;

  /// No description provided for @colourScopeDevice.
  ///
  /// In en, this message translates to:
  /// **'Whole device'**
  String get colourScopeDevice;

  /// No description provided for @colourScopeExceptApps.
  ///
  /// In en, this message translates to:
  /// **'All apps except…'**
  String get colourScopeExceptApps;

  /// No description provided for @colourScopeOnlyApps.
  ///
  /// In en, this message translates to:
  /// **'Only these apps…'**
  String get colourScopeOnlyApps;

  /// No description provided for @colourScopeAppsTitle.
  ///
  /// In en, this message translates to:
  /// **'Apps for {mode}'**
  String colourScopeAppsTitle(String mode);

  /// No description provided for @colourScopeAppsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} apps chosen'**
  String colourScopeAppsCount(int count);

  /// No description provided for @applyDuringFocus.
  ///
  /// In en, this message translates to:
  /// **'Also apply during focus sessions'**
  String get applyDuringFocus;

  /// No description provided for @applyDuringFocusDesc.
  ///
  /// In en, this message translates to:
  /// **'Grayscale stays on for the whole focus phase, even outside the windows above.'**
  String get applyDuringFocusDesc;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageDialogTitle;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageArabic.
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get languageArabic;

  /// No description provided for @languageSaved.
  ///
  /// In en, this message translates to:
  /// **'Language saved.'**
  String get languageSaved;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @changeRecoveryCode.
  ///
  /// In en, this message translates to:
  /// **'Change recovery code'**
  String get changeRecoveryCode;

  /// No description provided for @changeRecoveryCodeSub.
  ///
  /// In en, this message translates to:
  /// **'Requires a recovery session; the old code stops working'**
  String get changeRecoveryCodeSub;

  /// No description provided for @recoveryCodeChanged.
  ///
  /// In en, this message translates to:
  /// **'Recovery code changed.'**
  String get recoveryCodeChanged;

  /// No description provided for @dangerZone.
  ///
  /// In en, this message translates to:
  /// **'Danger zone'**
  String get dangerZone;

  /// No description provided for @removeOwnerNow.
  ///
  /// In en, this message translates to:
  /// **'Remove Device Owner now'**
  String get removeOwnerNow;

  /// No description provided for @removeOwnerNowSub.
  ///
  /// In en, this message translates to:
  /// **'Immediate, inside a recovery session — every restriction this app enforces stops at once.'**
  String get removeOwnerNowSub;

  /// No description provided for @forcedIdleSub.
  ///
  /// In en, this message translates to:
  /// **'The only code-free escape: after 24 hours, Device Owner can be removed without the recovery code.'**
  String get forcedIdleSub;

  /// No description provided for @forcedCompleteSub.
  ///
  /// In en, this message translates to:
  /// **'Complete — removal can now be finished without a code.'**
  String get forcedCompleteSub;

  /// No description provided for @forcedProgressSub.
  ///
  /// In en, this message translates to:
  /// **'In progress — {remaining} remaining (advances while the app is running)'**
  String forcedProgressSub(String remaining);

  /// No description provided for @startForcedRemoval.
  ///
  /// In en, this message translates to:
  /// **'Start forced removal'**
  String get startForcedRemoval;

  /// No description provided for @cancelForcedRemoval.
  ///
  /// In en, this message translates to:
  /// **'Cancel forced removal'**
  String get cancelForcedRemoval;

  /// No description provided for @finishRemoval.
  ///
  /// In en, this message translates to:
  /// **'Finish removal'**
  String get finishRemoval;

  /// No description provided for @startForcedTitle.
  ///
  /// In en, this message translates to:
  /// **'Start forced removal?'**
  String get startForcedTitle;

  /// No description provided for @startForcedBody.
  ///
  /// In en, this message translates to:
  /// **'This starts a 24-hour countdown. When it finishes, Device Owner — and with it every restriction this app enforces — can be removed without the recovery code. It is the only code-free escape, and it can be cancelled at any time before it completes.'**
  String get startForcedBody;

  /// No description provided for @cancelForcedTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel forced removal?'**
  String get cancelForcedTitle;

  /// No description provided for @cancelForcedBody.
  ///
  /// In en, this message translates to:
  /// **'The 24-hour countdown will be discarded. Device Owner removal will again require the recovery code.'**
  String get cancelForcedBody;

  /// No description provided for @finishForcedTitle.
  ///
  /// In en, this message translates to:
  /// **'Finish forced removal?'**
  String get finishForcedTitle;

  /// No description provided for @finishForcedBody.
  ///
  /// In en, this message translates to:
  /// **'The 24-hour wait is complete. Removing Device Owner now lifts every restriction this app enforces on this device.'**
  String get finishForcedBody;

  /// No description provided for @understandRemovesAll.
  ///
  /// In en, this message translates to:
  /// **'I understand this removes all protection'**
  String get understandRemovesAll;

  /// No description provided for @removeDeviceOwnerAction.
  ///
  /// In en, this message translates to:
  /// **'Remove Device Owner'**
  String get removeDeviceOwnerAction;

  /// No description provided for @deviceOwnerRemovedVerified.
  ///
  /// In en, this message translates to:
  /// **'Device Owner removed (verified).'**
  String get deviceOwnerRemovedVerified;

  /// No description provided for @removalCompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Protection fully removed'**
  String get removalCompleteTitle;

  /// No description provided for @removalCompleteBody.
  ///
  /// In en, this message translates to:
  /// **'Azm\'s protection has been completely removed: no restrictions remain, no app is suspended or hidden by Azm, and nothing of Azm is still running. You can now uninstall normally from your system settings.'**
  String get removalCompleteBody;

  /// No description provided for @removalPartialTitle.
  ///
  /// In en, this message translates to:
  /// **'Protection removed, with warnings'**
  String get removalPartialTitle;

  /// No description provided for @removalPartialBody.
  ///
  /// In en, this message translates to:
  /// **'Device Owner was removed, but some cleanup steps did not complete. You can try again, or uninstall normally — Android discards any remaining owner policies when the app is uninstalled.'**
  String get removalPartialBody;

  /// No description provided for @removalStepDisarm.
  ///
  /// In en, this message translates to:
  /// **'Disarm safeguards'**
  String get removalStepDisarm;

  /// No description provided for @removalStepFocus.
  ///
  /// In en, this message translates to:
  /// **'Stop focus mode'**
  String get removalStepFocus;

  /// No description provided for @removalStepUnsuspend.
  ///
  /// In en, this message translates to:
  /// **'Unsuspend apps'**
  String get removalStepUnsuspend;

  /// No description provided for @removalStepRestrictions.
  ///
  /// In en, this message translates to:
  /// **'Clear restrictions'**
  String get removalStepRestrictions;

  /// No description provided for @removalStepUnhide.
  ///
  /// In en, this message translates to:
  /// **'Unhide apps'**
  String get removalStepUnhide;

  /// No description provided for @removalStepUninstallBlocks.
  ///
  /// In en, this message translates to:
  /// **'Lift uninstall blocks'**
  String get removalStepUninstallBlocks;

  /// No description provided for @removalStepAppRestrictions.
  ///
  /// In en, this message translates to:
  /// **'Clear per-app restrictions'**
  String get removalStepAppRestrictions;

  /// No description provided for @info_disallow_biometric.
  ///
  /// In en, this message translates to:
  /// **'Blocks biometric unlock (fingerprint/face) at the system level (Samsung key). This also affects signing into Azm itself if you rely on fingerprint entry — use with care.'**
  String get info_disallow_biometric;

  /// No description provided for @info_disallow_camera_toggle.
  ///
  /// In en, this message translates to:
  /// **'Blocks the camera privacy toggle (quick-settings sensor switch). Keeps the camera state from being changed from the sensor panel.'**
  String get info_disallow_camera_toggle;

  /// No description provided for @info_disallow_config_default_apps.
  ///
  /// In en, this message translates to:
  /// **'Blocks changing the default apps (browser, dialer, SMS, assistant). Keeps your chosen safe defaults in place — for example, a filtered default browser stays the default.'**
  String get info_disallow_config_default_apps;

  /// No description provided for @info_disallow_config_private_dns.
  ///
  /// In en, this message translates to:
  /// **'Blocks changing the Private DNS setting. Important if your filtering relies on a specific DNS resolver — changing it would silently disable the filter. Side effect: the DNS provider is frozen while it is on.'**
  String get info_disallow_config_private_dns;

  /// No description provided for @info_disallow_microphone_toggle.
  ///
  /// In en, this message translates to:
  /// **'Blocks the microphone privacy toggle (Samsung/quick-settings sensor switch). Keeps the microphone state from being changed from the sensor panel.'**
  String get info_disallow_microphone_toggle;

  /// No description provided for @info_ensure_verify_apps.
  ///
  /// In en, this message translates to:
  /// **'Requires app verification (Play Protect-style scanning of installs) to stay on. Keeps a safety net against harmful apps; turning protections off is a common first step in bypass guides.'**
  String get info_ensure_verify_apps;

  /// No description provided for @info_no_add_clone_profile.
  ///
  /// In en, this message translates to:
  /// **'Blocks creating a clone profile or cloned apps (Samsung). Cloned apps are a second, separate copy that limits may not cover.'**
  String get info_no_add_clone_profile;

  /// No description provided for @info_no_add_managed_profile.
  ///
  /// In en, this message translates to:
  /// **'Blocks creating a work/managed profile. A separate profile can hold its own unfiltered apps.'**
  String get info_no_add_managed_profile;

  /// No description provided for @info_no_add_private_profile.
  ///
  /// In en, this message translates to:
  /// **'Blocks creating a private profile/space. A private space can hide apps from the main view and from casual checks.'**
  String get info_no_add_private_profile;

  /// No description provided for @info_no_add_user.
  ///
  /// In en, this message translates to:
  /// **'Blocks creating new Android users on the device. A second user is a completely unfiltered space, so this closes a major bypass.'**
  String get info_no_add_user;

  /// No description provided for @info_no_add_wifi_config.
  ///
  /// In en, this message translates to:
  /// **'Blocks adding new Wi-Fi network configurations while leaving existing ones usable. A softer version of locking Wi-Fi completely.'**
  String get info_no_add_wifi_config;

  /// No description provided for @info_no_adjust_volume.
  ///
  /// In en, this message translates to:
  /// **'Blocks changing the volume. Sometimes used to keep warning sounds audible. Side effect: volume keys stop working for media and calls.'**
  String get info_no_adjust_volume;

  /// No description provided for @info_no_airplane_mode.
  ///
  /// In en, this message translates to:
  /// **'Blocks turning on airplane mode. Prevents cutting connectivity to escape network filtering — though Wi-Fi can usually be rejoined. Side effect: no airplane mode for flights while it is on.'**
  String get info_no_airplane_mode;

  /// No description provided for @info_no_ambient_display.
  ///
  /// In en, this message translates to:
  /// **'Blocks the ambient display (always-on glance screen). Minor display behaviour control.'**
  String get info_no_ambient_display;

  /// No description provided for @info_no_assist_content.
  ///
  /// In en, this message translates to:
  /// **'Blocks sharing screen content with the assistant. Privacy-oriented; the assistant loses screen context.'**
  String get info_no_assist_content;

  /// No description provided for @info_no_autofill.
  ///
  /// In en, this message translates to:
  /// **'Blocks the autofill framework (password/form autofill). Security-oriented; side effect: no saved-password autofill anywhere.'**
  String get info_no_autofill;

  /// No description provided for @info_no_bluetooth.
  ///
  /// In en, this message translates to:
  /// **'Blocks using Bluetooth at all. Side effect: headphones, watches, and car connections stop working.'**
  String get info_no_bluetooth;

  /// No description provided for @info_no_bluetooth_sharing.
  ///
  /// In en, this message translates to:
  /// **'Blocks sharing files over Bluetooth while leaving Bluetooth audio working. A narrower, gentler option than blocking Bluetooth entirely.'**
  String get info_no_bluetooth_sharing;

  /// No description provided for @info_no_camera.
  ///
  /// In en, this message translates to:
  /// **'Blocks the camera entirely (Samsung key). Side effect: no app can take photos or video, including Azm-free uses like scanning documents.'**
  String get info_no_camera;

  /// No description provided for @info_no_change_wifi_state.
  ///
  /// In en, this message translates to:
  /// **'Blocks turning Wi-Fi on or off. Useful when the connection state itself is part of the routine. Side effect: no quick Wi-Fi toggling from quick settings.'**
  String get info_no_change_wifi_state;

  /// No description provided for @info_no_config_bluetooth.
  ///
  /// In en, this message translates to:
  /// **'Blocks changing Bluetooth settings (pairing new devices). Side effect: new accessories cannot be paired while it is on.'**
  String get info_no_config_bluetooth;

  /// No description provided for @info_no_config_brightness.
  ///
  /// In en, this message translates to:
  /// **'Blocks changing screen brightness settings. Minor; mainly keeps display settings stable.'**
  String get info_no_config_brightness;

  /// No description provided for @info_no_config_cell_broadcasts.
  ///
  /// In en, this message translates to:
  /// **'Blocks changing cell broadcast (emergency alert) settings. Leave this off unless you have a specific reason — emergency alerts matter.'**
  String get info_no_config_cell_broadcasts;

  /// No description provided for @info_no_config_credentials.
  ///
  /// In en, this message translates to:
  /// **'Blocks changing stored credentials and installing certificates. Important because a user-installed certificate can enable traffic interception and filter bypass. Side effect: work/school certificate setups are frozen.'**
  String get info_no_config_credentials;

  /// No description provided for @info_no_config_date_time.
  ///
  /// In en, this message translates to:
  /// **'Blocks changing the date and time. Protects time-based limits and schedules from being cheated by moving the clock. Side effect: manual time correction is off; automatic time still works.'**
  String get info_no_config_date_time;

  /// No description provided for @info_no_config_locale.
  ///
  /// In en, this message translates to:
  /// **'Blocks changing the system language/region settings. Keeps the device configuration stable.'**
  String get info_no_config_locale;

  /// No description provided for @info_no_config_location.
  ///
  /// In en, this message translates to:
  /// **'Blocks changing location settings. Keeps location-based behaviour stable; it does not itself block content.'**
  String get info_no_config_location;

  /// No description provided for @info_no_config_mobile_networks.
  ///
  /// In en, this message translates to:
  /// **'Blocks changing mobile network settings (APN, network mode, operator). Useful because APN tricks can route around DNS filtering. Side effect: roaming and carrier settings are frozen too.'**
  String get info_no_config_mobile_networks;

  /// No description provided for @info_no_config_screen_timeout.
  ///
  /// In en, this message translates to:
  /// **'Blocks changing the screen timeout. Keeps the display-off behaviour you chose; a minor routine protection.'**
  String get info_no_config_screen_timeout;

  /// No description provided for @info_no_config_tethering.
  ///
  /// In en, this message translates to:
  /// **'Blocks changing any tethering settings (Wi-Fi, USB, Bluetooth hotspot). Keeps the phone from becoming a side door around network filtering.'**
  String get info_no_config_tethering;

  /// No description provided for @info_no_config_vpn.
  ///
  /// In en, this message translates to:
  /// **'Blocks changing VPN settings. Important: a VPN can bypass DNS-based filtering entirely, so locking VPN settings protects the whole setup. Side effect: you cannot add or switch VPNs while it is on.'**
  String get info_no_config_vpn;

  /// No description provided for @info_no_config_wifi.
  ///
  /// In en, this message translates to:
  /// **'Blocks changing Wi-Fi settings: joining new networks or forgetting saved ones. Useful against hopping to an unfiltered network. Side effect: you cannot join a new Wi-Fi network while it is on.'**
  String get info_no_config_wifi;

  /// No description provided for @info_no_config_wifi_private.
  ///
  /// In en, this message translates to:
  /// **'Blocks changing the private (randomized) MAC address setting for Wi-Fi (Samsung). Keeps network identity stable so network-level filters keep recognizing the device.'**
  String get info_no_config_wifi_private;

  /// No description provided for @info_no_config_wifi_shared.
  ///
  /// In en, this message translates to:
  /// **'Blocks changing shared Wi-Fi configuration options (Samsung). Keeps network settings from being quietly altered.'**
  String get info_no_config_wifi_shared;

  /// No description provided for @info_no_content_capture.
  ///
  /// In en, this message translates to:
  /// **'Blocks apps from capturing screen content for features like screenshot-based assistants. A privacy control; may break some smart-selection features.'**
  String get info_no_content_capture;

  /// No description provided for @info_no_content_suggestions.
  ///
  /// In en, this message translates to:
  /// **'Blocks content suggestions (smart replies/suggestions drawn from screen content). Privacy-oriented; minor.'**
  String get info_no_content_suggestions;

  /// No description provided for @info_no_control_apps.
  ///
  /// In en, this message translates to:
  /// **'Blocks opening app-info screens where apps can be force-stopped, cleared, or have their permissions changed. Stops a common bypass route. Side effect: you also cannot manage app storage or permissions there while it is on.'**
  String get info_no_control_apps;

  /// No description provided for @info_no_create_windows.
  ///
  /// In en, this message translates to:
  /// **'Blocks apps from drawing overlay windows on top of other apps. Increases security against tap-jacking, but breaks legitimate overlays like chat bubbles and some accessibility tools.'**
  String get info_no_create_windows;

  /// No description provided for @info_no_cross_profile_copy_paste.
  ///
  /// In en, this message translates to:
  /// **'Blocks copy/paste between profiles. Stops text and links moving from the controlled profile into another one.'**
  String get info_no_cross_profile_copy_paste;

  /// No description provided for @info_no_data_roaming.
  ///
  /// In en, this message translates to:
  /// **'Blocks data roaming. Mostly a cost control; it does not filter content.'**
  String get info_no_data_roaming;

  /// No description provided for @info_no_debugging_features.
  ///
  /// In en, this message translates to:
  /// **'Blocks debugging features such as ADB. Prevents changing the device from a computer to bypass protection. Side effect: developers cannot debug this device while it is on.'**
  String get info_no_debugging_features;

  /// No description provided for @info_no_factory_reset.
  ///
  /// In en, this message translates to:
  /// **'Blocks factory reset from settings. Protects the whole setup from being wiped in a weak moment. This is a strong setting: recovery through Azm\'s own removal flow remains possible, but the settings route is closed.'**
  String get info_no_factory_reset;

  /// No description provided for @info_no_fun.
  ///
  /// In en, this message translates to:
  /// **'Blocks Android\'s fun/easter-egg features. Harmless and mostly cosmetic.'**
  String get info_no_fun;

  /// No description provided for @info_no_grant_admin.
  ///
  /// In en, this message translates to:
  /// **'Blocks granting device-admin rights to other apps. Prevents another admin app from interfering with Azm\'s position.'**
  String get info_no_grant_admin;

  /// No description provided for @info_no_install_apps.
  ///
  /// In en, this message translates to:
  /// **'Blocks installing new apps entirely. Useful when you want the phone\'s current app set frozen. Side effect: even trusted apps cannot be added until this is off.'**
  String get info_no_install_apps;

  /// No description provided for @info_no_install_unknown_sources.
  ///
  /// In en, this message translates to:
  /// **'Blocks installing apps from outside the Play Store (APK files, browsers, file managers). One of the strongest protections against sideloaded distractions and malware. Side effect: legitimate APK installs are also blocked.'**
  String get info_no_install_unknown_sources;

  /// No description provided for @info_no_install_unknown_sources_globally.
  ///
  /// In en, this message translates to:
  /// **'The global version of the unknown-sources block: it applies everywhere on the device, for every user and profile. Stronger than the per-source setting, and it also blocks legitimate APK installs device-wide.'**
  String get info_no_install_unknown_sources_globally;

  /// No description provided for @info_no_modify_accounts.
  ///
  /// In en, this message translates to:
  /// **'Blocks adding or removing accounts on the device. A new account can be a fresh start that escapes app-level habits. Side effect: you cannot sign into new services at the system level while it is on.'**
  String get info_no_modify_accounts;

  /// No description provided for @info_no_network_reset.
  ///
  /// In en, this message translates to:
  /// **'Blocks resetting network settings. A network reset can wipe saved Wi-Fi and DNS-related state in one tap.'**
  String get info_no_network_reset;

  /// No description provided for @info_no_non_market_app_by_knox.
  ///
  /// In en, this message translates to:
  /// **'Blocks apps from outside the official stores at the Samsung Knox level. Knox\'s own sideloading block; may overlap with the unknown-sources restrictions.'**
  String get info_no_non_market_app_by_knox;

  /// No description provided for @info_no_outgoing_beam.
  ///
  /// In en, this message translates to:
  /// **'Blocks Android Beam (NFC tap-to-share). A small side channel for passing links and files between phones.'**
  String get info_no_outgoing_beam;

  /// No description provided for @info_no_outgoing_calls.
  ///
  /// In en, this message translates to:
  /// **'Blocks making outgoing calls. A heavy restriction for communication control; emergency calls are never blocked by Android.'**
  String get info_no_outgoing_calls;

  /// No description provided for @info_no_physical_media.
  ///
  /// In en, this message translates to:
  /// **'Blocks mounting external storage (SD cards, USB drives). Closes a route for bringing in unfiltered content. Side effect: memory cards cannot be used while it is on.'**
  String get info_no_physical_media;

  /// No description provided for @info_no_printing.
  ///
  /// In en, this message translates to:
  /// **'Blocks printing from the device. Minor; closes a route for exporting content to paper or PDF printers.'**
  String get info_no_printing;

  /// No description provided for @info_no_remove_managed_profile.
  ///
  /// In en, this message translates to:
  /// **'Blocks removing the managed (work) profile. Keeps an existing managed space intact.'**
  String get info_no_remove_managed_profile;

  /// No description provided for @info_no_remove_user.
  ///
  /// In en, this message translates to:
  /// **'Blocks removing existing Android users. Keeps the device\'s user structure unchanged.'**
  String get info_no_remove_user;

  /// No description provided for @info_no_safe_boot.
  ///
  /// In en, this message translates to:
  /// **'Blocks booting into Safe Mode. Important: Safe Mode disables accessibility services and third-party enforcement, so it is a classic bypass. Side effect: Safe Mode troubleshooting is unavailable while it is on.'**
  String get info_no_safe_boot;

  /// No description provided for @info_no_set_user_icon.
  ///
  /// In en, this message translates to:
  /// **'Blocks changing the user profile picture. Cosmetic only.'**
  String get info_no_set_user_icon;

  /// No description provided for @info_no_set_wallpaper.
  ///
  /// In en, this message translates to:
  /// **'Blocks changing the wallpaper. Cosmetic stability; occasionally used to keep a motivational wallpaper in place.'**
  String get info_no_set_wallpaper;

  /// No description provided for @info_no_share_location.
  ///
  /// In en, this message translates to:
  /// **'Blocks sharing the device\'s location with apps. A privacy protection rather than a content filter.'**
  String get info_no_share_location;

  /// No description provided for @info_no_sharing_into_profile.
  ///
  /// In en, this message translates to:
  /// **'Blocks sharing content from the main profile into another profile. Keeps content from being passed into a less-controlled space.'**
  String get info_no_sharing_into_profile;

  /// No description provided for @info_no_sim_globally.
  ///
  /// In en, this message translates to:
  /// **'Blocks using the SIM entirely (calls and mobile data). A very heavy restriction — the phone loses mobile service while it is on.'**
  String get info_no_sim_globally;

  /// No description provided for @info_no_sms.
  ///
  /// In en, this message translates to:
  /// **'Blocks sending SMS messages. Communication control; messaging apps are unaffected.'**
  String get info_no_sms;

  /// No description provided for @info_no_system_error_dialogs.
  ///
  /// In en, this message translates to:
  /// **'Blocks system error dialogs (app-crash popups). Cosmetic/enterprise behaviour; crashes still happen, just silently.'**
  String get info_no_system_error_dialogs;

  /// No description provided for @info_no_thread_network.
  ///
  /// In en, this message translates to:
  /// **'Blocks creating/joining Thread border-router networks (smart-home). Niche; irrelevant for most phones.'**
  String get info_no_thread_network;

  /// No description provided for @info_no_ultra_wideband_radio.
  ///
  /// In en, this message translates to:
  /// **'Blocks the ultra-wideband (UWB) radio used by precision trackers. Niche hardware control.'**
  String get info_no_ultra_wideband_radio;

  /// No description provided for @info_no_unified_password.
  ///
  /// In en, this message translates to:
  /// **'Blocks requiring one unified password across work and personal profiles. Enterprise-oriented; irrelevant on a single-profile phone.'**
  String get info_no_unified_password;

  /// No description provided for @info_no_uninstall_apps.
  ///
  /// In en, this message translates to:
  /// **'Blocks uninstalling apps. Useful to stop a blocked app from simply being deleted to escape its limits — and to protect Azm\'s companion setup. Side effect: you cannot remove any app while this is on.'**
  String get info_no_uninstall_apps;

  /// No description provided for @info_no_unmute_microphone.
  ///
  /// In en, this message translates to:
  /// **'Blocks unmuting the microphone during calls. A managed-device privacy control; rarely relevant for personal use.'**
  String get info_no_unmute_microphone;

  /// No description provided for @info_no_usb_file_transfer.
  ///
  /// In en, this message translates to:
  /// **'Blocks transferring files over USB. Prevents moving content on or off the phone by cable. Side effect: USB photo/file import stops too; charging still works.'**
  String get info_no_usb_file_transfer;

  /// No description provided for @info_no_user_switch.
  ///
  /// In en, this message translates to:
  /// **'Blocks switching between Android users. Companions the no-new-users rule: even existing extra users cannot be entered.'**
  String get info_no_user_switch;

  /// No description provided for @info_no_wallpaper.
  ///
  /// In en, this message translates to:
  /// **'Blocks wallpaper changes (Samsung key). Cosmetic stability, like the standard wallpaper restriction.'**
  String get info_no_wallpaper;

  /// No description provided for @info_no_wifi_direct.
  ///
  /// In en, this message translates to:
  /// **'Blocks Wi-Fi Direct connections (device-to-device sharing without a router). Closes a side channel for sharing files and content. Side effect: some printers and sharing features stop working.'**
  String get info_no_wifi_direct;

  /// No description provided for @info_no_wifi_tethering.
  ///
  /// In en, this message translates to:
  /// **'Blocks Wi-Fi hotspot tethering settings. Prevents sharing the phone\'s connection to bypass filters on other devices.'**
  String get info_no_wifi_tethering;

  /// No description provided for @restrictionInfoGeneric.
  ///
  /// In en, this message translates to:
  /// **'This setting restricts part of the system. Turning it on tightens the device; turning it off loosens it. If you are not sure, leave it off and ask later.'**
  String get restrictionInfoGeneric;

  /// No description provided for @errGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again. If it keeps happening, restart the app.'**
  String get errGeneric;

  /// No description provided for @errSealed.
  ///
  /// In en, this message translates to:
  /// **'Removal is currently sealed by one of your seal rules.'**
  String get errSealed;

  /// No description provided for @errorCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get errorCardTitle;

  /// No description provided for @okButton.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get okButton;

  /// No description provided for @entryGraceTitle.
  ///
  /// In en, this message translates to:
  /// **'App lock timing'**
  String get entryGraceTitle;

  /// No description provided for @entryGraceSub.
  ///
  /// In en, this message translates to:
  /// **'How long Azm stays open after you enter, before it asks for your fingerprint or password again'**
  String get entryGraceSub;

  /// No description provided for @entryGraceImmediately.
  ///
  /// In en, this message translates to:
  /// **'Immediately'**
  String get entryGraceImmediately;

  /// No description provided for @entryGraceOneMinute.
  ///
  /// In en, this message translates to:
  /// **'After 1 minute'**
  String get entryGraceOneMinute;

  /// No description provided for @entryGraceFifteenMinutes.
  ///
  /// In en, this message translates to:
  /// **'After 15 minutes'**
  String get entryGraceFifteenMinutes;

  /// No description provided for @entryGraceOneHour.
  ///
  /// In en, this message translates to:
  /// **'After 1 hour'**
  String get entryGraceOneHour;

  /// No description provided for @visualBlockingTitle.
  ///
  /// In en, this message translates to:
  /// **'Content inspection'**
  String get visualBlockingTitle;

  /// No description provided for @visualBlockingSub.
  ///
  /// In en, this message translates to:
  /// **'On-device checking of images inside chosen apps'**
  String get visualBlockingSub;

  /// No description provided for @visualExplanation.
  ///
  /// In en, this message translates to:
  /// **'Azm checks images on screen inside the apps you choose, using a model that runs entirely on this device. Nothing is uploaded. When inappropriate content is detected, the app is closed; repeated detections can suspend it. Text checking is separate: it is the blocked-words feature, which also works per app.'**
  String get visualExplanation;

  /// No description provided for @visualEnable.
  ///
  /// In en, this message translates to:
  /// **'Inspect images in chosen apps'**
  String get visualEnable;

  /// No description provided for @visualRequiresAccessibility.
  ///
  /// In en, this message translates to:
  /// **'Requires the accessibility service to be on.'**
  String get visualRequiresAccessibility;

  /// No description provided for @visualAppsSection.
  ///
  /// In en, this message translates to:
  /// **'Apps to inspect'**
  String get visualAppsSection;

  /// No description provided for @visualAppsSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} app(s) chosen'**
  String visualAppsSelected(int count);

  /// No description provided for @visualSelectApps.
  ///
  /// In en, this message translates to:
  /// **'Choose apps'**
  String get visualSelectApps;

  /// No description provided for @visualCategoriesSection.
  ///
  /// In en, this message translates to:
  /// **'Block when detected'**
  String get visualCategoriesSection;

  /// No description provided for @visualCategoriesDesc.
  ///
  /// In en, this message translates to:
  /// **'The kinds of content that close the app when the model finds them on screen.'**
  String get visualCategoriesDesc;

  /// No description provided for @visualCategoryDrawings.
  ///
  /// In en, this message translates to:
  /// **'Drawings'**
  String get visualCategoryDrawings;

  /// No description provided for @visualCategoryHentai.
  ///
  /// In en, this message translates to:
  /// **'Hentai'**
  String get visualCategoryHentai;

  /// No description provided for @visualCategoryPorn.
  ///
  /// In en, this message translates to:
  /// **'Pornography'**
  String get visualCategoryPorn;

  /// No description provided for @visualCategorySexy.
  ///
  /// In en, this message translates to:
  /// **'Sexy / suggestive'**
  String get visualCategorySexy;

  /// No description provided for @visualThresholdSection.
  ///
  /// In en, this message translates to:
  /// **'Sensitivity'**
  String get visualThresholdSection;

  /// No description provided for @visualThresholdDesc.
  ///
  /// In en, this message translates to:
  /// **'Higher means Azm blocks only when it is more certain. Lower blocks more, with more mistakes.'**
  String get visualThresholdDesc;

  /// No description provided for @visualSuspend.
  ///
  /// In en, this message translates to:
  /// **'Suspend app after repeated detections'**
  String get visualSuspend;

  /// No description provided for @visualSuspendDesc.
  ///
  /// In en, this message translates to:
  /// **'After several detections in a short time, the app is suspended for a while instead of just being closed.'**
  String get visualSuspendDesc;

  /// No description provided for @visualSuspendCount.
  ///
  /// In en, this message translates to:
  /// **'Detections before suspending'**
  String get visualSuspendCount;

  /// No description provided for @visualSuspendWindow.
  ///
  /// In en, this message translates to:
  /// **'Within (minutes)'**
  String get visualSuspendWindow;

  /// No description provided for @visualSuspendDuration.
  ///
  /// In en, this message translates to:
  /// **'Suspend for (minutes)'**
  String get visualSuspendDuration;

  /// No description provided for @visualSaved.
  ///
  /// In en, this message translates to:
  /// **'Content inspection settings saved.'**
  String get visualSaved;

  /// No description provided for @sealRulesTitle.
  ///
  /// In en, this message translates to:
  /// **'Seal rules'**
  String get sealRulesTitle;

  /// No description provided for @sealRulesSub.
  ///
  /// In en, this message translates to:
  /// **'Conditions under which Azm refuses to be removed'**
  String get sealRulesSub;

  /// No description provided for @sealIntro.
  ///
  /// In en, this message translates to:
  /// **'While any seal rule is active, Azm refuses to remove Device Owner — immediately or by filing the delayed forced removal. A seal cannot be cancelled while it is active; it ends only when its time runs out or its condition clears. The paper recovery code does NOT break an active seal. A forced removal filed BEFORE a seal engaged still completes at its 24-hour mark. Seals have force only while Azm is Device Owner: without Device Owner, Android lets any app be uninstalled and no rule can prevent it.'**
  String get sealIntro;

  /// No description provided for @sealNoRules.
  ///
  /// In en, this message translates to:
  /// **'No seal rules yet.'**
  String get sealNoRules;

  /// No description provided for @sealAddRule.
  ///
  /// In en, this message translates to:
  /// **'Add a seal rule'**
  String get sealAddRule;

  /// No description provided for @sealEditRule.
  ///
  /// In en, this message translates to:
  /// **'Edit seal rule'**
  String get sealEditRule;

  /// No description provided for @sealDeleteRule.
  ///
  /// In en, this message translates to:
  /// **'Delete rule'**
  String get sealDeleteRule;

  /// No description provided for @sealTrigger.
  ///
  /// In en, this message translates to:
  /// **'Seal while / when'**
  String get sealTrigger;

  /// No description provided for @sealTriggerAppBlocked.
  ///
  /// In en, this message translates to:
  /// **'A chosen app is blocked by Azm'**
  String get sealTriggerAppBlocked;

  /// No description provided for @sealTriggerAppSuspended.
  ///
  /// In en, this message translates to:
  /// **'A chosen app is suspended by Azm'**
  String get sealTriggerAppSuspended;

  /// No description provided for @sealTriggerFocusRunning.
  ///
  /// In en, this message translates to:
  /// **'A focus session is running'**
  String get sealTriggerFocusRunning;

  /// No description provided for @sealTriggerVisual.
  ///
  /// In en, this message translates to:
  /// **'Inappropriate content is detected in a chosen app'**
  String get sealTriggerVisual;

  /// No description provided for @sealTriggerWord.
  ///
  /// In en, this message translates to:
  /// **'A banned word is detected in a chosen app'**
  String get sealTriggerWord;

  /// No description provided for @sealApp.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get sealApp;

  /// No description provided for @sealChooseApp.
  ///
  /// In en, this message translates to:
  /// **'Choose an app'**
  String get sealChooseApp;

  /// No description provided for @sealDuration.
  ///
  /// In en, this message translates to:
  /// **'Seal lasts'**
  String get sealDuration;

  /// No description provided for @sealDuration30m.
  ///
  /// In en, this message translates to:
  /// **'30 minutes'**
  String get sealDuration30m;

  /// No description provided for @sealDuration1h.
  ///
  /// In en, this message translates to:
  /// **'1 hour'**
  String get sealDuration1h;

  /// No description provided for @sealDuration6h.
  ///
  /// In en, this message translates to:
  /// **'6 hours'**
  String get sealDuration6h;

  /// No description provided for @sealDuration24h.
  ///
  /// In en, this message translates to:
  /// **'24 hours'**
  String get sealDuration24h;

  /// No description provided for @sealDuration7d.
  ///
  /// In en, this message translates to:
  /// **'7 days'**
  String get sealDuration7d;

  /// No description provided for @sealRuleEnabled.
  ///
  /// In en, this message translates to:
  /// **'Rule enabled'**
  String get sealRuleEnabled;

  /// No description provided for @sealActiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Seal active'**
  String get sealActiveTitle;

  /// No description provided for @sealActiveCondition.
  ///
  /// In en, this message translates to:
  /// **'A seal rule is holding: {rule}. Removal is refused while it holds.'**
  String sealActiveCondition(String rule);

  /// No description provided for @sealActiveTimed.
  ///
  /// In en, this message translates to:
  /// **'A seal rule is holding: {rule}. About {remaining} left.'**
  String sealActiveTimed(String rule, String remaining);

  /// No description provided for @sealStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Sealed: {rule}'**
  String sealStatusActive(String rule);

  /// No description provided for @sealNotEnforceable.
  ///
  /// In en, this message translates to:
  /// **'Not enforceable: Azm is not Device Owner.'**
  String get sealNotEnforceable;

  /// No description provided for @removalStepPolicies.
  ///
  /// In en, this message translates to:
  /// **'Reset device policies'**
  String get removalStepPolicies;

  /// No description provided for @removalStepPrivateDns.
  ///
  /// In en, this message translates to:
  /// **'Reset private DNS'**
  String get removalStepPrivateDns;

  /// No description provided for @removalStepNotifications.
  ///
  /// In en, this message translates to:
  /// **'Cancel notifications'**
  String get removalStepNotifications;

  /// No description provided for @removalStepVerify.
  ///
  /// In en, this message translates to:
  /// **'Post-removal verification'**
  String get removalStepVerify;

  /// No description provided for @residueTitle.
  ///
  /// In en, this message translates to:
  /// **'Leftover restrictions detected'**
  String get residueTitle;

  /// No description provided for @residueBody.
  ///
  /// In en, this message translates to:
  /// **'Some restrictions set by Azm are still in force on this device. Azm no longer has the rights to remove them. To clean up, provision Azm as Device Owner again from the Status tab, then run Remove Device Owner once more.'**
  String get residueBody;

  /// No description provided for @removalStepClearOwner.
  ///
  /// In en, this message translates to:
  /// **'Remove Device Owner'**
  String get removalStepClearOwner;

  /// No description provided for @dnsSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Private DNS settings'**
  String get dnsSettingsTitle;

  /// No description provided for @dnsCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get dnsCustom;

  /// No description provided for @dnsHostnameLabel.
  ///
  /// In en, this message translates to:
  /// **'DNS hostname'**
  String get dnsHostnameLabel;

  /// No description provided for @dnsHostnameHint.
  ///
  /// In en, this message translates to:
  /// **'dns.example.com'**
  String get dnsHostnameHint;

  /// No description provided for @dnsInvalidHostname.
  ///
  /// In en, this message translates to:
  /// **'Invalid DNS hostname'**
  String get dnsInvalidHostname;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @dnsTimeoutError.
  ///
  /// In en, this message translates to:
  /// **'Applying the DNS host timed out. Check the current DNS state before retrying.'**
  String get dnsTimeoutError;

  /// No description provided for @dnsNotServingError.
  ///
  /// In en, this message translates to:
  /// **'The chosen DNS host is not serving. Pick another host.'**
  String get dnsNotServingError;

  /// No description provided for @dnsApplyFailedError.
  ///
  /// In en, this message translates to:
  /// **'Failed to apply the private DNS host.'**
  String get dnsApplyFailedError;

  /// No description provided for @dnsAppliedVerified.
  ///
  /// In en, this message translates to:
  /// **'Private DNS forced to {host} (verified).'**
  String dnsAppliedVerified(String host);

  /// No description provided for @newBlocklist.
  ///
  /// In en, this message translates to:
  /// **'New blocklist'**
  String get newBlocklist;

  /// No description provided for @editBlocklist.
  ///
  /// In en, this message translates to:
  /// **'Edit blocklist'**
  String get editBlocklist;

  /// No description provided for @titleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get titleLabel;

  /// No description provided for @sitesLabel.
  ///
  /// In en, this message translates to:
  /// **'Sites, one per line (e.g. example.com)'**
  String get sitesLabel;

  /// No description provided for @appliedToBrowsers.
  ///
  /// In en, this message translates to:
  /// **'Applied to {count} browser(s), verified.'**
  String appliedToBrowsers(int count);

  /// No description provided for @supportingBrowsers.
  ///
  /// In en, this message translates to:
  /// **'Supporting browsers'**
  String get supportingBrowsers;

  /// No description provided for @noSupportingBrowser.
  ///
  /// In en, this message translates to:
  /// **'No installed browser declares URLBlocklist in its managed restrictions, so there is nothing to push policy to. Browsers without support are handled by suspension rules.'**
  String get noSupportingBrowser;

  /// No description provided for @blocklists.
  ///
  /// In en, this message translates to:
  /// **'Blocklists'**
  String get blocklists;

  /// No description provided for @noBlocklists.
  ///
  /// In en, this message translates to:
  /// **'No blocklists yet. Create one to start blocking sites.'**
  String get noBlocklists;

  /// No description provided for @sitesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} site(s)'**
  String sitesCount(int count);

  /// No description provided for @applyBlocklists.
  ///
  /// In en, this message translates to:
  /// **'Apply blocklists to browsers'**
  String get applyBlocklists;

  /// No description provided for @loadingBlocklists.
  ///
  /// In en, this message translates to:
  /// **'Loading blocklists…'**
  String get loadingBlocklists;

  /// No description provided for @activeBlockingWords.
  ///
  /// In en, this message translates to:
  /// **'Active blocking words'**
  String get activeBlockingWords;

  /// No description provided for @oneWordPerLine.
  ///
  /// In en, this message translates to:
  /// **'One word or phrase per line'**
  String get oneWordPerLine;

  /// No description provided for @appsWhereWordsBlock.
  ///
  /// In en, this message translates to:
  /// **'Apps where active words block'**
  String get appsWhereWordsBlock;

  /// No description provided for @onScreenWordsFor.
  ///
  /// In en, this message translates to:
  /// **'On-screen words for {app}'**
  String onScreenWordsFor(String app);

  /// No description provided for @loadingBlockedWords.
  ///
  /// In en, this message translates to:
  /// **'Loading blocked words…'**
  String get loadingBlockedWords;

  /// No description provided for @activeBlockingSection.
  ///
  /// In en, this message translates to:
  /// **'Active blocking (F14)'**
  String get activeBlockingSection;

  /// No description provided for @activeBlockingBody.
  ///
  /// In en, this message translates to:
  /// **'When a word is present in the text field of a chosen app and typing ends, the app is backed out of and a block screen shows.'**
  String get activeBlockingBody;

  /// No description provided for @wordsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} word(s)'**
  String wordsCount(int count);

  /// No description provided for @targetAppsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} target app(s)'**
  String targetAppsCount(int count);

  /// No description provided for @passiveBlockingSection.
  ///
  /// In en, this message translates to:
  /// **'Passive blocking (F15)'**
  String get passiveBlockingSection;

  /// No description provided for @passiveBlockingBody.
  ///
  /// In en, this message translates to:
  /// **'Words appearing anywhere on screen in a specific app.'**
  String get passiveBlockingBody;

  /// No description provided for @noPerAppLists.
  ///
  /// In en, this message translates to:
  /// **'No per-app lists yet.'**
  String get noPerAppLists;

  /// No description provided for @addTargetAppsFirst.
  ///
  /// In en, this message translates to:
  /// **'Add target apps above first — passive lists attach to them in v1.'**
  String get addTargetAppsFirst;

  /// No description provided for @addPerAppList.
  ///
  /// In en, this message translates to:
  /// **'Add per-app list'**
  String get addPerAppList;

  /// No description provided for @loadingWarningStages.
  ///
  /// In en, this message translates to:
  /// **'Loading warning stages…'**
  String get loadingWarningStages;

  /// No description provided for @stagedWarningsTitle.
  ///
  /// In en, this message translates to:
  /// **'Staged warnings before a limit expires'**
  String get stagedWarningsTitle;

  /// No description provided for @warningsBody.
  ///
  /// In en, this message translates to:
  /// **'Each stage warns once, the configured number of minutes before an app\'s daily limit runs out. Stages are stored for the Accessibility Service to fire; notification delivery depends on the native notifier.'**
  String get warningsBody;

  /// No description provided for @noWarningStages.
  ///
  /// In en, this message translates to:
  /// **'No warning stages. Add at least one stage or no warnings will be shown.'**
  String get noWarningStages;

  /// No description provided for @addStage.
  ///
  /// In en, this message translates to:
  /// **'Add stage'**
  String get addStage;

  /// No description provided for @minutesBeforeLabel.
  ///
  /// In en, this message translates to:
  /// **'Minutes before'**
  String get minutesBeforeLabel;

  /// No description provided for @removeStage.
  ///
  /// In en, this message translates to:
  /// **'Remove stage'**
  String get removeStage;

  /// No description provided for @silent.
  ///
  /// In en, this message translates to:
  /// **'Silent'**
  String get silent;

  /// No description provided for @sound.
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get sound;

  /// No description provided for @vibrate.
  ///
  /// In en, this message translates to:
  /// **'Vibrate'**
  String get vibrate;

  /// No description provided for @vibrationCount.
  ///
  /// In en, this message translates to:
  /// **'Vibration count'**
  String get vibrationCount;

  /// No description provided for @clearLogsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear logs (recovery session required)'**
  String get clearLogsTooltip;

  /// No description provided for @searchLogs.
  ///
  /// In en, this message translates to:
  /// **'Search logs'**
  String get searchLogs;

  /// No description provided for @loadingLogs.
  ///
  /// In en, this message translates to:
  /// **'Loading logs…'**
  String get loadingLogs;

  /// No description provided for @noSuspensionsLogged.
  ///
  /// In en, this message translates to:
  /// **'No suspensions have been logged.'**
  String get noSuspensionsLogged;

  /// No description provided for @impulseLockTitle.
  ///
  /// In en, this message translates to:
  /// **'Impulse lock'**
  String get impulseLockTitle;

  /// No description provided for @loadingImpulseLock.
  ///
  /// In en, this message translates to:
  /// **'Loading impulse lock…'**
  String get loadingImpulseLock;

  /// No description provided for @impulseActiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Impulse lock active — {remaining} left'**
  String impulseActiveTitle(String remaining);

  /// No description provided for @impulseActiveBody.
  ///
  /// In en, this message translates to:
  /// **'Like the original, the lock has no early stop: it ends on its own when the timer runs out, and the apps it suspended are released then.'**
  String get impulseActiveBody;

  /// No description provided for @startImpulseLockFor.
  ///
  /// In en, this message translates to:
  /// **'Start impulse lock ({minutes} min)'**
  String startImpulseLockFor(int minutes);

  /// No description provided for @settingsLockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings are locked'**
  String get settingsLockedTitle;

  /// No description provided for @settingsLockedBody.
  ///
  /// In en, this message translates to:
  /// **'Impulse lock settings can only be changed during a recovery session. Tap to open one.'**
  String get settingsLockedBody;

  /// No description provided for @configurationSection.
  ///
  /// In en, this message translates to:
  /// **'Configuration'**
  String get configurationSection;

  /// No description provided for @durationLabel.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get durationLabel;

  /// No description provided for @durationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{minutes} minutes (15–360)'**
  String durationSubtitle(int minutes);

  /// No description provided for @minutesSliderLabel.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String minutesSliderLabel(int minutes);

  /// No description provided for @timerOnly.
  ///
  /// In en, this message translates to:
  /// **'Timer only'**
  String get timerOnly;

  /// No description provided for @timerAndSuspend.
  ///
  /// In en, this message translates to:
  /// **'Timer + suspend chosen apps'**
  String get timerAndSuspend;

  /// No description provided for @appsToSuspendCount.
  ///
  /// In en, this message translates to:
  /// **'{count} app(s) to suspend'**
  String appsToSuspendCount(int count);

  /// No description provided for @accessChallengesTitle.
  ///
  /// In en, this message translates to:
  /// **'Access challenges'**
  String get accessChallengesTitle;

  /// No description provided for @accessChallengesBody.
  ///
  /// In en, this message translates to:
  /// **'These challenges belong to Impulse Lock only. The recovery code on its own opens a recovery session — no challenges are asked after it.'**
  String get accessChallengesBody;

  /// No description provided for @challengeUnavailableNote.
  ///
  /// In en, this message translates to:
  /// **'Not available in this version — v1.1. It can be selected in stored config but is skipped, never simulated.'**
  String get challengeUnavailableNote;

  /// No description provided for @shuffledKeypadTitle.
  ///
  /// In en, this message translates to:
  /// **'Shuffled keypad for recovery code'**
  String get shuffledKeypadTitle;

  /// No description provided for @shuffledKeypadSub.
  ///
  /// In en, this message translates to:
  /// **'So the code cannot be learned from finger positions (F24).'**
  String get shuffledKeypadSub;

  /// No description provided for @customPhrasesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} custom reading phrase(s)'**
  String customPhrasesCount(int count);

  /// No description provided for @customPhrasesSub.
  ///
  /// In en, this message translates to:
  /// **'Added to the bundled reading passages'**
  String get customPhrasesSub;

  /// No description provided for @customReadingPhrases.
  ///
  /// In en, this message translates to:
  /// **'Custom reading phrases'**
  String get customReadingPhrases;

  /// No description provided for @onePhrasePerLine.
  ///
  /// In en, this message translates to:
  /// **'One phrase per line (your own words)'**
  String get onePhrasePerLine;

  /// No description provided for @appsSuspendedDuringImpulse.
  ///
  /// In en, this message translates to:
  /// **'Apps suspended during impulse lock'**
  String get appsSuspendedDuringImpulse;

  /// No description provided for @focusModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Focus mode'**
  String get focusModeTitle;

  /// No description provided for @loadingFocusMode.
  ///
  /// In en, this message translates to:
  /// **'Loading focus mode…'**
  String get loadingFocusMode;

  /// No description provided for @phaseNotStarted.
  ///
  /// In en, this message translates to:
  /// **'Not started'**
  String get phaseNotStarted;

  /// No description provided for @phaseFocusing.
  ///
  /// In en, this message translates to:
  /// **'Focusing'**
  String get phaseFocusing;

  /// No description provided for @phaseBreak.
  ///
  /// In en, this message translates to:
  /// **'Break'**
  String get phaseBreak;

  /// No description provided for @phaseLongBreak.
  ///
  /// In en, this message translates to:
  /// **'Long break'**
  String get phaseLongBreak;

  /// No description provided for @phaseWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get phaseWaiting;

  /// No description provided for @phasePaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get phasePaused;

  /// No description provided for @phaseDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get phaseDone;

  /// No description provided for @ringIdleSummary.
  ///
  /// In en, this message translates to:
  /// **'{focus} min focus · {breakTime} min break'**
  String ringIdleSummary(int focus, int breakTime);

  /// No description provided for @waitingNextFocus.
  ///
  /// In en, this message translates to:
  /// **'Waiting to start the next focus'**
  String get waitingNextFocus;

  /// No description provided for @cycleOf.
  ///
  /// In en, this message translates to:
  /// **'Cycle {current} of {total}'**
  String cycleOf(int current, int total);

  /// No description provided for @completedFocusPeriods.
  ///
  /// In en, this message translates to:
  /// **'Completed focus periods: {count}'**
  String completedFocusPeriods(int count);

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @startFocusBtn.
  ///
  /// In en, this message translates to:
  /// **'Start focus'**
  String get startFocusBtn;

  /// No description provided for @endSessionBtn.
  ///
  /// In en, this message translates to:
  /// **'End session'**
  String get endSessionBtn;

  /// No description provided for @pauseBtn.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pauseBtn;

  /// No description provided for @endRecoveryBtn.
  ///
  /// In en, this message translates to:
  /// **'End (recovery)'**
  String get endRecoveryBtn;

  /// No description provided for @resumeBtn.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resumeBtn;

  /// No description provided for @skipBreakBtn.
  ///
  /// In en, this message translates to:
  /// **'Skip break'**
  String get skipBreakBtn;

  /// No description provided for @focusWaitingBody.
  ///
  /// In en, this message translates to:
  /// **'The break is over. Nothing is suspended while waiting — start the next focus when ready, or end the session.'**
  String get focusWaitingBody;

  /// No description provided for @focusFocusBody.
  ///
  /// In en, this message translates to:
  /// **'Pause is free while the apps stay suspended. Long-press Pause to release them instead (recovery session required).'**
  String get focusFocusBody;

  /// No description provided for @focusDefaultBody.
  ///
  /// In en, this message translates to:
  /// **'The session is kept by the native focus service: it survives this app being closed, holds its suspensions between phases, and this screen mirrors it.'**
  String get focusDefaultBody;

  /// No description provided for @durationsSection.
  ///
  /// In en, this message translates to:
  /// **'Durations'**
  String get durationsSection;

  /// No description provided for @focusMinutesLabel.
  ///
  /// In en, this message translates to:
  /// **'Focus minutes'**
  String get focusMinutesLabel;

  /// No description provided for @breakMinutesLabel.
  ///
  /// In en, this message translates to:
  /// **'Break minutes'**
  String get breakMinutesLabel;

  /// No description provided for @longBreakMinutesLabel.
  ///
  /// In en, this message translates to:
  /// **'Long break minutes'**
  String get longBreakMinutesLabel;

  /// No description provided for @cyclesLabel.
  ///
  /// In en, this message translates to:
  /// **'Cycles before long break'**
  String get cyclesLabel;

  /// No description provided for @autoStartTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-start next focus'**
  String get autoStartTitle;

  /// No description provided for @autoStartSub.
  ///
  /// In en, this message translates to:
  /// **'Start the next focus phase by itself when a break ends; otherwise the session waits. Turning it off is a loosening.'**
  String get autoStartSub;

  /// No description provided for @soundTitle.
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get soundTitle;

  /// No description provided for @soundSub.
  ///
  /// In en, this message translates to:
  /// **'Play a sound at phase changes.'**
  String get soundSub;

  /// No description provided for @vibrationTitle.
  ///
  /// In en, this message translates to:
  /// **'Vibration'**
  String get vibrationTitle;

  /// No description provided for @vibrationSub.
  ///
  /// In en, this message translates to:
  /// **'Vibrate at phase changes.'**
  String get vibrationSub;

  /// No description provided for @suspendedWhileFocusing.
  ///
  /// In en, this message translates to:
  /// **'Suspended while focusing'**
  String get suspendedWhileFocusing;

  /// No description provided for @appsSuspendedWhileFocusing.
  ///
  /// In en, this message translates to:
  /// **'{count} app(s) suspended while focusing'**
  String appsSuspendedWhileFocusing(int count);

  /// No description provided for @groupsSuspendedWhileFocusing.
  ///
  /// In en, this message translates to:
  /// **'{count} group(s) suspended while focusing'**
  String groupsSuspendedWhileFocusing(int count);

  /// No description provided for @restrictionsAppliedWhileFocusing.
  ///
  /// In en, this message translates to:
  /// **'{count} restriction(s) applied while focusing'**
  String restrictionsAppliedWhileFocusing(int count);

  /// No description provided for @focusSchedulesTitle.
  ///
  /// In en, this message translates to:
  /// **'Focus schedules & reminders'**
  String get focusSchedulesTitle;

  /// No description provided for @focusSchedulesNote.
  ///
  /// In en, this message translates to:
  /// **'Scheduled auto-start sessions are not in this version.'**
  String get focusSchedulesNote;

  /// No description provided for @appsToSuspendWhileFocusing.
  ///
  /// In en, this message translates to:
  /// **'Apps to suspend while focusing'**
  String get appsToSuspendWhileFocusing;

  /// No description provided for @groupsToSuspendWhileFocusing.
  ///
  /// In en, this message translates to:
  /// **'Groups to suspend while focusing'**
  String get groupsToSuspendWhileFocusing;

  /// No description provided for @noGroupsYet.
  ///
  /// In en, this message translates to:
  /// **'No groups yet'**
  String get noGroupsYet;

  /// No description provided for @groupAppsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} app(s)'**
  String groupAppsCount(int count);

  /// No description provided for @restrictionsDuringFocus.
  ///
  /// In en, this message translates to:
  /// **'Restrictions during focus'**
  String get restrictionsDuringFocus;

  /// No description provided for @noDeviceOwnerPrivileges.
  ///
  /// In en, this message translates to:
  /// **'No Device Owner privileges'**
  String get noDeviceOwnerPrivileges;

  /// No description provided for @noOwnerBody.
  ///
  /// In en, this message translates to:
  /// **'System restrictions only work while Azm is the Device Owner. Complete the Setup flow first — restrictions are not faked without it.'**
  String get noOwnerBody;

  /// No description provided for @openSetup.
  ///
  /// In en, this message translates to:
  /// **'Open Setup'**
  String get openSetup;

  /// No description provided for @restrictionsUpdatedVerified.
  ///
  /// In en, this message translates to:
  /// **'Restrictions updated and verified.'**
  String get restrictionsUpdatedVerified;

  /// No description provided for @searchRestrictions.
  ///
  /// In en, this message translates to:
  /// **'Search restrictions'**
  String get searchRestrictions;

  /// No description provided for @loadingRestrictions.
  ///
  /// In en, this message translates to:
  /// **'Loading restrictions…'**
  String get loadingRestrictions;

  /// No description provided for @recommendedSection.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get recommendedSection;

  /// No description provided for @otherRestrictionsSection.
  ///
  /// In en, this message translates to:
  /// **'Other restrictions'**
  String get otherRestrictionsSection;

  /// No description provided for @changedNotApplied.
  ///
  /// In en, this message translates to:
  /// **'Changed — not applied yet'**
  String get changedNotApplied;

  /// No description provided for @applying.
  ///
  /// In en, this message translates to:
  /// **'Applying…'**
  String get applying;

  /// No description provided for @applyChanges.
  ///
  /// In en, this message translates to:
  /// **'Apply changes'**
  String get applyChanges;

  /// No description provided for @activeBadge.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get activeBadge;

  /// No description provided for @searchApps.
  ///
  /// In en, this message translates to:
  /// **'Search apps'**
  String get searchApps;

  /// No description provided for @includeSystemApps.
  ///
  /// In en, this message translates to:
  /// **'Include system apps'**
  String get includeSystemApps;

  /// No description provided for @appGroups.
  ///
  /// In en, this message translates to:
  /// **'App groups'**
  String get appGroups;

  /// No description provided for @appGroupsSub.
  ///
  /// In en, this message translates to:
  /// **'Shared limits and windows for a set of apps'**
  String get appGroupsSub;

  /// No description provided for @loadingInstalledApps.
  ///
  /// In en, this message translates to:
  /// **'Loading installed apps…'**
  String get loadingInstalledApps;

  /// No description provided for @noAppsMatch.
  ///
  /// In en, this message translates to:
  /// **'No apps match. Try a different search, or include system apps.'**
  String get noAppsMatch;

  /// No description provided for @stateSystem.
  ///
  /// In en, this message translates to:
  /// **'system'**
  String get stateSystem;

  /// No description provided for @stateHidden.
  ///
  /// In en, this message translates to:
  /// **'hidden'**
  String get stateHidden;

  /// No description provided for @stateSuspended.
  ///
  /// In en, this message translates to:
  /// **'suspended'**
  String get stateSuspended;

  /// No description provided for @stateUninstallBlocked.
  ///
  /// In en, this message translates to:
  /// **'uninstall blocked'**
  String get stateUninstallBlocked;

  /// No description provided for @usedTodaySuffix.
  ///
  /// In en, this message translates to:
  /// **'used {duration} today'**
  String usedTodaySuffix(String duration);

  /// No description provided for @suspendedTitle.
  ///
  /// In en, this message translates to:
  /// **'Suspended'**
  String get suspendedTitle;

  /// No description provided for @suspendedSub.
  ///
  /// In en, this message translates to:
  /// **'The app cannot be opened while suspended.'**
  String get suspendedSub;

  /// No description provided for @hiddenTitle.
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get hiddenTitle;

  /// No description provided for @hiddenSub.
  ///
  /// In en, this message translates to:
  /// **'Removed from the launcher and app list.'**
  String get hiddenSub;

  /// No description provided for @uninstallBlockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Uninstall blocked'**
  String get uninstallBlockedTitle;

  /// No description provided for @suspensionEnabledFor.
  ///
  /// In en, this message translates to:
  /// **'Suspension enabled for {app}'**
  String suspensionEnabledFor(String app);

  /// No description provided for @hidingEnabledFor.
  ///
  /// In en, this message translates to:
  /// **'Hiding enabled for {app}'**
  String hidingEnabledFor(String app);

  /// No description provided for @uninstallBlockEnabledFor.
  ///
  /// In en, this message translates to:
  /// **'Uninstall block enabled for {app}'**
  String uninstallBlockEnabledFor(String app);

  /// No description provided for @timeLimitUpdatedFor.
  ///
  /// In en, this message translates to:
  /// **'Time limit updated for {app}'**
  String timeLimitUpdatedFor(String app);

  /// No description provided for @timeWindowsUpdatedFor.
  ///
  /// In en, this message translates to:
  /// **'Time windows updated for {app}'**
  String timeWindowsUpdatedFor(String app);

  /// No description provided for @groupMembersUpdated.
  ///
  /// In en, this message translates to:
  /// **'Members of {group} updated'**
  String groupMembersUpdated(String group);

  /// No description provided for @groupLimitUpdated.
  ///
  /// In en, this message translates to:
  /// **'Limit of {group} updated'**
  String groupLimitUpdated(String group);

  /// No description provided for @restrictionsUpdatedFor.
  ///
  /// In en, this message translates to:
  /// **'Restrictions updated for {app}'**
  String restrictionsUpdatedFor(String app);

  /// No description provided for @timeLimitTile.
  ///
  /// In en, this message translates to:
  /// **'Time limit'**
  String get timeLimitTile;

  /// No description provided for @loadingEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loadingEllipsis;

  /// No description provided for @todayLimit.
  ///
  /// In en, this message translates to:
  /// **'Today: {limit}'**
  String todayLimit(String limit);

  /// No description provided for @perWeekdaySuffix.
  ///
  /// In en, this message translates to:
  /// **' (per-weekday)'**
  String get perWeekdaySuffix;

  /// No description provided for @noLimitSet.
  ///
  /// In en, this message translates to:
  /// **'No limit set'**
  String get noLimitSet;

  /// No description provided for @allowedWindowsTile.
  ///
  /// In en, this message translates to:
  /// **'Allowed time windows'**
  String get allowedWindowsTile;

  /// No description provided for @windowsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} window(s)'**
  String windowsCount(int count);

  /// No description provided for @usableAnyTime.
  ///
  /// In en, this message translates to:
  /// **'Usable at any time'**
  String get usableAnyTime;

  /// No description provided for @managedRestrictionsTile.
  ///
  /// In en, this message translates to:
  /// **'Managed restrictions'**
  String get managedRestrictionsTile;

  /// No description provided for @managedRestrictionsSub.
  ///
  /// In en, this message translates to:
  /// **'Edit this app\'s declared managed configuration'**
  String get managedRestrictionsSub;

  /// No description provided for @timeLimitDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Time limit (minutes)'**
  String get timeLimitDialogTitle;

  /// No description provided for @dailySegment.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get dailySegment;

  /// No description provided for @perWeekdaySegment.
  ///
  /// In en, this message translates to:
  /// **'Per weekday'**
  String get perWeekdaySegment;

  /// No description provided for @minutesPerDayLabel.
  ///
  /// In en, this message translates to:
  /// **'Minutes per day (0 = no limit)'**
  String get minutesPerDayLabel;

  /// No description provided for @dayNoLimit.
  ///
  /// In en, this message translates to:
  /// **'{day} (0 = no limit)'**
  String dayNoLimit(String day);

  /// No description provided for @reopenLabel.
  ///
  /// In en, this message translates to:
  /// **'Reopening cooldown, seconds (stored; enforcement is v1.1)'**
  String get reopenLabel;

  /// No description provided for @dayMon.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get dayMon;

  /// No description provided for @dayTue.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get dayTue;

  /// No description provided for @dayWed.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get dayWed;

  /// No description provided for @dayThu.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get dayThu;

  /// No description provided for @dayFri.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get dayFri;

  /// No description provided for @daySat.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get daySat;

  /// No description provided for @daySun.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get daySun;

  /// No description provided for @allowedWindowsTitle.
  ///
  /// In en, this message translates to:
  /// **'Allowed windows (daily)'**
  String get allowedWindowsTitle;

  /// No description provided for @windowsBody.
  ///
  /// In en, this message translates to:
  /// **'Outside these windows the app is blocked. An empty list means usable at any time.'**
  String get windowsBody;

  /// No description provided for @noWindowsSet.
  ///
  /// In en, this message translates to:
  /// **'No windows set.'**
  String get noWindowsSet;

  /// No description provided for @addWindow.
  ///
  /// In en, this message translates to:
  /// **'Add window'**
  String get addWindow;

  /// No description provided for @windowStartHelp.
  ///
  /// In en, this message translates to:
  /// **'Window start'**
  String get windowStartHelp;

  /// No description provided for @windowEndHelp.
  ///
  /// In en, this message translates to:
  /// **'Window end (may be next day)'**
  String get windowEndHelp;

  /// No description provided for @appGroupsTitle.
  ///
  /// In en, this message translates to:
  /// **'App groups'**
  String get appGroupsTitle;

  /// No description provided for @newGroupTooltip.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get newGroupTooltip;

  /// No description provided for @loadingGroups.
  ///
  /// In en, this message translates to:
  /// **'Loading groups…'**
  String get loadingGroups;

  /// No description provided for @noGroupsYetEmpty.
  ///
  /// In en, this message translates to:
  /// **'No groups yet. Create one to share a limit across apps.'**
  String get noGroupsYetEmpty;

  /// No description provided for @newGroup.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get newGroup;

  /// No description provided for @groupNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get groupNameLabel;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @renameGroup.
  ///
  /// In en, this message translates to:
  /// **'Rename group'**
  String get renameGroup;

  /// No description provided for @groupAppsLimitLine.
  ///
  /// In en, this message translates to:
  /// **'{count} apps · limit {limit}'**
  String groupAppsLimitLine(int count, String limit);

  /// No description provided for @editMembers.
  ///
  /// In en, this message translates to:
  /// **'Edit members'**
  String get editMembers;

  /// No description provided for @editLimit.
  ///
  /// In en, this message translates to:
  /// **'Edit limit'**
  String get editLimit;

  /// No description provided for @renameGroupAction.
  ///
  /// In en, this message translates to:
  /// **'Rename group'**
  String get renameGroupAction;

  /// No description provided for @deleteGroup.
  ///
  /// In en, this message translates to:
  /// **'Delete group'**
  String get deleteGroup;

  /// No description provided for @membersOf.
  ///
  /// In en, this message translates to:
  /// **'Members of {group}'**
  String membersOf(String group);

  /// No description provided for @restrictionsForApp.
  ///
  /// In en, this message translates to:
  /// **'Restrictions — {app}'**
  String restrictionsForApp(String app);

  /// No description provided for @loadingDeclaredRestrictions.
  ///
  /// In en, this message translates to:
  /// **'Loading declared restrictions…'**
  String get loadingDeclaredRestrictions;

  /// No description provided for @noRestrictionsForApp.
  ///
  /// In en, this message translates to:
  /// **'No restrictions available for {app}. This app does not declare any managed restrictions.'**
  String noRestrictionsForApp(String app);

  /// No description provided for @clearAllRestrictions.
  ///
  /// In en, this message translates to:
  /// **'Clear all restrictions'**
  String get clearAllRestrictions;

  /// No description provided for @clearAllBody.
  ///
  /// In en, this message translates to:
  /// **'Remove every managed restriction for {app}? This only edits the draft — tap Save to apply it.'**
  String clearAllBody(String app);

  /// No description provided for @unsavedChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get unsavedChangesTitle;

  /// No description provided for @unsavedChangesBody.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved restriction changes. Discard them?'**
  String get unsavedChangesBody;

  /// No description provided for @keepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get keepEditing;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @allFilter.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get allFilter;

  /// No description provided for @activeFilterCount.
  ///
  /// In en, this message translates to:
  /// **'Active ({count})'**
  String activeFilterCount(int count);

  /// No description provided for @defaultFilterCount.
  ///
  /// In en, this message translates to:
  /// **'Default ({count})'**
  String defaultFilterCount(int count);

  /// No description provided for @noRestrictionsMatching.
  ///
  /// In en, this message translates to:
  /// **'No restrictions matching \"{query}\"'**
  String noRestrictionsMatching(String query);

  /// No description provided for @noRestrictionsAvailableFor.
  ///
  /// In en, this message translates to:
  /// **'No restrictions available for {app}'**
  String noRestrictionsAvailableFor(String app);

  /// No description provided for @savingEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get savingEllipsis;

  /// No description provided for @saveRestrictions.
  ///
  /// In en, this message translates to:
  /// **'Save restrictions'**
  String get saveRestrictions;

  /// No description provided for @seeMore.
  ///
  /// In en, this message translates to:
  /// **'See more'**
  String get seeMore;

  /// No description provided for @seeLess.
  ///
  /// In en, this message translates to:
  /// **'See less'**
  String get seeLess;

  /// No description provided for @enabledLabel.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get enabledLabel;

  /// No description provided for @disabledLabel.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get disabledLabel;

  /// No description provided for @unsupportedRestrictionType.
  ///
  /// In en, this message translates to:
  /// **'Unsupported restriction type: {type}'**
  String unsupportedRestrictionType(String type);

  /// No description provided for @removeValue.
  ///
  /// In en, this message translates to:
  /// **'Remove value'**
  String get removeValue;

  /// No description provided for @addValueLabel.
  ///
  /// In en, this message translates to:
  /// **'Add value'**
  String get addValueLabel;

  /// No description provided for @addValueTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add value'**
  String get addValueTooltip;

  /// No description provided for @itemNumber.
  ///
  /// In en, this message translates to:
  /// **'Item {number}'**
  String itemNumber(int number);

  /// No description provided for @removeItem.
  ///
  /// In en, this message translates to:
  /// **'Remove item'**
  String get removeItem;

  /// No description provided for @addItem.
  ///
  /// In en, this message translates to:
  /// **'Add item'**
  String get addItem;

  /// No description provided for @brandTagline.
  ///
  /// In en, this message translates to:
  /// **'BREAK THE CHAIN'**
  String get brandTagline;

  /// No description provided for @lockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Azm is locked'**
  String get lockedTitle;

  /// No description provided for @startFocusAction.
  ///
  /// In en, this message translates to:
  /// **'Start focus'**
  String get startFocusAction;

  /// No description provided for @skipBreakAction.
  ///
  /// In en, this message translates to:
  /// **'Skip break'**
  String get skipBreakAction;

  /// No description provided for @pauseAction.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pauseAction;

  /// No description provided for @resumeAction.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resumeAction;

  /// No description provided for @focusCycleTitle.
  ///
  /// In en, this message translates to:
  /// **'Focus {current}/{total}'**
  String focusCycleTitle(int current, int total);

  /// No description provided for @focusPausedSuffix.
  ///
  /// In en, this message translates to:
  /// **' · paused'**
  String get focusPausedSuffix;

  /// No description provided for @focusShortBreak.
  ///
  /// In en, this message translates to:
  /// **'Short break'**
  String get focusShortBreak;

  /// No description provided for @focusLongBreak.
  ///
  /// In en, this message translates to:
  /// **'Long break'**
  String get focusLongBreak;

  /// No description provided for @focusBreakOver.
  ///
  /// In en, this message translates to:
  /// **'Break over'**
  String get focusBreakOver;

  /// No description provided for @focusSuspendingSummary.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min of focus, suspending the selected apps'**
  String focusSuspendingSummary(int minutes);

  /// No description provided for @groupsSection.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get groupsSection;

  /// No description provided for @appsSection.
  ///
  /// In en, this message translates to:
  /// **'Apps'**
  String get appsSection;

  /// No description provided for @gateBody.
  ///
  /// In en, this message translates to:
  /// **'Enter your recovery code to open a 10-minute session.'**
  String get gateBody;

  /// No description provided for @provisionOutput.
  ///
  /// In en, this message translates to:
  /// **'Path used: {path}\n{output}'**
  String provisionOutput(String path, String output);

  /// No description provided for @noStoreMsg.
  ///
  /// In en, this message translates to:
  /// **'No store or browser could be opened for the Shizuku page.'**
  String get noStoreMsg;

  /// No description provided for @setupAndOwner.
  ///
  /// In en, this message translates to:
  /// **'Setup & Device Owner'**
  String get setupAndOwner;

  /// No description provided for @setupTitle.
  ///
  /// In en, this message translates to:
  /// **'Setup'**
  String get setupTitle;

  /// No description provided for @dnsNeedsOwnerMsg.
  ///
  /// In en, this message translates to:
  /// **'Private DNS requires Device Owner — finish Setup first.'**
  String get dnsNeedsOwnerMsg;

  /// No description provided for @forcedRemovalTitle.
  ///
  /// In en, this message translates to:
  /// **'24-hour forced removal'**
  String get forcedRemovalTitle;

  /// No description provided for @forcedInProgressSub.
  ///
  /// In en, this message translates to:
  /// **'In progress — {remaining} remaining (advances while the app is running)'**
  String forcedInProgressSub(String remaining);

  /// No description provided for @dnsApplyTimeout.
  ///
  /// In en, this message translates to:
  /// **'Applying the DNS host timed out. Check the current DNS state before retrying.'**
  String get dnsApplyTimeout;

  /// No description provided for @dnsNotServing.
  ///
  /// In en, this message translates to:
  /// **'The chosen DNS host is not serving. Pick another host.'**
  String get dnsNotServing;

  /// No description provided for @dnsApplyFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to apply the private DNS host.'**
  String get dnsApplyFailed;

  /// No description provided for @dnsAppliedMsg.
  ///
  /// In en, this message translates to:
  /// **'Private DNS forced to {host} (verified).'**
  String dnsAppliedMsg(String host);

  /// No description provided for @ownerStillActiveMsg.
  ///
  /// In en, this message translates to:
  /// **'Device Owner is still active after removal'**
  String get ownerStillActiveMsg;

  /// No description provided for @noCapableBrowser.
  ///
  /// In en, this message translates to:
  /// **'No installed browser declares URLBlocklist in its managed restrictions, so there is nothing to push policy to. Browsers without support are handled by suspension rules.'**
  String get noCapableBrowser;

  /// No description provided for @blocklistsSection.
  ///
  /// In en, this message translates to:
  /// **'Blocklists'**
  String get blocklistsSection;

  /// No description provided for @noBlocklistsYet.
  ///
  /// In en, this message translates to:
  /// **'No blocklists yet. Create one to start blocking sites.'**
  String get noBlocklistsYet;

  /// No description provided for @usageWarningsBody.
  ///
  /// In en, this message translates to:
  /// **'Each stage warns once, the configured number of minutes before an app\'s daily limit runs out. Stages are stored for the Accessibility Service to fire; notification delivery depends on the native notifier.'**
  String get usageWarningsBody;

  /// No description provided for @removeStageTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove stage'**
  String get removeStageTooltip;

  /// No description provided for @vibrationCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Vibration count'**
  String get vibrationCountLabel;

  /// No description provided for @noLogsYet.
  ///
  /// In en, this message translates to:
  /// **'No suspensions have been logged.'**
  String get noLogsYet;

  /// No description provided for @impulseActiveLeft.
  ///
  /// In en, this message translates to:
  /// **'Impulse lock active — {time} left'**
  String impulseActiveLeft(String time);

  /// No description provided for @impulseNoEarlyStop.
  ///
  /// In en, this message translates to:
  /// **'The lock ends when its timer runs out — or early, if you complete the challenges you selected for Impulse Lock. The apps it suspended are released when it ends.'**
  String get impulseNoEarlyStop;

  /// No description provided for @startImpulseLock.
  ///
  /// In en, this message translates to:
  /// **'Start impulse lock ({minutes} min)'**
  String startImpulseLock(int minutes);

  /// No description provided for @settingsLocked.
  ///
  /// In en, this message translates to:
  /// **'Settings are locked'**
  String get settingsLocked;

  /// No description provided for @settingsLockedSub.
  ///
  /// In en, this message translates to:
  /// **'Impulse lock settings can only be changed during a recovery session. Tap to open one.'**
  String get settingsLockedSub;

  /// No description provided for @durationMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} minutes (15–360)'**
  String durationMinutes(int minutes);

  /// No description provided for @minutesShort.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String minutesShort(int minutes);

  /// No description provided for @accessChallengesSection.
  ///
  /// In en, this message translates to:
  /// **'Access challenges'**
  String get accessChallengesSection;

  /// No description provided for @shuffledKeypad.
  ///
  /// In en, this message translates to:
  /// **'Shuffled keypad for recovery code'**
  String get shuffledKeypad;

  /// No description provided for @focusIdleSummary.
  ///
  /// In en, this message translates to:
  /// **'{focus} min focus · {breakTime} min break'**
  String focusIdleSummary(int focus, int breakTime);

  /// No description provided for @startAction.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get startAction;

  /// No description provided for @endRecovery.
  ///
  /// In en, this message translates to:
  /// **'End (recovery)'**
  String get endRecovery;

  /// No description provided for @waitingBody.
  ///
  /// In en, this message translates to:
  /// **'The break is over. Nothing is suspended while waiting — start the next focus when ready, or end the session.'**
  String get waitingBody;

  /// No description provided for @focusPauseNote.
  ///
  /// In en, this message translates to:
  /// **'Pause is free while the apps stay suspended. Long-press Pause to release them instead (recovery session required).'**
  String get focusPauseNote;

  /// No description provided for @focusNativeNote.
  ///
  /// In en, this message translates to:
  /// **'The session is kept by the native focus service: it survives this app being closed, holds its suspensions between phases, and this screen mirrors it.'**
  String get focusNativeNote;

  /// No description provided for @groupsSuspendedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} group(s) suspended while focusing'**
  String groupsSuspendedCount(int count);

  /// No description provided for @restrictionsAppliedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} restriction(s) applied while focusing'**
  String restrictionsAppliedCount(int count);

  /// No description provided for @memberCount.
  ///
  /// In en, this message translates to:
  /// **'{count} app(s)'**
  String memberCount(int count);

  /// No description provided for @noOwnerRestrictionsBody.
  ///
  /// In en, this message translates to:
  /// **'System restrictions only work while Azm is the Device Owner. Complete the Setup flow first — restrictions are not faked without it.'**
  String get noOwnerRestrictionsBody;

  /// No description provided for @restrictionsUpdated.
  ///
  /// In en, this message translates to:
  /// **'Restrictions updated and verified.'**
  String get restrictionsUpdated;

  /// No description provided for @usedToday.
  ///
  /// In en, this message translates to:
  /// **'used {time} today'**
  String usedToday(String time);

  /// No description provided for @badgeSystem.
  ///
  /// In en, this message translates to:
  /// **'system'**
  String get badgeSystem;

  /// No description provided for @badgeHidden.
  ///
  /// In en, this message translates to:
  /// **'hidden'**
  String get badgeHidden;

  /// No description provided for @badgeSuspended.
  ///
  /// In en, this message translates to:
  /// **'suspended'**
  String get badgeSuspended;

  /// No description provided for @badgeUninstallBlocked.
  ///
  /// In en, this message translates to:
  /// **'uninstall blocked'**
  String get badgeUninstallBlocked;

  /// No description provided for @loadingShort.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loadingShort;

  /// No description provided for @todayLimitLine.
  ///
  /// In en, this message translates to:
  /// **'Today: {limit}'**
  String todayLimitLine(String limit);

  /// No description provided for @managedRestrictions.
  ///
  /// In en, this message translates to:
  /// **'Managed restrictions'**
  String get managedRestrictions;

  /// No description provided for @timeLimitUpdatedDesc.
  ///
  /// In en, this message translates to:
  /// **'Time limit updated for {app}'**
  String timeLimitUpdatedDesc(String app);

  /// No description provided for @timeWindowsUpdatedDesc.
  ///
  /// In en, this message translates to:
  /// **'Time windows updated for {app}'**
  String timeWindowsUpdatedDesc(String app);

  /// No description provided for @timeLimitEditorTitle.
  ///
  /// In en, this message translates to:
  /// **'Time limit (minutes)'**
  String get timeLimitEditorTitle;

  /// No description provided for @dayLimitLabel.
  ///
  /// In en, this message translates to:
  /// **'{day} (0 = no limit)'**
  String dayLimitLabel(String day);

  /// No description provided for @noGroupsYetMsg.
  ///
  /// In en, this message translates to:
  /// **'No groups yet. Create one to share a limit across apps.'**
  String get noGroupsYetMsg;

  /// No description provided for @membersUpdatedDesc.
  ///
  /// In en, this message translates to:
  /// **'Members of {name} updated'**
  String membersUpdatedDesc(String name);

  /// No description provided for @groupLimitUpdatedDesc.
  ///
  /// In en, this message translates to:
  /// **'Limit of {name} updated'**
  String groupLimitUpdatedDesc(String name);

  /// No description provided for @noRestrictionsFor.
  ///
  /// In en, this message translates to:
  /// **'No restrictions available for {app}. This app does not declare any managed restrictions.'**
  String noRestrictionsFor(String app);

  /// No description provided for @restrictionsForTitle.
  ///
  /// In en, this message translates to:
  /// **'Restrictions — {app}'**
  String restrictionsForTitle(String app);

  /// No description provided for @unsavedTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get unsavedTitle;

  /// No description provided for @unsavedBody.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved restriction changes. Discard them?'**
  String get unsavedBody;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get saving;

  /// No description provided for @unsupportedType.
  ///
  /// In en, this message translates to:
  /// **'Unsupported restriction type: {type}'**
  String unsupportedType(String type);

  /// No description provided for @removeValueTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove value'**
  String get removeValueTooltip;

  /// No description provided for @removeItemTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove item'**
  String get removeItemTooltip;

  /// No description provided for @restrictionsUpdatedDesc.
  ///
  /// In en, this message translates to:
  /// **'Restrictions updated for {app}'**
  String restrictionsUpdatedDesc(String app);

  /// No description provided for @generalSettings.
  ///
  /// In en, this message translates to:
  /// **'General Settings'**
  String get generalSettings;

  /// No description provided for @protectionTools.
  ///
  /// In en, this message translates to:
  /// **'Protection tools'**
  String get protectionTools;

  /// No description provided for @preferencesSection.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get preferencesSection;

  /// No description provided for @passwordVerifyError.
  ///
  /// In en, this message translates to:
  /// **'The password could not be verified. Nothing was changed — try again.'**
  String get passwordVerifyError;

  /// No description provided for @passwordRecordCorrupt.
  ///
  /// In en, this message translates to:
  /// **'The stored app password is damaged and cannot be used. Set a new password to replace it.'**
  String get passwordRecordCorrupt;

  /// No description provided for @impulseUnlockEarly.
  ///
  /// In en, this message translates to:
  /// **'End early with challenges'**
  String get impulseUnlockEarly;

  /// No description provided for @impulseUnlockTitle.
  ///
  /// In en, this message translates to:
  /// **'End impulse lock early'**
  String get impulseUnlockTitle;

  /// No description provided for @impulseUnlockBody.
  ///
  /// In en, this message translates to:
  /// **'Complete the challenges you selected for Impulse Lock to end this lock now and release the apps it suspended.'**
  String get impulseUnlockBody;

  /// No description provided for @impulseLockEndedEarly.
  ///
  /// In en, this message translates to:
  /// **'Impulse lock ended — the apps it suspended were released.'**
  String get impulseLockEndedEarly;

  /// No description provided for @appsBrowseSection.
  ///
  /// In en, this message translates to:
  /// **'App list options'**
  String get appsBrowseSection;

  /// No description provided for @appProtectionSection.
  ///
  /// In en, this message translates to:
  /// **'Protection'**
  String get appProtectionSection;

  /// No description provided for @appLimitsSection.
  ///
  /// In en, this message translates to:
  /// **'Limits & windows'**
  String get appLimitsSection;

  /// No description provided for @setupServicesSection.
  ///
  /// In en, this message translates to:
  /// **'Services & permissions'**
  String get setupServicesSection;

  /// No description provided for @storeCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Keep it safe'**
  String get storeCardTitle;

  /// No description provided for @removalLoadingTitle.
  ///
  /// In en, this message translates to:
  /// **'Completing Device Owner removal…'**
  String get removalLoadingTitle;

  /// No description provided for @removalLoadingBody.
  ///
  /// In en, this message translates to:
  /// **'Please wait. Do not close the app or uninstall until teardown completes.'**
  String get removalLoadingBody;

  /// No description provided for @removalTimeoutWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Teardown incomplete — do not uninstall yet'**
  String get removalTimeoutWarningTitle;

  /// No description provided for @removalTimeoutWarningBody.
  ///
  /// In en, this message translates to:
  /// **'Device Owner was cleared, but the system has not finished settling all teardown steps. Do NOT uninstall yet, or the device may experience issues. The following checks are unverified:'**
  String get removalTimeoutWarningBody;

  /// No description provided for @removalRecheckAction.
  ///
  /// In en, this message translates to:
  /// **'Re-check status'**
  String get removalRecheckAction;

  /// No description provided for @removalUnverifiedOwner.
  ///
  /// In en, this message translates to:
  /// **'Device Owner is still active'**
  String get removalUnverifiedOwner;

  /// No description provided for @removalUnverifiedAdmin.
  ///
  /// In en, this message translates to:
  /// **'Device Admin is still active'**
  String get removalUnverifiedAdmin;

  /// No description provided for @removalUnverifiedRestrictions.
  ///
  /// In en, this message translates to:
  /// **'Restrictions still in force: {restrictions}'**
  String removalUnverifiedRestrictions(String restrictions);

  /// No description provided for @removalUnverifiedScreenCapture.
  ///
  /// In en, this message translates to:
  /// **'Screen capture is still blocked'**
  String get removalUnverifiedScreenCapture;

  /// No description provided for @deleteGroupConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete group?'**
  String get deleteGroupConfirmTitle;

  /// No description provided for @deleteGroupConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"? All its limits and time windows will be permanently removed.'**
  String deleteGroupConfirmMessage(String name);

  /// No description provided for @deleteWindowConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete time window?'**
  String get deleteWindowConfirmTitle;

  /// No description provided for @deleteWindowConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete the time window \"{window}\"?'**
  String deleteWindowConfirmMessage(String window);

  /// No description provided for @deleteBlocklistConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete blocklist?'**
  String get deleteBlocklistConfirmTitle;

  /// No description provided for @deleteBlocklistConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete the blocklist \"{title}\"?'**
  String deleteBlocklistConfirmMessage(String title);

  /// No description provided for @deleteStageConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete warning stage?'**
  String get deleteStageConfirmTitle;

  /// No description provided for @deleteStageConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete the warning stage at {minutes} minutes?'**
  String deleteStageConfirmMessage(String minutes);

  /// No description provided for @deleteRuleConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete seal rule?'**
  String get deleteRuleConfirmTitle;

  /// No description provided for @deleteRuleConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this seal rule: \"{summary}\"?'**
  String deleteRuleConfirmMessage(String summary);

  /// No description provided for @removeOwnerConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove Device Owner and end protection?'**
  String get removeOwnerConfirmTitle;

  /// No description provided for @removeOwnerConsequenceRestrictions.
  ///
  /// In en, this message translates to:
  /// **'All system restrictions, app suspensions, and website blocks will be lifted immediately.'**
  String get removeOwnerConsequenceRestrictions;

  /// No description provided for @removeOwnerConsequenceDns.
  ///
  /// In en, this message translates to:
  /// **'Private DNS settings will be reset.'**
  String get removeOwnerConsequenceDns;

  /// No description provided for @removeOwnerConsequenceUninstall.
  ///
  /// In en, this message translates to:
  /// **'Uninstalling the Azm app will be allowed.'**
  String get removeOwnerConsequenceUninstall;

  /// No description provided for @removeOwnerUnderstandCheckbox.
  ///
  /// In en, this message translates to:
  /// **'I understand the consequences of this action'**
  String get removeOwnerUnderstandCheckbox;

  /// No description provided for @removeOwnerConfirmButton.
  ///
  /// In en, this message translates to:
  /// **'Remove protection'**
  String get removeOwnerConfirmButton;

  /// No description provided for @scratchToReveal.
  ///
  /// In en, this message translates to:
  /// **'Scratch to reveal'**
  String get scratchToReveal;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
