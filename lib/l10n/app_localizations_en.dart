// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Dominanter';

  @override
  String get loadingDefault => 'Loading…';

  @override
  String get retry => 'Retry';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get close => 'Close';

  @override
  String get confirm => 'Confirm';

  @override
  String get continueAction => 'Continue';

  @override
  String get undo => 'Undo';

  @override
  String errorCodeLine(String code) {
    return 'Error code: $code';
  }

  @override
  String errorCodeExitLine(String code, int exitCode) {
    return 'Error code: $code · exit $exitCode';
  }

  @override
  String get errUnavailable =>
      'The Android service layer is not available here (this happens in tests or off-device). No operation was performed.';

  @override
  String get errShizukuNotInstalled =>
      'Shizuku is not installed on this device.';

  @override
  String get errShizukuNotRunning =>
      'Shizuku is installed but its server is not running. Start it from the Shizuku app, then retry.';

  @override
  String get errShizukuNoPermission =>
      'Shizuku permission has not been granted to Dominanter.';

  @override
  String get errShizukuPreV11 =>
      'This Shizuku server is older than v11. Update Shizuku, then retry.';

  @override
  String get errShizukuBinderDead =>
      'The Shizuku connection dropped during the operation. Its outcome is unknown — check the current state before retrying.';

  @override
  String get errShellFailed => 'A system command failed.';

  @override
  String errShellFailedExit(int exitCode) {
    return 'A system command failed (exit code $exitCode).';
  }

  @override
  String get errProvisioningFailed =>
      'Device Owner provisioning failed on both the direct and the fallback path. See Diagnostics on the Setup screen.';

  @override
  String get errDpmNotOwner =>
      'Dominanter is not the Device Owner, so this operation is not available. Complete Setup first.';

  @override
  String get errDpmFailed =>
      'The system refused or could not verify this change. Nothing was reported as successful.';

  @override
  String get errPackageNotFound => 'That app is not installed on this device.';

  @override
  String get errPermissionDenied => 'A required permission is not granted.';

  @override
  String get errUnsupportedAndroid =>
      'This Android version does not support this operation.';

  @override
  String get errTimeout =>
      'The operation timed out and was not reported as successful.';

  @override
  String errInvalidArgument(String message) {
    return 'Invalid input: $message';
  }

  @override
  String get errNotImplemented => 'This is not implemented in this version.';

  @override
  String get noLimit => 'No limit';

  @override
  String minutesOnly(int count) {
    return '$count min';
  }

  @override
  String hoursOnly(int count) {
    return '$count h';
  }

  @override
  String hoursMinutes(int hours, int minutes) {
    return '$hours h $minutes min';
  }

  @override
  String durationHoursMinutes(String hours, String minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String durationMinutesSeconds(String minutes, String seconds) {
    return '${minutes}m ${seconds}s';
  }

  @override
  String durationSecondsOnly(String seconds) {
    return '${seconds}s';
  }

  @override
  String get chipV11 => 'v1.1';

  @override
  String get sessionRemaining => 'Recovery session';

  @override
  String get renewSession => 'Renew';

  @override
  String get endSession => 'End session';

  @override
  String get wordYes => 'yes';

  @override
  String get wordNo => 'no';

  @override
  String get startingDominanter => 'Starting Dominanter…';

  @override
  String get unknownStartupError => 'Unknown startup error';

  @override
  String get tabStatus => 'Status';

  @override
  String get tabRestrictions => 'Restrictions';

  @override
  String get tabApps => 'Apps';

  @override
  String get tabConfig => 'Config';

  @override
  String get lockTitle => 'Dominanter is locked';

  @override
  String get panicButton => 'I\'m having impulses';

  @override
  String get accessApp => 'Access app';

  @override
  String get viewLimits => 'View limits';

  @override
  String get lockHelperBiometric =>
      'Use your fingerprint, face or device PIN to open the app.';

  @override
  String get lockHelperWithPassword =>
      'Use your fingerprint, face or device PIN — or your app password.';

  @override
  String get usePasswordInstead => 'Use password instead';

  @override
  String versionFooter(String version) {
    return 'Dominanter $version';
  }

  @override
  String get impulseBlockActive => 'Impulse block active';

  @override
  String impulseStartedSuspended(int minutes) {
    return 'Impulse lock started; chosen apps suspended for $minutes min.';
  }

  @override
  String impulseStarted(int minutes) {
    return 'Impulse lock started for $minutes min.';
  }

  @override
  String focusPhaseFocusOf(int current, int total) {
    return 'Focus $current/$total';
  }

  @override
  String get focusPhaseShortBreak => 'Short break';

  @override
  String get focusPhaseLongBreak => 'Long break';

  @override
  String get focusPhaseBreakOver => 'Break over';

  @override
  String get focusPhaseMode => 'Focus mode';

  @override
  String focusPausedTitle(String title) {
    return '$title · paused';
  }

  @override
  String focusConfigSummary(int minutes) {
    return '$minutes min of focus, suspending the selected apps';
  }

  @override
  String focusPeriodsCompleted(int done, int total) {
    return 'Focus periods completed: $done/$total';
  }

  @override
  String get focusStart => 'Start focus';

  @override
  String get focusResume => 'Resume';

  @override
  String get focusSkipBreak => 'Skip break';

  @override
  String get focusPause => 'Pause';

  @override
  String get focusEndSession => 'End session';

  @override
  String get todaysUsage => 'Today\'s usage';

  @override
  String get loadingUsageLimits => 'Loading usage limits…';

  @override
  String get noLimitsSet => 'No time limit set for apps or groups.';

  @override
  String get sectionGroups => 'Groups';

  @override
  String get sectionApps => 'Apps';

  @override
  String groupPrefix(String name) {
    return 'Group: $name';
  }

  @override
  String usageOf(String used, String limit) {
    return '$used of $limit';
  }

  @override
  String get limitReached => 'Limit reached';

  @override
  String timeLeft(String time) {
    return '$time left';
  }

  @override
  String overviewMinutes(int count) {
    return '${count}min';
  }

  @override
  String overviewHours(int count) {
    return '${count}h';
  }

  @override
  String overviewHoursMinutes(int hours, int minutes) {
    return '${hours}h ${minutes}min';
  }

  @override
  String get noDeviceLockTitle => 'No device lock is set up';

  @override
  String get noDeviceLockBody =>
      'This device has no biometric or screen credential enrolled, so there is nothing to authenticate against. Entry is allowed — exactly as the original app behaves in this case. Consider setting a device PIN.';

  @override
  String get unlockReason => 'Unlock Dominanter';

  @override
  String get authNotCompleted => 'Authentication was not completed.';

  @override
  String authFailed(String message) {
    return 'Authentication failed: $message';
  }

  @override
  String authCouldNotStart(String error) {
    return 'Authentication could not start: $error';
  }

  @override
  String get passwordPromptTitle => 'Enter app password';

  @override
  String get passwordFieldLabel => 'App password';

  @override
  String get passwordUnlock => 'Unlock';

  @override
  String get passwordWrong => 'That password is not correct.';

  @override
  String passwordRetryIn(int seconds) {
    return 'Try again in ${seconds}s';
  }

  @override
  String get passwordChecking => 'Checking…';

  @override
  String get appEntrySection => 'App entry';

  @override
  String get appEntryExplanation =>
      'Set an app password as another way to open Dominanter from the lock screen. The password only opens the app — loosening restrictions or removing Device Owner still needs the recovery code.';

  @override
  String get appEntryStatusSet => 'An app password is set.';

  @override
  String get appEntryStatusUnset => 'No app password is set.';

  @override
  String get appEntrySet => 'Set password';

  @override
  String get appEntryChange => 'Change password';

  @override
  String get appEntryRemove => 'Remove password';

  @override
  String get passwordNewLabel => 'New password';

  @override
  String get passwordConfirmLabel => 'Repeat password';

  @override
  String passwordMinLength(int count) {
    return 'Use at least $count characters.';
  }

  @override
  String get passwordMismatch => 'The two passwords do not match.';

  @override
  String get passwordSetDone => 'App password set.';

  @override
  String get passwordRemovedDone => 'App password removed.';

  @override
  String get passwordRemoveTitle => 'Remove app password?';

  @override
  String get passwordRemoveBody =>
      'You will open the app with your fingerprint or device credential again. This does not change the recovery code.';

  @override
  String get passwordRemoveConfirm => 'Remove';

  @override
  String get passwordShow => 'Show password';

  @override
  String get passwordHide => 'Hide password';

  @override
  String get recoveryCodeLabel => 'Recovery code';

  @override
  String get wizardSetupTitle => 'Set up your recovery code';

  @override
  String get wizardChangeTitle => 'Change recovery code';

  @override
  String stepOf(int step, int total) {
    return 'Step $step of $total';
  }

  @override
  String get grabPaper => 'Grab a pen and paper before continuing.';

  @override
  String get back => 'Back';

  @override
  String get next => 'Next';

  @override
  String get finish => 'Finish';

  @override
  String get wizardIntroTitle => 'Your recovery code';

  @override
  String get howItWorks => 'How it works';

  @override
  String get tipGenerates => 'Dominanter generates a 16-letter code';

  @override
  String get tipWrite => 'Write the code down on a piece of paper';

  @override
  String get tipTypeBack => 'Type it back to make sure it\'s correct';

  @override
  String get tipStorePaper => 'Store the paper in a safe place';

  @override
  String get wizardIntroBody =>
      'The code will be asked for whenever you change Dominanter\'s settings. Without it, you could be locked out of the blocked features. It is stored only as a salted hash on this device — it cannot be shown again after this wizard, and there is no account or cloud copy.';

  @override
  String get writeTitle => 'Write it on paper';

  @override
  String get writeBody =>
      'Copy the 16 letters exactly as shown. Don\'t take a screenshot or save it on your phone — a copy within reach is easy to use in a moment of impulse.';

  @override
  String get generatingCode => 'Generating your code…';

  @override
  String get showCode => 'Show code';

  @override
  String get wroteOnPaper => 'I wrote the code on paper';

  @override
  String get confirmTitle => 'Check what you wrote';

  @override
  String get confirmBody =>
      'The code is hidden now. Type it from your paper to make sure every letter is right.';

  @override
  String get codeCorrect => 'The code is correct';

  @override
  String get codeMismatchBack =>
      'It doesn\'t match. Go back and compare it with your paper.';

  @override
  String codeCountOf(int count) {
    return '$count/16';
  }

  @override
  String get storeTitle => 'Store it in a safe place';

  @override
  String get storeBody =>
      'The paper is now the only copy of your code. Choose carefully where to keep it.';

  @override
  String get tipAway =>
      'Away from your phone, somewhere you won\'t reach on impulse';

  @override
  String get tipEasyFind =>
      'Easy to find when you really need it — a drawer, a folder or with someone you trust';

  @override
  String get tipNoPhotos => 'No photos or digital copies';

  @override
  String get tipThrowOld => 'Throw away the paper with the old code';

  @override
  String get storedPaperCheckbox => 'I stored the paper in a safe place';

  @override
  String get codeMismatchStore =>
      'That does not match the code shown. Check your paper copy and try again.';

  @override
  String get codeNotStored => 'The code was not stored. Nothing was changed.';

  @override
  String get firstRunTitle => 'Dominanter — first run';

  @override
  String get gateChallengesTitle => 'Access challenges';

  @override
  String get gateCodeTitle => 'Enter recovery code';

  @override
  String get gateIntroText =>
      'Enter your recovery code to open a 10-minute session. Your configured access challenges run only after the code is accepted.';

  @override
  String get gateEnterCodeError =>
      'Enter the 16-letter code from your paper copy.';

  @override
  String get gateWrongCode => 'That code does not match. Nothing was unlocked.';

  @override
  String get preparingGate => 'Preparing the gate…';

  @override
  String get undoWindowPassed =>
      'The undo window has passed; the change stands.';

  @override
  String mathSolveTitle(int count) {
    return 'Solve $count problems';
  }

  @override
  String get mathNotQuite => 'Not quite — try again.';

  @override
  String get answerLabel => 'Answer';

  @override
  String get check => 'Check';

  @override
  String get wordsTypeTitle => 'Type the words';

  @override
  String wordsCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get typeWordLabel => 'Type the word';

  @override
  String readingTitle(int current, int total, String title) {
    return 'Read slowly — passage $current of $total: $title';
  }

  @override
  String get readingFinish => 'Finish';

  @override
  String get readingNextPassage => 'Next passage';

  @override
  String get tetrisSkippedNote =>
      'Note: the Tetris challenge is not available in this version (v1.1) and was skipped — it was not simulated.';

  @override
  String get passageOnWaiting => 'On waiting';

  @override
  String get passageOnFutureSelf => 'On the future self';

  @override
  String get passageOnAttention => 'On attention';

  @override
  String get passageOnBeginningAgain => 'On beginning again';

  @override
  String get passageOnPatience => 'On patience';

  @override
  String get yourPhrase => 'Your phrase';

  @override
  String get challengeMath => 'Math problems';

  @override
  String get challengeWords => 'Typing words';

  @override
  String get challengeTetris => 'Tetris';

  @override
  String get challengeReading => 'Reflective reading';

  @override
  String get checkingSetupState => 'Checking setup state…';

  @override
  String get iUnderstand => 'I understand';

  @override
  String get details => 'Details';

  @override
  String get shizukuNotInstalledTitle => 'Shizuku: not installed';

  @override
  String get shizukuNotInstalledBody =>
      'Install Shizuku (moe.shizuku.privileged.api) from the Play Store or its official site, then return here.';

  @override
  String get shizukuNotRunningTitle => 'Shizuku: not running';

  @override
  String get shizukuNotRunningBody =>
      'Shizuku is installed, but its server is not running. Dominanter cannot start it — open the Shizuku app and start the server (via wireless debugging or ADB), then pull to refresh.';

  @override
  String get shizukuPreV11Title => 'Shizuku: too old (pre-v11)';

  @override
  String get shizukuPreV11Body =>
      'This Shizuku server predates v11 and cannot run commands. Update Shizuku, restart its server, then refresh.';

  @override
  String get shizukuNoPermissionTitle => 'Shizuku: permission needed';

  @override
  String get shizukuNoPermissionBody =>
      'The server is running. Grant Dominanter permission in Shizuku to continue setup.';

  @override
  String get shizukuGrantedTitle => 'Shizuku: connected & granted';

  @override
  String get shizukuGrantedBody =>
      'Setup operations are available. Day-to-day enforcement does not need Shizuku after provisioning.';

  @override
  String get shizukuUnknownTitle => 'Shizuku: unknown state';

  @override
  String get shizukuUnknownBody =>
      'The native layer returned an unrecognised state.';

  @override
  String serverVersionLine(int version, int uid) {
    return 'Server version $version, UID $uid';
  }

  @override
  String diagnosticLine(String text) {
    return 'Diagnostic: $text';
  }

  @override
  String get installShizuku => 'Install Shizuku';

  @override
  String get waitingShizukuAppear => 'Waiting for Shizuku to appear…';

  @override
  String get requestShizukuPermission => 'Request Shizuku permission';

  @override
  String get waitingShizukuAnswer => 'Waiting for Shizuku\'s answer…';

  @override
  String get shizukuPermissionGrantedMsg =>
      'Shizuku permission granted — provisioning is unlocked.';

  @override
  String get permissionNotGrantedYetMsg =>
      'Permission not granted yet. Approve Dominanter in Shizuku, then tap Request again.';

  @override
  String get noStoreOpenedMsg =>
      'No store or browser could be opened for the Shizuku page.';

  @override
  String get shizukuDetectedMsg => 'Shizuku detected.';

  @override
  String get deviceOwnerTitle => 'Device Owner';

  @override
  String get deviceOwnerYes => 'Dominanter is the Device Owner of this device.';

  @override
  String deviceOwnerNo(String admin) {
    return 'Not provisioned. Most restrictions need Device Owner. Admin active: $admin.';
  }

  @override
  String accountsNote(int count) {
    return 'Note: $count account(s) detected. Provisioning usually still works via Shizuku, but removing accounts first is the original app\'s recommended path.';
  }

  @override
  String get becomeDeviceOwner => 'Become Device Owner via Shizuku';

  @override
  String get provisioningUnlocksNote =>
      'Provisioning unlocks when Shizuku is running and permission is granted.';

  @override
  String pathUsed(String path) {
    return 'Path used: $path';
  }

  @override
  String get accessibilityService => 'Accessibility Service';

  @override
  String get a11yUnknown => 'Unknown';

  @override
  String get a11yRunning => 'Enabled and running — enforcement is live.';

  @override
  String get a11yBinding => 'Enabled but not yet running (binding).';

  @override
  String get a11yOff =>
      'Off. Turning it off later suspends every controlled app (anti-bypass lockdown).';

  @override
  String get wssTitle => 'Extra system permission';

  @override
  String get wssGrantedText => 'Granted (verified by re-check).';

  @override
  String get wssPurpose =>
      'Grants the WRITE_SECURE_SETTINGS permission, needed for colour modes (v1.1). Granted via Shizuku and verified by re-check; the state shown here is read on every refresh.';

  @override
  String get granted => 'Granted';

  @override
  String get granting => 'Granting…';

  @override
  String get grant => 'Grant';

  @override
  String get wssGrantedMsg => 'WRITE_SECURE_SETTINGS is granted.';

  @override
  String get wssStillNotGrantedMsg =>
      'WRITE_SECURE_SETTINGS is still not granted. Shizuku must be running with permission granted first.';

  @override
  String get diagnosticsTitle => 'Provisioning diagnostics';

  @override
  String get diagnosticsSubtitle =>
      'Accounts, extra users and the current Device Owner — these can block provisioning.';

  @override
  String get runDiagnostics => 'Run diagnostics';

  @override
  String diagAccounts(int count) {
    return 'Accounts ($count)';
  }

  @override
  String get diagNoAccounts => 'No accounts found — good for provisioning.';

  @override
  String diagUsers(int count) {
    return 'Users ($count)';
  }

  @override
  String get diagOnlyPrimaryUser => 'Only the primary user.';

  @override
  String get diagCurrentOwner => 'Current Device Owner';

  @override
  String get diagNone => 'None';

  @override
  String get blockerExtraUsersTitle => 'Provisioning blocked: extra users';

  @override
  String blockerExtraUsersBody(String names) {
    return 'This device has additional users or profiles: $names.\n\nAndroid cannot provision a Device Owner while other users exist. Remove the extra users/profiles (Settings → Users), then return here and refresh. This matches the original app, which replaces the provisioning button with this warning.';
  }

  @override
  String get blockerOtherOwnerTitle =>
      'Provisioning blocked: another Device Owner';

  @override
  String blockerOtherOwnerBody(String packageName, String receiver) {
    return '$packageName is already the Device Owner of this device ($receiver).\n\nA device can have only one Device Owner. That app must relinquish ownership (or the device must be factory-reset) before Dominanter can be provisioned. This matches the original app, which replaces the provisioning button with this warning.';
  }

  @override
  String userIdSuffix(String name, int id) {
    return '$name (id $id)';
  }

  @override
  String get setupAppBarTitle => 'Setup';

  @override
  String get setupTileTitle => 'Setup & Device Owner';

  @override
  String get checking => 'Checking…';

  @override
  String get provisionedAsOwner => 'Provisioned as Device Owner';

  @override
  String get notOwnerOpenSetup => 'Not Device Owner — open Setup';

  @override
  String get privateDns => 'Private DNS';

  @override
  String get dnsCouldNotRead => 'Could not read current DNS state';

  @override
  String get dnsRequiresOwner => 'Requires Device Owner';

  @override
  String dnsForcedHost(String host) {
    return 'Forced host: $host';
  }

  @override
  String dnsMode(String mode) {
    return 'Mode: $mode';
  }

  @override
  String get dnsRequiresOwnerSnack =>
      'Private DNS requires Device Owner — finish Setup first.';

  @override
  String get browserRestrictions => 'Browser restrictions';

  @override
  String get browserRestrictionsSub =>
      'URL blocklists + SafeSearch on supporting browsers';

  @override
  String get blockedWords => 'Blocked words';

  @override
  String get blockedWordsSub => 'Active and per-app on-screen word blocking';

  @override
  String get impulseLock => 'Impulse lock';

  @override
  String get impulseLockSub =>
      'Panic lock, challenges, recovery keypad options';

  @override
  String get focusMode => 'Focus mode';

  @override
  String get focusModeSub => 'Pomodoro sessions that suspend chosen apps';

  @override
  String get usageWarnings => 'Usage warnings';

  @override
  String get usageWarningsSub => 'Staged warnings before a time limit expires';

  @override
  String get suspensionLogs => 'Suspension logs';

  @override
  String get suspensionLogsSub => 'Audit log of every suspension';

  @override
  String get colourModes => 'Colour modes';

  @override
  String get colourModesNote =>
      'Scheduled grayscale / night light / extra dim ship in v1.1 (the WRITE_SECURE_SETTINGS grant they need is on the Setup screen).';

  @override
  String get activityBlocker => 'Activity blocker';

  @override
  String get activityBlockerNote =>
      'Blocking specific activity screens ships in v1.1.';

  @override
  String get language => 'Language';

  @override
  String get languageDialogTitle => 'Language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageSaved => 'Language saved.';

  @override
  String get theme => 'Theme';

  @override
  String get themeSystem => 'System default';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get changeRecoveryCode => 'Change recovery code';

  @override
  String get changeRecoveryCodeSub =>
      'Requires a recovery session; the old code stops working';

  @override
  String get recoveryCodeChanged => 'Recovery code changed.';

  @override
  String get dangerZone => 'Danger zone';

  @override
  String get removeOwnerNow => 'Remove Device Owner now';

  @override
  String get removeOwnerNowSub =>
      'Immediate, inside a recovery session — every restriction this app enforces stops at once.';

  @override
  String get forcedRemoval48 => 'Force removal in 48 hours';

  @override
  String get forcedIdleSub =>
      'The only code-free escape: after 48 hours, Device Owner can be removed without the recovery code.';

  @override
  String get forcedCompleteSub =>
      'Complete — removal can now be finished without a code.';

  @override
  String forcedProgressSub(String remaining) {
    return 'In progress — $remaining remaining (advances while the app is running)';
  }

  @override
  String get startForcedRemoval => 'Start forced removal';

  @override
  String get cancelForcedRemoval => 'Cancel forced removal';

  @override
  String get finishRemoval => 'Finish removal';

  @override
  String get startForcedTitle => 'Start forced removal?';

  @override
  String get startForcedBody =>
      'This starts a 48-hour countdown. When it finishes, Device Owner — and with it every restriction this app enforces — can be removed without the recovery code. It is the only code-free escape, and it can be cancelled at any time before it completes.';

  @override
  String get cancelForcedTitle => 'Cancel forced removal?';

  @override
  String get cancelForcedBody =>
      'The 48-hour countdown will be discarded. Device Owner removal will again require the recovery code.';

  @override
  String get finishForcedTitle => 'Finish forced removal?';

  @override
  String get finishForcedBody =>
      'The 48-hour wait is complete. Removing Device Owner now lifts every restriction this app enforces on this device.';

  @override
  String get understandRemovesAll => 'I understand this removes all protection';

  @override
  String get removeDeviceOwnerAction => 'Remove Device Owner';

  @override
  String get deviceOwnerRemovedVerified => 'Device Owner removed (verified).';

  @override
  String get dnsSettingsTitle => 'Private DNS settings';

  @override
  String get dnsCustom => 'Custom';

  @override
  String get dnsHostnameLabel => 'DNS hostname';

  @override
  String get dnsHostnameHint => 'dns.example.com';

  @override
  String get dnsInvalidHostname => 'Invalid DNS hostname';

  @override
  String get apply => 'Apply';

  @override
  String get dnsTimeoutError =>
      'Applying the DNS host timed out. Check the current DNS state before retrying.';

  @override
  String get dnsNotServingError =>
      'The chosen DNS host is not serving. Pick another host.';

  @override
  String get dnsApplyFailedError => 'Failed to apply the private DNS host.';

  @override
  String dnsAppliedVerified(String host) {
    return 'Private DNS forced to $host (verified).';
  }

  @override
  String get newBlocklist => 'New blocklist';

  @override
  String get editBlocklist => 'Edit blocklist';

  @override
  String get titleLabel => 'Title';

  @override
  String get sitesLabel => 'Sites, one per line (e.g. example.com)';

  @override
  String appliedToBrowsers(int count) {
    return 'Applied to $count browser(s), verified.';
  }

  @override
  String get supportingBrowsers => 'Supporting browsers';

  @override
  String get noSupportingBrowser =>
      'No installed browser declares URLBlocklist in its managed restrictions, so there is nothing to push policy to. Browsers without support are handled by suspension rules (v1.1 auto-suspension).';

  @override
  String get blocklists => 'Blocklists';

  @override
  String get noBlocklists =>
      'No blocklists yet. Create one to start blocking sites.';

  @override
  String sitesCount(int count) {
    return '$count site(s)';
  }

  @override
  String get applyBlocklists => 'Apply blocklists to browsers';

  @override
  String get loadingBlocklists => 'Loading blocklists…';

  @override
  String get activeBlockingWords => 'Active blocking words';

  @override
  String get oneWordPerLine => 'One word or phrase per line';

  @override
  String get appsWhereWordsBlock => 'Apps where active words block';

  @override
  String onScreenWordsFor(String app) {
    return 'On-screen words for $app';
  }

  @override
  String get loadingBlockedWords => 'Loading blocked words…';

  @override
  String get activeBlockingSection => 'Active blocking (F14)';

  @override
  String get activeBlockingBody =>
      'When a word is present in the text field of a chosen app and typing ends, the app is backed out of and a block screen shows.';

  @override
  String wordsCount(int count) {
    return '$count word(s)';
  }

  @override
  String targetAppsCount(int count) {
    return '$count target app(s)';
  }

  @override
  String get passiveBlockingSection => 'Passive blocking (F15)';

  @override
  String get passiveBlockingBody =>
      'Words appearing anywhere on screen in a specific app.';

  @override
  String get noPerAppLists => 'No per-app lists yet.';

  @override
  String get addTargetAppsFirst =>
      'Add target apps above first — passive lists attach to them in v1.';

  @override
  String get addPerAppList => 'Add per-app list';

  @override
  String get loadingWarningStages => 'Loading warning stages…';

  @override
  String get stagedWarningsTitle => 'Staged warnings before a limit expires';

  @override
  String get warningsBody =>
      'Each stage warns once, the configured number of minutes before an app\'s daily limit runs out. Stages are stored for the Accessibility Service to fire; notification delivery depends on the native notifier.';

  @override
  String get noWarningStages =>
      'No warning stages. Add at least one stage or no warnings will be shown.';

  @override
  String get addStage => 'Add stage';

  @override
  String get minutesBeforeLabel => 'Minutes before';

  @override
  String get removeStage => 'Remove stage';

  @override
  String get silent => 'Silent';

  @override
  String get sound => 'Sound';

  @override
  String get vibrate => 'Vibrate';

  @override
  String get vibrationCount => 'Vibration count';

  @override
  String get clearLogsTooltip => 'Clear logs (recovery session required)';

  @override
  String get searchLogs => 'Search logs';

  @override
  String get loadingLogs => 'Loading logs…';

  @override
  String get noSuspensionsLogged => 'No suspensions have been logged.';

  @override
  String get impulseLockTitle => 'Impulse lock';

  @override
  String get loadingImpulseLock => 'Loading impulse lock…';

  @override
  String impulseActiveTitle(String remaining) {
    return 'Impulse lock active — $remaining left';
  }

  @override
  String get impulseActiveBody =>
      'Like the original, the lock has no early stop: it ends on its own when the timer runs out, and the apps it suspended are released then.';

  @override
  String startImpulseLockFor(int minutes) {
    return 'Start impulse lock ($minutes min)';
  }

  @override
  String get settingsLockedTitle => 'Settings are locked';

  @override
  String get settingsLockedBody =>
      'Impulse lock settings can only be changed during a recovery session. Tap to open one.';

  @override
  String get configurationSection => 'Configuration';

  @override
  String get durationLabel => 'Duration';

  @override
  String durationSubtitle(int minutes) {
    return '$minutes minutes (15–360)';
  }

  @override
  String minutesSliderLabel(int minutes) {
    return '$minutes min';
  }

  @override
  String get timerOnly => 'Timer only';

  @override
  String get timerAndSuspend => 'Timer + suspend chosen apps';

  @override
  String appsToSuspendCount(int count) {
    return '$count app(s) to suspend';
  }

  @override
  String get accessChallengesTitle =>
      'Access challenges (before a recovery session)';

  @override
  String get accessChallengesBody =>
      'The recovery code is asked for first; the selected challenges then run, in order, before the session starts.';

  @override
  String get challengeUnavailableNote =>
      'Not available in this version — v1.1. It can be selected in stored config but is skipped, never simulated.';

  @override
  String get shuffledKeypadTitle => 'Shuffled keypad for recovery code';

  @override
  String get shuffledKeypadSub =>
      'So the code cannot be learned from finger positions (F24).';

  @override
  String customPhrasesCount(int count) {
    return '$count custom reading phrase(s)';
  }

  @override
  String get customPhrasesSub => 'Added to the bundled reading passages';

  @override
  String get customReadingPhrases => 'Custom reading phrases';

  @override
  String get onePhrasePerLine => 'One phrase per line (your own words)';

  @override
  String get appsSuspendedDuringImpulse => 'Apps suspended during impulse lock';

  @override
  String get focusModeTitle => 'Focus mode';

  @override
  String get loadingFocusMode => 'Loading focus mode…';

  @override
  String get phaseNotStarted => 'Not started';

  @override
  String get phaseFocusing => 'Focusing';

  @override
  String get phaseBreak => 'Break';

  @override
  String get phaseLongBreak => 'Long break';

  @override
  String get phaseWaiting => 'Waiting';

  @override
  String get phasePaused => 'Paused';

  @override
  String get phaseDone => 'Done';

  @override
  String ringIdleSummary(int focus, int breakTime) {
    return '$focus min focus · $breakTime min break';
  }

  @override
  String get waitingNextFocus => 'Waiting to start the next focus';

  @override
  String cycleOf(int current, int total) {
    return 'Cycle $current of $total';
  }

  @override
  String completedFocusPeriods(int count) {
    return 'Completed focus periods: $count';
  }

  @override
  String get start => 'Start';

  @override
  String get startFocusBtn => 'Start focus';

  @override
  String get endSessionBtn => 'End session';

  @override
  String get pauseBtn => 'Pause';

  @override
  String get endRecoveryBtn => 'End (recovery)';

  @override
  String get resumeBtn => 'Resume';

  @override
  String get skipBreakBtn => 'Skip break';

  @override
  String get focusWaitingBody =>
      'The break is over. Nothing is suspended while waiting — start the next focus when ready, or end the session.';

  @override
  String get focusFocusBody =>
      'Pause is free while the apps stay suspended. Long-press Pause to release them instead (recovery session required).';

  @override
  String get focusDefaultBody =>
      'The session is kept by the native focus service: it survives this app being closed, holds its suspensions between phases, and this screen mirrors it.';

  @override
  String get durationsSection => 'Durations';

  @override
  String get focusMinutesLabel => 'Focus minutes';

  @override
  String get breakMinutesLabel => 'Break minutes';

  @override
  String get longBreakMinutesLabel => 'Long break minutes';

  @override
  String get cyclesLabel => 'Cycles before long break';

  @override
  String get autoStartTitle => 'Auto-start next focus';

  @override
  String get autoStartSub =>
      'Start the next focus phase by itself when a break ends; otherwise the session waits. Turning it off is a loosening.';

  @override
  String get soundTitle => 'Sound';

  @override
  String get soundSub => 'Play a sound at phase changes.';

  @override
  String get vibrationTitle => 'Vibration';

  @override
  String get vibrationSub => 'Vibrate at phase changes.';

  @override
  String get suspendedWhileFocusing => 'Suspended while focusing';

  @override
  String appsSuspendedWhileFocusing(int count) {
    return '$count app(s) suspended while focusing';
  }

  @override
  String groupsSuspendedWhileFocusing(int count) {
    return '$count group(s) suspended while focusing';
  }

  @override
  String restrictionsAppliedWhileFocusing(int count) {
    return '$count restriction(s) applied while focusing';
  }

  @override
  String get focusSchedulesTitle => 'Focus schedules & reminders';

  @override
  String get focusSchedulesNote =>
      'Scheduled auto-start sessions are not in this version.';

  @override
  String get appsToSuspendWhileFocusing => 'Apps to suspend while focusing';

  @override
  String get groupsToSuspendWhileFocusing => 'Groups to suspend while focusing';

  @override
  String get noGroupsYet => 'No groups yet';

  @override
  String groupAppsCount(int count) {
    return '$count app(s)';
  }

  @override
  String get restrictionsDuringFocus => 'Restrictions during focus';

  @override
  String get noDeviceOwnerPrivileges => 'No Device Owner privileges';

  @override
  String get noOwnerBody =>
      'System restrictions only work while Dominanter is the Device Owner. Complete the Setup flow first — restrictions are not faked without it.';

  @override
  String get openSetup => 'Open Setup';

  @override
  String get restrictionsUpdatedVerified =>
      'Restrictions updated and verified.';

  @override
  String get searchRestrictions => 'Search restrictions';

  @override
  String get loadingRestrictions => 'Loading restrictions…';

  @override
  String get recommendedSection => 'Recommended';

  @override
  String get otherRestrictionsSection => 'Other restrictions';

  @override
  String get changedNotApplied => 'Changed — not applied yet';

  @override
  String get applying => 'Applying…';

  @override
  String get applyChanges => 'Apply changes';

  @override
  String get activeBadge => 'Active';

  @override
  String get searchApps => 'Search apps';

  @override
  String get includeSystemApps => 'Include system apps';

  @override
  String get appGroups => 'App groups';

  @override
  String get appGroupsSub => 'Shared limits and windows for a set of apps';

  @override
  String get loadingInstalledApps => 'Loading installed apps…';

  @override
  String get noAppsMatch =>
      'No apps match. Try a different search, or include system apps.';

  @override
  String get stateSystem => 'system';

  @override
  String get stateHidden => 'hidden';

  @override
  String get stateSuspended => 'suspended';

  @override
  String get stateUninstallBlocked => 'uninstall blocked';

  @override
  String usedTodaySuffix(String duration) {
    return 'used $duration today';
  }

  @override
  String get suspendedTitle => 'Suspended';

  @override
  String get suspendedSub => 'The app cannot be opened while suspended.';

  @override
  String get hiddenTitle => 'Hidden';

  @override
  String get hiddenSub => 'Removed from the launcher and app list.';

  @override
  String get uninstallBlockedTitle => 'Uninstall blocked';

  @override
  String suspensionEnabledFor(String app) {
    return 'Suspension enabled for $app';
  }

  @override
  String hidingEnabledFor(String app) {
    return 'Hiding enabled for $app';
  }

  @override
  String uninstallBlockEnabledFor(String app) {
    return 'Uninstall block enabled for $app';
  }

  @override
  String timeLimitUpdatedFor(String app) {
    return 'Time limit updated for $app';
  }

  @override
  String timeWindowsUpdatedFor(String app) {
    return 'Time windows updated for $app';
  }

  @override
  String groupMembersUpdated(String group) {
    return 'Members of $group updated';
  }

  @override
  String groupLimitUpdated(String group) {
    return 'Limit of $group updated';
  }

  @override
  String restrictionsUpdatedFor(String app) {
    return 'Restrictions updated for $app';
  }

  @override
  String get timeLimitTile => 'Time limit';

  @override
  String get loadingEllipsis => 'Loading…';

  @override
  String todayLimit(String limit) {
    return 'Today: $limit';
  }

  @override
  String get perWeekdaySuffix => ' (per-weekday)';

  @override
  String get noLimitSet => 'No limit set';

  @override
  String get allowedWindowsTile => 'Allowed time windows';

  @override
  String windowsCount(int count) {
    return '$count window(s)';
  }

  @override
  String get usableAnyTime => 'Usable at any time';

  @override
  String get managedRestrictionsTile => 'Managed restrictions';

  @override
  String get managedRestrictionsSub =>
      'Edit this app\'s declared managed configuration';

  @override
  String get timeLimitDialogTitle => 'Time limit (minutes)';

  @override
  String get dailySegment => 'Daily';

  @override
  String get perWeekdaySegment => 'Per weekday';

  @override
  String get minutesPerDayLabel => 'Minutes per day (0 = no limit)';

  @override
  String dayNoLimit(String day) {
    return '$day (0 = no limit)';
  }

  @override
  String get reopenLabel =>
      'Reopening cooldown, seconds (stored; enforcement is v1.1)';

  @override
  String get dayMon => 'Mon';

  @override
  String get dayTue => 'Tue';

  @override
  String get dayWed => 'Wed';

  @override
  String get dayThu => 'Thu';

  @override
  String get dayFri => 'Fri';

  @override
  String get daySat => 'Sat';

  @override
  String get daySun => 'Sun';

  @override
  String get allowedWindowsTitle => 'Allowed windows (daily)';

  @override
  String get windowsBody =>
      'Outside these windows the app is blocked. An empty list means usable at any time.';

  @override
  String get noWindowsSet => 'No windows set.';

  @override
  String get addWindow => 'Add window';

  @override
  String get windowStartHelp => 'Window start';

  @override
  String get windowEndHelp => 'Window end (may be next day)';

  @override
  String get appGroupsTitle => 'App groups';

  @override
  String get newGroupTooltip => 'New group';

  @override
  String get loadingGroups => 'Loading groups…';

  @override
  String get noGroupsYetEmpty =>
      'No groups yet. Create one to share a limit across apps.';

  @override
  String get newGroup => 'New group';

  @override
  String get groupNameLabel => 'Group name';

  @override
  String get create => 'Create';

  @override
  String get renameGroup => 'Rename group';

  @override
  String groupAppsLimitLine(int count, String limit) {
    return '$count apps · limit $limit';
  }

  @override
  String get editMembers => 'Edit members';

  @override
  String get editLimit => 'Edit limit';

  @override
  String get renameGroupAction => 'Rename group';

  @override
  String get deleteGroup => 'Delete group';

  @override
  String membersOf(String group) {
    return 'Members of $group';
  }

  @override
  String restrictionsForApp(String app) {
    return 'Restrictions — $app';
  }

  @override
  String get loadingDeclaredRestrictions => 'Loading declared restrictions…';

  @override
  String noRestrictionsForApp(String app) {
    return 'No restrictions available for $app. This app does not declare any managed restrictions.';
  }

  @override
  String get clearAllRestrictions => 'Clear all restrictions';

  @override
  String clearAllBody(String app) {
    return 'Remove every managed restriction for $app? This only edits the draft — tap Save to apply it.';
  }

  @override
  String get unsavedChangesTitle => 'Unsaved changes';

  @override
  String get unsavedChangesBody =>
      'You have unsaved restriction changes. Discard them?';

  @override
  String get keepEditing => 'Keep editing';

  @override
  String get discard => 'Discard';

  @override
  String get allFilter => 'All';

  @override
  String activeFilterCount(int count) {
    return 'Active ($count)';
  }

  @override
  String defaultFilterCount(int count) {
    return 'Default ($count)';
  }

  @override
  String noRestrictionsMatching(String query) {
    return 'No restrictions matching \"$query\"';
  }

  @override
  String noRestrictionsAvailableFor(String app) {
    return 'No restrictions available for $app';
  }

  @override
  String get savingEllipsis => 'Saving…';

  @override
  String get saveRestrictions => 'Save restrictions';

  @override
  String get seeMore => 'See more';

  @override
  String get seeLess => 'See less';

  @override
  String get enabledLabel => 'Enabled';

  @override
  String get disabledLabel => 'Disabled';

  @override
  String unsupportedRestrictionType(String type) {
    return 'Unsupported restriction type: $type';
  }

  @override
  String get removeValue => 'Remove value';

  @override
  String get addValueLabel => 'Add value';

  @override
  String get addValueTooltip => 'Add value';

  @override
  String itemNumber(int number) {
    return 'Item $number';
  }

  @override
  String get removeItem => 'Remove item';

  @override
  String get addItem => 'Add item';

  @override
  String get brandTagline => 'BREAK THE CHAIN';

  @override
  String get lockedTitle => 'Dominanter is locked';

  @override
  String get startFocusAction => 'Start focus';

  @override
  String get skipBreakAction => 'Skip break';

  @override
  String get pauseAction => 'Pause';

  @override
  String get resumeAction => 'Resume';

  @override
  String focusCycleTitle(int current, int total) {
    return 'Focus $current/$total';
  }

  @override
  String get focusPausedSuffix => ' · paused';

  @override
  String get focusShortBreak => 'Short break';

  @override
  String get focusLongBreak => 'Long break';

  @override
  String get focusBreakOver => 'Break over';

  @override
  String focusSuspendingSummary(int minutes) {
    return '$minutes min of focus, suspending the selected apps';
  }

  @override
  String get groupsSection => 'Groups';

  @override
  String get appsSection => 'Apps';

  @override
  String get gateBody =>
      'Enter your recovery code to open a 10-minute session. Your configured access challenges run only after the code is accepted.';

  @override
  String provisionOutput(String path, String output) {
    return 'Path used: $path\n$output';
  }

  @override
  String get noStoreMsg =>
      'No store or browser could be opened for the Shizuku page.';

  @override
  String get setupAndOwner => 'Setup & Device Owner';

  @override
  String get setupTitle => 'Setup';

  @override
  String get dnsNeedsOwnerMsg =>
      'Private DNS requires Device Owner — finish Setup first.';

  @override
  String get forcedRemovalTitle => '48-hour forced removal';

  @override
  String forcedInProgressSub(String remaining) {
    return 'In progress — $remaining remaining (advances while the app is running)';
  }

  @override
  String get dnsApplyTimeout =>
      'Applying the DNS host timed out. Check the current DNS state before retrying.';

  @override
  String get dnsNotServing =>
      'The chosen DNS host is not serving. Pick another host.';

  @override
  String get dnsApplyFailed => 'Failed to apply the private DNS host.';

  @override
  String dnsAppliedMsg(String host) {
    return 'Private DNS forced to $host (verified).';
  }

  @override
  String get ownerStillActiveMsg =>
      'Device Owner is still active after removal';

  @override
  String get noCapableBrowser =>
      'No installed browser declares URLBlocklist in its managed restrictions, so there is nothing to push policy to. Browsers without support are handled by suspension rules (v1.1 auto-suspension).';

  @override
  String get blocklistsSection => 'Blocklists';

  @override
  String get noBlocklistsYet =>
      'No blocklists yet. Create one to start blocking sites.';

  @override
  String get usageWarningsBody =>
      'Each stage warns once, the configured number of minutes before an app\'s daily limit runs out. Stages are stored for the Accessibility Service to fire; notification delivery depends on the native notifier.';

  @override
  String get removeStageTooltip => 'Remove stage';

  @override
  String get vibrationCountLabel => 'Vibration count';

  @override
  String get noLogsYet => 'No suspensions have been logged.';

  @override
  String impulseActiveLeft(String time) {
    return 'Impulse lock active — $time left';
  }

  @override
  String get impulseNoEarlyStop =>
      'Like the original, the lock has no early stop: it ends on its own when the timer runs out, and the apps it suspended are released then.';

  @override
  String startImpulseLock(int minutes) {
    return 'Start impulse lock ($minutes min)';
  }

  @override
  String get settingsLocked => 'Settings are locked';

  @override
  String get settingsLockedSub =>
      'Impulse lock settings can only be changed during a recovery session. Tap to open one.';

  @override
  String durationMinutes(int minutes) {
    return '$minutes minutes (15–360)';
  }

  @override
  String minutesShort(int minutes) {
    return '$minutes min';
  }

  @override
  String get accessChallengesSection =>
      'Access challenges (before a recovery session)';

  @override
  String get shuffledKeypad => 'Shuffled keypad for recovery code';

  @override
  String focusIdleSummary(int focus, int breakTime) {
    return '$focus min focus · $breakTime min break';
  }

  @override
  String get startAction => 'Start';

  @override
  String get endRecovery => 'End (recovery)';

  @override
  String get waitingBody =>
      'The break is over. Nothing is suspended while waiting — start the next focus when ready, or end the session.';

  @override
  String get focusPauseNote =>
      'Pause is free while the apps stay suspended. Long-press Pause to release them instead (recovery session required).';

  @override
  String get focusNativeNote =>
      'The session is kept by the native focus service: it survives this app being closed, holds its suspensions between phases, and this screen mirrors it.';

  @override
  String groupsSuspendedCount(int count) {
    return '$count group(s) suspended while focusing';
  }

  @override
  String restrictionsAppliedCount(int count) {
    return '$count restriction(s) applied while focusing';
  }

  @override
  String memberCount(int count) {
    return '$count app(s)';
  }

  @override
  String get noOwnerRestrictionsBody =>
      'System restrictions only work while Dominanter is the Device Owner. Complete the Setup flow first — restrictions are not faked without it.';

  @override
  String get restrictionsUpdated => 'Restrictions updated and verified.';

  @override
  String usedToday(String time) {
    return 'used $time today';
  }

  @override
  String get badgeSystem => 'system';

  @override
  String get badgeHidden => 'hidden';

  @override
  String get badgeSuspended => 'suspended';

  @override
  String get badgeUninstallBlocked => 'uninstall blocked';

  @override
  String get loadingShort => 'Loading…';

  @override
  String todayLimitLine(String limit) {
    return 'Today: $limit';
  }

  @override
  String get managedRestrictions => 'Managed restrictions';

  @override
  String timeLimitUpdatedDesc(String app) {
    return 'Time limit updated for $app';
  }

  @override
  String timeWindowsUpdatedDesc(String app) {
    return 'Time windows updated for $app';
  }

  @override
  String get timeLimitEditorTitle => 'Time limit (minutes)';

  @override
  String dayLimitLabel(String day) {
    return '$day (0 = no limit)';
  }

  @override
  String get noGroupsYetMsg =>
      'No groups yet. Create one to share a limit across apps.';

  @override
  String membersUpdatedDesc(String name) {
    return 'Members of $name updated';
  }

  @override
  String groupLimitUpdatedDesc(String name) {
    return 'Limit of $name updated';
  }

  @override
  String noRestrictionsFor(String app) {
    return 'No restrictions available for $app. This app does not declare any managed restrictions.';
  }

  @override
  String restrictionsForTitle(String app) {
    return 'Restrictions — $app';
  }

  @override
  String get unsavedTitle => 'Unsaved changes';

  @override
  String get unsavedBody =>
      'You have unsaved restriction changes. Discard them?';

  @override
  String get saving => 'Saving…';

  @override
  String unsupportedType(String type) {
    return 'Unsupported restriction type: $type';
  }

  @override
  String get removeValueTooltip => 'Remove value';

  @override
  String get removeItemTooltip => 'Remove item';

  @override
  String restrictionsUpdatedDesc(String app) {
    return 'Restrictions updated for $app';
  }
}
