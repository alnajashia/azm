# Dominanter — Full Literal Parity Audit vs DeChainer 1.12.0

> **Date:** 2026-11-09 · **Phase A (report only — no code was changed for this audit)**
> **Reference (single source of truth):** the user-supplied archive
> `dechainer-1.12.0_2_5crz.zip`, extracted to
> `~/workspace/dominater-rebuild/reference/dechainer-zip/dechainer-1.12.0/`.
> **Reference verification:** the archive's comment is commit
> `29822c059b74def1a14d609b20e2647f02162d05`; extracted tree compared against the
> local clone `sources/dechainer` with `diff -rq` (zero differences) **and**
> per-file SHA-256 manifests (199 files, identical). The zip and the clone are
> the same tree; all citations below are to the zip tree.
> **Method:** literal file-by-file, function-by-function comparison. Where the
> structure legitimately differs (original UI is Jetpack Compose, ours is Dart;
> some logic migrated between Kotlin and Dart), the comparison unit is
> **behavioural/logical**, and every original unit is mapped to its counterpart
> in ours — or to its absence. Full per-file tables are in the appendices:
> `docs/parity_appendix/part1_core.md` (native core + build config),
> `part2_data.md` (data layer + models), `part3_runtime.md` (services,
> notifications, block activities, NSFW), `part4_ui.md` (screens + viewmodels),
> `part5_flows.md` (challenges, recovery, setup, tests).
> **Severity scale:** S1 = weakens the anti-bypass security core or silently
> loses user restrictions; S2 = behaviour materially differs from the original;
> S3 = minor drift / cosmetic / dormant.
> Findings not present in the earlier `COMPLIANCE_AUDIT.md` are marked **NEW**.
> The five most serious NEW findings (D-01, D-03, D-05, D-07/D-33 area, D-34)
> were independently re-verified by the audit lead against both source trees
> before inclusion.

## Headline verdict

The Kotlin privileged layer is a substantially faithful port (all 13 Shizuku
commands, reflection provisioning, DPM verify-by-reread, limits/windows
accounting, lockdown). **The Dart layer is not.** It was written from feature
descriptions rather than ported line-by-line, and the literal audit finds
semantic inversions inside the recovery-gate core, flipped defaults, drifted
constants, dead controls, and whole runtime services (notifications, focus
service) that were never built. Of the areas audited, **nothing in the Dart UI
scope is fully equivalent** to the original; the defects register below lists
37 numbered defects (D-01…D-37), the large majority of them NEW.

---

## A. Units missing entirely in ours

