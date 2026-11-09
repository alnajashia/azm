# Dominanter — Implementation Status

> **Last updated:** 2026-11-09
> **Honesty rule:** a feature is listed as *Implemented and tested* only with
> build + test evidence. A successful build alone never upgrades a status.
> This is the **initial** version of this file: the analysis and architecture
> stages are done; **no application code exists yet**, and every feature and
> deliverable below says so.
>
> Legend: ✅ Done · 🟡 In progress · ⬜ Not implemented yet · 🚫 Not ported
> (deliberate, with reason — see `ARCHITECTURE.md` §6.2/§7) · 🧪 Implemented
> but not fully tested (none yet)

---

## 1. Stage / deliverable status

| Deliverable | Status | Evidence / notes |
|---|---|---|
| Reverse-engineering report — DeChainer features | ✅ Done | `analysis/DECHAINER_FEATURES.md` — F1–F34, storage, DPM inventory, Accessibility Service, source-verified at DeChainer v1.12.0 / commit `29822c0` |
| Reverse-engineering report — Shizuku integration | ✅ Done | `analysis/SHIZUKU_INTEGRATION.md` — Shizuku is setup-time only; 13 shell commands inventoried; binder-wrapped DPM path traced; API 13.1.5 |
| REA analysis results | ✅ Done | `analysis/REA_AND_GITHUB.md` + raw outputs (`rea_doctor.json`, `rea_help.txt`, `rea_inspect.json`, `rea_import_ref.json`). Honest finding: REA has no Kotlin-source route on this install (no Java/JADX/native engine); its one applicable result is the hashed source inventory. REA is re-planned for the APK stage only. |
| DeChainer ↔ Shizuku integration documentation | ✅ Done | `analysis/SHIZUKU_INTEGRATION.md` §8 (setup-time vs runtime paths) |
| Architecture diagrams | ✅ Done | `project/docs/ARCHITECTURE.md` §3 — ASCII + Mermaid layer diagrams, with the corrected setup-only Shizuku path |
| Architecture document | ✅ Done | `project/docs/ARCHITECTURE.md` — design principles, channel contract, F1–F34 mapping, security deviations, data model, testing strategy |
| Implementation status document | ✅ Done | This file (initial version) |
| README.md (project) | ⬜ Not implemented yet | Written in the documentation stage, once build instructions are real |
| TESTING.md | ⬜ Not implemented yet | Test plan is defined in `ARCHITECTURE.md` §9; the results document is created when testing runs |
| REVERSE_ENGINEERING.md (project docs copy) | ⬜ Not implemented yet | To be derived from the `analysis/` reports for the published repo |
| LICENSE | ⬜ Not implemented yet | Added only after attribution is finalised — DeChainer and Shizuku are Apache-2.0; Shizuku name/icon/applicationId restrictions noted in `ARCHITECTURE.md` §2 |
| Complete Flutter project (scaffold) | ⬜ Not implemented yet | No `pubspec.yaml`, no Dart code exists yet |
| Kotlin native implementation | ⬜ Not implemented yet | No Kotlin code exists yet (`ShizukuProvisioning`, `DeviceOwnerManager`, Accessibility Service, `SettingsStore` are design only) |
| Functional Shizuku integration | ⬜ Not implemented yet | Contract defined in `ARCHITECTURE.md` §5; not coded |
| Reimplemented original features | ⬜ Not implemented yet | See §2 — every feature is *Not implemented yet* except the deliberate *Not ported* decisions |
| Modern UI/UX (Material 3, light/dark) | ⬜ Not implemented yet | Design requirements recorded in `ARCHITECTURE.md` §3.3/§6; no UI code exists |
| Automated tests | ⬜ Not implemented yet | Strategy defined in `ARCHITECTURE.md` §9 (17 areas); no test code exists |
| Real-device testing report | ⬜ Not implemented yet | No device testing has been performed. No feature may be called verified before this exists for it |
| APK build | ⬜ Not implemented yet | No build has been produced |
| GitHub push | ⬜ Not implemented yet | Destination confirmed by the user 2026-11-09: existing empty repo `alnajashia/dominanter` (`https://github.com/alnajashia/dominanter`). `alnajashia/dominater` does **not** exist. Nothing has been pushed; the repo is empty, so there is no existing work to preserve |

---

## 2. Feature status — F1–F34

Scope is from `ARCHITECTURE.md` §6. **Status is independent of scope:** a
*Core v1* scope does not mean any part of it is built.

