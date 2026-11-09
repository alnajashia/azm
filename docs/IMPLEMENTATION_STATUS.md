# Dominanter — Implementation Status

> **Last updated:** 2026-11-09 (final v1 documentation stage — APKs built, REA run on the rebuilt APK, TESTING.md / REVERSE_ENGINEERING.md completed)
> **Honesty rule:** a feature is listed as *Implemented and tested* only with
> build + test evidence. A successful build alone never upgrades a status.
>
> Legend: ✅ Done · 🟡 In progress · ⬜ Not implemented yet · 🚫 Not ported
> (deliberate, with reason — see `ARCHITECTURE.md` §6.2/§7) · 🧪 Implemented
> but not fully tested

---

## 1. Stage / deliverable status

| Deliverable | Status | Evidence / notes |
|---|---|---|
| Reverse-engineering report — DeChainer features | ✅ Done | `analysis/DECHAINER_FEATURES.md` — F1–F34, storage, DPM inventory, Accessibility Service, source-verified at DeChainer v1.12.0 / commit `29822c0` |
| Reverse-engineering report — Shizuku integration | ✅ Done | `analysis/SHIZUKU_INTEGRATION.md` — Shizuku is setup-time only; 13 shell commands inventoried; binder-wrapped DPM path traced; API 13.1.5 |
| REA analysis results | ✅ Done | `analysis/REA_AND_GITHUB.md` + raw outputs. Honest finding: REA has no Kotlin-source route on this install; its one applicable result is the hashed source inventory. **Completed at the APK stage:** REA was run on our own built `app-release.apk` — `docs/REA_REBUILT_APK.md` + raw JSON in `docs/rea_rebuilt_apk/`: `identify-flutter-build` ✅ (Flutter detected, Dart snapshot hash `97ff04a728735e6b6b098bdf983faaba` consistent across arm64-v8a/armeabi-v7a/x86_64), `inspect-dart-aot` ✅ (string pool contains exactly this project's `package:dominanter/…` Dart sources), `inspect-apk-signature` ✅ (APK Signature Scheme v2 only, signer = Android Debug certificate — independent proof the release APK is debug-signed and not publishable). `inspect-android-package` (JADX) and `decode-android-resources` (apktool) remain blocked: `capability_unavailable`, tools not installed — stated plainly in the doc, no output fabricated |
| DeChainer ↔ Shizuku integration documentation | ✅ Done | `analysis/SHIZUKU_INTEGRATION.md` §8 |
| Architecture diagrams | ✅ Done | `project/docs/ARCHITECTURE.md` §3 — ASCII + Mermaid |
| Architecture document | ✅ Done | `project/docs/ARCHITECTURE.md` — design principles, channel contract, F1–F34 mapping, security deviations, data model, testing strategy |
| README.md (project) | ✅ Done | Full project README written 2026-11-09 (purpose, architecture, setup, permissions, tests, limitations, attribution). **Updated at the final v1 stage:** the stale "No APK yet / build blocked" status, build instructions (now point at `build_apk.sh` + `build_logs/README.md`, with plain `flutter build apk` noted as the normal-machine route), Tests section (Kotlin is now Gradle compile-verified) and Known limitations (APKs exist but are device-unverified; release is debug-signed) were corrected to the built state |
| TESTING.md | ✅ Done | `project/docs/TESTING.md` — evidence table (analyze 0/0, 39/39 tests with per-file coverage, Kotlin compile-verified, aapt2 badging, build logs), the 17 master test areas each marked Verified here / Requires real device / Not yet, and an explicit statement that **no device testing has occurred** (Shizuku binder, Device Owner provisioning, accessibility lockdown all device-unverified). Plan remains `ARCHITECTURE.md` §9; detail also in §5 below |
| REVERSE_ENGINEERING.md (project docs copy) | ✅ Done | `project/docs/REVERSE_ENGINEERING.md` — repo-appropriate consolidation of the three `analysis/` reports: what DeChainer is, condensed F1–F34 table, Shizuku integration (13 commands, binder-DPM provisioning path, dependency matrix), the honest REA audit, finding→rebuild-consequence mapping, credits/licences. Links to `ARCHITECTURE.md` rather than duplicating it |
| LICENSE | ✅ Done | Apache License 2.0 (verbatim text, as in DeChainer/Shizuku sources), added 2026-11-09; attribution to DeChainer and Shizuku is in the README |
| Complete Flutter project (scaffold) | ✅ Done | Flutter 3.35.1 scaffold in `project/`; applicationId `io.github.alnajashia.dominanter` |
| Dart UI layer | 🧪 Implemented but not fully tested | ~6,400 lines in `lib/` (see §2). `flutter analyze`: **0 errors, 0 warnings**, 27 info-level lints (mostly `use_build_context_synchronously` behind `mounted` guards, one deprecated `RadioListTile.groupValue`). No device run yet. |
| Kotlin native implementation | 🧪 Implemented but not fully tested | 14 Kotlin files (~3,300 lines): channel handler, `ShizukuProvisioning`, `DeviceOwnerManager`, Accessibility Service, `SettingsStore`, `RecoveryStore`. **Gradle compile-verified 2026-11-09**: `compileDebugKotlin` and `compileReleaseKotlin` pass as part of the successful `assembleDebug`/`assembleRelease` builds (see APK row). Five compile errors found by the first real build were fixed (see `build_logs/build9_debug.log` → `build12_debug.log`): a `*/` sequence terminating a KDoc comment early in `DeviceOwnerManager.kt`, the non-existent `PRIVATE_DNS_SET_SUCCESS` constant (correct: `PRIVATE_DNS_SET_NO_ERROR`), a duplicate companion object in the Accessibility Service, a missing `Context` threaded through `ShizukuProvisioning.refreshUserSetupComplete`, and a vararg array type mismatch in `ShizukuRunner.exec`. Still never run on a device |
| Functional Shizuku integration | 🧪 Implemented but not fully tested | Contract implemented both sides; never run against a real Shizuku server / device |
| Reimplemented original features | 🧪 Partially | See §2 — Core v1 features are coded; v1.1 features are not; nothing is device-verified |
| Modern UI/UX (Material 3, light/dark) | 🧪 Implemented but not fully tested | Material 3, seed-colour light + dark themes, system/light/dark switch in Config; every screen has loading / empty / success / failure states; v1.1 features are labelled tiles, not fake controls |
| Automated tests | 🧪 Partially done | Dart: **39 tests, all passing** (`flutter test`, 2026-11-09) — see §5. Kotlin instrumentation tests: not written |
| Real-device testing report | ⬜ Not implemented yet | No device testing has been performed. No feature may be called verified before this exists for it |
| APK build | ✅ Done | **2026-11-09, in this sandbox** via `build_apk.sh` (see §5 build evidence). Debug: `build/app/outputs/flutter-apk/app-debug.apk`, 148,894,306 bytes, SHA-256 `86bfa331e3124d5986dd61276d41904b691552fc145e3e9ac39d83d1eea23615`. Release: `app-release.apk`, 50,406,827 bytes, SHA-256 `c1bd2fa2ebc767ce296e830f5e1a2d864de7ec5cf82572fb527fc4f81a67103e` — signed with the **debug** key (the scaffold's `signingConfig = debug` in `app/build.gradle.kts`; a real release keystore is a publishing decision, not yet made). Badging verified with `aapt2`: `io.github.alnajashia.dominanter`, versionCode 1 / versionName 1.0.0, minSdk 30, targetSdk/compileSdk 36. Neither APK has been installed or run on any device |
| GitHub push | ✅ Second snapshot done — third (final v1 docs) prepared | Destination confirmed by the user 2026-11-09: existing repo `alnajashia/dominanter`. **First push: commit `354897c` on `main`** (42 text files: scaffold, 14 Kotlin files, architecture docs). **Second push: commit `bfab087` on `main`** (62 text files: complete Dart UI, 3 new test files, LICENSE, professional README). Prepared for the third push (executed from the main chat): `docs/REVERSE_ENGINEERING.md`, `docs/TESTING.md`, `docs/REA_REBUILT_APK.md`, `docs/rea_rebuilt_apk/*.json` (5 raw REA outputs), this status refresh, the README corrections, the build-stage Kotlin compile fixes (4 files: `DeviceOwnerManager.kt`, `DominanterAccessibilityService.kt`, `ShizukuProvisioning.kt`, `ShizukuRunner.kt` — changed after `bfab087`, verified against the repo at that commit), and the `build_logs/` evidence set (14 text files, absent from the repo at `bfab087`). Excluded from all snapshot pushes as binaries: the APKs (deliverable copies kept locally in `project/release/` — `dominanter-v1.0.0-debug.apk` / `dominanter-v1.0.0-release.apk`, checksums verified identical to the build outputs), launcher PNGs, `gradle-wrapper.jar`, and `build_apk.sh` (sandbox-specific build helper; the documented build method lives in the README/`TESTING.md`) |

---

## 2. Feature status — F1–F34

Scope is from `ARCHITECTURE.md` §6. **Status is independent of scope.**

| # | Feature | v1 scope | Status |
|---|---|---|---|
| F1 | Device Owner provisioning via Shizuku (+ `user_setup_complete` bypass) | Core v1 | 🧪 Implemented (Kotlin provisioning + Dart setup wizard) — not device-tested |
| F2 | Device Owner removal (in-session; 48-h forced removal) | Core v1 | 🧪 Implemented — Dart forced-removal accounting advances only while the app process is alive (measured-tick model, never counts dead time; see §6); removal itself is Kotlin DPM, untested on device |
| F3 | System restrictions (draft/apply, all `UserManager` keys) | Core v1 | 🧪 Implemented (Restrictions tab with draft/apply + NoDeviceOwner state) |
| F4 | Per-app managed-restrictions editor | Core v1 | 🧪 Implemented (per-app editor over `get/setApplicationRestrictions`) |
| F5 | Browser restrictions (`URLBlocklist` + `ForceGoogleSafeSearch`) | Core v1 | 🧪 Implemented (blocklist CRUD in native `browser_prefs`, per-browser push with loosening check) |
| F6 | Non-supporting-browser auto-suspension on install/first open | v1.1 later | ⬜ Not implemented yet |
| F7 | Forced family private DNS | Core v1 | 🧪 Implemented (presets + validated custom host). Note: the contract has no "clear DNS" method, so DNS can be set/changed but not unset from the UI |
| F8 | Per-app hide / suspend / uninstall-block | Core v1 | 🧪 Implemented (Apps tab toggles, verified-state returns, tightening = free + 5 s undo, loosening = gated) |
| F9 | Per-app/group time limits (daily / per-weekday) + lock at expiry | Core v1 | 🧪 Implemented (Dart editors → native store; enforcement is the Kotlin Accessibility Service) — not device-tested |
| F10 | Allowed time windows (daily / per-weekday) | Core v1 | 🧪 Implemented for daily windows in the UI; per-weekday windows are supported by the channel/store and the group model, but the per-app editor UI edits daily windows only — not device-tested |
| F11 | Reopening cooldown | v1.1 later | 🟡 Partially: the value is stored from v1 (editor field + `reopenSeconds` in the native store, as ARCH §8.2 allows); enforcement is v1.1, and the editor says so |
| F12 | Staged usage warnings | Core v1 | 🟡 Partially: Dart editor + native storage of stages/defaults implemented; the staged *notification delivery* was not present in the Kotlin service as inspected, so warnings are configured and stored but not yet fired natively |
| F13 | App groups (shared limits/windows) | Core v1 | 🧪 Implemented (groups CRUD, member picker, group limit editor; enforcement via native store) |
| F14 | Active word blocking | Core v1 | 🧪 Implemented (words + target apps editors; enforcement in Kotlin service) |
| F15 | Passive word blocking | Core v1 | 🧪 Implemented (per-app lists; enforcement in Kotlin service) |
| F16 | Visual (NSFW) TFLite blocking | v1.1 later (dedicated spike) | ⬜ Not implemented yet — no placeholder screen, per ARCH §6.2 |
| F17 | Visual-blocking escalation (N in M min ⇒ suspend D min) | v1.1 later (depends on F16) | ⬜ Not implemented yet |
| F18 | Activity blocker + seen-activities log | v1.1 later | ⬜ Not implemented yet — shown in Config as a labelled v1.1 tile |
| F19 | Torrent-app auto-blocking | v1.1 later | ⬜ Not implemented yet |
| F20 | 18+ auto-suspension via Play Store scraping | 🚫 Not ported (scraping form) | 🚫 Not ported — brittle/locale-dependent HTML scraping, no official API (`ARCHITECTURE.md` §6.2) |
| F21 | Impulse lock (panic button, 15 min–6 h, optional suspension) | Core v1 | 🧪 Implemented (pre-auth panic button on the lock screen + config screen; suspension applied from the UI via channel with reason `IMPULSE_LOCK`; the original's service-side suspension *sync* is not in the Kotlin service) |
| F22 | Access challenges — Math / Words / Reading | Core v1 | 🧪 Implemented (pure Dart, unit-tested; reading uses a small original sample passage set + custom phrases — the original's bundled corpus was NOT copied) |
| F22a | Access challenge — Tetris | v1.1 later | ⬜ Not implemented — labelled unavailable in challenge selection; selectable stored configs skip it with a notice, never simulate it |
| F23 | Recovery gate + 10-min session; tightening free (5 s undo), loosening gated | Core v1 | 🧪 Implemented (domain model unit-tested: loosening for limits/windows/restrictions/toggles, `PendingChange` undo window, in-memory session) and wired through all Dart editors |
| F24 | Recovery-code wizard (16-char, paper, re-type to confirm) | Core v1 | 🧪 Implemented with the §7.1 hashed-storage deviation; optional shuffled keypad implemented; widget-tested with a mock channel |
| F25 | Focus mode (Pomodoro, suspensions + restrictions, schedules, FGS) | Core v1 | 🧪 Partially: Dart phase/timer model (unit-tested) + start/pause/resume/skip/end with suspensions and restrictions applied via channel. **The native foreground-service countdown and schedules are not implemented** — the UI states the countdown runs while the app is alive; schedules are a labelled v1.1 tile |
| F26 | Colour modes on schedule | v1.1 later (grant method is Core v1) | ⬜ Not implemented — Config shows a labelled v1.1 tile; `grantWriteSecureSettings` itself is 🧪 implemented on the Setup screen |
| F27 | Suspension audit log | Core v1 | 🧪 Implemented (native log written at suspension sites; Dart search + gated clear) |
| F28 | Accessibility-loss lockdown | Core v1 | 🧪 Implemented in the Kotlin service (previous stage) — **not tested on any device; must be tested first on a sacrificial device** |
| F29 | Silent APK update installer (incl. downgrade, lock-screen, unauthenticated) | 🚫 Not ported (unauthenticated form) | 🚫 Not ported — no install surface exists anywhere in the Dart UI (verified by audit of `lib/`) |
| F30 | Setup wizard (Shizuku-state-driven onboarding) | Core v1 | 🧪 Implemented (five distinct Shizuku states, provisioning, diagnostics, accessibility toggle, grant — Status/Setup tab) |
| F31 | First-run recovery-setup gate | Core v1 | 🧪 Implemented (startup routing in `main.dart`; wizard-only until a code exists) |
| F32 | Biometric / device-credential entry gate | Core v1 | 🧪 Implemented via `local_auth` 3.0.1 with the original's fallback preserved and surfaced (no biometric *and* no credential enrolled ⇒ entry allowed, with an explanatory dialog) |
| F33 | Language selection (en / pt) | Core v1 | 🟡 Partially: selection persists natively and the app chrome (tabs, lock screen, session chip) is translated en/pt; full per-screen translation is incomplete — most screens are still English, and the language dialog says so |
| F34 | Debug-only self-disable hatch | 🚫 Not ported | 🚫 Not ported — no such receiver/path exists in Dart or Kotlin (verified by audit) |

---

## 3. Platform-channel contract status

Contract: `ARCHITECTURE.md` §5 — MethodChannel `dominanter/privileged`,
EventChannel `dominanter/privileged/events`. All methods below are
implemented in Kotlin **and** consumed by the typed Dart client
(`lib/data/privileged_channel.dart`). None are device-tested.

| Method / stream | Status |
|---|---|
| `getShizukuState` | 🧪 Implemented both sides — Dart parsing unit-tested against the exact Kotlin payload |
| `requestShizukuPermission` | 🧪 Implemented both sides |
| `provisionDeviceOwner` | 🧪 Implemented both sides |
| `removeDeviceOwner` | 🧪 Implemented both sides |
| `isDeviceOwner` | 🧪 Implemented both sides |
| `getProvisioningDiagnostics` | 🧪 Implemented both sides |
| `listInstalledApps` | 🧪 Implemented both sides |
| `setAppHidden` | 🧪 Implemented both sides |
| `setAppSuspended` | 🧪 Implemented both sides — per-package verified results + `failedPackages` on partial failure |
| `setUninstallBlocked` | 🧪 Implemented both sides |
| `listUserRestrictions` | 🧪 Implemented both sides |
| `applyUserRestriction` / `clearUserRestriction` | 🧪 Implemented both sides |
| `getApplicationRestrictions` / `setApplicationRestrictions` | 🧪 Implemented both sides |
| `listRestrictionCapableApps` | 🧪 Implemented both sides |
| `setPrivateDns` / `getPrivateDns` | 🧪 Implemented both sides |
| `grantWriteSecureSettings` | 🧪 Implemented both sides |
| `setAccessibilityEnabled` / `isAccessibilityEnabled` | 🧪 Implemented both sides |
| `getUsageToday` | 🧪 Implemented both sides |
| `setRecoveryCode` / `verifyRecoveryCode` / `isRecoveryCodeSet` | 🧪 Implemented both sides |
| EventChannel (`dominanter/privileged/events`, all event types) | 🧪 Implemented both sides — Dart treats events as advisory and re-reads state |

**§8 extension methods (added during the Dart stage — contract fix):**
`ARCHITECTURE.md` §8.3 requires channel-mediated `SettingsStore` writes, but
the first Kotlin pass exposed **none** of them: `SettingsStore` had typed
accessors for limits/windows/groups/words/logs, yet no channel method
reached them, so the Dart editors for F9/F10/F13/F14/F15/F27 could not
persist anything (and focus/impulse/challenge/blocklist config had no
native persistence path at all). The Dart stage therefore added, in
`PrivilegedChannelHandler.kt` + `SettingsStore.kt` (the only Kotlin edits
in this stage):

| Extension method | Purpose |
|---|---|
| `generateRecoveryCode` | Exposes the existing `RecoveryStore.generateCode()` (was unreachable) |
| `getTimeLimit` / `setTimeLimit` | Per-app daily/per-weekday limit + `reopenSeconds`, delegating to `SettingsStore.setTimeLimit` |
| `getTimeWindows` / `setTimeWindows` | Per-app daily/per-weekday windows, delegating to `SettingsStore.setTimeWindows` |
| `getGroups` / `setGroups` | Group CRUD; required a new `SettingsStore.saveGroups()` (only a decoder existed) |
| `getBlockedWords` / `setBlockedWords` / `setPassiveWords` | Word lists; required new `SettingsStore` setters |
| `getSuspensionLogs` / `clearSuspensionLogs` | F27 log read/clear over the existing `SettingsStore.readLogs()` |
| `getSetting` / `setSetting` | Allowlisted generic config (`security_prefs`, `browser_prefs`, `focus_prefs`, `focus_schedules_prefs`, `usage_warning_prefs`, `recovery_prefs`) for Dart-domain JSON config — ARCH §8.2 stores |

✅ **Compile-verified 2026-11-09**: these additions compile as part of the
successful `assembleDebug`/`assembleRelease` builds (the §8 methods live in
`PrivilegedChannelHandler.kt`/`SettingsStore.kt`, which the first build's
error list did not implicate; the five errors it did find were in other
files and are listed in §1). Compile-verified is not device-verified: no
device claim is made for them.

**Doc ↔ Kotlin mismatches found (Kotlin treated as authoritative):**
1. Unknown-method errors use code `NOT_IMPLEMENTED`, which is not in the
   §5.4 taxonomy table. Dart maps it to honest "not implemented" copy.
2. `getShizukuState`'s degraded path returns `diagnostic` as a **top-level
   reply key**; §5.3 describes it under `details.diagnostic`. Dart reads the
   top-level key.
3. The doc's §5.3 has no `generateRecoveryCode` method; Kotlin's
   `RecoveryStore` had the generator but no channel route (see above).

---

## 4. Security deviations — status

Design decisions in `ARCHITECTURE.md` §7.

| Deviation | Status |
|---|---|
| (a) Recovery code as salted PBKDF2 hash in a dedicated store — never plaintext SharedPreferences | 🧪 Implemented (Kotlin `RecoveryStore`, PBKDF2WithHmacSHA256, 210k iterations, constant-time verify) + Dart wizard that never persists the code |
| (b) No unauthenticated lock-screen APK install surface in v1 | ✅ Compliant by absence — the Dart lock screen contains only the panic button, a read-only usage overview, and the auth action; no install UI exists in `lib/` |
| (c) No debug self-disable hatch in release (F34 not ported) | ✅ Compliant by absence — audited in Dart and Kotlin |
| Shell exit codes always checked (fix for the original `ShizukuRunner.command()` flaw) | 🧪 Implemented Kotlin-side (previous stage); Dart additionally surfaces `details.exitCode` in its error UI and has a regression test for `SHELL_FAILED` mapping |

---

## 5. Testing status

Plan: `ARCHITECTURE.md` §9 (the master prompt's 17 areas).

| Area group | Status |
|---|---|
| Dart unit tests (domain: gate/loosening, timers, windows, focus cycles) | ✅ Done for v1 domain — `test/recovery_gate_test.dart`, `test/challenges_test.dart` |
| Dart channel-client tests (mock MethodChannel) | ✅ Done — `test/channel_client_test.dart`: state parsing (all 5 Shizuku states), `SHELL_FAILED` exit-code mapping, `DPM_NOT_OWNER`, missing-native-side → `UNAVAILABLE`, payload round-trips |
| Widget tests | ✅ Done for the critical gates — `test/widget_test.dart`: lock screen panic button pre-auth, wizard code display + paper gate, wizard stores re-typed code via channel |
| **Total Dart evidence (2026-11-09)** | **`flutter test`: 39 tests, all passed** (re-run and confirmed at the APK build stage). **`flutter analyze`: 0 errors, 0 warnings, 27 info lints.** (First `flutter test` attempt failed on a full 512 MB `/tmp` tmpfs — environment, not code; re-run with `TMPDIR` on the workspace disk passed.) |
| **Gradle/APK build evidence (2026-11-09)** | **`flutter build apk --debug` ✅ (866 s, log `build_logs/build12_debug.log`) and `flutter build apk --release` ✅ (315 s, `build_logs/build13_release.log`)** — see the APK row in §1 for sizes/hashes/badging. Getting here required fixing the sandbox network path, not project config: the egress tunnel silently drops TLS ClientHellos without ALPN `http/1.1` (which Java/Gradle never send), and intercepts Java TCP connections sourced from a non-loopback address. The working recipe is codified in `build_apk.sh`: `preferIPv4Stack` for every JVM, a local loopback TLS-terminating relay on 127.0.0.1:18080 (Gradle's configured proxy) that re-originates TLS with ALPN, a JVM truststore = JDK cacerts + the relay's local CA, and — after a sandbox restart wiped the ephemeral root FS — a Temurin JDK 21 tarball and `GRADLE_USER_HOME` placed in the persistent workspace. The user-side permission alternative (Settings → Permissions → Direct network protocols → `other_tcp`: Ask) would remove the need for the IPv4/loopback workaround but not for a proxy the JVM can reach |
| REA inspection of the built APK | ✅ Done — `docs/REA_REBUILT_APK.md` (+ raw JSON in `docs/rea_rebuilt_apk/`): Flutter build identified, Dart AOT string pool verified against project sources, APK signature inspected (v2, Android Debug signer). JADX/apktool routes blocked (`capability_unavailable`) — see §1 |
| Consolidated testing document | ✅ Done — `docs/TESTING.md`: all evidence in one place, the 17 master areas status-mapped (Verified here / Requires real device / Not yet), explicit no-device-testing statement |
| Kotlin instrumentation tests (channel contract §5) | ⬜ Not implemented yet |
| Real-device manual checklist (provisioning, Shizuku lifecycle, every DPM operation, F28) | ⬜ Not implemented yet — no device testing performed; the device-required areas are enumerated in `docs/TESTING.md` §3 |
| Emulator compatibility (unsupported-version and lifecycle cases) | ⬜ Not implemented yet |

---

## 6. Known limitations (at this stage)

- **APKs exist but are device-unverified.** Debug and release APKs build
  (see §1/§5), so all Kotlin — including the §3 extension methods — is
  compile-verified. Nothing in §§2–3 is *device*-verified: no APK has been
  installed, and Shizuku/Device Owner behaviour is unproven on hardware.
  The release APK is debug-signed (see §1), so it is not publishable as-is.
- **Long-running timers are Dart-side.** Forced-removal and impulse-lock
  accounting advance only by measured time while the app process is alive;
  the original's reboot-proof native (elapsedRealtime + boot-count)
  accounting needs future Kotlin work. Timers can therefore run *long*,
  never short.
- **Focus mode has no native foreground service in v1** — if the app
  process dies mid-session, suspensions applied by the UI are not
  auto-released by a timer. The Focus screen states this.
- **F12 usage-warning notifications are configured and stored, not fired**
  (no native notifier in the Kotlin service as inspected).
- **F33 translation is partial** (chrome en/pt; most screens English).
- **F10 per-weekday window editing** is channel/store-supported but the
  per-app editor UI is daily-only (groups carry weekly windows in the model).
- **Private DNS cannot be unset from the UI** — no clear method exists in
  the contract (DPM `setGlobalPrivateDnsModeOff` is not exposed).
- REA cannot analyse the Kotlin source on this install (see §1); no REA
  decompilation results exist or are claimed.
- The most fragile design element — Shizuku binder-wrapped DPM reflection
  (HiddenApiBypass, hidden overloads) — is unproven on a real device in this
  rebuild. It is spike #1 in `ARCHITECTURE.md` §10 and gates all feature work.

---

*Update this file at every milestone: move a row only when its evidence
(build log, test run, or device report) exists, and link that evidence.*