| Original unit | What it is | Status in ours |
|---|---|---|
| `notifications/FocusService.kt` + `FocusNotifier.kt`, `FocusReceiver.kt`, `FocusScheduleReceiver.kt`, `FocusReminderNotifier.kt` | The entire native focus runtime: foreground service, exact alarms, boot/time resync | **Absent** — no service, no receiver, grep for Notification/AlarmManager in our Kotlin = 0 hits (see D-13/D-30) |
| `notifications/UsageWarningNotifier.kt`, `UsageWarningDismissReceiver.kt` | F12 warning notifications + dismiss handling | **Absent** — nothing fires warnings (D-30) |
| `DechainerPolicyUpdateReceiver` (API-34 `PolicyUpdateReceiver`) | Authoritative policy-result logging | Replaced by a plain no-op `BroadcastReceiver` (D-36) |
| `utils/HomeScreenDetector.kt` | F11 reopening-cooldown detection support | **Absent** (F11 deferred, but the unit was never even inventoried before) |
| `utils/NsfwContentDetector.kt` + `assets/models/nsfw_model.tflite` (17,355,548 B) + screenshot/region pipeline + `VisualBlockingSuspensionTracker` | F16/F17 visual blocking | **Absent** — deferred v1.1 (documented) |
| `data/ColorFilterController.kt`, `ColorFilterSettings.kt`, `models/ColorFilter*.kt`, `screens/tabs/ColorFilterScreen.kt`, `viewmodels/ColorFilterViewModel.kt` | F26 colour modes | **Absent** — deferred v1.1 (documented) |
| `screens/tabs/ActivityBlockerScreen.kt` + `viewmodels/ActivityBlockerViewModel.kt` + channel/storage setter | F18 blocked activities | **Absent as a feature**; enforcement plumbing exists but can never be populated (gap G1, confirmed) |
| `data/PlayStoreRatingFetcher.kt` | F20 18+ rating scraping | **Absent** — excluded deliberately → **decision U-1** |
| `data/ApkUpdateInstaller.kt`, `notifications/ApkUpdateResultReceiver.kt`, `screens/common/ApkUpdateDialog.kt` | F29 in-app APK update reachable from the lock screen | **Absent** — excluded deliberately → **decision U-2** |
| `DeviceOwnerSetupBypass` (test-pinned debug hatch) | F34 | **Absent** — excluded deliberately → **decision U-3** |
| `screens/challenges/TetrisChallenge.kt`, `TetrisSounds.kt` | F22 Tetris challenge | **Absent** — deferred v1.1 → **decision U-4** |
| Install-watchers for unsupported browsers / torrent apps (in `AppRepository`/service) | F6/F19 | **Absent** — deferred v1.1 → **decision U-4** |
| `getAvailableRestrictions` (DeviceOwnerViewModel operation) | Declared-restrictions model behind AppRestrictionsScreen | **Never ported** — root cause of D-33 |
| Group time-windows UI | Editing windows for app groups | **Absent** — model supports it, no screen exists (part 4) |
| Original's JVM test suite (12 test files pinning behaviour) | Behaviour contracts | **Absent as contracts** — our tests pin our own design instead (see §C.5) |

## B. Defect register — missing or wrong behaviour inside existing files

### B.1 Recovery gate & anti-bypass semantics (the security core)

- **D-01 (S1, NEW) — Gate order inverted.** Original: the recovery **code is
  validated first**, then challenges run, then the session starts
  (`screens/common/RecoveryGate.kt:23` KDoc, `:69-87`). Ours runs the
  challenges first and asks for the code second (`lib/ui/recovery_ui.dart`,
  gate flow). Anyone can rehearse/complete challenges without possessing the
  code, and the session semantics differ from the original's contract.
- **D-02 (S1, NEW) — PendingChange semantics inverted.** Original defers a
  loosening change until the 5-second undo window lapses — undo means *never
  applied* (`screens/common/PendingChange.kt:26-37`). Ours applies
  immediately and relies on a compensating revert
  (`lib/domain/recovery.dart:131-145`) — during the window the loosened state
  is live, and a process death inside the window leaves it applied.
- **D-03 (S1, NEW) — `isLooserWindows` weakened.** Original tests per-minute
  coverage: loosening = any minute newly allowed
  (`PendingChange.kt:44-55`, incl. per-weekday). Ours compares **total
  minutes only** (`lib/domain/recovery.dart:52-68`), so moving a window to a
  different time of day at equal length **bypasses the gate entirely**.
- **D-04 (S1, NEW) — `isLooserRestrictions` weakened.** Original iterates keys
  with per-type containment (`PendingChange.kt:58-79`); ours has no String
  case and compares lists **by length, not containment**
  (`lib/domain/recovery.dart:85-104`) — a same-length blocklist swap is
  gate-invisible.
- **D-05 (S1, NEW) — Group member removal is ungated.** Removing an app from
  a group strips its group limits/windows with no recovery session
  (`lib/ui/apps_tab.dart:715-720`, `_save` called directly). The original
  gates membership changes that loosen restrictions.
- **D-06 (S1, NEW) — Two silent-loosening paths in group editing.** (i) The
  reopening-cooldown decrease lost its gate term
  (`lib/ui/apps_tab.dart:348-353`); (ii) weekly windows can be silently
  dropped by daily-only saves, with no loosening check on the weekly part.
