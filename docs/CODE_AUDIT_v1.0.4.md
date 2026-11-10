# Dominanter v1.0.4 — Full Line-by-Line Code Audit

**Date:** 2026-11-10 · **Version audited:** 1.0.4+5 (pre-release source)
**Method:** every file listed below was read completely, line by line,
against these criteria: (a) logic/correctness, (b) security — no
plaintext secrets, no silent failures (every shell result carries its
exit code), and a deliberate bypass hunt for any path that unlocks app
entry or loosens/activates a restriction without the intended
credential, including state-restoration, process-death and
intent/deep-link edges, (c) parity with the DeChainer behaviour
contracts, (d) zero placeholders/TODOs/dead code/fake buttons,
(e) l10n completeness, (f) palette compliance, (g) lifecycle/resource
leaks. Findings were fixed in code and the audit re-run until **zero
open findings** remained.

**Final state: 0 open findings.** `flutter analyze` → "No issues
found!"; `flutter test` → **99/99 passed** (72 pre-v1.0.4 + 27 new).

---

## 1. Coverage

### Dart — lib/ (27 files, 21,024 lines)

| File | Lines | Reviewed |
|---|---:|---|
| lib/main.dart | 146 | yes |
| lib/app_controller.dart | 206 | yes |
| lib/theme.dart | 223 | yes |
| lib/data/config_store.dart | 463 | yes |
| lib/data/privileged_channel.dart | 1001 | yes |
| lib/domain/challenges.dart | 403 | yes |
| lib/domain/entry_password.dart | 289 | yes |
| lib/domain/focus.dart | 347 | yes |
| lib/domain/recovery.dart | 425 | yes |
| lib/l10n/l10n.dart | 21 | yes |
| lib/l10n/app_en.arb / app_ar.arb | 1439 + 1439 | yes (see note) |
| lib/ui/apps_tab.dart | 2152 | yes |
| lib/ui/challenges_ui.dart | 385 | yes |
| lib/ui/common.dart | 378 | yes |
| lib/ui/config_screens.dart | 927 | yes |
| lib/ui/config_tab.dart | 668 | yes |
| lib/ui/entry_password_ui.dart | 394 | yes |
| lib/ui/impulse_focus_screens.dart | 1153 | yes |
| lib/ui/lock_screen.dart | 1046 | yes |
| lib/ui/pill_nav.dart | 220 | yes |
| lib/ui/recovery_ui.dart | 1048 | yes |
| lib/ui/restrictions_tab.dart | 327 | yes |
| lib/ui/setup_screen.dart | 857 | yes |
| lib/l10n/app_localizations.dart (generated) | 3716 | mechanical¹ |
| lib/l10n/app_localizations_ar.dart (generated) | 2105 | mechanical¹ |
| lib/l10n/app_localizations_en.dart (generated) | 2124 | mechanical¹ |

¹ The three generated localization files are produced by
`flutter gen-l10n` from the two ARB tables. They were verified
mechanically instead of by eye: the ARB key sets are asserted identical
by `test/localization_test.dart`, every generated getter maps 1:1 to an
ARB key, and the files were regenerated from the audited ARBs during
this audit (4 dead keys removed, see G2).

### Kotlin — android/app/src/main/kotlin/…/dominanter/ (18 files, 5,445 lines)

| File | Lines | Reviewed |
|---|---:|---|
| DominanterApplication.kt | 120 | yes |
| MainActivity.kt | 148 | yes |
| accessibility/BlockActivity.kt | 148 | yes |
| accessibility/DominanterAccessibilityService.kt | 745 | yes |
| channel/ChannelErrors.kt | 87 | yes |
| channel/PrivilegedChannelHandler.kt | 587 | yes |
| data/SettingsStore.kt | 509 | yes |
| data/TimeModels.kt | 122 | yes |
| deviceowner/AdminReceiver.kt | 126 | yes |
| deviceowner/DeviceOwnerManager.kt | 620 | yes |
| focus/FocusService.kt | 326 | yes |
| focus/FocusSessionStore.kt | 710 | yes |
| notifications/FocusSystemReceiver.kt | 90 | yes |
| notifications/UsageWarningNotifier.kt | 293 | yes |
| security/RecoveryStore.kt | 99 | yes |
| shizuku/ShizukuGateway.kt | 179 | yes |
| shizuku/ShizukuProvisioning.kt | 391 | yes |
| shizuku/ShizukuRunner.kt | 145 | yes |

### Config, resources, tests

