// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Azm';

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
      'Shizuku permission has not been granted to Azm.';

  @override
  String get errShizukuPreV11 =>
      'This Shizuku server is older than v11. Update Shizuku, then retry.';

  @override
  String get errShizukuBinderDead =>
      'The Shizuku connection dropped during the operation. Its outcome is unknown — check the current state before retrying.';

  @override
  String get errShellFailed => 'A system command failed.';

  @override
  String get errProvisioningFailed =>
      'Device Owner provisioning failed on both the direct and the fallback path. See Diagnostics on the Setup screen.';

  @override
  String get errDpmNotOwner =>
      'Azm is not the Device Owner, so this operation is not available. Complete Setup first.';

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
  String get errInvalidArgument =>
      'Some of the information entered is not valid. Please check it and try again.';

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
  String get startingAzm => 'Starting Azm…';

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
  String get lockTitle => 'Azm is locked';

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
    return 'Azm $version';
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
  String get unlockReason => 'Unlock Azm';

  @override
  String get authNotCompleted => 'Authentication was not completed.';

  @override
  String authFailed(String message) {
    return 'Authentication failed: $message';
  }

  @override
  String get authCouldNotStart =>
      'Authentication could not start. Please try again.';

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
      'Set an app password as another way to open Azm from the lock screen. The password only opens the app — loosening restrictions or removing Device Owner still needs the recovery code.';

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
  String get tipGenerates => 'Azm generates a 16-letter code';

  @override
  String get tipWrite => 'Write the code down on a piece of paper';

  @override
  String get tipTypeBack => 'Type it back to make sure it\'s correct';

  @override
  String get tipStorePaper => 'Store the paper in a safe place';

  @override
  String get wizardIntroBody =>
      'The code will be asked for whenever you change Azm\'s settings. Without it, you could be locked out of the blocked features. It is stored only as a salted hash on this device — it cannot be shown again after this wizard, and there is no account or cloud copy.';

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
  String get firstRunTitle => 'Azm — first run';

  @override
  String get gateCodeTitle => 'Enter recovery code';

  @override
  String get gateIntroText =>
      'Enter your recovery code to open a 10-minute session.';

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
      'Shizuku is installed, but its server is not running. Azm cannot start it — open the Shizuku app and start the server (via wireless debugging or ADB), then pull to refresh.';

  @override
  String get shizukuPreV11Title => 'Shizuku: too old (pre-v11)';

  @override
  String get shizukuPreV11Body =>
      'This Shizuku server predates v11 and cannot run commands. Update Shizuku, restart its server, then refresh.';

  @override
  String get shizukuNoPermissionTitle => 'Shizuku: permission needed';

  @override
  String get shizukuNoPermissionBody =>
      'The server is running. Grant Azm permission in Shizuku to continue setup.';

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
      'Permission not granted yet. Approve Azm in Shizuku, then tap Request again.';

  @override
  String get noStoreOpenedMsg =>
      'No store or browser could be opened for the Shizuku page.';

  @override
  String get shizukuDetectedMsg => 'Shizuku detected.';

  @override
  String get deviceOwnerTitle => 'Device Owner';

  @override
  String get deviceOwnerYes => 'Azm is the Device Owner of this device.';

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
    return '$packageName is already the Device Owner of this device ($receiver).\n\nA device can have only one Device Owner. That app must relinquish ownership (or the device must be factory-reset) before Azm can be provisioned. This matches the original app, which replaces the provisioning button with this warning.';
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
      'Grayscale, night light, extra dim and colour inversion — scheduled and per app.';

  @override
  String get activityBlocker => 'Activity blocker';

  @override
  String get activityBlockerNote =>
      'Block specific activity screens; the launcher and system apps can never be blocked.';

  @override
  String get removalStepColourModes => 'Colour modes released';

  @override
  String get browserUnsupportedWarning =>
      'Restrictions do not work in this browser, it is recommended to disable it.';

  @override
  String get refresh => 'Refresh';

  @override
  String get loading => 'Loading…';

  @override
  String get block => 'Block';

  @override
  String get blocked => 'Blocked';

  @override
  String get unblock => 'Unblock';

  @override
  String get activityBlockerDescription =>
      'When a blocked activity opens, Azm sends it back. The launcher, system UI, Settings, calls and Azm itself can never be blocked.';

  @override
  String get blockedActivities => 'Blocked activities';

  @override
  String get noBlockedActivities => 'No activities blocked yet.';

  @override
  String get recentlyAccessedActivities => 'Recently accessed';

  @override
  String get noAccessedActivities =>
      'No activities seen yet — open some apps and come back.';

  @override
  String activitiesCount(int count) {
    return '$count activities';
  }

  @override
  String get unblockActivityConfirmTitle => 'Unblock this activity?';

  @override
  String unblockActivityConfirmMessage(String activity) {
    return '“$activity” will be allowed to open again.';
  }

  @override
  String get addActivityTitle => 'Block an activity';

  @override
  String get addActivityBody =>
      'Enter the full activity class name, as shown in the recently accessed list.';

  @override
  String get activityClassNameLabel => 'Activity class name';

  @override
  String get addActivityInvalid =>
      'Enter a full class name, e.g. com.example.app.MainActivity.';

  @override
  String get addActivityProtected =>
      'This activity is protected and can never be blocked.';

  @override
  String get addActivityAlreadyBlocked => 'This activity is already blocked.';

  @override
  String get colourModesDescription =>
      'Make the screen less stimulating: grayscale, night light, extra dim and colour inversion, on schedules and per app. A mode that is on right now cannot be loosened without the recovery code.';

  @override
  String get colourModesStatusTitle => 'Status';

  @override
  String get colourModesStatusNoAccessibility =>
      'Accessibility service is off — colour modes cannot apply. Turn it on below.';

  @override
  String get colourModesStatusNoGrant =>
      'WRITE_SECURE_SETTINGS is not granted — enable the feature below to grant it via Shizuku.';

  @override
  String get colourModesStatusUnsupported =>
      'This device could not apply the grayscale keys — the feature may not work here.';

  @override
  String colourModesStatusActive(String modes) {
    return 'Active now: $modes';
  }

  @override
  String get colourModesStatusIdle => 'Enabled — no mode is active right now.';

  @override
  String get colourModesStatusOff => 'Off.';

  @override
  String get colourModesEnableTitle => 'Colour modes';

  @override
  String get colourModesEnable => 'Enable colour modes';

  @override
  String colourModesSummaryActive(String modes) {
    return 'Active: $modes';
  }

  @override
  String get colourModesSummaryIdle => 'Enabled — nothing active right now';

  @override
  String get colourModesSummaryOff => 'Off';

  @override
  String get colourModeGrayscale => 'Grayscale';

  @override
  String get colourModeGrayscaleDesc => 'Removes all colour from the screen.';

  @override
  String get colourModeNightLight => 'Night light';

  @override
  String get colourModeNightLightDesc => 'Warms the screen colours at night.';

  @override
  String get colourModeExtraDim => 'Extra dim';

  @override
  String get colourModeExtraDimDesc =>
      'Dims the screen below its lowest brightness.';

  @override
  String get colourModeInversion => 'Colour inversion';

  @override
  String get colourModeInversionDesc => 'Inverts all colours on screen.';

  @override
  String get colourModeExtraDimUnavailable =>
      'Extra dim is not available on this device.';

  @override
  String colourModeLockedUntil(String time) {
    return 'Locked until $time — the recovery code opens it.';
  }

  @override
  String get colourModeLockedActive =>
      'Locked while active — the recovery code opens it.';

  @override
  String get colourModesLockedTitle => 'Locked right now';

  @override
  String colourModesLockedMessage(String modes) {
    return '$modes is on right now, so it cannot be loosened without the recovery code.';
  }

  @override
  String get openRecoveryGate => 'Open recovery gate';

  @override
  String get colourModesNeedAccessibilityTitle =>
      'Accessibility service is off';

  @override
  String get colourModesNeedAccessibility =>
      'Colour modes are enforced by the accessibility service. Enable it now?';

  @override
  String get enableAccessibility => 'Enable accessibility';

  @override
  String get accessibilityStillDisabled => 'Accessibility is still off.';

  @override
  String get secureSettingsGrantFailed =>
      'The WRITE_SECURE_SETTINGS grant failed.';

  @override
  String get nightLightTemperature => 'Temperature';

  @override
  String nightLightIntensity(int value) {
    return 'Intensity: $value';
  }

  @override
  String extraDimLevel(int value) {
    return 'Dim level: $value';
  }

  @override
  String colourWindowsLabel(String windows) {
    return 'Windows: $windows';
  }

  @override
  String get colourWindowsAlways => 'Always, while enabled';

  @override
  String get editWindows => 'Edit windows';

  @override
  String get colourScopeDevice => 'Whole device';

  @override
  String get colourScopeExceptApps => 'All apps except…';

  @override
  String get colourScopeOnlyApps => 'Only these apps…';

  @override
  String colourScopeAppsTitle(String mode) {
    return 'Apps for $mode';
  }

  @override
  String colourScopeAppsCount(int count) {
    return '$count apps chosen';
  }

  @override
  String get applyDuringFocus => 'Also apply during focus sessions';

  @override
  String get applyDuringFocusDesc =>
      'Grayscale stays on for the whole focus phase, even outside the windows above.';

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
  String get forcedIdleSub =>
      'The only code-free escape: after 24 hours, Device Owner can be removed without the recovery code.';

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
      'This starts a 24-hour countdown. When it finishes, Device Owner — and with it every restriction this app enforces — can be removed without the recovery code. It is the only code-free escape, and it can be cancelled at any time before it completes.';

  @override
  String get cancelForcedTitle => 'Cancel forced removal?';

  @override
  String get cancelForcedBody =>
      'The 24-hour countdown will be discarded. Device Owner removal will again require the recovery code.';

  @override
  String get finishForcedTitle => 'Finish forced removal?';

  @override
  String get finishForcedBody =>
      'The 24-hour wait is complete. Removing Device Owner now lifts every restriction this app enforces on this device.';

  @override
  String get understandRemovesAll => 'I understand this removes all protection';

  @override
  String get removeDeviceOwnerAction => 'Remove Device Owner';

  @override
  String get deviceOwnerRemovedVerified => 'Device Owner removed (verified).';

  @override
  String get removalCompleteTitle => 'Protection fully removed';

  @override
  String get removalCompleteBody =>
      'Azm\'s protection has been completely removed: no restrictions remain, no app is suspended or hidden by Azm, and nothing of Azm is still running. You can now uninstall normally from your system settings.';

  @override
  String get removalPartialTitle => 'Protection removed, with warnings';

  @override
  String get removalPartialBody =>
      'Device Owner was removed, but some cleanup steps did not complete. You can try again, or uninstall normally — Android discards any remaining owner policies when the app is uninstalled.';

  @override
  String get removalStepDisarm => 'Disarm safeguards';

  @override
  String get removalStepFocus => 'Stop focus mode';

  @override
  String get removalStepUnsuspend => 'Unsuspend apps';

  @override
  String get removalStepRestrictions => 'Clear restrictions';

  @override
  String get removalStepUnhide => 'Unhide apps';

  @override
  String get removalStepUninstallBlocks => 'Lift uninstall blocks';

  @override
  String get removalStepAppRestrictions => 'Clear per-app restrictions';

  @override
  String get info_disallow_biometric =>
      'Blocks biometric unlock (fingerprint/face) at the system level (Samsung key). This also affects signing into Azm itself if you rely on fingerprint entry — use with care.';

  @override
  String get info_disallow_camera_toggle =>
      'Blocks the camera privacy toggle (quick-settings sensor switch). Keeps the camera state from being changed from the sensor panel.';

  @override
  String get info_disallow_config_default_apps =>
      'Blocks changing the default apps (browser, dialer, SMS, assistant). Keeps your chosen safe defaults in place — for example, a filtered default browser stays the default.';

  @override
  String get info_disallow_config_private_dns =>
      'Blocks changing the Private DNS setting. Important if your filtering relies on a specific DNS resolver — changing it would silently disable the filter. Side effect: the DNS provider is frozen while it is on.';

  @override
  String get info_disallow_microphone_toggle =>
      'Blocks the microphone privacy toggle (Samsung/quick-settings sensor switch). Keeps the microphone state from being changed from the sensor panel.';

  @override
  String get info_ensure_verify_apps =>
      'Requires app verification (Play Protect-style scanning of installs) to stay on. Keeps a safety net against harmful apps; turning protections off is a common first step in bypass guides.';

  @override
  String get info_no_add_clone_profile =>
      'Blocks creating a clone profile or cloned apps (Samsung). Cloned apps are a second, separate copy that limits may not cover.';

  @override
  String get info_no_add_managed_profile =>
      'Blocks creating a work/managed profile. A separate profile can hold its own unfiltered apps.';

  @override
  String get info_no_add_private_profile =>
      'Blocks creating a private profile/space. A private space can hide apps from the main view and from casual checks.';

  @override
  String get info_no_add_user =>
      'Blocks creating new Android users on the device. A second user is a completely unfiltered space, so this closes a major bypass.';

  @override
  String get info_no_add_wifi_config =>
      'Blocks adding new Wi-Fi network configurations while leaving existing ones usable. A softer version of locking Wi-Fi completely.';

  @override
  String get info_no_adjust_volume =>
      'Blocks changing the volume. Sometimes used to keep warning sounds audible. Side effect: volume keys stop working for media and calls.';

  @override
  String get info_no_airplane_mode =>
      'Blocks turning on airplane mode. Prevents cutting connectivity to escape network filtering — though Wi-Fi can usually be rejoined. Side effect: no airplane mode for flights while it is on.';

  @override
  String get info_no_ambient_display =>
      'Blocks the ambient display (always-on glance screen). Minor display behaviour control.';

  @override
  String get info_no_assist_content =>
      'Blocks sharing screen content with the assistant. Privacy-oriented; the assistant loses screen context.';

  @override
  String get info_no_autofill =>
      'Blocks the autofill framework (password/form autofill). Security-oriented; side effect: no saved-password autofill anywhere.';

  @override
  String get info_no_bluetooth =>
      'Blocks using Bluetooth at all. Side effect: headphones, watches, and car connections stop working.';

  @override
  String get info_no_bluetooth_sharing =>
      'Blocks sharing files over Bluetooth while leaving Bluetooth audio working. A narrower, gentler option than blocking Bluetooth entirely.';

  @override
  String get info_no_camera =>
      'Blocks the camera entirely (Samsung key). Side effect: no app can take photos or video, including Azm-free uses like scanning documents.';

  @override
  String get info_no_change_wifi_state =>
      'Blocks turning Wi-Fi on or off. Useful when the connection state itself is part of the routine. Side effect: no quick Wi-Fi toggling from quick settings.';

  @override
  String get info_no_config_bluetooth =>
      'Blocks changing Bluetooth settings (pairing new devices). Side effect: new accessories cannot be paired while it is on.';

  @override
  String get info_no_config_brightness =>
      'Blocks changing screen brightness settings. Minor; mainly keeps display settings stable.';

  @override
  String get info_no_config_cell_broadcasts =>
      'Blocks changing cell broadcast (emergency alert) settings. Leave this off unless you have a specific reason — emergency alerts matter.';

  @override
  String get info_no_config_credentials =>
      'Blocks changing stored credentials and installing certificates. Important because a user-installed certificate can enable traffic interception and filter bypass. Side effect: work/school certificate setups are frozen.';

  @override
  String get info_no_config_date_time =>
      'Blocks changing the date and time. Protects time-based limits and schedules from being cheated by moving the clock. Side effect: manual time correction is off; automatic time still works.';

  @override
  String get info_no_config_locale =>
      'Blocks changing the system language/region settings. Keeps the device configuration stable.';

  @override
  String get info_no_config_location =>
      'Blocks changing location settings. Keeps location-based behaviour stable; it does not itself block content.';

  @override
  String get info_no_config_mobile_networks =>
      'Blocks changing mobile network settings (APN, network mode, operator). Useful because APN tricks can route around DNS filtering. Side effect: roaming and carrier settings are frozen too.';

  @override
  String get info_no_config_screen_timeout =>
      'Blocks changing the screen timeout. Keeps the display-off behaviour you chose; a minor routine protection.';

  @override
  String get info_no_config_tethering =>
      'Blocks changing any tethering settings (Wi-Fi, USB, Bluetooth hotspot). Keeps the phone from becoming a side door around network filtering.';

  @override
  String get info_no_config_vpn =>
      'Blocks changing VPN settings. Important: a VPN can bypass DNS-based filtering entirely, so locking VPN settings protects the whole setup. Side effect: you cannot add or switch VPNs while it is on.';

  @override
  String get info_no_config_wifi =>
      'Blocks changing Wi-Fi settings: joining new networks or forgetting saved ones. Useful against hopping to an unfiltered network. Side effect: you cannot join a new Wi-Fi network while it is on.';

  @override
  String get info_no_config_wifi_private =>
      'Blocks changing the private (randomized) MAC address setting for Wi-Fi (Samsung). Keeps network identity stable so network-level filters keep recognizing the device.';

  @override
  String get info_no_config_wifi_shared =>
      'Blocks changing shared Wi-Fi configuration options (Samsung). Keeps network settings from being quietly altered.';

  @override
  String get info_no_content_capture =>
      'Blocks apps from capturing screen content for features like screenshot-based assistants. A privacy control; may break some smart-selection features.';

  @override
  String get info_no_content_suggestions =>
      'Blocks content suggestions (smart replies/suggestions drawn from screen content). Privacy-oriented; minor.';

  @override
  String get info_no_control_apps =>
      'Blocks opening app-info screens where apps can be force-stopped, cleared, or have their permissions changed. Stops a common bypass route. Side effect: you also cannot manage app storage or permissions there while it is on.';

  @override
  String get info_no_create_windows =>
      'Blocks apps from drawing overlay windows on top of other apps. Increases security against tap-jacking, but breaks legitimate overlays like chat bubbles and some accessibility tools.';

  @override
  String get info_no_cross_profile_copy_paste =>
      'Blocks copy/paste between profiles. Stops text and links moving from the controlled profile into another one.';

  @override
  String get info_no_data_roaming =>
      'Blocks data roaming. Mostly a cost control; it does not filter content.';

  @override
  String get info_no_debugging_features =>
      'Blocks debugging features such as ADB. Prevents changing the device from a computer to bypass protection. Side effect: developers cannot debug this device while it is on.';

  @override
  String get info_no_factory_reset =>
      'Blocks factory reset from settings. Protects the whole setup from being wiped in a weak moment. This is a strong setting: recovery through Azm\'s own removal flow remains possible, but the settings route is closed.';

  @override
  String get info_no_fun =>
      'Blocks Android\'s fun/easter-egg features. Harmless and mostly cosmetic.';

  @override
  String get info_no_grant_admin =>
      'Blocks granting device-admin rights to other apps. Prevents another admin app from interfering with Azm\'s position.';

  @override
  String get info_no_install_apps =>
      'Blocks installing new apps entirely. Useful when you want the phone\'s current app set frozen. Side effect: even trusted apps cannot be added until this is off.';

  @override
  String get info_no_install_unknown_sources =>
      'Blocks installing apps from outside the Play Store (APK files, browsers, file managers). One of the strongest protections against sideloaded distractions and malware. Side effect: legitimate APK installs are also blocked.';

  @override
  String get info_no_install_unknown_sources_globally =>
      'The global version of the unknown-sources block: it applies everywhere on the device, for every user and profile. Stronger than the per-source setting, and it also blocks legitimate APK installs device-wide.';

  @override
  String get info_no_modify_accounts =>
      'Blocks adding or removing accounts on the device. A new account can be a fresh start that escapes app-level habits. Side effect: you cannot sign into new services at the system level while it is on.';

  @override
  String get info_no_network_reset =>
      'Blocks resetting network settings. A network reset can wipe saved Wi-Fi and DNS-related state in one tap.';

  @override
  String get info_no_non_market_app_by_knox =>
      'Blocks apps from outside the official stores at the Samsung Knox level. Knox\'s own sideloading block; may overlap with the unknown-sources restrictions.';

  @override
  String get info_no_outgoing_beam =>
      'Blocks Android Beam (NFC tap-to-share). A small side channel for passing links and files between phones.';

  @override
  String get info_no_outgoing_calls =>
      'Blocks making outgoing calls. A heavy restriction for communication control; emergency calls are never blocked by Android.';

  @override
  String get info_no_physical_media =>
      'Blocks mounting external storage (SD cards, USB drives). Closes a route for bringing in unfiltered content. Side effect: memory cards cannot be used while it is on.';

  @override
  String get info_no_printing =>
      'Blocks printing from the device. Minor; closes a route for exporting content to paper or PDF printers.';

  @override
  String get info_no_remove_managed_profile =>
      'Blocks removing the managed (work) profile. Keeps an existing managed space intact.';

  @override
  String get info_no_remove_user =>
      'Blocks removing existing Android users. Keeps the device\'s user structure unchanged.';

  @override
  String get info_no_safe_boot =>
      'Blocks booting into Safe Mode. Important: Safe Mode disables accessibility services and third-party enforcement, so it is a classic bypass. Side effect: Safe Mode troubleshooting is unavailable while it is on.';

  @override
  String get info_no_set_user_icon =>
      'Blocks changing the user profile picture. Cosmetic only.';

  @override
  String get info_no_set_wallpaper =>
      'Blocks changing the wallpaper. Cosmetic stability; occasionally used to keep a motivational wallpaper in place.';

  @override
  String get info_no_share_location =>
      'Blocks sharing the device\'s location with apps. A privacy protection rather than a content filter.';

  @override
  String get info_no_sharing_into_profile =>
      'Blocks sharing content from the main profile into another profile. Keeps content from being passed into a less-controlled space.';

  @override
  String get info_no_sim_globally =>
      'Blocks using the SIM entirely (calls and mobile data). A very heavy restriction — the phone loses mobile service while it is on.';

  @override
  String get info_no_sms =>
      'Blocks sending SMS messages. Communication control; messaging apps are unaffected.';

  @override
  String get info_no_system_error_dialogs =>
      'Blocks system error dialogs (app-crash popups). Cosmetic/enterprise behaviour; crashes still happen, just silently.';

  @override
  String get info_no_thread_network =>
      'Blocks creating/joining Thread border-router networks (smart-home). Niche; irrelevant for most phones.';

  @override
  String get info_no_ultra_wideband_radio =>
      'Blocks the ultra-wideband (UWB) radio used by precision trackers. Niche hardware control.';

  @override
  String get info_no_unified_password =>
      'Blocks requiring one unified password across work and personal profiles. Enterprise-oriented; irrelevant on a single-profile phone.';

  @override
  String get info_no_uninstall_apps =>
      'Blocks uninstalling apps. Useful to stop a blocked app from simply being deleted to escape its limits — and to protect Azm\'s companion setup. Side effect: you cannot remove any app while this is on.';

  @override
  String get info_no_unmute_microphone =>
      'Blocks unmuting the microphone during calls. A managed-device privacy control; rarely relevant for personal use.';

  @override
  String get info_no_usb_file_transfer =>
      'Blocks transferring files over USB. Prevents moving content on or off the phone by cable. Side effect: USB photo/file import stops too; charging still works.';

  @override
  String get info_no_user_switch =>
      'Blocks switching between Android users. Companions the no-new-users rule: even existing extra users cannot be entered.';

  @override
  String get info_no_wallpaper =>
      'Blocks wallpaper changes (Samsung key). Cosmetic stability, like the standard wallpaper restriction.';

  @override
  String get info_no_wifi_direct =>
      'Blocks Wi-Fi Direct connections (device-to-device sharing without a router). Closes a side channel for sharing files and content. Side effect: some printers and sharing features stop working.';

  @override
  String get info_no_wifi_tethering =>
      'Blocks Wi-Fi hotspot tethering settings. Prevents sharing the phone\'s connection to bypass filters on other devices.';

  @override
  String get restrictionInfoGeneric =>
      'This setting restricts part of the system. Turning it on tightens the device; turning it off loosens it. If you are not sure, leave it off and ask later.';

  @override
  String get errGeneric =>
      'Something went wrong. Please try again. If it keeps happening, restart the app.';

  @override
  String get errSealed =>
      'Removal is currently sealed by one of your seal rules.';

  @override
  String get errorCardTitle => 'Something went wrong';

  @override
  String get okButton => 'OK';

  @override
  String get entryGraceTitle => 'App lock timing';

  @override
  String get entryGraceSub =>
      'How long Azm stays open after you enter, before it asks for your fingerprint or password again';

  @override
  String get entryGraceImmediately => 'Immediately';

  @override
  String get entryGraceOneMinute => 'After 1 minute';

  @override
  String get entryGraceFifteenMinutes => 'After 15 minutes';

  @override
  String get entryGraceOneHour => 'After 1 hour';

  @override
  String get visualBlockingTitle => 'Content inspection';

  @override
  String get visualBlockingSub =>
      'On-device checking of images inside chosen apps';

  @override
  String get visualExplanation =>
      'Azm checks images on screen inside the apps you choose, using a model that runs entirely on this device. Nothing is uploaded. When inappropriate content is detected, the app is closed; repeated detections can suspend it. Text checking is separate: it is the blocked-words feature, which also works per app.';

  @override
  String get visualEnable => 'Inspect images in chosen apps';

  @override
  String get visualRequiresAccessibility =>
      'Requires the accessibility service to be on.';

  @override
  String get visualAppsSection => 'Apps to inspect';

  @override
  String visualAppsSelected(int count) {
    return '$count app(s) chosen';
  }

  @override
  String get visualSelectApps => 'Choose apps';

  @override
  String get visualCategoriesSection => 'Block when detected';

  @override
  String get visualCategoriesDesc =>
      'The kinds of content that close the app when the model finds them on screen.';

  @override
  String get visualCategoryDrawings => 'Drawings';

  @override
  String get visualCategoryHentai => 'Hentai';

  @override
  String get visualCategoryPorn => 'Pornography';

  @override
  String get visualCategorySexy => 'Sexy / suggestive';

  @override
  String get visualThresholdSection => 'Sensitivity';

  @override
  String get visualThresholdDesc =>
      'Higher means Azm blocks only when it is more certain. Lower blocks more, with more mistakes.';

  @override
  String get visualSuspend => 'Suspend app after repeated detections';

  @override
  String get visualSuspendDesc =>
      'After several detections in a short time, the app is suspended for a while instead of just being closed.';

  @override
  String get visualSuspendCount => 'Detections before suspending';

  @override
  String get visualSuspendWindow => 'Within (minutes)';

  @override
  String get visualSuspendDuration => 'Suspend for (minutes)';

  @override
  String get visualSaved => 'Content inspection settings saved.';

  @override
  String get sealRulesTitle => 'Seal rules';

  @override
  String get sealRulesSub => 'Conditions under which Azm refuses to be removed';

  @override
  String get sealIntro =>
      'While any seal rule is active, Azm refuses to remove Device Owner — immediately or by filing the delayed forced removal. A seal cannot be cancelled while it is active; it ends only when its time runs out or its condition clears. The paper recovery code does NOT break an active seal. A forced removal filed BEFORE a seal engaged still completes at its 24-hour mark. Seals have force only while Azm is Device Owner: without Device Owner, Android lets any app be uninstalled and no rule can prevent it.';

  @override
  String get sealNoRules => 'No seal rules yet.';

  @override
  String get sealAddRule => 'Add a seal rule';

  @override
  String get sealEditRule => 'Edit seal rule';

  @override
  String get sealDeleteRule => 'Delete rule';

  @override
  String get sealTrigger => 'Seal while / when';

  @override
  String get sealTriggerAppBlocked => 'A chosen app is blocked by Azm';

  @override
  String get sealTriggerAppSuspended => 'A chosen app is suspended by Azm';

  @override
  String get sealTriggerFocusRunning => 'A focus session is running';

  @override
  String get sealTriggerVisual =>
      'Inappropriate content is detected in a chosen app';

  @override
  String get sealTriggerWord => 'A banned word is detected in a chosen app';

  @override
  String get sealApp => 'App';

  @override
  String get sealChooseApp => 'Choose an app';

  @override
  String get sealDuration => 'Seal lasts';

  @override
  String get sealDuration30m => '30 minutes';

  @override
  String get sealDuration1h => '1 hour';

  @override
  String get sealDuration6h => '6 hours';

  @override
  String get sealDuration24h => '24 hours';

  @override
  String get sealDuration7d => '7 days';

  @override
  String get sealRuleEnabled => 'Rule enabled';

  @override
  String get sealActiveTitle => 'Seal active';

  @override
  String sealActiveCondition(String rule) {
    return 'A seal rule is holding: $rule. Removal is refused while it holds.';
  }

  @override
  String sealActiveTimed(String rule, String remaining) {
    return 'A seal rule is holding: $rule. About $remaining left.';
  }

  @override
  String sealStatusActive(String rule) {
    return 'Sealed: $rule';
  }

  @override
  String get sealNotEnforceable => 'Not enforceable: Azm is not Device Owner.';

  @override
  String get removalStepPolicies => 'Reset device policies';

  @override
  String get removalStepPrivateDns => 'Reset private DNS';

  @override
  String get removalStepNotifications => 'Cancel notifications';

  @override
  String get removalStepVerify => 'Post-removal verification';

  @override
  String get residueTitle => 'Leftover restrictions detected';

  @override
  String get residueBody =>
      'Some restrictions set by Azm are still in force on this device. Azm no longer has the rights to remove them. To clean up, provision Azm as Device Owner again from the Status tab, then run Remove Device Owner once more.';

  @override
  String get removalStepClearOwner => 'Remove Device Owner';

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
  String get accessChallengesTitle => 'Access challenges';

  @override
  String get accessChallengesBody =>
      'These challenges belong to Impulse Lock only. The recovery code on its own opens a recovery session — no challenges are asked after it.';

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
      'System restrictions only work while Azm is the Device Owner. Complete the Setup flow first — restrictions are not faked without it.';

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
  String get lockedTitle => 'Azm is locked';

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
      'Enter your recovery code to open a 10-minute session.';

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
  String get forcedRemovalTitle => '24-hour forced removal';

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
      'The lock ends when its timer runs out — or early, if you complete the challenges you selected for Impulse Lock. The apps it suspended are released when it ends.';

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
  String get accessChallengesSection => 'Access challenges';

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
      'System restrictions only work while Azm is the Device Owner. Complete the Setup flow first — restrictions are not faked without it.';

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

  @override
  String get generalSettings => 'General Settings';

  @override
  String get protectionTools => 'Protection tools';

  @override
  String get preferencesSection => 'Preferences';

  @override
  String get passwordVerifyError =>
      'The password could not be verified. Nothing was changed — try again.';

  @override
  String get passwordRecordCorrupt =>
      'The stored app password is damaged and cannot be used. Set a new password to replace it.';

  @override
  String get impulseUnlockEarly => 'End early with challenges';

  @override
  String get impulseUnlockTitle => 'End impulse lock early';

  @override
  String get impulseUnlockBody =>
      'Complete the challenges you selected for Impulse Lock to end this lock now and release the apps it suspended.';

  @override
  String get impulseLockEndedEarly =>
      'Impulse lock ended — the apps it suspended were released.';

  @override
  String get appsBrowseSection => 'App list options';

  @override
  String get appProtectionSection => 'Protection';

  @override
  String get appLimitsSection => 'Limits & windows';

  @override
  String get setupServicesSection => 'Services & permissions';

  @override
  String get storeCardTitle => 'Keep it safe';

  @override
  String get removalLoadingTitle => 'Completing Device Owner removal…';

  @override
  String get removalLoadingBody =>
      'Please wait. Do not close the app or uninstall until teardown completes.';

  @override
  String get removalTimeoutWarningTitle =>
      'Teardown incomplete — do not uninstall yet';

  @override
  String get removalTimeoutWarningBody =>
      'Device Owner was cleared, but the system has not finished settling all teardown steps. Do NOT uninstall yet, or the device may experience issues. The following checks are unverified:';

  @override
  String get removalRecheckAction => 'Re-check status';

  @override
  String get removalUnverifiedOwner => 'Device Owner is still active';

  @override
  String get removalUnverifiedAdmin => 'Device Admin is still active';

  @override
  String removalUnverifiedRestrictions(String restrictions) {
    return 'Restrictions still in force: $restrictions';
  }

  @override
  String get removalUnverifiedScreenCapture =>
      'Screen capture is still blocked';

  @override
  String get deleteGroupConfirmTitle => 'Delete group?';

  @override
  String deleteGroupConfirmMessage(String name) {
    return 'Are you sure you want to delete \"$name\"? All its limits and time windows will be permanently removed.';
  }

  @override
  String get deleteWindowConfirmTitle => 'Delete time window?';

  @override
  String deleteWindowConfirmMessage(String window) {
    return 'Are you sure you want to delete the time window \"$window\"?';
  }

  @override
  String get deleteBlocklistConfirmTitle => 'Delete blocklist?';

  @override
  String deleteBlocklistConfirmMessage(String title) {
    return 'Are you sure you want to delete the blocklist \"$title\"?';
  }

  @override
  String get deleteStageConfirmTitle => 'Delete warning stage?';

  @override
  String deleteStageConfirmMessage(String minutes) {
    return 'Are you sure you want to delete the warning stage at $minutes minutes?';
  }

  @override
  String get deleteRuleConfirmTitle => 'Delete seal rule?';

  @override
  String deleteRuleConfirmMessage(String summary) {
    return 'Are you sure you want to delete this seal rule: \"$summary\"?';
  }

  @override
  String get removeOwnerConfirmTitle =>
      'Remove Device Owner and end protection?';

  @override
  String get removeOwnerConsequenceRestrictions =>
      'All system restrictions, app suspensions, and website blocks will be lifted immediately.';

  @override
  String get removeOwnerConsequenceDns => 'Private DNS settings will be reset.';

  @override
  String get removeOwnerConsequenceUninstall =>
      'Uninstalling the Azm app will be allowed.';

  @override
  String get removeOwnerUnderstandCheckbox =>
      'I understand the consequences of this action';

  @override
  String get removeOwnerConfirmButton => 'Remove protection';

  @override
  String get scratchToReveal => 'Scratch to reveal';
}