| # | Feature | v1 scope | Status |
|---|---|---|---|
| F1 | Device Owner provisioning via Shizuku (+ `user_setup_complete` bypass) | Core v1 | ⬜ Not implemented yet |
| F2 | Device Owner removal (in-session; 48-h forced removal) | Core v1 | ⬜ Not implemented yet |
| F3 | System restrictions (draft/apply, all `UserManager` keys) | Core v1 | ⬜ Not implemented yet |
| F4 | Per-app managed-restrictions editor | Core v1 | ⬜ Not implemented yet |
| F5 | Browser restrictions (`URLBlocklist` + `ForceGoogleSafeSearch`) | Core v1 | ⬜ Not implemented yet |
| F6 | Non-supporting-browser auto-suspension on install/first open | v1.1 later | ⬜ Not implemented yet |
| F7 | Forced family private DNS | Core v1 | ⬜ Not implemented yet |
| F8 | Per-app hide / suspend / uninstall-block | Core v1 | ⬜ Not implemented yet |
| F9 | Per-app/group time limits (daily / per-weekday) + lock at expiry | Core v1 | ⬜ Not implemented yet |
| F10 | Allowed time windows (daily / per-weekday) | Core v1 | ⬜ Not implemented yet |
| F11 | Reopening cooldown | v1.1 later | ⬜ Not implemented yet |
| F12 | Staged usage warnings | Core v1 | ⬜ Not implemented yet |
| F13 | App groups (shared limits/windows) | Core v1 | ⬜ Not implemented yet |
| F14 | Active word blocking | Core v1 | ⬜ Not implemented yet |
| F15 | Passive word blocking | Core v1 | ⬜ Not implemented yet |
| F16 | Visual (NSFW) TFLite blocking | v1.1 later (dedicated spike) | ⬜ Not implemented yet |
| F17 | Visual-blocking escalation (N in M min ⇒ suspend D min) | v1.1 later (depends on F16) | ⬜ Not implemented yet |
| F18 | Activity blocker + seen-activities log | v1.1 later | ⬜ Not implemented yet |
| F19 | Torrent-app auto-blocking | v1.1 later | ⬜ Not implemented yet |
| F20 | 18+ auto-suspension via Play Store scraping | 🚫 Not ported (scraping form) | 🚫 Not ported — brittle/locale-dependent HTML scraping, no official API; alternative mechanism is a v1.1 research spike (`ARCHITECTURE.md` §6.2) |
| F21 | Impulse lock (panic button, 15 min–6 h, optional suspension) | Core v1 | ⬜ Not implemented yet |
| F22 | Access challenges — Math / Words / Reading | Core v1 | ⬜ Not implemented yet |
| F22a | Access challenge — Tetris | v1.1 later | ⬜ Not implemented yet — full game engine; Math/Words/Reading preserve the gate's friction model in v1 |
| F23 | Recovery gate + 10-min session; tightening free (5 s undo), loosening gated | Core v1 | ⬜ Not implemented yet |
| F24 | Recovery-code wizard (16-char, paper, re-type to confirm) | Core v1 | ⬜ Not implemented yet — with the §7.1 hashed-storage deviation designed, not coded |
| F25 | Focus mode (Pomodoro, suspensions + restrictions, schedules, FGS) | Core v1 | ⬜ Not implemented yet |
| F26 | Colour modes on schedule (grayscale/night/extra-dim/inversion) | v1.1 later (grant method is Core v1) | ⬜ Not implemented yet |
| F27 | Suspension audit log | Core v1 | ⬜ Not implemented yet |
| F28 | Accessibility-loss lockdown | Core v1 | ⬜ Not implemented yet — must be tested first on a sacrificial device |
| F29 | Silent APK update installer (incl. downgrade, lock-screen, unauthenticated) | 🚫 Not ported (unauthenticated form) | 🚫 Not ported — no unauthenticated lock-screen install surface in v1 (`ARCHITECTURE.md` §7.2); authenticated in-session alternative is a v1.1 candidate requiring its own security review |
| F30 | Setup wizard (Shizuku-state-driven onboarding) | Core v1 | ⬜ Not implemented yet |
| F31 | First-run recovery-setup gate | Core v1 | ⬜ Not implemented yet |
| F32 | Biometric / device-credential entry gate | Core v1 | ⬜ Not implemented yet |
| F33 | Language selection (en / pt) | Core v1 | ⬜ Not implemented yet |
| F34 | Debug-only self-disable hatch | 🚫 Not ported | 🚫 Not ported — must not exist in any release build (`ARCHITECTURE.md` §7.3) |