| File | Lines | Reviewed |
|---|---:|---|
| android/app/src/main/AndroidManifest.xml | 161 | yes |
| android/app/build.gradle.kts | 118 | yes |
| android/app/proguard-rules.pro | 84 | yes |
| build_apk.sh | 25 | yes |
| pubspec.yaml | 109 | yes |
| l10n.yaml | 6 | yes |
| res/values/strings.xml / res/values-ar/strings.xml | 49 / 52 | yes |
| test/ (10 files: challenges, channel_client, entry_password, entry_password_ui, gate_coverage, localization, parity_contracts, recovery_gate, redesign, widget) | 2,403 | yes |

**Totals: 56 source/config files + 10 test files; 29,375 lines**
(21,024 Dart + 5,445 Kotlin + 503 config + 2,403 tests), plus the ARB
tables (2,878 lines), native string resources (101 lines), 4 bundled
Cairo TTFs (verified real TrueType, OS/2 weights 400/600/700/800,
Arabic+Latin coverage), and the launcher-icon set (adaptive-icon XML,
background colour #0B0B0C, foreground/monochrome PNGs at all five
densities, legacy PNGs at all five densities — user-picked concept A
"The Broken D", verified present and consistent).

---

## 2. Gate coverage (formal, per the user's security directive)

**Entry gate** — unlock requires one of: fingerprint/biometric
(local_auth, `biometricOnly: false`, so the device PIN/pattern/password
is offered by the same system prompt), OR the user-set app password
(PBKDF2, entry only — it never opens a recovery session), OR, when the
device has **no credential at all**, the documented no-credential
fallback (original F32 behaviour). State restoration cannot bypass it:
the lock state lives in memory only, so process death returns to the
lock screen; there are no deep links, and `MainActivity` is exported
with only MAIN/LAUNCHER. The setup wizard — the only other pre-shell
surface — is reachable solely from the locked/startup states.

**In-app gate** — every action below was traced from its UI control to
its channel call. Verdict key: **gated** = runs inside
`runLoosening`/`ensureRecoverySession` (paper-code-first session);
**free** = allowed without a session, with the reason recorded.

| # | Action | Verdict |
|---|---|---|
| 1 | Remove Device Owner now | gated |
| 2 | Forced removal in 48 h — schedule | gated |
| 3 | Forced removal — start/finish the wait | free by design: this is the documented code-free escape (original F2); finishing it *removes* protection only after 48 h |
| 4 | Forced removal — cancel | free: cancelling restores protection |
| 5 | Shizuku provisioning (Device Owner grant) | **gated — fixed (G13)** |
| 6 | WRITE_SECURE_SETTINGS grant (both entry points) | **gated — fixed (G13)** |
| 7 | Accessibility service enable | **gated — fixed (G13)**; disabling stays free (it triggers the F28 fail-closed lockdown — protective) |
| 8 | Restrictions tab — apply (activate or clear) | **gated — fixed (G1)** |
| 9 | Per-app suspend / hide / uninstall-block toggles, both directions | **gated — fixed (G2)** |
| 10 | Per-app restrictions editor — any change | **gated — fixed (G7)** |
| 11 | Per-app time limit — loosen or remove | gated (pre-existing) |
| 12 | Per-app time limit — create where none existed | **gated — fixed (G4)** |
| 13 | Per-app time windows — loosen or remove | gated (pre-existing) |
| 14 | Per-app time windows — add where none existed | **gated — fixed (G5)** |
| 15 | Group create / rename | free: a group alone enforces nothing until restrictions/limits are set (those are gated) |
| 16 | Group delete | gated (pre-existing) |
| 17 | Group member changes | removals gated (pre-existing); **additions to a group carrying restrictions gated — fixed (G3)** |
| 18 | Group time limit — loosen/remove | gated (pre-existing); **create gated — fixed (G6)** |
| 19 | Blocked-word list — remove a word | gated (pre-existing) |
| 20 | Blocked-word list — add a word | free: tightening (parity rule) |
| 21 | URL blocklist — save / apply to browsers | **always gated — fixed (G8/G9)**: every save auto-applies to browsers, so it is an activation surface, not a passive edit |
| 22 | Blocklist target set changes | **gated — fixed (G10)** (additions activate coverage; removals loosen it) |
| 23 | New per-app passive blocklist | **gated — fixed (G11)** |
| 24 | Focus settings — every loosening (durations, release toggle, shuffle off) | gated (pre-existing); the whole screen's controls are disabled without a session |
| 25 | Focus suspend-list / restriction picker changes | removals gated (pre-existing); **additions gated — fixed (G12)** |
| 26 | Focus session start | free: protective action (parity); *ending* early is gated (pre-existing) |
| 27 | Impulse lock start | free: one-tap protective action (parity); there is deliberately no early-stop path |
| 28 | Usage-warning thresholds — loosen | gated (pre-existing); tightening free |
| 29 | Challenge selection — reduce below 1 | gated (pre-existing, original parity) |
| 30 | Custom reading passages — edit | gated (pre-existing) |
| 31 | Shuffle-keypad toggle | free: a hardening/display preference with no enforcement effect |
| 32 | Entry password set / change / remove | gated (new in v1.0.4; the password prompt itself never opens a session) |
| 33 | Suspension-log clear | free: matches the original; a log view is not an enforcement control and is not in the user's enumerated list |
| 34 | Setup ceremony order | verified: the wizard requires the paper code to be generated, written and confirmed in an earlier step **before** any provisioning action can run, so privileges never exist before the code does |

