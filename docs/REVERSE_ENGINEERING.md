# Reverse Engineering — DeChainer & Shizuku

> How Dominanter was derived: a source-level reverse-engineering study of
> **DeChainer v1.12.0** (commit `29822c0`) and its **Shizuku** integration,
> performed 2026-11-09, plus an audit of the REA tool that was mandated for
> the work. This document is the repo-appropriate consolidation of the
> three working reports produced during the study; the full reports are
> the evidence trail and are cited per section.
>
> Design consequences live in [`ARCHITECTURE.md`](ARCHITECTURE.md) — this
> document describes the *original* system and the findings; it does not
> duplicate the rebuild's design. Results of running REA on Dominanter's
> own built APK are in [`REA_REBUILT_APK.md`](REA_REBUILT_APK.md).

**Sources studied**

| Project | Source | Licence |
|---|---|---|
| DeChainer | https://github.com/warleysr/dechainer — v1.12.0, commit `29822c059b74def1a14d609b20e2647f02162d05`, `applicationId io.github.warleysr.dechainer`, 111 Kotlin files, ~20.8k LOC | Apache License 2.0 — © warleysr |
| Shizuku | https://github.com/RikkaApps/Shizuku (incl. the Shizuku-API submodule) — DeChainer pins API/provider `13.1.5` | Apache License 2.0 — © RikkaApps (with Shizuku's own name/icon/applicationId restrictions, see README attribution) |

Dominanter is a clean-room reimplementation of DeChainer's *verified
behaviour*, not a copy of its source.

---

## 1. What DeChainer actually is

DeChainer is **not** a Shizuku app manager, package manager, or debloater.
In its author's words, it is *"a hard-to-bypass Android barrier against
pornography and digital addiction — Device Owner restrictions, an
Accessibility Service and an on-device ML model working together, built so
that your future self can't simply turn it off."* It is a self-imposed
lockdown system whose threat model is **the device owner's own future,
impulsive self**.

Three privileged pillars, in order of importance:

1. **Device Owner** (`DevicePolicyManager`, DPM) — the privileged core:
   app hide/suspend/uninstall-block, user restrictions, managed
   restrictions, global private DNS. Everything else is setup or
   enforcement around this.
2. **Accessibility Service** — a single 1,546-line service
   (`DechainerAccessibilityService.kt`) that enforces time
   limits/windows, reopening cooldowns, active/passive word blocking,
   activity blocking, colour-filter integrity, impulse suspensions, and
   install-watching, and drives the on-device NSFW classifier.
3. **Shizuku** — **setup-time only**: a bootstrap bridge used to *become*
   Device Owner, enable the Accessibility Service, and grant
   `WRITE_SECURE_SETTINGS`. After setup, enforcement runs entirely without
   Shizuku (§3).

The anti-bypass model is the product: a 16-character paper-only recovery
code; a 10-minute recovery session; challenges (math / typing / Tetris /
slow reading) before a session opens; *tightening* any restriction is
always free (with a 5-second undo) while *loosening* requires the code; an
impulse lock anchored to `elapsedRealtime` so clock changes can't shorten
it; and a 48-hour delayed forced removal as the only code-free escape.

Verified platform envelope: `minSdk 30`, `targetSdk/compileSdk 36`,
Java 21. Verified **absent**: arbitrary install/uninstall, root, accounts,
telemetry/analytics, a VPN/DNS filter of its own, and any use of
`UsageStatsManager` (usage is self-tracked by the Accessibility Service,
despite declaring `PACKAGE_USAGE_STATS`).

Storage is **SharedPreferences only** — 20 named preference files, no
database, no DataStore, no Room. One consequence is a genuine flaw in the
original: **the recovery code is stored in plaintext** in
`recovery_prefs` and checked with a plain `==` (see §6, deviation (a)).

## 2. Feature inventory — F1–F34 (condensed)

Full evidence — file/function citations, storage keys, DPM inventory —
is in the working report `DECHAINER_FEATURES.md` (703 lines). Class key:
**F** = fully understood, **P** = partially understood (external/brittle
dependency), **N** = effect not reproducible without native/Device Owner
(the UI is portable; the effect is Kotlin/DPM/Accessibility).

