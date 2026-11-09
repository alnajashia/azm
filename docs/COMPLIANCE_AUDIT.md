# Dominanter — Compliance Audit (F1–F34 + Shizuku integration)

> **Date:** 2026-11-09 (post-redesign verification chain)
> **Auditor method:** every row below was checked against the actual code in
> `project/lib/**` and `project/android/app/src/main/**` (grep + source
> reading), the rebuilt APKs, and a fresh `flutter analyze` / `flutter test`
> run — not against prior documentation. Where documentation and code
> disagreed, code was treated as authoritative and the disagreement is
> listed in §4.
> **Sources of truth for the requirements:**
> `analysis/DECHAINER_FEATURES.md` §2 (F1–F34) and
> `analysis/SHIZUKU_INTEGRATION.md` (13 shell commands, detection,
> permission, provisioning paths).
>
> **Status vocabulary (exactly one per row):**
> - **Implemented & unit/build-tested** — the feature's own logic is covered
>   by named unit/widget tests or a build artefact, and no untested native
>   device effect is the feature's core.
> - **Implemented, device-untested** — code exists on both sides of the
>   channel (or in the native service) and compiles into the shipped APKs,
>   but its effect has never run on a device.
> - **Deferred v1.1** — not functional in v1 (any partial aspects are stated
>   plainly in Notes).
> - **Not ported deliberately** — excluded by a documented design decision.
>
> **Real-device testing: NOT DONE.** No APK from this project has been
> installed on any device or emulator. Nothing in this audit upgrades any
> device-dependent claim.

---

## 1. Part A evidence — post-redesign rebuild (2026-11-09)

| Check | Result | Evidence |
|---|---|---|
| `flutter analyze` | **0 errors, 0 warnings, 32 info-level lints** | `build_logs/redesign_analyze.log` (re-run by this audit; the 32 infos are pre-existing patterns — `use_build_context_synchronously` behind `mounted` guards, deprecated `RadioListTile.groupValue`/`onChanged`, curly-brace and one dangling-doc-comment infos) |
| `flutter test` | **41/41 passed** | `build_logs/redesign_test.log` — recovery_gate 20, channel_client 8, challenges 8, widget 3, redesign 2 |
| `assembleDebug` (redesign) | ✅ Succeeded | `build_logs/build14_redesign_debug.log` |
| `assembleRelease` (redesign) | ✅ Succeeded | `build_logs/build15_redesign_release.log` |
| Debug APK (refreshed in `project/release/`) | **163,293,074 bytes**, SHA-256 `4fdbab00ab3596740231a11a7546792cb64823d5d8022f5bd04033a1f3de49bc` | `release/dominanter-v1.0.0-debug.apk`, checksum verified identical to the build output |
| Release APK (refreshed in `project/release/`) | **50,472,363 bytes**, SHA-256 `14017379ad806dfb5b120708e94e35a02d192a1d459b7b63ac1f35a6b411c7a4`, **debug-signed** | `release/dominanter-v1.0.0-release.apk`, checksum verified identical to the build output |
| Badging (both new APKs) | `io.github.alnajashia.dominanter`, versionCode 1 / versionName 1.0.0, minSdk 30, targetSdk 36, compileSdk 36 — **unchanged** | `aapt2 dump badging` run by this audit on both refreshed copies |
| Superseded first builds | debug 148,894,306 B / `86bfa331…`; release 50,406,827 B / `c1bd2fa2…` | `build_logs/build12_debug.log`, `build13_release.log` (historical) |

The redesign itself is presentation-only (`lib/theme.dart`,
`lib/ui/pill_nav.dart`, `GradientCard`/`FocusTimerRing` in
`lib/ui/common.dart`, plus hero-card applications): no channel method,
domain model, or Kotlin file changed in the redesign, which this audit
confirmed by the channel-parity check in §4.1.

---

## 2. Feature compliance — F1–F34