Gate mechanics verified: the dialog asks for the **paper code first**
(`barrierDismissible: false`), challenges run only after a correct
code, and the session starts only after all selected challenges pass.
Sessions are in-memory, expire after 10 minutes, and never survive
process death. The native STOP action of the focus notification
refuses to act outside the WAITING phase, so no intent can shorten a
focus period. `test/gate_coverage_test.dart` pins row 8 behaviourally:
activation with no session opens the gate and applies nothing;
with a session it applies directly.

---

## 3. Findings and resolutions

Severity counts: **3 high, 9 medium, 5 low, 2 cosmetic — 19 total. All
fixed; 0 open.**

### High — gate gaps (user directive: activation is gated too)

- **G1** `lib/ui/restrictions_tab.dart:94` — Apply ran ungated when the
  change only *activated* restrictions. Fixed: the gate now triggers
  when anything is applied or cleared.
- **G2** `lib/ui/apps_tab.dart:202` — per-app protection toggles
  (suspend/hide/uninstall-block) ran ungated in **both** directions,
  contradicting the code comment above them. Fixed: both directions go
  through `runLoosening`; the four now-dead ARB keys were removed from
  both ARB tables (597 keys per locale, sets still identical).
- **G13** `lib/ui/setup_screen.dart:387,544,607` — Shizuku Device Owner
  provisioning, the WRITE_SECURE_SETTINGS grant and the accessibility
  enable were reachable from the setup tab with no paper code, although
  granting privileges is in the user's gated list. Fixed: the
  provisioning flow and the grant now open a code-first session at
  entry (the grant's retry poll calls the channel directly so it is
  not re-gated); enabling accessibility is gated, disabling is not
  (see gate table row 7).

### Medium

- **G3** `lib/ui/apps_tab.dart:796` — adding members to a group that
  carries restrictions activated enforcement on them ungated. Fixed.
- **G4/G5/G6** `lib/ui/apps_tab.dart:331,388,870` — creating a time
  limit or time windows where none existed (per-app and per-group) was
  ungated. Fixed: creation is gated; loosening/removal were already
  gated.
- **G7** `lib/ui/apps_tab.dart:1414` — the per-app restrictions editor
  saved additions/activations ungated. Fixed via an activation check
  mirroring the loosening check.
- **G8/G9** `lib/ui/config_screens.dart:67,183` — URL blocklist saves
  and "apply to browsers" were ungated on the tightening path, yet
  every save auto-applies the list to all browsers. Fixed: both always
  run through the gate.
- **G10** `lib/ui/config_screens.dart:353` — blocklist target changes
  ungated. Fixed: any change to the target set is gated.
- **G11** `lib/ui/config_screens.dart:411` — creating a new per-app
  passive blocklist ungated. Fixed.
- **G12** `lib/ui/impulse_focus_screens.dart:880+` — the focus
  suspend-apps/groups/restrictions pickers gated removals only. Fixed:
  additions (activation) are gated too; the flag is documented as
  "session required".
- **L1/L2** `android/.../notifications/UsageWarningNotifier.kt`,
  `android/.../focus/FocusService.kt`, `res/values/strings.xml` —
  native user-visible strings (usage-warning and focus notifications,
  notification channels) were hardcoded English, so an Arabic user got
  English system notifications. Fixed: all native strings moved to
  resources and a complete `res/values-ar/strings.xml` added (block
  screens and the accessibility request were already resource-based
  and are translated too). Native strings follow the **device** locale
  (Android per-app language APIs are out of scope for the native
  layer); the in-app UI follows the persisted in-app choice.
- **C1** `android/.../channel/PrivilegedChannelHandler.kt:503,514` —
  `parseGroup` dropped a group's `reopenSeconds` and `groupToMap` did
  not emit it, so **every group save silently reset the reopen
  cooldown to 0**. Fixed on both sides of the round-trip. (Not covered
  by a Dart test: the project has no JVM test harness — the fix is a
  symmetric read/write of the same key, verified by inspection.)