- **D-07 (S1, NEW) — Impulse lock diverges in four ways.** (i) Original gates
  impulse **settings** behind a recovery session; ours saves every edit
  immediately, ungated (part 4/5). (ii) Default action flipped: original
  `TIMER_ONLY`, ours `timerAndSuspend` (parts 1/5). (iii) Ours adds a
  code-gated early **Stop** the original deliberately lacks. (iv) On natural
  expiry ours never releases the apps the lock suspended.
- **D-08 (S2, NEW) — Setup blockers downgraded.** Original **hard-blocks**
  provisioning on extra users / an existing device owner with non-dismissible
  dialogs (`screens/setup/SetupDeviceOwnerPrivileges.kt:23-139`); ours shows
  the same conditions as optional diagnostics and never disables provisioning.
  The Install-Shizuku button and the 500 ms binder polling are also missing
  (`lib/ui/setup_screen.dart`).
- **D-36 (S3, NEW) — PolicyUpdateReceiver reduced to a no-op plain receiver**
  (see §A); the original's authoritative-result logging purpose is lost.

### B.2 Accessibility service & native runtime

- **D-09 (S1, NEW) — SCREEN_ON tracking resume missing.** The receiver is
  registered but has no SCREEN_ON branch; foreground usage after unlock can
  go unaccounted — fail-open (part 1).
- **D-10 (S2, NEW) — Settings edits don't re-arm tracking.** Our prefs
  listener only refreshes word patterns; editing the foreground app's
  limit/window/group does not re-track until the next app switch. The
  original re-tracks immediately (part 1).
- **D-11 (S2, NEW) — Hidden apps are never re-hidden.** Original
  `AppRepository.reapplyHiddenIfNeeded` re-hides a hidden app after it is
  updated/reinstalled; no counterpart exists in ours (part 1).
- **D-12 (S2, NEW) — Word matching differs.** Ours uses ASCII `\b`
  boundaries instead of the original's Unicode `\p{L}\p{N}` lookarounds
  (false positives inside longer non-ASCII words — the app ships a Portuguese
  locale), and `buildScreenText` walks `rootInActiveWindow` instead of
  `event.source` (part 1).
- **D-31 (S3, NEW) — BlockedWord screen shows the word unblurred** in body
  text; the original blurs it behind an eye-toggle. No `FLAG_KEEP_SCREEN_ON`
  anywhere in our block activities (part 3). The reopening variant
  (`VARIANT_REOPENING`, gap G1) is static text; the original is a live
  1-second countdown that auto-closes.

### B.3 Focus mode

- **D-13 (S1, NEW) — The focus session is not persisted at all.** Only the
  config is stored; the session object is recreated idle on every Focus
  screen load. Process death — or mere navigation — discards a running
  session and orphans the suspensions it applied, with no release record.
  Original persists the full session natively with a dual-clock
  (elapsed + RTC + boot-count) deadline, an exact
  `ELAPSED_REALTIME_WAKEUP` alarm, a foreground service, and
  boot/update/time-change resync (parts 2/3/4).
- **D-14 (S2, NEW) — `resume()` changes phase.** Ours always re-enters FOCUS,
  discarding a paused break (`lib/domain/focus.dart:163-175`); the original
  re-anchors the same phase (`data/FocusMode.kt:246-260`).
- **D-15 (S2, NEW) — WAITING phase and three config fields absent.**
  `auto_start_focus`, `sound_enabled`, `vibration_enabled`
  (`data/FocusMode.kt:70-72`) exist nowhere in ours; auto-start is
  effectively hard-wired ON and the WAITING phase is unrepresentable
  (`lib/domain/focus.dart:11,130-135`).
- **D-16 (S2, NEW) — Focus timing is wall-clock only** in ours
  (`focus.dart:105-110`) — clock changes move the deadline; the original is
  elapsed-realtime anchored. Ours also lacks the original's duration clamps
  on read/write.