| # | Feature | Status | Evidence | Notes |
|---|---|---|---|---|
| F1 | Device Owner provisioning via Shizuku (+ `user_setup_complete` bypass) | Implemented, device-untested | Kotlin `shizuku/ShizukuProvisioning.kt`: `provisionDeviceOwner()`, `withShizukuDevicePolicyManager()`, `setDeviceOwnerCompat()`, `setActiveAdminCompat()`, `forceUpdateUserSetupComplete()`, `bypassUserSetupComplete()`; Dart wizard in `lib/ui/setup_screen.dart`; compile-verified in both redesign APKs | The binder-wrapped DPM reflection path (HiddenApiBypass 4.3 in `android/app/build.gradle.kts`) has never executed on a device; it is the project's highest-risk item |
| F2 | Device Owner removal (in-session; 48-h forced removal) | Implemented, device-untested | Kotlin `deviceowner/DeviceOwnerManager.kt` `removeDeviceOwner()` → `clearDeviceOwnerApp`; Dart `lib/domain/recovery.dart` `ForcedRemoval`; `lib/ui/config_tab.dart` removal + forced-removal flows; test `recovery_gate_test.dart`: "48 h total; negative deltas never rewind it" | Partial: forced-removal accounting is Dart-side and advances only while the app process is alive (measured-tick model in `lib/app_controller.dart`); it can run long, never short. The DPM removal call itself is device-untested |
| F3 | System restrictions (all `UserManager` keys, draft/apply) | Implemented, device-untested | Kotlin `DeviceOwnerManager.listUserRestrictions()` / `applyUserRestriction()` / `clearUserRestriction()` (keys from `allRestrictionKeys()` reflection); Dart `lib/ui/restrictions_tab.dart` draft/apply + NoDeviceOwner state; test `recovery_gate_test.dart`: "dropping a key loosens", "boolean true -> false loosens" (gate logic only) | DPM effect device-untested |
| F4 | Per-app managed-restrictions editor | Implemented, device-untested | Kotlin `DeviceOwnerManager.getApplicationRestrictions()` / `setApplicationRestrictions()` (Bundle round-trip, verified re-read); Dart editor in `lib/ui/apps_tab.dart` calling `setApplicationRestrictions(..., merge: false)` | — |
| F5 | Browser restrictions (`URLBlocklist` + `ForceGoogleSafeSearch`) | Implemented, device-untested | Dart `lib/ui/config_screens.dart`: `listRestrictionCapableApps(requiredKeys: ['URLBlocklist','ForceGoogleSafeSearch'])`, bundle `{'URLBlocklist': sites, 'ForceGoogleSafeSearch': true}` pushed via `setApplicationRestrictions`; Kotlin `DeviceOwnerManager.listRestrictionCapableApps()` requires both declared keys, as in the original | Blocklists persist in native `browser_prefs` via `lib/data/config_store.dart` |
| F6 | Non-supporting-browser auto-suspension on install/first open | Deferred v1.1 | Absence verified: no package-install watcher in `DominanterAccessibilityService.kt`; `DominanterApplication.kt`'s package receiver only emits a `packageChanged` event and suspends nothing; `SuspensionReason.UNSUPPORTED_BROWSER` is never produced by any code | — |
| F7 | Forced family private DNS | Implemented, device-untested | Kotlin `DeviceOwnerManager.setPrivateDns()` (`setGlobalPrivateDnsModeSpecifiedHost`, result-code mapping) / `getPrivateDns()`; Dart presets + custom host in `lib/ui/config_tab.dart` | Partial: **cannot be unset from the UI** — no `setGlobalPrivateDnsModeOff` call exists anywhere (grep: 0 hits); already documented in `IMPLEMENTATION_STATUS.md` §6 |
| F8 | Per-app hide / suspend / uninstall-block | Implemented, device-untested | Kotlin `DeviceOwnerManager.setAppHidden()` / `setPackagesSuspended()` / `setUninstallBlocked()` — each re-reads and returns the verified state; Dart `lib/ui/apps_tab.dart` toggles with reason `MANUAL`; test `channel_client_test.dart`: "setAppSuspended returns verified per-package results" (client side, mock channel) | Native effects device-untested |
| F9 | Per-app/group time limits (daily/per-weekday) + block at expiry | Implemented, device-untested | Kotlin service `DominanterAccessibilityService.startTracking()` / `stopTrackingAndSave()` / `executeBlocking()` (self-tracked usage on `elapsedRealtime`, as in the original); store `SettingsStore.timeLimitFor/setTimeLimit`; test `channel_client_test.dart`: "time limit / windows / groups payloads round-trip through the client" | Enforcement is native and device-untested; no `UsageStatsManager` use, matching the original |
| F10 | Allowed time windows (daily/per-weekday) | Implemented, device-untested | Kotlin `SettingsStore.timeWindowsFor/setTimeWindows`, service window logic with app ∩ group intersection (`trackingConfigFor()` → `TimeWindow.intersect`); gate tests in `recovery_gate_test.dart` (widen/narrow/midnight-spanning) | Partial: per-app editor UI edits **daily windows only**; per-weekday windows are channel/store/group-model supported (documented in `IMPLEMENTATION_STATUS.md` §6) |
| F11 | Reopening cooldown | Deferred v1.1 | Storage only: `SettingsStore.setReopenSeconds()` + channel `setTimeLimit(reopenSeconds)`; Dart editor field in `lib/ui/apps_tab.dart` is labelled "stored; enforcement is v1.1" | The Kotlin service never reads `reopenSeconds` (grep: no service call site). See also gap G1: `BlockActivity.VARIANT_REOPENING` exists but has no caller |
| F12 | Staged usage warnings | Deferred v1.1 | Config only: `lib/data/config_store.dart` `getUsageWarnings/setUsageWarnings` (defaults match the original: 15 min silent, 5 sound, 1 vibrate×1, 0.5 vibrate×3) persisted via generic settings; editor in `lib/ui/config_screens.dart` | **Notifications are not fired**: there is no notification code anywhere in the Kotlin layer (grep for `Notification`/`startForeground`: 0 hits) and the service header lists F12 among the deliberately-absent v1 effects. Editor + storage are v1; delivery is v1.1 |
| F13 | App groups (shared limits/windows) | Implemented, device-untested | Kotlin `SettingsStore.groups()/saveGroups()/groupForPackage()`; service `trackingConfigFor()` applies group limit/windows alongside the app's; Dart groups CRUD in `lib/ui/apps_tab.dart`; channel round-trip test (see F9) | Enforcement device-untested |
| F14 | Active word blocking | Implemented, device-untested | Kotlin service `checkActiveBlocking()` + `extractEditableFieldsTextAndFocus()` — checks field content when typing ends, preserving the original's nuance (not per-keystroke); store/channel `setBlockedWords`; Dart editors in `lib/ui/config_screens.dart` | Device-untested |
| F15 | Passive word blocking | Implemented, device-untested | Kotlin service passive branch on `TYPE_WINDOW_CONTENT_CHANGED`: `buildScreenText()` (event text + full node-tree walk) matched against per-app patterns from `SettingsStore.passiveWordsFor()`; channel `setPassiveWords` | Device-untested |
| F16 | Visual (NSFW) TFLite blocking | Deferred v1.1 | Absence verified: no TFLite/LiteRT dependency in `pubspec.yaml` or `android/app/build.gradle.kts`, no classifier code; service header explicitly excludes the pipeline; **no placeholder screen** (grep for nsfw/tflite in `lib/`: 0 hits) | Requires its own spike (Accessibility screenshot + model + suspend escalation), per `ARCHITECTURE.md` §6.2 |
| F17 | Visual-blocking escalation (N in M min ⇒ suspend D min) | Deferred v1.1 | Absence verified: no suspension tracker code; `SuspensionReason.VISUAL_BLOCKING` is never produced | Depends on F16 |
| F18 | Activity blocker + seen-activities log | Deferred v1.1 | Dart: only a labelled v1.1 tile in `lib/ui/config_tab.dart` ("Blocking specific activity screens ships in v1.1") | **Half-wired native side — see gap G1**: the service already enforces `SettingsStore.blockedActivities()` and keeps the in-memory `accessedActivities` log, but nothing can ever populate or read them |
| F19 | Torrent-app auto-blocking | Deferred v1.1 | Absence verified: no torrent/magnet detection anywhere (grep: only the unused `SuspensionReason.TORRENT_APP` enum entry in `data/TimeModels.kt`) | — |
| F20 | 18+ auto-suspension via Play Store scraping | Not ported deliberately | No scraping code (no Jsoup-equivalent, no Play Store fetch); Kotlin `DeviceOwnerManager.AppInfo.toMap()` always emits `hasExplicitContentRating: null` — the Dart model parses the field but no rating is ever fetched | Rationale in `ARCHITECTURE.md` §6.2: brittle, locale-dependent HTML scraping with no official API. The always-null field is a deliberate non-port, not a silent fake: no UI presents a rating |
| F21 | Impulse lock (panic button, 15 min–6 h, optional suspension) | Implemented, device-untested | Dart `lib/ui/lock_screen.dart` pre-auth panic button + `lib/ui/impulse_focus_screens.dart`; suspensions applied via channel `setAppSuspended(..., reason: 'IMPULSE_LOCK')`; tests `recovery_gate_test.dart`: "duration is clamped to 15 min – 6 h", "ticks down to completion; negative ticks ignored"; widget test "Lock screen: panic button is visible BEFORE any auth (F21/F32)" | Partial: the original's **service-side suspension sync is absent** — suspensions are applied/released by the UI process, so they depend on the app process being alive (documented in `IMPLEMENTATION_STATUS.md` §2/§6). Timer accounting has the same alive-only limitation as F2 |
| F22 | Access challenges — Math / Words / Reading | Implemented & unit/build-tested | Pure Dart `lib/domain/challenges.dart` + `lib/ui/challenges_ui.dart`; tests `challenges_test.dart`: "requires 5 correct answers; wrong answers do not advance", "all four operations produce self-consistent problems", "a mistake restarts the streak" (words), "words reveal one tick at a time; passages advance; completes" (reading) | Reading passages are a small original sample set + user custom phrases — the original's bundled corpus was **not** copied (licence/attribution decision, documented) |
| F22a | Access challenge — Tetris | Deferred v1.1 | `ChallengeType.tetris` exists with `isAvailableInV1 == false`; test `challenges_test.dart`: "Tetris is the only challenge unavailable in v1"; the challenge runner skips it with an explicit notice, never simulates it (`lib/ui/challenges_ui.dart`) | Sub-row of F22; not counted in the §5 totals |
| F23 | Recovery gate + 10-min session; tightening free (5 s undo), loosening gated | Implemented & unit/build-tested | Pure Dart `lib/domain/recovery.dart` (`Loosening`, `PendingChange`, `RecoverySession`); 20 tests in `recovery_gate_test.dart` covering loosening for limits/windows/restrictions/toggles, the 5-second undo (reverts exactly once), session start/expiry/renew/end; wired through all Dart editors via `lib/ui/recovery_ui.dart` | The gate is a UI/domain enforcement model; the native stores it protects are device-untested (see F1/F8) |
| F24 | Recovery-code wizard (16-char, paper, re-type to confirm) | Implemented & unit/build-tested | Widget tests `widget_test.dart`: "First-run wizard shows the generated code grouped for paper (F24)", "Wizard stores the re-typed code via the channel (F24)"; Kotlin `security/RecoveryStore.kt` (PBKDF2WithHmacSHA256, 210k iterations, 16-byte salt, constant-time verify) compile-verified in both APKs | **Deliberate deviation from the original**: salted PBKDF2 hash in a dedicated `recovery_secure` store, never plaintext (original stored plaintext in SharedPreferences) — `ARCHITECTURE.md` §7.1. Native KDF execution is compile-verified only |
| F25 | Focus mode (Pomodoro, suspensions + restrictions, schedules, FGS) | Implemented, device-untested | Dart `lib/domain/focus.dart` + `lib/ui/impulse_focus_screens.dart` (`_syncEffects()` suspends with reason `FOCUS_MODE` and applies/clears user restrictions by phase); tests `challenges_test.dart`: "phase cycle: focus -> break -> focus -> long break (cycle 2)", "pause stores remaining; resume re-enters focus with it", "config json round-trip…"; redesign test: "Focus timer ring shows the model remaining time" | Partial, stated in the UI: **no native foreground service and no schedules** in v1 (labelled v1.1 tile in the Focus screen); the countdown runs only while the app process is alive. See also gap G3 (manifest still declares the FGS permissions) |
| F26 | Colour modes on schedule | Deferred v1.1 | Absence verified: no colour-filter code in the service or Dart (grep: only the v1.1 tile in `lib/ui/config_tab.dart` and explanatory text); service header explicitly excludes colour-filter sync | The prerequisite `grantWriteSecureSettings` **is** implemented — see Shizuku table S6/#6 |
| F27 | Suspension audit log | Implemented, device-untested | Kotlin `SettingsStore.logSuspension()` (500-entry cap, 5 s dedupe) written at the service's lockdown site and at channel suspension sites; channel `getSuspensionLogs`/`clearSuspensionLogs`; Dart `SuspensionLogsScreen` (`lib/ui/config_screens.dart`) with search + gated clear | Log *writing* on a real suspension is device-untested |
| F28 | Accessibility-loss lockdown | Implemented, device-untested | Kotlin service `onUnbind()`: if `SettingsStore.consumeIntentionalAccessibilityDisable()` is false → suspend all `SettingsStore.controlledPackages()` with reason `ACCESSIBILITY_DISABLED`, add `DISALLOW_INSTALL_APPS`, launch `AccessibilityRequestActivity`; `onServiceConnected()` restores both | **Highest-caution row in the project**: fail-closed and hard to undo casually. Must be tested first, on a sacrificial device. Never run on any device to date |
| F29 | Silent APK update installer (incl. downgrade, lock-screen, unauthenticated) | Not ported deliberately | Absence verified: no `PackageInstaller` use, no `REQUEST_INSTALL_PACKAGES`/`REQUEST_DELETE_PACKAGES` in manifest or code (grep: 0 hits); the Dart lock screen contains only the panic button, a read-only usage overview and the auth action | Rationale: an unauthenticated install surface is a security liability the rebuild does not reproduce (`ARCHITECTURE.md` §7). A future authenticated variant would be new scope, not a port |
| F30 | Setup wizard (Shizuku-state-driven onboarding) | Implemented, device-untested | Dart `lib/ui/setup_screen.dart` driven by the five-state `ShizukuStatus`; Kotlin `ShizukuGateway.state()` (see §3); diagnostics, provisioning, accessibility toggle and grant actions on the same screen | One difference from the original, stated plainly: when Shizuku is not running, the original opened `https://shizuku.rikka.app/guide/setup/`; the rebuild shows text instructions instead (no URL-launcher dependency in `pubspec.yaml`) |
| F31 | First-run recovery-setup gate | Implemented, device-untested | Dart `lib/main.dart` startup routing + `AppController.initialise()` (`isRecoveryCodeSet` → wizard-only until a code exists); wizard itself widget-tested (F24) | The installed app's real first launch has never run anywhere |
| F32 | Biometric / device-credential entry gate | Implemented, device-untested | Dart `lib/ui/lock_screen.dart` using `local_auth` 3.0.1 (`pubspec.yaml`); original's fallback preserved and surfaced: no biometric **and** no credential enrolled ⇒ entry allowed, with an explanatory dialog; widget test asserts the panic button precedes auth | Real biometric/credential prompts are device-only |
| F33 | Language selection (en / pt) | Implemented, device-untested | Selection persists natively (`lib/data/config_store.dart` `getLanguage/setLanguage` via `security_prefs`); `lib/ui/common.dart` `isPt` chrome strings; language dialog in `lib/ui/config_tab.dart` | Partial, stated in the dialog itself: app chrome (tabs, lock screen, session chip) is translated en/pt; most screens are still English |
| F34 | Debug-only self-disable hatch | Not ported deliberately | Absence verified in Dart and Kotlin: no debug receiver, no `disableSelf`, no auto-session path (grep for the original's `DEBUG_INSTALL` action and related symbols: 0 hits) | Compliant by absence — `IMPLEMENTATION_STATUS.md` §4 |

---

## 3. Shizuku integration compliance

All rows verified against the Kotlin in
`android/app/src/main/kotlin/io/github/alnajashia/dominanter/shizuku/`
(`ShizukuGateway.kt`, `ShizukuProvisioning.kt`, `ShizukuRunner.kt`), the
manifest, and `android/app/build.gradle.kts`. The rebuild's runner fixes
the original's central flaw: `ShizukuRunner.execChecked` /
`execShellChecked` throw `SHELL_FAILED` with the exit code on any non-zero
exit — shell failure is never reported as success (regression-tested on the
Dart side: `channel_client_test.dart`, "SHELL_FAILED keeps code, exitCode,
command and stderr from details").

| # | Integration point | Status | Evidence | Notes |
|---|---|---|---|---|
| S1 | Detection sequence: installed → binder alive → pre-V11 → permission | Implemented, device-untested | `ShizukuGateway.state()`: `isInstalled()` (`PackageManager.getPackageInfo("moe.shizuku.privileged.api")`) → `isBinderAlive()` (`Shizuku.pingBinder()`) → `Shizuku.isPreV11()` → `checkSelfPermission()`; Dart parses all five states — tests `channel_client_test.dart`: "getShizukuState parses the exact Kotlin payload", "all five Shizuku states parse distinctly" | Improvements over the original, deliberate: binder-received/dead listeners are registered (the original used none; it polled `pingBinder()` every 500 ms in the setup UI — the rebuild still re-reads state on refresh). The original's `shouldShowRequestPermissionRationale()` was never called and is likewise unused here |
| S2 | Permission request, code **911**, + result listener | Implemented, device-untested | `ShizukuGateway.REQUEST_CODE = 911`; `requestPermission()` calls `Shizuku.requestPermission(911)` and refuses (with taxonomy errors) when not installed / not running / pre-V11; `OnRequestPermissionResultListener` registered in `MainActivity.configureFlutterEngine`, removed in `cleanUpFlutterEngine` | Two fixes vs the original, deliberate: the listener **verifies requestCode == 911** (the original ignored it) and listeners are **removed** on engine cleanup (the original's `removeShizukuListener()` had no call site — a leak) |
| S3 | Pre-V11 handling | Implemented, device-untested | `ShizukuGateway.State.PRE_V11`; `hasPermission()` returns false pre-V11; `ShizukuRunner.run()` returns null pre-V11, which provisioning callers convert to `SHIZUKU_NOT_RUNNING`-family errors via `ShizukuGateway.unavailableException()` | Matches the original's hard-fail with no fallback; the rebuild surfaces it as a distinct UI state instead of only failing |
| S4 | `ShizukuProvider` manifest entry | Implemented & unit/build-tested | `android/app/src/main/AndroidManifest.xml`: `rikka.shizuku.ShizukuProvider`, authorities `${applicationId}.shizuku`, `INTERACT_ACROSS_USERS_FULL`; **verified in the built artefact**: `aapt2 dump xmltree` on the redesign release APK shows the provider with authorities `io.github.alnajashia.dominanter.shizuku`, plus the API's `moe.shizuku.manager.permission.API_V23` permission | Whether the provider actually receives a binder from a real Shizuku server is device-untested (S1) |
| S5 | API coordinates **13.1.5** | Implemented & unit/build-tested | `android/app/build.gradle.kts`: `implementation("dev.rikka.shizuku:api:13.1.5")` + `implementation("dev.rikka.shizuku:provider:13.1.5")` — exactly the original's coordinates; both redesign APKs compile and link against them | Shizuku imports exist **only** in the `shizuku/` provisioning package, `MainActivity` (listener registration) and `DominanterApplication` (cold-start repair) — never in the Accessibility Service or `DeviceOwnerManager` (grep-verified), preserving the original's setup-time-only role |
| S6 | Binder-wrapped DPM provisioning path + `dpm` fallback | Implemented, device-untested | `ShizukuProvisioning.withShizukuDevicePolicyManager()` wraps `IDevicePolicyManager` in `rikka.shizuku.ShizukuBinderWrapper` and reflectively swaps `DevicePolicyManager.mService`, then `setActiveAdminCompat()` / `setDeviceOwnerCompat()` / `forceUpdateUserSetupComplete()` (hidden overloads, HiddenApiBypass 4.3); fallback is command #7 below with its exit code checked | **Never executed on a device** — Android-version-fragile by construction; spike #1 in `ARCHITECTURE.md` §10 |
| S7 | Cold-start stuck-setup repair | Implemented, device-untested | `DominanterApplication.onCreate()` spawns a thread calling `ShizukuProvisioning.restoreStuckUserSetupComplete()` (commands #4/#5 below); no-ops safely without a granted binder | Mirrors the original's `DechainerApplication` behaviour |
| S8 | `WRITE_SECURE_SETTINGS` grant | Implemented, device-untested | `ShizukuProvisioning.grantWriteSecureSettings()` (command #6), verified by re-checking `checkSelfPermission(WRITE_SECURE_SETTINGS)` afterwards; also attempted automatically after successful provisioning, with failure reported in `commandOutput`, not hidden; channel `grantWriteSecureSettings` on the Setup screen | — |
| S9 | Accessibility enable/disable via secure settings | Implemented, device-untested | `ShizukuProvisioning.setAccessibilityEnabled()` (commands #11–#13), which also arms the intentional-disable guard (`SettingsStore.armIntentionalAccessibilityDisable()`) so F28 does not fire on an intentional disable, and grants `WRITE_SECURE_SETTINGS` on enable as the original did; channel `setAccessibilityEnabled` / `isAccessibilityEnabled` | The original read the list with `settings get` and rewrote it; the rebuild does the same read-modify-write, exit-code-checked |

### The 13 shell commands — one row each

All 13 run through `ShizukuRunner` (`IShizukuService.newProcess`, as in the
original). Commands #1–#5 use the argv form (`exec`); #6–#13 use the
`sh -c` form (`execShellChecked`, exit-code-checked — the original's
`command()` path never checked exit codes).

| # | Command (as built in code) | Status | Evidence |
|---|---|---|---|
| 1 | `settings --user <userId> get secure user_setup_complete` | Implemented, device-untested | `ShizukuProvisioning.getUserSetupComplete()` via `ShizukuRunner.exec("settings","--user",…)`; `<userId> = Process.myUid()/100000` |
| 2 | `settings --user <userId> put secure user_setup_complete 0` | Implemented, device-untested | `ShizukuProvisioning.bypassUserSetupComplete()` (checked variant) |
| 3 | `settings --user <userId> put secure user_setup_complete 1` | Implemented, device-untested | `ShizukuProvisioning.restoreUserSetupComplete()`; invoked from a `finally` in `provisionDeviceOwner()` so a failed provisioning cannot leave the flag at 0 |
| 4 | `settings --user <userId> get secure user_setup_complete` (cold-start repair check) | Implemented, device-untested | `ShizukuProvisioning.restoreStuckUserSetupComplete()` (same getter as #1, distinct call site and purpose, as in the original inventory) |
| 5 | `settings --user <userId> get global device_provisioned` | Implemented, device-untested | `ShizukuProvisioning.refreshUserSetupComplete()` via `ShizukuRunner.exec("settings","--user",…,"get","global","device_provisioned")` |
| 6 | `pm grant <applicationId> android.permission.WRITE_SECURE_SETTINGS` | Implemented, device-untested | `ShizukuProvisioning.grantWriteSecureSettings()` via `execShellChecked("pm grant ${context.packageName} ${Manifest.permission.WRITE_SECURE_SETTINGS}")` — see S8 |
| 7 | `dpm set-device-owner <applicationId>/.deviceowner.DominanterDeviceAdminReceiver` | Implemented, device-untested | `ShizukuProvisioning.provisionDeviceOwner()` fallback branch via `execShell("dpm set-device-owner ${context.packageName}/${DeviceOwnerManager.adminReceiverShortName()}")`, exit code checked — see S6. Receiver class name differs from the original's, correctly tracking this app's own package structure |
| 8 | `dumpsys account` | Implemented, device-untested | `ShizukuProvisioning.diagnostics()` via `execShellChecked("dumpsys account")`, parsed into the diagnostics payload |
| 9 | `dpm list-owners` | Implemented, device-untested | `ShizukuProvisioning.diagnostics()` via `execShellChecked("dpm list-owners")` → `currentOwner` |
| 10 | `pm list users` | Implemented, device-untested | `ShizukuProvisioning.diagnostics()` via `execShellChecked("pm list users")` → `extraUsers` |
| 11 | `settings get secure enabled_accessibility_services` | Implemented, device-untested | `ShizukuProvisioning.getEnabledAccessibilityServices()` via `execShellChecked(...)` |
| 12 | `settings put secure enabled_accessibility_services <colon-joined list or 'null'>` | Implemented, device-untested | `ShizukuProvisioning.setAccessibilityEnabled()` — read-modify-write of the #11 list adding/removing `io.github.alnajashia.dominanter/.accessibility.DominanterAccessibilityService`; writes `null` when the resulting list is empty, as in the original |
| 13 | `settings put secure accessibility_enabled 1` | Implemented, device-untested | `ShizukuProvisioning.setAccessibilityEnabled()` via `execShellChecked("settings put secure accessibility_enabled 1")`, immediately after #12 |

No other shell commands exist in the rebuild (grep over the Kotlin tree
for `exec`/`execShell` call sites returns only the sites above) — matching
the original's complete inventory of 13, with no `pm install/uninstall`,
`appops`, or `am` commands added.

---

## 4. New gaps found by this audit

Findings **not** already documented in `IMPLEMENTATION_STATUS.md` §2/§6.
Method note: the checks behind this section were — full channel-parity
extraction (every method string in the Dart client vs every `when` branch
in the Kotlin handler), event-type extraction on both sides, a function
inventory of `SettingsStore` (getters vs setters), caller analysis for
every `SettingsStore` getter and every `BlockActivity` variant, manifest
component/permission cross-check against Kotlin classes, and grep audits
for the deferred features' code (TFLite, torrent, PackageInstaller,
notifications, colour filters). Severity is stated per item; none of these
change a §2/§3 status, but each is a real code-vs-claim mismatch.

### G1 — F18 has half-wired, unreachable native plumbing (minor, dead code)

`DominanterAccessibilityService` already enforces activity blocking
(class-name match → `GLOBAL_ACTION_BACK` against
`SettingsStore.blockedActivities()`) and maintains the original's
in-memory seen-activities log (`accessedActivities`, capped at 100). But:

- `SettingsStore` exposes **only a getter** for `blocked_activities` —
  there is no setter anywhere in Kotlin, no channel method, and no Dart
  UI. The blocked set therefore can never become non-empty through the
  app, and the enforcement branch is dead in practice.
- `accessedActivities` is written by the service and read by **nothing** —
  no channel method or UI can ever display the seen-activities log.

`IMPLEMENTATION_STATUS.md` says F18 is "not implemented yet" with a v1.1
tile, which is true at the user level, but it does not disclose that the
native side is half-built and unreachable. Same pattern, smaller: 
`BlockActivity` implements a `VARIANT_REOPENING` screen (title/body
strings included) that **no code ever launches** (F11 enforcement is
deferred), and the `focus_schedules_prefs` store sits in the channel's
generic-settings allowlist although no Dart code ever reads or writes it
(F25 schedules are deferred). All harmless, all should be either wired or
removed when F18/F11/F25 land.

### G2 — EventChannel: two Kotlin event types have no Dart handling, and one name is inconsistent (minor)

Kotlin emits 8 event types. Dart's `AppController` handles events only
generically (`lastEvent = e; notifyListeners()`), and two types are never
referenced anywhere in Dart:

- `packageChanged` (from `DominanterApplication`'s package receiver). The
  receiver's KDoc says it exists to invalidate "the Dart app-list cache" —
  **no such cache or invalidation exists**: `lib/ui/apps_tab.dart` loads
  the installed-app list on init/manual refresh only. Installing or
  removing an app while the Apps tab is open leaves a stale list until
  manual refresh. (The original invalidated its `AppRepository` cache on
  the same broadcasts.)
- `accessibilityStatus` (emitted only by the service's F28 lockdown path,
  with a `controlledPackagesSuspended` payload). It is also **named
  inconsistently within Kotlin itself**: the same service emits routine
  state as `accessibilityStateChanged` (`emitState()`), so a future Dart
  handler written against one name would silently miss the other.

Impact is limited by the documented "events are advisory; state is
re-read" design, and `IMPLEMENTATION_STATUS.md` §3 already flags two
smaller doc↔Kotlin mismatches of the same family — but the §3 claim that
the EventChannel is simply "implemented both sides" does not mention
either point.

### G3 — Manifest requests permissions that v1 never uses (minor, hygiene)

`AndroidManifest.xml` mirrors the original's permission set wholesale,
including `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SPECIAL_USE`,
`USE_EXACT_ALARM`, `SCHEDULE_EXACT_ALARM`, and `RECEIVE_BOOT_COMPLETED`.
In v1 there is **no foreground service, no alarm, and no boot receiver**
anywhere in the Kotlin code or the manifest's components (the only
service declared is the Accessibility Service) — because F25's native
FGS/schedules are deferred. `IMPLEMENTATION_STATUS.md` §6 documents the
missing FGS but not that the permissions for it are already being
requested. Worth resolving before any store submission (permission
hygiene review) or when F25's native components land.

### G4 — Documentation drift found and fixed during this audit (cosmetic)

- `IMPLEMENTATION_STATUS.md` §1/§5 and `TESTING.md` §1 still quoted the
  pre-redesign numbers (27 info lints, 39 tests) while §2a of the same
  status file already recorded the redesign numbers (32 infos, 41 tests).
  Fixed in this pass: both files now consistently state 0 errors /
  0 warnings / 32 infos and 41/41, and all APK sizes/hashes were updated
  to the redesign rebuilds (§1).
- `docs/REA_REBUILT_APK.md` describes the **pre-redesign** release APK
  (50,406,827 B, `c1bd2fa2…`). Its values were left untouched — they are
  the accurate record of the artefact REA actually inspected — but
  `TESTING.md` now states explicitly that REA has not been re-run on the
  redesign APK, so the REA doc must not be read as describing the
  current build.

### 4.1 Checks that came back clean (no gap)

- **Channel parity: exact.** 39 method names implemented in the Kotlin
  handler's dispatch; all 39 are invoked by the Dart client; no Dart-only
  or Kotlin-only channel method exists. (`getAppEnforcement` in Dart is a
  composite of `getTimeLimit` + `getTimeWindows`, not a channel method.)
- **No fake-success paths found in the audited surfaces**: every DPM
  mutator in `DeviceOwnerManager` re-reads and returns verified state;
  every provisioning shell call is exit-code-checked; the Dart client
  converts a missing native side to `UNAVAILABLE` (unit-tested).
- **Manifest components all exist**: `BlockActivity`,
  `AccessibilityRequestActivity`, `DominanterDeviceAdminReceiver`,
  `DominanterPolicyUpdateReceiver`, `DominanterAccessibilityService`,
  and the Shizuku provider (S4) each resolve to a real class.
- **Deferred features are honestly absent**, not stubbed behind working-
  looking UI: F6/F16/F17/F19 have no code and (except F18/F26's labelled
  v1.1 tiles) no screens; F20/F29/F34 have no code paths at all.

---

## 5. Summary counts

### F1–F34 (34 features; F22a counted within F22)

| Status | Count | Features |
|---|---|---|
| Implemented & unit/build-tested | **3** | F22 (Math/Words/Reading), F23, F24 |
| Implemented, device-untested | **20** | F1, F2, F3, F4, F5, F7, F8, F9, F10, F13, F14, F15, F21, F25, F27, F28, F30, F31, F32, F33 |
| Deferred v1.1 | **8** | F6, F11, F12, F16, F17, F18, F19, F26 |
| Not ported deliberately | **3** | F20, F29, F34 |
| **Total** | **34** | |

### Shizuku integration points (9 points + 13 commands = 22 rows)

| Status | Count | Rows |
|---|---|---|
| Implemented & unit/build-tested | **2** | S4 (provider — verified in the built APK), S5 (13.1.5 coordinates — linked into both APKs) |
| Implemented, device-untested | **20** | S1, S2, S3, S6, S7, S8, S9 + commands #1–#13 |
| Deferred / Not ported | **0** | — |

### Headline

The v1 scope promised in `ARCHITECTURE.md` §6 is present in code and
compiles into both rebuilt APKs; the pure-Dart core (challenges, recovery
gate, wizard) is unit/widget-tested at 41/41. **Everything that touches a
real Shizuku server, Device Policy Manager, or Accessibility Service
remains device-untested**, and F28 must be the first thing exercised —
on a sacrificial device — when hardware testing begins.