| # | Feature | Class | Rebuild disposition (detail: `IMPLEMENTATION_STATUS.md` §2) |
|---|---|---|---|
| F1 | Device Owner provisioning via Shizuku, incl. `user_setup_complete` bypass | F/N | Core v1 — Kotlin provisioning |
| F2 | Device Owner removal; 48-hour forced removal | F/N | Core v1 |
| F3 | System restrictions (all `UserManager` keys, draft/apply) | F/N | Core v1 |
| F4 | Per-app managed-restrictions editor | F/N | Core v1 |
| F5 | Browser restrictions (`URLBlocklist` + `ForceGoogleSafeSearch`) | F/N | Core v1 |
| F6 | Non-supporting-browser auto-suspension on install/first open | F/N | v1.1 |
| F7 | Forced family private DNS | F/N | Core v1 |
| F8 | Per-app hide / suspend / uninstall-block | F/N | Core v1 |
| F9 | Per-app/group time limits (daily/per-weekday), lock at expiry | F/N | Core v1 |
| F10 | Allowed time windows (daily/per-weekday) | F/N | Core v1 (UI edits daily windows) |
| F11 | Reopening cooldown | F/N | Value stored in v1; enforcement v1.1 |
| F12 | Staged usage warnings | F/N | Configured/stored in v1; native firing not yet implemented |
| F13 | App groups (shared limits/windows) | F/N | Core v1 |
| F14 | Active word blocking (focused editable field) | F/N | Core v1 |
| F15 | Passive word blocking (anywhere on screen, per-app lists) | F/N | Core v1 |
| F16 | Visual NSFW blocking — on-device MobileNetV2 TFLite (17 MB model, labels drawings/hentai/neutral/porn/sexy), Accessibility screenshots + media-region heuristics, 2 s throttle | F/N | v1.1 — dedicated spike; hardest port, no Flutter plugin covers this pipeline |
| F17 | Visual-blocking escalation (N blocks in M min ⇒ suspend D min; defaults 5 / 15 min / 30 min) | F/N | v1.1 (depends on F16) |
| F18 | Activity blocker + seen-activities log | F/N | v1.1 |
| F19 | Torrent-app auto-blocking (magnet/`.torrent` handlers, default off) | F/N | v1.1 |
| F20 | 18+ auto-suspension via Play Store HTML scraping (Jsoup) | P/N | **Not ported** — brittle, locale-dependent scraping, no official API |
| F21 | Impulse lock / panic button (15 min–6 h, optional suspension, pre-auth on lock screen) | F/N | Core v1 |
| F22 | Access challenges: Math (×5), Words (typing streak), Tetris (1–15 min), Reflective Reading (Bible/Quran/quotes/custom) | F | Math/Words/Reading Core v1 (pure Dart); Tetris v1.1 |
| F23 | Recovery gate + 10-min session; tightening free (5 s undo), loosening gated | F | Core v1 — the safety model, reimplemented faithfully |
| F24 | Recovery-code wizard (16-char, paper, re-type to confirm, optional shuffled keypad) | F | Core v1 — with deviation (a) on storage |
| F25 | Focus mode (Pomodoro: suspend apps/groups + restrictions during focus, schedules, foreground-service countdown) | F/N | Core v1 partially — Dart timer/suspension logic done; native foreground service + schedules v1.1 |
| F26 | Colour modes on schedule (grayscale/night light/extra dim/inversion, tamper-reverting) | F/N | v1.1 (the `WRITE_SECURE_SETTINGS` grant method is Core v1) |
| F27 | Suspension audit log (8 `SuspensionReason` values) | F | Core v1 |
| F28 | Accessibility-loss lockdown — service off ⇒ suspend every controlled package + `DISALLOW_INSTALL_APPS` + re-enable plea; reversed on re-enable | F/N | Core v1 — anti-bypass keystone; **device-unverified, sacrificial-device test first** |
| F29 | Silent APK update/downgrade installer, reachable from the lock screen **without authentication** | F/N | **Not ported** in that form — unauthenticated install surface is a security liability |
| F30 | Setup wizard driven by live Shizuku state | F/N | Core v1 |
| F31 | First-run gate — app unusable until a recovery code exists | F | Core v1 |
| F32 | Biometric/device-credential entry gate (entry allowed if neither enrolled — deliberate fallback; panic button stays one tap away, auth never auto-prompted) | F | Core v1 via `local_auth`, fallback preserved |
| F33 | Language selection (en/pt) | F | Core v1 partially — chrome translated, per-screen pt incomplete |
| F34 | Debug-only self-disable hatch (`DEBUG_INSTALL` receiver) | F | **Not ported** — flagged so it is never cloned into a release |

Other findings that shaped the rebuild:

- **Screens:** single-Activity Compose app, hand-rolled string navigation
  stack, 3 root tabs (Restrictions / Apps / Config), 10 Config
  sub-screens, and 7 standalone block activities (`TimeUpActivity`,
  `BlockedWordActivity`, `NsfwContentBlockedActivity`, …) — most
  `showOnLockScreen`, `singleInstance`, `excludeFromRecents`.
- **DPM inventory (grep-verified):** `add/clearUserRestriction`,
  `setPackagesSuspended`, `setApplicationHidden`, `setUninstallBlocked`,
  `get/setApplicationRestrictions`, global private DNS setters/getters,
  `setPermissionGrantState` (Focus only), `clearDeviceOwnerApp`.
  `device_admin_policies.xml` also lists password/wipe/lock policies that
  **no code ever calls** — decoy declarations, not features.
- **Active word blocking nuance:** despite README wording ("erased as
  typed"), the code checks field content when typing *ends*, then issues
  `GLOBAL_ACTION_BACK` and opens the block activity — no per-keystroke
  deletion. The rebuild implements the code's behaviour, not the prose.
- Small README/code drift was resolved in favour of code throughout
  (e.g. 4 pre-selected recommended restrictions in code vs "three" in
  prose).

## 3. Shizuku integration — the evidence

Full report: `SHIZUKU_INTEGRATION.md` (581 lines). Summary:

### 3.1 Detection, permission, liveness (exact sequence)

- **Manifest first:** the app declares `rikka.shizuku.ShizukuProvider`
  (authority `${applicationId}.shizuku`) — that is how the Shizuku server
  can deliver its binder into the app process at all.
- **Installed?** A `PackageManager` check for the manager package
  `moe.shizuku.privileged.api` — not a binder check.
- **Running?** `Shizuku.pingBinder()`, polled every 500 ms in the setup
  UI. DeChainer cannot start the Shizuku server; if it isn't running, the
  UI only links to the setup guide.
- **Version gate:** `Shizuku.isPreV11()` hard-fails permission and
  execution paths — no fallback, no distinct UI.
- **Permission:** `checkSelfPermission()` must be `PERMISSION_GRANTED`;
  otherwise `Shizuku.requestPermission(911)` (hard-coded request code
  911), with the result delivered to a registered
  `OnRequestPermissionResultListener`. `shouldShowRequestPermissionRationale()`
  is never called.
- **Dependencies:** API + provider `dev.rikka.shizuku:api:13.1.5` /
  `dev.rikka.shizuku:provider:13.1.5`; `HiddenApiBypass` for the
  provisioning path (§3.3).

### 3.2 The choke point and the 13 shell commands

All low-level Shizuku use is in one file, `utils/ShizukuRunner.kt`,
touching `moe.shizuku.server.IShizukuService.newProcess()` two ways:

- `exec(vararg)` — synchronous argv form; guards binder + pre-V11;
  returns a `ProcessResult` (exit code available) or `null` on failure.
- `command(String, listener)` — always `sh -c "<command>"`, callback
  form, **no binder/pre-V11 guard and it never checks the exit code**
  (empty stderr is treated as success). This flaw is fixed in the rebuild:
  every shell result carries its exit code and failures surface as
  `SHELL_FAILED` with code/command/stderr (see `ARCHITECTURE.md`).

The **complete** shell inventory — 13 invocations, no others exist
(verified by grepping every call site; notably there is **no**
`pm install/uninstall/disable`, `appops`, or `am` usage — app management
is DPM, not shell):

| # | Via | Command | Purpose |
|---|---|---|---|
| 1 | `exec` | `settings --user <userId> get secure user_setup_complete` | Read setup flag; bypass proceeds only if `"1"` |
| 2 | `exec` | `settings --user <userId> put secure user_setup_complete 0` | Temporarily mark setup incomplete so `setDeviceOwner` is allowed on a set-up device |
| 3 | `exec` | `settings --user <userId> put secure user_setup_complete 1` | Undo #2 (always, in `finally`) |
| 4 | `exec` | `settings --user <userId> get secure user_setup_complete` | Cold-start stuck-flag check |
| 5 | `exec` | `settings --user <userId> get global device_provisioned` | Only repair if genuinely provisioned |
| 6 | `command` | `pm grant io.github.warleysr.dechainer android.permission.WRITE_SECURE_SETTINGS` | Self-grant the protected permission (colour filters, secure settings) |
| 7 | `command` | `dpm set-device-owner io.github.warleysr.dechainer/.DechainerDeviceAdminReceiver` | **Fallback** Device Owner provisioning (§3.3) |
| 8 | `command` | `dumpsys account` | Setup diagnostic: list accounts that could block provisioning |
| 9 | `command` | `dpm list-owners` | Detect a different existing Device Owner |
| 10 | `command` | `pm list users` | Setup diagnostic: extra users/profiles block provisioning |
| 11 | `command` | `settings get secure enabled_accessibility_services` | Read enabled accessibility services |
| 12 | `command` | `settings put secure enabled_accessibility_services <colon-joined list>` (or `'null'` to revoke) | Enable/disable its own Accessibility Service without sending the user to Settings |
| 13 | `command` | `settings put secure accessibility_enabled 1` | Global accessibility master switch on |

(`<userId>` is `Process.myUid() / 100000`. Commands 1–5 are in
`DeviceOwnerRepository.kt`; 6 in `ColorFilterController.kt`; 7–13 in
`DeviceOwnerRepository.kt`.)

### 3.3 The primary provisioning path is not shell

`dpm set-device-owner` (#7) is only the fallback. The primary path is
binder-level: `withShizukuDevicePolicyManager()` reflectively replaces
`DevicePolicyManager`'s internal `mService` with a
`ShizukuBinderWrapper`-wrapped binder, so DPM transactions execute **as
the Shizuku server's UID** (2000 shell, or 0 root) in system_server. It
then calls hidden DPM methods by reflection (with `HiddenApiBypass`):
`setActiveAdmin`, `setDeviceOwner`, and
`forceUpdateUserSetupComplete` (to make the framework re-read the flag
from §3.2 #2/#3 immediately). The original service is restored in a
`finally` block. This is inherently Android-version-fragile, mutates a
shared framework object (not thread-safe), and silently degrades to the
shell fallback — it is the rebuild's #1 device-verification risk
(`ARCHITECTURE.md` §10), and it lives entirely in Kotlin, behind the
platform channel; it cannot be expressed in Dart.

### 3.4 Who needs what — dependency classification

| Capability | Shizuku | Device Owner | Accessibility |
|---|:---:|:---:|:---:|
| Become Device Owner | ✅ primary + fallback | — (result) | ❌ |
| Remove Device Owner | ❌ | ✅ | ❌ |
| Enable/disable Accessibility Service in-app | ✅ (#11–#13) | ❌ | — (result) |
| Grant `WRITE_SECURE_SETTINGS` | ✅ (#6) | ❌ | ❌ |
| Apply/restore colour filters | ❌ (after #6) | ❌ | ✅ |
| Hide/suspend/uninstall-block, user restrictions, private DNS | ❌ | ✅ | ❌ |
| Word/visual/activity blocking, time limits at runtime | ❌ | (state in places) | ✅ |
| Setup diagnostics (accounts/users/existing owner) | ✅ (#8–#10) | ❌ | ❌ |
| Stuck `user_setup_complete` repair (every cold start) | ✅ (#3–#5) | ❌ | ❌ |

Practical consequence: **if Shizuku is never granted, DeChainer cannot
complete setup — but a fully set-up DeChainer does not need Shizuku
running day-to-day.** Shizuku's own architecture (from the Shizuku
clone): a server process started via root or ADB (`app_process`,
UID 0/2000) whose binder reaches client apps through their declared
`ShizukuProvider`; per-app authorisation is persisted server-side and
revocable in the manager app; `IShizukuService.newProcess` is a plain
`Runtime.exec` in the server process after a permission check.

## 4. How each finding shaped the rebuild

| Finding | Rebuild consequence (`ARCHITECTURE.md` ref) |
|---|---|
| Shizuku is setup-time only | Shizuku lives **only** in the Kotlin provisioning layer (`ShizukuProvisioning`/`ShizukuRunner`); no runtime feature path touches it (§2, §5) |
| Privileged core is DPM + Accessibility | All privileged effects in Kotlin (`DeviceOwnerManager`, Accessibility Service) behind one MethodChannel `dominanter/privileged` (25 methods) + events channel; Dart is UI + pure logic only (§2–§5) |
| `ShizukuRunner.command()` ignores exit codes | Rebuild's runner always returns exit code/output/stderr; Dart surfaces `SHELL_FAILED` with details and has a regression test (§5.4; `TESTING.md` §2) |
| Recovery code in plaintext SharedPreferences | **Deviation (a):** salted PBKDF2 hash (PBKDF2WithHmacSHA256, 210k iterations, constant-time verify) in a dedicated store; the code can be verified but never re-displayed (§7.1) |
| Unauthenticated lock-screen APK installer (F29) | **Deviation (b):** not ported — no install surface exists anywhere in the rebuild (§6.2, §7.2) |
| Debug self-disable hatch (F34) | **Deviation (c):** not ported; audited absent in Dart and Kotlin (§7.2) |
| Play Store scraping (F20) | Not ported in scraping form — brittle/locale-dependent, no official API (§6.2) |
| Challenges, gate/session model, logs, timers are pure logic | Implemented in Dart and unit-tested (39 tests; `TESTING.md` §2); reading challenges use a small original sample passage set — the original's bundled corpus was **not** copied |
| Self-tracked usage (no UsageStatsManager) | Preserved: the Kotlin Accessibility Service tracks usage; no usage-stats permission abuse (§8) |
| Reflection-based provisioning is fragile | Kept in Kotlin, isolated behind the channel, with the `dpm` fallback; flagged as device-spike #1 (§10) |
| Storage was 20 SharedPreferences files | Mirrored conceptually in a clean Kotlin `SettingsStore` + Dart repositories; stores enumerated in §8 |

## 5. The REA audit — honest results

Full report: `REA_AND_GITHUB.md`. REA (Reverse Engineer Anything) 6.8.0
was installed and mandated as a primary tool. It was used for real; its
applicability to this project was tested, not assumed:

- **Catalog:** 175 CLI commands / 229 MCP tools / 6 prompts. All 229
  tool names were classified by category (native-binary ~59+, JS/Web/
  Electron ~26, ADB device ~24, Frida/GDB/Rizin ~20, Apple ~12,
  Android APK/JADX ~9–12, .NET ~7, Flutter/Dart AOT 2, other formats
  ~20, meta/evidence the remainder). **Zero tools parse Kotlin source.**
- **Environment:** `rea doctor` reports `healthy: false` — no native
  engine (Ghidra/Hopper/IDA), no JADX, no Kuna, and (at audit time) no
  Java on the machine. The connector gate allowed exactly one MCP tool,
  `inspect_analysis_settings`, which was run live and succeeded.
- **Tried on the DeChainer source tree:**
  - `import-reference-source` ✅ — the one useful source-tree result:
    inventory of 252 entries / 188 files / 21,035,192 bytes (Kotlin,
    Markdown, TOML, XML, YAML), git HEAD `29822c0…`, explicitly
    "historical reference only" (hashing/inventory, no Kotlin semantics).
  - `analyze` ✅ ran but routed to the JavaScript analyser: **0 sources,
    0 routes** — direct evidence no Kotlin route exists.
  - `inspect-android-package` on the source directory ❌
    `target_unavailable` — requires a standalone APK; neither source tree
    contains an `.apk`/`.aab`.
  - `inspect-artifact` on DeChainer's `nsfw_model.tflite` ❌
    `unsupported_target` / unsupported binary format.
- **Conclusion:** for a *source-available* Kotlin app, direct source
  analysis is the correct primary method, and that is what §§1–3 above
  are. Any claim that REA decompiled DeChainer on this install would be
  fabricated. REA's genuine value in this project is against a
  **compiled APK** — which is why, once Dominanter itself built, REA was
  run against it: `identify-flutter-build`, `inspect-dart-aot`, and
  `inspect-apk-signature` succeeded with real, independently useful
  results (including proof the release APK is debug-signed), while the
  JADX/apktool routes remain blocked by missing tooling. See
  [`REA_REBUILT_APK.md`](REA_REBUILT_APK.md).

## 6. Credits and licences

- **DeChainer** by **warleysr** — https://github.com/warleysr/dechainer —
  Apache License 2.0. Dominanter reimplements its verified behaviour;
  its source, assets, bundled reading corpus, and TFLite model were not
  copied.
- **Shizuku** by **RikkaApps** — https://github.com/RikkaApps/Shizuku —
  Apache License 2.0. Shizuku's additional restrictions are respected:
  Dominanter does not reuse Shizuku's launcher icons, the name "Shizuku"
  (other than to refer to the dependency), the applicationId
  `moe.shizuku.privileged.api`, or `moe.shizuku.manager.permission.*`;
  it uses its own applicationId `io.github.alnajashia.dominanter` and its
  own Shizuku provider authority.
- **REA** — `rea-agents` 6.8.0 (MIT) — used as an analysis tool only;
  see §5 and [`REA_REBUILT_APK.md`](REA_REBUILT_APK.md).
- Dominanter itself is licensed under the Apache License 2.0 — see
  [`../LICENSE`](../LICENSE).