- **D-17 (S2, NEW) — Editor ranges drift.** Ours allows durations 1–180 min
  and cycles 1–12; original bounds are focus 5–120, break 5–60, cycles 2–8
  (part 5).
- **D-18 (S1, NEW) — Focus group-suspension and focus-restrictions are dead
  plumbing.** `FocusConfig.suspendGroups` is never set by any UI and never
  consumed; `FocusConfig.restrictions` is consumed by `_syncEffects` but no
  UI can populate it. Two advertised F25 behaviours are unreachable — the
  earlier audit's F25 evidence is **overstated** (part 4).
- **D-19 (S3, NEW) — Pause gating differs.** Ours gates every pause behind
  the recovery session; the original's plain pause is free (only stopping is
  gated) (part 4).

### B.4 Challenges (numeric/behavioural drift — all NEW)

- **D-27 (S2) — Math challenge is a different challenge.** Original:
  addition only, operands 10..98, **a wrong answer resets progress to 0**
  (`screens/challenges/ChallengeScreens.kt:61-66,107-112`). Ours adds
  subtraction/multiplication/division with different ranges and **keeps**
  progress on errors (`lib/domain/challenges.dart:66-94`).
- **D-28 (S2) — Words challenge mechanics invented.** Original: per-keystroke
  checking against a ~190-word five-letter pool, no failure state. Ours: a
  24-word mixed-length pool, whole-word submission, and a streak-reset-to-
  zero on any error that the original does not have
  (`lib/domain/challenges.dart:99-137`).
- **D-29 (S2) — Reading timing formula differs.** Original: 300 ms/word +
  45 ms/letter + punctuation pauses. Ours: flat 450 ms/word. The source
  selection (Bible/Quran/Quotes/Custom), the passage-count setting, and the
  per-passage attribution field are also absent — beyond the documented
  corpus decision (parts 2/5; see D-24).

### B.5 Data layer & storage schema

- **D-20 (S2, NEW) — Usage-warning `enabled` default inverted.** Original
  `DEFAULT_ENABLED = true` (`data/UsageWarningSettings.kt:16`); ours treats
  unset as false (`lib/data/config_store.dart:202-203`) — fresh installs get
  F12 warnings OFF.
- **D-21 (S2, NEW) — Same-name schema collisions.** Three stores share the
  original's preference file/key names with incompatible shapes:
  `reading_custom_passages` (original: objects `{text, source}`; ours: plain
  strings), `access_challenges` (original: StringSet; ours: JSON string),
  usage-warning stages (ours drops the `id`, lowercases type names). Neither
  side can read the other's data (part 2).
- **D-22 (S2, NEW) — Group schema is not a mirror.** Ours' `saveGroups`
  writes `weeklyLimit` XOR `limit` (`SettingsStore.kt:198-211`); the
  original always writes both. The one-group-per-app invariant and
  group-usage cleanup on group deletion
  (`data/AppGroupRepository.kt:48-84`) are absent from our data layer.
- **D-23 (S3, NEW) — Suspension-log cap 500 vs the original's 100**
  (`SettingsStore.kt:60` vs `data/SuspensionLogRepository.kt:13`).
- **D-24 (S2, NEW) — Reading settings missing.** `reading_source` /
  `reading_count` have no counterpart in ours (part 2). (The corpus itself —
  5 original English passages vs the original's 60 bilingual passages — is
  the documented corpus decision, not a defect.)
- **D-25 (S2, NEW) — Browser-restriction apply semantics differ.** Ours
  pushes blocklists with `merge:false` to capable apps only and always
  forces SafeSearch (`lib/ui/config_screens.dart:141-161`); the original
  applies with `merge:true` to all detected browsers
  (`data/BrowserRestrictionsManager.kt:124-149`). Intent-based browser
  detection itself is missing, as are the per-browser suspend switch and
  the unsupported-browser dialog (part 4). Blank-title lists are persisted
  by ours; the original discards them. `merge:false` can wipe restrictions
  set by other means.