---

## 3. Platform-channel contract status

Contract: `ARCHITECTURE.md` §5 — MethodChannel `dominanter/privileged`,
EventChannel `dominanter/privileged/events`.

| Method / stream | Status |
|---|---|
| `getShizukuState` | ⬜ Not implemented yet |
| `requestShizukuPermission` | ⬜ Not implemented yet |
| `provisionDeviceOwner` | ⬜ Not implemented yet |
| `removeDeviceOwner` | ⬜ Not implemented yet |
| `isDeviceOwner` | ⬜ Not implemented yet |
| `getProvisioningDiagnostics` | ⬜ Not implemented yet |
| `listInstalledApps` | ⬜ Not implemented yet |
| `setAppHidden` | ⬜ Not implemented yet |
| `setAppSuspended` | ⬜ Not implemented yet |
| `setUninstallBlocked` | ⬜ Not implemented yet |
| `listUserRestrictions` | ⬜ Not implemented yet |
| `applyUserRestriction` / `clearUserRestriction` | ⬜ Not implemented yet |
| `getApplicationRestrictions` / `setApplicationRestrictions` | ⬜ Not implemented yet |
| `listRestrictionCapableApps` | ⬜ Not implemented yet |
| `setPrivateDns` / `getPrivateDns` | ⬜ Not implemented yet |
| `grantWriteSecureSettings` | ⬜ Not implemented yet |
| `setAccessibilityEnabled` / `isAccessibilityEnabled` | ⬜ Not implemented yet |
| `getUsageToday` | ⬜ Not implemented yet |
| `setRecoveryCode` / `verifyRecoveryCode` / `isRecoveryCodeSet` | ⬜ Not implemented yet |
| EventChannel (`dominanter/privileged/events`, all event types) | ⬜ Not implemented yet |

---

## 4. Security deviations — status

Design decisions in `ARCHITECTURE.md` §7. All are **designed, none coded**.

| Deviation | Status |
|---|---|
| (a) Recovery code as salted PBKDF2 hash in Keystore-backed storage — never plaintext SharedPreferences | ⬜ Not implemented yet (designed, §7.1) |
| (b) No unauthenticated lock-screen APK install surface in v1 | 🚫 Surface not ported by decision (§7.2) — compliance is verified by its absence in code review + manifest/Activity audit once code exists |
| (c) No debug self-disable hatch in release (F34 not ported) | 🚫 Hatch not ported by decision (§7.3) — compliance is verified by receiver/manifest audit once code exists |
| Shell exit codes always checked (fix for the original `ShizukuRunner.command()` flaw) | ⬜ Not implemented yet (contract requirement, §5.4 — includes a named regression test in §9 area 15) |

---

## 5. Testing status

Plan: `ARCHITECTURE.md` §9 (the master prompt's 17 areas, each marked for
real-device requirement). **No tests have been written or run.**

| Area group | Status |
|---|---|
| Dart unit tests (domain: gate/loosening, timers, windows, focus cycles) | ⬜ Not implemented yet |
| Widget tests (screens, setup state machine, fake channel) | ⬜ Not implemented yet |
| Kotlin instrumentation tests (channel contract §5) | ⬜ Not implemented yet |
| Real-device manual checklist (provisioning, Shizuku lifecycle, every DPM operation, F28) | ⬜ Not implemented yet — no device testing performed |
| Emulator compatibility (unsupported-version and lifecycle cases) | ⬜ Not implemented yet |

---

## 6. Known limitations (at this stage)

- Everything in §§2–5 is unbuilt: the only verified artefacts in the project
  are the `analysis/` reports and this architecture.
- The destination repo name in the original master prompt (`dominater`) does
  not exist; the confirmed target is the existing empty `alnajashia/dominanter`.
  The applicationId (`io.github.alnajashia.dominanter`) and channel names
  (`dominanter/privileged`) follow the confirmed spelling.
- REA cannot analyse the Kotlin source on this install (see §1); no REA
  decompilation results exist or are claimed.
- The most fragile design element — Shizuku binder-wrapped DPM reflection
  (HiddenApiBypass, hidden overloads) — is unproven on a real device in this
  rebuild. It is spike #1 in `ARCHITECTURE.md` §10 and gates all feature work.

---

*Update this file at every milestone: move a row only when its evidence
(build log, test run, or device report) exists, and link that evidence.*
