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
  /// **'Dominanter'**
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

  /// No description provided for @errorCodeLine.
  ///
  /// In en, this message translates to:
  /// **'Error code: {code}'**
  String errorCodeLine(String code);

  /// No description provided for @errorCodeExitLine.
  ///
  /// In en, this message translates to:
  /// **'Error code: {code} · exit {exitCode}'**
  String errorCodeExitLine(String code, int exitCode);

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
  /// **'Shizuku permission has not been granted to Dominanter.'**
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

  /// No description provided for @errShellFailedExit.
  ///
  /// In en, this message translates to:
  /// **'A system command failed (exit code {exitCode}).'**
  String errShellFailedExit(int exitCode);

  /// No description provided for @errProvisioningFailed.
  ///
  /// In en, this message translates to:
  /// **'Device Owner provisioning failed on both the direct and the fallback path. See Diagnostics on the Setup screen.'**
  String get errProvisioningFailed;

  /// No description provided for @errDpmNotOwner.
  ///
  /// In en, this message translates to:
  /// **'Dominanter is not the Device Owner, so this operation is not available. Complete Setup first.'**
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
  /// **'Invalid input: {message}'**
  String errInvalidArgument(String message);

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

  /// No description provided for @startingDominanter.
  ///
  /// In en, this message translates to:
  /// **'Starting Dominanter…'**
  String get startingDominanter;

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
  /// **'Dominanter is locked'**
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
  /// **'Dominanter {version}'**
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
  /// **'Unlock Dominanter'**
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
  /// **'Authentication could not start: {error}'**
  String authCouldNotStart(String error);

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
  /// **'Set an app password as another way to open Dominanter from the lock screen. The password only opens the app — loosening restrictions or removing Device Owner still needs the recovery code.'**
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
  /// **'Dominanter generates a 16-letter code'**
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
  /// **'The code will be asked for whenever you change Dominanter\'s settings. Without it, you could be locked out of the blocked features. It is stored only as a salted hash on this device — it cannot be shown again after this wizard, and there is no account or cloud copy.'**
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
  /// **'Dominanter — first run'**
  String get firstRunTitle;

  /// No description provided for @gateChallengesTitle.
  ///
  /// In en, this message translates to:
  /// **'Access challenges'**
  String get gateChallengesTitle;

  /// No description provided for @gateCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter recovery code'**
  String get gateCodeTitle;

  /// No description provided for @gateIntroText.
  ///
  /// In en, this message translates to:
  /// **'Enter your recovery code to open a 10-minute session. Your configured access challenges run only after the code is accepted.'**
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
  /// **'Shizuku is installed, but its server is not running. Dominanter cannot start it — open the Shizuku app and start the server (via wireless debugging or ADB), then pull to refresh.'**
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
  /// **'The server is running. Grant Dominanter permission in Shizuku to continue setup.'**
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
  /// **'Permission not granted yet. Approve Dominanter in Shizuku, then tap Request again.'**
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
  /// **'Dominanter is the Device Owner of this device.'**
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
  /// **'{packageName} is already the Device Owner of this device ({receiver}).\n\nA device can have only one Device Owner. That app must relinquish ownership (or the device must be factory-reset) before Dominanter can be provisioned. This matches the original app, which replaces the provisioning button with this warning.'**
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
  /// **'Scheduled grayscale / night light / extra dim ship in v1.1 (the WRITE_SECURE_SETTINGS grant they need is on the Setup screen).'**
  String get colourModesNote;

  /// No description provided for @activityBlocker.
  ///
  /// In en, this message translates to:
  /// **'Activity blocker'**
  String get activityBlocker;

  /// No description provided for @activityBlockerNote.
  ///
  /// In en, this message translates to:
  /// **'Blocking specific activity screens ships in v1.1.'**
  String get activityBlockerNote;

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

  /// No description provided for @forcedRemoval48.
  ///
  /// In en, this message translates to:
  /// **'Force removal in 48 hours'**
  String get forcedRemoval48;

  /// No description provided for @forcedIdleSub.
  ///
  /// In en, this message translates to:
  /// **'The only code-free escape: after 48 hours, Device Owner can be removed without the recovery code.'**
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
  /// **'This starts a 48-hour countdown. When it finishes, Device Owner — and with it every restriction this app enforces — can be removed without the recovery code. It is the only code-free escape, and it can be cancelled at any time before it completes.'**
  String get startForcedBody;

  /// No description provided for @cancelForcedTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel forced removal?'**
  String get cancelForcedTitle;

  /// No description provided for @cancelForcedBody.
  ///
  /// In en, this message translates to:
  /// **'The 48-hour countdown will be discarded. Device Owner removal will again require the recovery code.'**
  String get cancelForcedBody;

  /// No description provided for @finishForcedTitle.
  ///
  /// In en, this message translates to:
  /// **'Finish forced removal?'**
  String get finishForcedTitle;

  /// No description provided for @finishForcedBody.
  ///
  /// In en, this message translates to:
  /// **'The 48-hour wait is complete. Removing Device Owner now lifts every restriction this app enforces on this device.'**
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
  /// **'No installed browser declares URLBlocklist in its managed restrictions, so there is nothing to push policy to. Browsers without support are handled by suspension rules (v1.1 auto-suspension).'**
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
  /// **'Access challenges (before a recovery session)'**
  String get accessChallengesTitle;

  /// No description provided for @accessChallengesBody.
  ///
  /// In en, this message translates to:
  /// **'The recovery code is asked for first; the selected challenges then run, in order, before the session starts.'**
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
  /// **'System restrictions only work while Dominanter is the Device Owner. Complete the Setup flow first — restrictions are not faked without it.'**
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
  /// **'Dominanter is locked'**
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
  /// **'Enter your recovery code to open a 10-minute session. Your configured access challenges run only after the code is accepted.'**
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
  /// **'48-hour forced removal'**
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
  /// **'No installed browser declares URLBlocklist in its managed restrictions, so there is nothing to push policy to. Browsers without support are handled by suspension rules (v1.1 auto-suspension).'**
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
  /// **'Like the original, the lock has no early stop: it ends on its own when the timer runs out, and the apps it suspended are released then.'**
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
  /// **'Access challenges (before a recovery session)'**
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
  /// **'System restrictions only work while Dominanter is the Device Owner. Complete the Setup flow first — restrictions are not faked without it.'**
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