- **D-26 (S3, NEW) — Restriction labels/search degraded.** The original's
  `resolveStringRes` label resolution and diacritic-insensitive search
  normalisation are missing; our UI can only show raw restriction keys
  (part 2/4).

### B.6 Screens & flows

- **D-33 (S1, NEW) — AppRestrictionsScreen is a different feature in
  effect.** Ours edits only currently-set raw key/values with immediate
  save: no declared-restrictions model, no draft/Save flow, no search, no
  All/Active/Default filters, no CHOICE/MULTI_SELECT/BUNDLE editors, no
  clear-all — and it exposes `URLBlocklist`, which the original deliberately
  hides and force-preserves (root cause: §A, `getAvailableRestrictions`
  never ported) (part 4).
- **D-34 (S1, NEW) — Two of three Private-DNS presets point at different
  services.** Original: `family.cloudflare-dns.com`,
  `family.adguard-dns.com`, `adult-filter-dns.cleanbrowsing.org`
  (`screens/tabs/ConfigTab.kt:522-524`). Ours: `security.cloudflare-dns.com`
  and `security-filter-dns.cleanbrowsing.org`
  (`lib/ui/config_tab.dart:20-22`) — different filtering policies than the
  labels promise. The DNS dialog's gate, timeout, and finish-confirmation
  checkbox were also stripped, and the keyboard-shuffle toggle became
  ungated (part 4).
- **D-35 (S2, NEW) — Recovery wizard thinned from 4 steps to 2.** The Intro
  and Store steps and the reveal-gating are gone. The shuffle keyboard was
  redesigned: original shuffles 26 letters once and uses a 4×4
  single-correct-cell grid reshuffled per tap; ours differs — and the
  original's design is **unimplementable under the PBKDF2 deviation** (the
  code must be re-displayed for that grid), a coupling the earlier audit
  missed → **decision U-5** (part 5).
- **D-32 (S2, NEW) — Lock screen reduced.** No pre-auth FocusSessionCard;
  the usage overview is a generic top-5 list instead of the original's
  limit-scoped UsageLimitsOverview; the impulse countdown is a Dart
  tick-decrement (30 s period, frozen while the process is dead) vs the
  original's native elapsedRealtime 1-second countdown (part 3).
- **Usage-warning stages are display+delete only** (part 4): no editor for
  minutes/type/vibration; "Add" hardcodes a 10-minute silent stage; no
  notification-permission flow. (Compounds D-20/D-30.)
- **AppsTab gaps** (part 4): no NoDeviceOwner empty-state gate (an
  error/retry loop instead), no group filter chips, no restricted-first
  sort, no per-app group assignment UI, no group rename.
- **RestrictionsTab gaps** (part 4): no select-all, key-only search, no
  labels or Active badges.
- **Dead control (S1, NEW):** the group-limit editor's "Reopening cooldown"
  field is editable, but the editor is opened with `reopenSeconds: 0` and
  the returned value is never written (`lib/ui/apps_tab.dart:722-748`,
  verified by the audit lead) — user input is silently discarded.

### B.7 Build & manifest

- **D-37 (S2, NEW) — Release build is weaker than the original's.** No
  minify/shrink-resources/ProGuard (the original enables all); AGP 8.9.1 /
  Kotlin 2.1.0 vs the original's 8.13.2 / 2.4.10; no JVM native test
  harness; manifest lacks the original's backup/locale attributes;
  accessibility feedback type Spoken→Generic (part 1). The unused
  FGS/exact-alarm/boot permissions remain declared with no consumer (gap G3,
  confirmed).

### Confirmed faithful (for the record)