### Low

- **C2** `lib/app_controller.dart:96` — `initialise()` re-subscribed to
  the native event stream without cancelling the previous
  subscription, so the Retry path stacked duplicate handlers. Fixed.
- **S1** `lib/data/config_store.dart:431` — `setEntryPassword` threw
  `ArgumentError.value(...)`, which embeds the attempted password in
  the exception text that surfaces in error snackbars/logs. Fixed:
  plain `ArgumentError` with an explanatory comment.
- **D1** `lib/app_controller.dart`, `lib/domain/recovery.dart` — dead
  code: `AppController.stopImpulseLock()` and `ImpulseLock.stop()` had
  no callers (the impulse lock deliberately has no early-stop path).
  Removed.
- **D2** `android/.../DominanterApplication.kt` — dead `getInstance()`
  singleton accessor, never called. Removed.
- **D3** `android/.../deviceowner/DeviceOwnerManager.kt` — dead
  `logTag()`/`TAG` and the now-unused `Log` import. Removed.

### Cosmetic

- **M1** `lib/ui/entry_password_ui.dart` — two `Icons.chevron_right`
  (not mirrored in RTL) replaced with `Icons.navigate_next`, matching
  the rest of the app.
- **M2** `lib/ui/pill_nav.dart` — header comment still described the
  red under-glow removed by the premium-minimal pass. Updated.

---

## 4. Verified clean (no findings)

- **Secrets:** the recovery code and the entry password exist only as
  salted PBKDF2-HMAC-SHA256 records (210,000 iterations, per-record
  salt, constant-time verify, malformed record → `false`). The
  recovery record lives in a native store excluded from the generic
  settings-store allowlist, so no channel method can read it back;
  there is no getter for it anywhere. No secret is logged on either
  side; the entry-password record never leaves `ConfigStore`.
- **Silent failures:** `ShizukuRunner` returns the exit code on every
  result (drains both streams concurrently, enforces timeouts);
  `ShizukuProvisioning` checks the exit code of all 13 shell calls and
  restores `user_setup_complete` in a `finally`; `DeviceOwnerManager`
  re-reads state to verify every mutation and throws on partial
  suspension failure; the channel handler validates every argument and
  answers NOT_IMPLEMENTED for unknown methods.
- **Bypass hunt extras:** notification actions cannot shorten a focus
  session (STOP refuses outside WAITING); the accessibility-loss
  lockdown (F28) is fail-closed; the manifest exports only
  `MainActivity` (MAIN/LAUNCHER), the admin receiver
  (BIND_DEVICE_ADMIN) and signature-protected Shizuku components;
  boot/app-replace receivers are not exported.
- **Placeholders:** repository-wide grep for TODO/FIXME/XXX/HACK and
  `print`/`debugPrint` in `lib/` → zero hits.
- **l10n (criterion e):** a literal-string scan of all UI code finds no
  natural-language strings outside the ARB system (remaining literals
  are wire-format constants, popup-menu action keys and the monospace
  font name). The two ARBs hold identical key sets (597). Documented
  content exceptions: the reading-challenge passage *texts* and the
  words-challenge word list are English study content in both locales
  (their titles/labels are localized) — parity with the original's
  English corpus.
- **Palette (criterion f):** zero `Color(0x…)` literals outside
  `lib/theme.dart`; zero off-palette material colour constants;
  `test/redesign_test.dart` asserts every theme colour is red-dominant
  or true greyscale (R==G==B) and that the pill bar is black in both
  themes.
- **Lifecycle:** controllers/timers/subscriptions are disposed along
  every path reviewed; the one leak found is C2 above.

## 5. Documented deviations and directives (not defects)

- **F20** Play Store rating scraping — excluded by decision.
- **F29** Unauthenticated lock-screen APK installer — excluded by
  decision (security).
- **F34** Debug self-disable hatch — excluded by decision.
- **PBKDF2 recovery storage** — the code is stored as a salted hash,
  so it can be verified but never re-displayed (decision U-5).
- **v1.1 deferrals** — NSFW TFLite pipeline (F16/F17), Tetris
  challenge, colour modes (F26), install watchers (F6/F19), F11, F18.
- **User directive (v1.0.4):** activating advanced-block features
  requires the paper code, overriding the original's "tightening is
  free" rule — implemented by G1–G13 above and pinned by
  `test/gate_coverage_test.dart`.
- **Accepted behaviours:** the entry-password prompt treats a channel
  error as a wrong password (fail-closed — it can only ever refuse
  entry); the recovery gate has no attempt throttle beyond the native
  PBKDF2 cost, matching the original.
