# Dominanter — Implementation Status

> **Last updated:** 2026-11-09 (Dart UI stage)
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
| REA analysis results | ✅ Done | `analysis/REA_AND_GITHUB.md` + raw outputs. Honest finding: REA has no Kotlin-source route on this install; its one applicable result is the hashed source inventory. REA is re-planned for the APK stage only. |
| DeChainer ↔ Shizuku integration documentation | ✅ Done | `analysis/SHIZUKU_INTEGRATION.md` §8 |
| Architecture diagrams | ✅ Done | `project/docs/ARCHITECTURE.md` §3 — ASCII + Mermaid |
| Architecture document | ✅ Done | `project/docs/ARCHITECTURE.md` — design principles, channel contract, F1–F34 mapping, security deviations, data model, testing strategy |
| README.md (project) | ✅ Done | Full project README written 2026-11-09 (purpose, architecture, setup, permissions, tests, limitations, attribution); states honestly that there is no APK / no device testing yet |
| TESTING.md | ⬜ Not implemented yet | Test plan is `ARCHITECTURE.md` §9; results so far are in §5 below |
| REVERSE_ENGINEERING.md (project docs copy) | ⬜ Not implemented yet | To be derived from the `analysis/` reports for the published repo |
| LICENSE | ✅ Done | Apache License 2.0 (verbatim text, as in DeChainer/Shizuku sources), added 2026-11-09; attribution to DeChainer and Shizuku is in the README |
| Complete Flutter project (scaffold) | ✅ Done | Flutter 3.35.1 scaffold in `project/`; applicationId `io.github.alnajashia.dominanter` |
| Dart UI layer | 🧪 Implemented but not fully tested | ~6,400 lines in `lib/` (see §2). `flutter analyze`: **0 errors, 0 warnings**, 27 info-level lints (mostly `use_build_context_synchronously` behind `mounted` guards, one deprecated `RadioListTile.groupValue`). No device run yet. |
| Kotlin native implementation | 🧪 Implemented but not fully tested | 14 Kotlin files (~3,000 lines): channel handler, `ShizukuProvisioning`, `DeviceOwnerManager`, Accessibility Service, `SettingsStore`, `RecoveryStore`. Passed `flutter analyze` at scaffold stage; the §8 extension methods added in the Dart stage (see §3) have **not** yet been compile-verified by a Gradle build |
| Functional Shizuku integration | 🧪 Implemented but not fully tested | Contract implemented both sides; never run against a real Shizuku server / device |
| Reimplemented original features | 🧪 Partially | See §2 — Core v1 features are coded; v1.1 features are not; nothing is device-verified |
| Modern UI/UX (Material 3, light/dark) | 🧪 Implemented but not fully tested | Material 3, seed-colour light + dark themes, system/light/dark switch in Config; every screen has loading / empty / success / failure states; v1.1 features are labelled tiles, not fake controls |
| Automated tests | 🧪 Partially done | Dart: **39 tests, all passing** (`flutter test`, 2026-11-09) — see §5. Kotlin instrumentation tests: not written |
| Real-device testing report | ⬜ Not implemented yet | No device testing has been performed. No feature may be called verified before this exists for it |
| APK build | ⬜ Not implemented yet | No APK has been produced; the Gradle build is a separate step (network/Gradle issue) |
| GitHub push | ✅ First snapshot done | Destination confirmed by the user 2026-11-09: existing repo `alnajashia/dominanter`. **First push: commit `354897c` on `main`** (scaffold, 14 Kotlin files, architecture docs). The Dart UI layer and the §3 Kotlin contract extension were written *after* that snapshot and are **not yet pushed** — nor are the README/LICENSE written 2026-11-09; all are ready for the second push the user requested on UI completion |

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

⚠️ These Kotlin additions follow the existing handler/store patterns but
have **not been compiled by a Gradle build yet** (the APK/Gradle step is
separate). They must be compile-checked there before any device claim.

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
| **Total Dart evidence (2026-11-09)** | **`flutter test`: 39 tests, all passed. `flutter analyze`: 0 errors, 0 warnings, 27 info lints.** (First `flutter test` attempt failed on a full 512 MB `/tmp` tmpfs — environment, not code; re-run with `TMPDIR` on the workspace disk passed.) |
| Kotlin instrumentation tests (channel contract §5) | ⬜ Not implemented yet |
| Real-device manual checklist (provisioning, Shizuku lifecycle, every DPM operation, F28) | ⬜ Not implemented yet — no device testing performed |
| Emulator compatibility (unsupported-version and lifecycle cases) | ⬜ Not implemented yet |

---

## 6. Known limitations (at this stage)

- **No APK exists.** The Gradle build is a separate step; until it runs, the
  Kotlin §8 extension methods of §3 are not even compile-verified, and
  nothing in §§2–3 is device-verified.
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