All 13 Shizuku commands present verbatim and exit-code-checked; reflection
provisioning chain identical in effect; request code 911; DPM
verify-by-reread; TimeLimit/TimeWindow/AppTimeLimits/AppTimeWindows/
BlockedList/SuspensionLogEntry storage truly equivalent; F28 accessibility-
loss lockdown; SystemRestrictions key enumeration equivalent; block
activities TimeUp/OutsideWindow equivalent via the consolidated
BlockActivity. Deferred features (F6/F11/F16/F17/F19/F26) verified genuinely
absent, not stubbed; exclusions F20/F29/F34 genuinely absent.

---

## C. Diagnosis — why the previous version has these problems

1. **The five Kotlin compile errors (first build).** The Kotlin layer was
   written in one pass and never compiled until the full build: a KDoc
   containing `DISALLOW_*/` closed a comment early; a non-existent constant
   (`PRIVATE_DNS_SET_SUCCESS` for `PRIVATE_DNS_SET_NO_ERROR`); a duplicate
   companion object; a missing `Context` parameter thread-through; a vararg
   array type mismatch. Root cause: no incremental compilation during the
   write; all five were in the original Kotlin pass, none in the later
   channel additions.
2. **The SettingsStore channel omission.** The Dart UI stage discovered that
   the save methods for limits/windows/groups/words existed in
   `SettingsStore` but had never been exposed through the channel — the
   channel contract was written before the store was finished and never
   reconciled against it. Root cause: contract-first without a parity check.
3. **Gaps G1–G3 (from COMPLIANCE_AUDIT, all confirmed by this audit).** G1:
   F18 blocked-activities enforcement plumbing with no setter/channel/UI —
   half-wired. G2: EventChannel events (`packageChanged`,
   `accessibilityStatus`) emitted but unhandled in Dart; a KDoc claims a
   Dart cache exists that doesn't; the app list goes stale. G3: manifest
   permissions for a foreground service/alarms/boot receiver that were never
   built (see D-13/D-30 — the permissions are the fossil of the unbuilt
   focus/notification runtime).
4. **NEW root cause — the Dart layer was designed, not ported.** The
   recovery-gate inversions (D-01…D-04), flipped defaults (D-07, D-20),
   drifted constants (D-17, D-27…D-29, D-34), and schema collisions (D-21)
   share one origin: Dart domain logic was written from feature summaries
   (the F-list) without line-level comparison against the original's
   `PendingChange.kt`, `RecoveryGate.kt`, `ChallengeScreens.kt`, and
   settings classes. Summaries preserve *what* a feature does; they lose
   *order, defaults, edge semantics* — exactly where this app's security
   lives.
5. **NEW root cause — test parity was never checked.** Of the 7 in-scope
   behaviour contracts pinned by the original's own JVM tests, ours fully
   covers **none** (3 partial, 4 absent — including RecoveryGate semantics;
   and there are no Kotlin-side tests at all). Our 41 tests verify our own
   design decisions, so design drift passed the suite silently (part 5).
6. **NEW root cause — state ownership was never ported.** In the original,
   sessions live in native services (focus, warnings, impulse). Ours kept
   them in widget State and Dart timers (D-13, D-30, D-32). Every
   "alive-only accounting" caveat in the earlier docs traces back to this
   single architectural omission.
7. **ViewModel operations were never inventoried.** Screens were rebuilt
   from the original's layouts, not from its ViewModel APIs — which is how
   `getAvailableRestrictions` (D-33), per-app group assignment, group
   rename, and several dialogs came to be missing while their screens look
   superficially similar (part 4).

## D. Decisions required from the user

Nothing in this section will be changed in Phase B without an explicit
decision. Everything in §A/§B **not** listed here is a plain defect and needs
no decision — Phase B can fix it on the user's go-ahead.

- **U-1 — F20 (Play Store 18+ rating scraping).** Excluded earlier as a
  brittle HTML scrape with no official API. Literal parity would reinstate
  `PlayStoreRatingFetcher` and the auto-suspend-on-install flow. **Keep
  excluded, or reinstate?**
- **U-2 — F29 (APK self-update installer).** The original ships a silent
  install/downgrade path reachable from the lock screen **without
  authentication** — excluded earlier as a security flaw; a middle option
  (authenticated, in-session update flow) was floated for v1.1. **Keep
  excluded, adopt the authenticated variant, or reinstate as-is?**
- **U-3 — F34 (debug setup-bypass hatch).** Excluded earlier; the original
  pins it with a test (`DeviceOwnerSetupBypassTest`). **Keep excluded, or
  reinstate for debug builds only?**
- **U-4 — The eight v1.1 deferrals** (F6 install-watcher for unsupported
  browsers, F11 reopening cooldown, F12 native warning firing — note: the
  *firing* is D-30, a defect against the documented "partial", but full
  parity needs the notifier built; F16/F17 NSFW pipeline, F18 blocked
  activities wiring, F19 torrent watcher, F22 Tetris, F26 colour modes).
  **Which, if any, move into Phase B scope, and in what order?**
- **U-5 — Recovery-code storage: PBKDF2 hash (ours) vs plaintext
  (original).** Ours stores a salted PBKDF2 hash — verifiable but never
  re-displayable; the original stores plaintext and its setup wizard's
  4×4 single-correct-cell shuffle grid (D-35) **requires** re-displaying
  the code, so literal parity of the wizard is impossible while the hash
  stands. **Keep the hash (and accept the redesigned wizard), or return to
  plaintext storage for full parity?** This is a security-vs-parity
  trade-off only the user can settle.

---

*Appendices (exhaustive per-file tables, every claim cited file:line on both
sides): `docs/parity_appendix/part1_core.md`, `part2_data.md`,
`part3_runtime.md`, `part4_ui.md`, `part5_flows.md`.*


---

## Phase B addendum (2026-11-09, v1.0.1) — defects D-01…D-37 fixed

All 37 defects in §B were fixed in Phase B, on the user's instruction, and
verified: `flutter analyze` 0 errors (24 pre-existing info lints), `flutter
test` **72/72** (including the new `test/parity_contracts_test.dart`, 17 tests
pinning the original's behaviour contracts — among them the equal-length
window time-shift case for D-03 and the same-length blocklist swap for D-04),
and debug + release APK builds succeed (release now minified per D-37; the
first R8 run needed the standard Flutter Play-Core `-dontwarn` rules, which
the native original never required — recorded in `proguard-rules.pro`).

Highlights: gate order restored (code → challenges → session, D-01);
PendingChange defers application (D-02); per-minute windows and containment
comparators ported line-by-line (D-03/D-04); group gates + dead cooldown
control (D-05/D-06); impulse defaults/gating/expiry release (D-07); setup
hard blockers + the Grant flow now polls every 500 ms until Shizuku answers
(the user-reported "Grant shows a message but never activates" bug, D-08);
SCREEN_ON resume, re-tracking, Unicode word boundaries, re-hide on update
(D-09…D-12); a native focus runtime — persisted dual-clock session,
foreground service, exact alarms, boot/time resync (D-13…D-19); challenge
mechanics re-ported numerically (D-27…D-29); usage warnings fire natively
and default ON (D-20/D-30); schema alignment (D-21/D-22/D-23/D-24); browser
apply merge semantics (D-25); declared-restrictions AppRestrictionsScreen
(D-33); correct DNS preset hosts inside a session-gated dialog (D-34);
4-step reveal-gated wizard (D-35); API-34 PolicyUpdateReceiver (D-36);
release hardening (D-37).

NOT changed (still awaiting explicit user decisions, §D): U-1 F20, U-2 F29,
U-3 F34 remain excluded; U-4 deferrals (NSFW F16/F17, Tetris, colour modes
F26, install watchers F6/F19, F18 wiring, F11 reopening cooldown) remain
deferred — F11/F12/F18 plumbing improved only where §B required it; U-5
PBKDF2 storage kept (wizard's 4×4 re-display grid remains impossible by
design and is documented in code). Still device-untested: no real-device run
has occurred; all native behaviour above is build-verified only.
