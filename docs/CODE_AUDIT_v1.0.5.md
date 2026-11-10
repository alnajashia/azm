# Code Audit — Azm v1.0.5 → v1.0.6 (second full audit)

**Scope note.** This is the second complete line-by-line audit of the
codebase. It re-read the tree as shipped at v1.0.5 (pubspec `1.0.5+6`,
105/105 tests, analyzer clean), applied every fix, and then absorbed
the user-ordered feature phases B–E and UI items 8–12. Because the
content changed, the result ships as **v1.0.6 (pubspec `1.0.6+7`)**;
the published v1.0.5 artifact was not modified.

**Method.** Every file below was read completely, in full, in its
pre-fix state; post-fix states were re-read at every edit site.
Mechanical verifications (l10n parity, gradient/icon/raw-error scans,
catalog coverage) are pinned by tests in the suite, not by eyeballing.

## Coverage

| Area | Files | Lines |
|---|---|---|
| Dart — hand-written (`lib/`, excl. generated l10n) | 27 | 16,097 |
| Dart — generated localizations (`lib/l10n/*.dart`, machine-verified for key parity) | 3 | 10,076 |
| ARB sources (`app_en.arb`, `app_ar.arb` — identical key sets, verified as valid JSON + parity test) | 2 | 3,188 |
| Kotlin (`android/**/*.kt`) | 21 | 7,238 |
| Tests (`test/*.dart`) | 15 | 3,592 |
| **Total read** | **68** | **40,191** |

Also read in full (not line-counted above): `AndroidManifest.xml`,
`android/app/build.gradle.kts`, `android/build.gradle.kts`,
`proguard-rules.pro`, `pubspec.yaml`, `l10n.yaml`,
`analysis_options.yaml`, native string resources (`values/`,
`values-ar/`), the accessibility-service XML configuration, and
`build_apk.sh`.

Per-file line counts (post-fix state) are reproducible with
`wc -l` over the paths above; the table sums were produced from the
same command output used to compile this report.

## FIELD FAILURE — removal residue on v1.0.5 AS SHIPPED (top hunt)

**Field report (2026-11-10):** the user updated to v1.0.5, pressed
“Remove Device Owner now”, the app reported completion — and the
Status tab read “not device owner”, yet (a) screenshots stayed
blocked, (b) the device would not restart normally, and (c) a stale
usage-warning notification (an app with a 5-minute timer) still sat in
the notification shade. This is a **proven false-success defect** in
the shipped teardown.

### Which dialog fired, and the exact success computation

The shipped `DeviceOwnerManager.removeDeviceOwner` ran **9 steps**:
flag → focus → unsuspend → restrictions → unhide → uninstallBlocks →
appRestrictions → clearOwner → flagClear. The Dart side marked the
removal **clean iff `!isDeviceOwner && failedSteps.isEmpty`** across
exactly those 9 steps, and the dialog showed the full-success text.
Every surface the 9 steps did not model **could not fail the dialog** —
there was no post-removal verification read of any kind. The
restrictions step, additionally, built its reset list from **one
read-back of the admin restriction bundle at one instant** and
verified against the same source.

### Missed surfaces (each proven from the shipped code)

1. **Notifications — never touched (proven gap).** The shipped
   teardown cancelled only the *focus* notification (inside the focus
   step). `UsageWarningNotifier` notifications and the
   `usage_warning_state` preferences were never cancelled or reset.
   This is the stale 5-minute usage-warning notification, verbatim.
2. **Standalone DPM policies — never reset.** The shipped code
   contains **zero** calls to `setScreenCaptureDisabled` (grep-proven
   across the whole tree) and no reset/verification of
   `setCameraDisabled`, `setStatusBarDisabled`, or
   `setKeyguardDisabledFeatures` anywhere in the teardown. The
   platform's API-36 restriction vocabulary contains **no**
   screen-capture or reboot key at all (verified against the SDK's
   `UserManager` class), so the user-restriction bundle the teardown
   read back could not even represent the screenshot policy.
3. **Samsung residue the read-back could not see.** The teardown
   trusted one read of the admin-composed bundle. On this device a
   restriction surface evidently persisted past both that read and the
   owner-clearing (Samsung composes restrictions from additional
   sources). The design flaw is independent of which specific key
   persisted: **success was computed from step bookkeeping, not from
   post-state.**
4. **Private DNS global state — never reset (proven gap).**
   `PrivateDnsController.apply` writes the system-global private-DNS
   mode/host via `Settings.Global`; owner-clearing does not revert
   global settings, and the shipped teardown never reset them.
5. **Notification-permission grant — never reverted.** The
   POST_NOTIFICATIONS runtime grant the app requests during setup
   stayed granted after removal.
6. **Removal-flag coverage was incomplete.** In the shipped code,
   `FocusReceiver`/`FocusSystemReceiver` had **no** removal-flag
   check, and the accessibility service's enforcement engines
   (`startTracking`, `tickUsageWarning`, `executeBlocking`) had **no**
   flag check either — during a long teardown these could re-suspend
   an app or re-post a usage warning *after* the clearing steps,
   manufacturing residue of exactly the reported class.

### What blocks restart

No reboot/power policy exists in our code or in the platform
restriction set. Screenshots and the power menu are both **SystemUI**
surfaces: the coherent explanation is a wedged SystemUI, consistent
with (i) the shipped `onUnbind` accessibility-loss lockdown firing
`AccessibilityRequestActivity` with **no admin-active guard**, and
(ii) enforcement engines staying armed through the teardown (item 6
above). A power menu that cannot complete a restart is the expected
fingerprint of that wedge once ownership is gone.

### The direct-uninstall question (hunt 1, explicit answer)

What happens on a direct system uninstall attempt while Azm is still
Device Owner: **Android itself refuses** — a live Device Owner cannot
be uninstalled (`DELETE_FAILED_DEVICE_POLICY_MANAGER`); the Settings
uninstall affordance is disabled. The removal never starts, none of
our code runs, and nothing can wedge from our side. The earlier
v1.0.4 freeze required the owner to be *already removed* (the bare
`clearDeviceOwnerApp` path) with uninstall then proceeding into the
service-unbind lockdown — a path the shipped v1.0.5 fixes, and this
build additionally guards (admin-active check before the lockdown can
launch its activity), close. An in-place **update** while owner is
safe by construction: the old process dies, the new service
connection restores state off the main thread.

### Teardown v2 — the fix (13 steps, verification-only success)

`removeDeviceOwner` now runs: **flag → focus → policies → privateDns →
unsuspend → restrictions → unhide → uninstallBlocks → appRestrictions
→ notifications → clearOwner → verify → flagClear**.

- **policies**: zeroes and *verifies by getter* screen-capture,
  camera, status-bar, and keyguard-feature policies; reverts the
  POST_NOTIFICATIONS grant to its default state on API 33+.
- **privateDns**: resets the global private-DNS mode to opportunistic
  and verifies the read-back.
- **restrictions**: sweeps the **complete** key vocabulary
  (`allRestrictionKeys()` ∪ every key currently true in the live
  bundle — never read-back-only), records the swept set as
  `residueKeys`, and verifies the admin bundle holds no true key.
- **notifications**: `NotificationManager.cancelAll()`, the
  usage-warning notifier's state is fully reset, and the step verifies
  zero active notifications remain.
- **verify (post-clear, admin-free reads)**: the step fails — and the
  dialog therefore reports a *partial* removal, never a clean “done” —
  if the app is somehow still owner, if the **calling user's**
  `UserManager` restriction bundle still shows any swept key true, if
  a readable screen-capture policy is still on, or if any of the app's
  notifications is still active.
- Flag coverage is now total: the focus receivers and the
  accessibility enforcement engines return early while a removal is in
  progress.
- New channel method `getUserRestrictionResidue` (needs no admin
  rights) backs a **residue warning on the Config tab**: if a run
  detects leftover restrictions while *not* owner, the UI says plainly
  that cleanup requires re-provisioning as Device Owner first — the
  only in-app route back to clearing power — instead of pretending it
  can clean up unprivileged. (This is also the recovery route for the
  device affected by the field failure: install this build,
  re-provision, run Remove Device Owner.)

**Reference verdicts.** Against the original DeChainer: its removal
was the bare owner-clear this audit's predecessor already replaced;
teardown v2 keeps the original's *surface inventory* (everything the
original could set, this teardown resets) and adds verification the
original never had. Against Android's DevicePolicyManager lifecycle
documentation: clearing order (policies before `clearDeviceOwnerApp`)
and admin-free post-verification reads match the documented contract.

## Phase A — audit findings and resolutions

Severity counts (pre-fix tree): HIGH 3 (gate-path challenge runner —
already fixed in v1.0.5 and re-verified here; monotonic-clock pending
changes; teardown false-success — the field failure above),
MEDIUM 14, LOW 18, plus 9 adjudicated as documented-accepted with
reasoning recorded in the working notes (parse-fallback defaults,
advisory event-stream swallowing, public controller fields, the focus
receivers' bounded main-thread work at original parity, synthetic
exit-code −1, an unreachable defensive branch, non-atomic dual-pref
writes at original parity, the usage-warning gate formula, and the
internal asset filename keeping the project name — internal
identifiers are out of rename scope).

Principal fixes, by area:

- **Domain (Dart):** pending-change countdowns now advance on
  monotonic deltas, never wall-clock jumps (a +48 h clock change would
  previously have completed a forced removal early); the recovery
  session carries the same dual-clock hardening; a disposed
  pending-change now completes its future instead of hanging a caller;
  the words challenge is safe before start; entry-password hash
  verification enforces structural floors (salt/hash sizes, iteration
  bounds); entry-password state distinguishes unset / set / corrupt.
- **Channel:** boolean setters verify their native `verified` field
  and throw a typed error when it is absent (a native no-op can no
  longer masquerade as success); app-restriction reads reject
  malformed payloads instead of coercing them.
- **Controller/UI:** the per-second tick is re-entrancy-guarded; the
  challenge runner is constructed **only** in the Impulse Lock screen
  (source-scan pinned — fix-1 re-verification); the lock screen's
  no-credential fallback surfaces a dialog for *every* failure mode;
  a mistyped entry password is reported distinctly from a verify
  error; tightening saves surface their errors; the remaining control
  groups completed the titled-card regrouping without moving any
  control across a gate boundary (handlers diffed, not just widgets —
  fix-3 re-verification).
- **Native (Kotlin):** Shizuku provisioning checks shell exit codes;
  the removal-flag guard reached the focus receivers; the reflective
  device-owner setter no longer defaults to success; shell failures
  are logged with their exit codes; persisted decoders log and clamp
  corruption instead of silently discarding state; the removal flag
  write is synchronous (`commit()`); the intentional-disable window
  for the accessibility service is actually enforced (120 s); the
  accessibility toggle verifies its post-state strictly; two
  components that must not be exported no longer are; app backups are
  disabled; recovery-code verification bounds its input.
- **Fixes 2/4/5 re-verified:** zero gradient APIs in `lib/` (scan test
  + independent grep); logo sizing/spacing as specified (and halved
  again under item 8 below); rename completeness — no user-visible
  old-name string remains in UI, native strings, or notifications,
  while internal identifiers are untouched by design.
- **Hunt 2 (biometrics/entry) verdict:** `MainActivity` is a
  `FlutterFragmentActivity` (grep-proven, as local_auth requires);
  every lock-screen error path surfaces visibly (per-code mapping plus
  a generic catch — nothing swallowed); the no-credential fallback,
  the entry-password path (salted hash verification, persisted
  anti-guess throttling, never any plaintext, and the entry password
  never opens a recovery session), and entry state across process
  recreation were traced end-to-end against the local_auth documented
  contract. **Pass**, with the Phase E presentation replacing the old
  raw error text (below).
- **Hunt 3 (main-thread sweep):** every channel handler, receiver
  body, service/activity lifecycle callback, and accessibility
  callback was classified; the only main-thread platform work is the
  focus receivers' bounded policy calls, at parity with the original
  and documented-accepted above. Everything else runs on the channel
  executor or a dedicated worker.

## Phase B — on-device content inspection (user order)

Full spec extraction, provenance, and deviations live in
`docs/FEATURE_v1.0.6.md`. Summary: the original's visual blocking was
re-implemented natively in the accessibility service — per-app
enablement, media-region detection first (screenshots only when a
region exists), a 2-second non-overlapping scan throttle, per-region
classification with the original's label set and 0.5 default
threshold, the original's reaction (suspend pulse + blocked screen)
and its optional escalation (5 detections / 15 min → 30-min hold).
The model is the official GantMan/nsfw_model **v1.2.0** release model
(MIT — see the notice bundled in the app), obtained from the official
release, verified byte-identical to the model the original ships and
exercised offline against the LiteRT runtime before bundling.
Inference and capture are native-only; screen content never leaves the
device. **Verification limit, stated honestly: actual detection on
real content is device-only and is NOT verified by this audit.**

## Phase C — app-lock timing (user order)

WhatsApp-style entry grace: Immediately (default — existing users see
no weakening), 1 minute, 15 minutes, 1 hour. The unlock moment is a
persisted wall-clock timestamp (process death cannot extend the
grace; future timestamps clamp to expired); a 3-second transient
debounce keeps the biometric prompt and system dialogs from causing
relock loops; failed attempts record nothing. The grace governs the
entry gate only — the recovery session and every sensitive-action gate
are untouched. Lengthening requires the recovery session; shortening
is free.

## Phase D — seal rules (user order)

User-defined seals make Azm refuse its own removal: condition seals
(a chosen app is uninstall-blocked/hidden, a chosen app is suspended,
a focus session is running — all probed **live, natively**, at attempt
time) and event seals (a Phase B image detection or banned-word hit in
a chosen app seals removal for 30 min – 7 days, anchored to
`elapsedRealtime` with a wall-clock fallback across reboot). Refusal
is native and typed: immediate removal checks the seals first, and
filing the delayed forced removal is refused while a seal is active —
while a countdown filed *before* a seal still executes at its mark
(stated in the UI copy). An active seal cannot be cancelled from the
UI and the paper code does **not** break it (stated honestly in the
copy). The UI states the honest limit: seals have teeth only while
Azm is Device Owner. Native refusal is verified at compile/inspection
level; on-device refusal behaviour remains device-unverified.

## 24-hour directive (user order)

The delayed forced removal is **24 hours** (a deliberate, user-directed
deviation from the original's 48). One native constant is the source
of truth; the Dart side binds the value delivered in the native state
at startup rather than hard-coding its own. All countdown logic, ARB
strings (both locales), UI copy, and tests were updated; a scan test
proves no forced-removal “48” remains in code or strings (historical
descriptions of the *original's* behaviour in analysis documents are
unchanged — they describe the reference, not this product).

## Phase E — plain-language errors + centered Card (user order)

Every user-visible error now crosses the channel as a **typed code**
and is mapped by one total Dart-side mapper to a localized
plain-language message; raw exception text, platform codes, and exit
codes never reach the UI (they go to a local debug log only), and
unmapped errors fall back to one generic friendly message. Seal
refusals render the responsible rule and remaining time.

Presentation (user addendum): errors are a **centered modal Card**
over a dimmed scrim — white card with near-black text in light theme,
near-black card with white text in dark theme, red accent icon,
comfortably sized text, explicit OK button, `barrierDismissible:
false`, never auto-dismissed. Short success/info confirmations remain
lightweight but were restyled to the same contrast bar. The old inline
error view that printed raw codes was removed. Tests pin the mapper
contract (every typed code × both locales, no technical tokens, no
raw-message leakage), the Card presentation (dialog present, snackbar
absent, no auto-vanish), and a source scan banning raw-error
interpolation into UI text.

## Items 8–13 — UI polish (user orders)

- **Item 8 — logo:** the lock-screen brand mark halved (80 dp → 40 dp,
  corner radius 20 → 10) with increased surrounding whitespace
  (48 → 64 dp above, 24 → 32 dp below). Grep-proven as the only
  in-UI brand placement; launcher/adaptive icons untouched.
- **Item 9 — icons:** every icon in the UI is now the outlined
  variant. Before: 36 filled-variant names in use across `lib/`.
  After: **0** filled references outside the single sanctioned
  exception below; active states are carried by the red accent and
  indicators, never a filled glyph. A source-scan test pins this
  (names ending in `_outline` are Material's outlined glyphs under
  their canonical names).
- **Item 10 — shapes + Apps search:** one documented radius scale
  (16 / 20 / 28 / pill 999) applied through the theme to cards,
  dialogs (incl. the error Card), buttons, fields, sheets, chips,
  menus, and snackbars, with local stragglers normalized (Apps cards
  10 → 20, badges to pill, lock progress clip 4 → 8, hero 24 → 28).
  The Apps search field is now a pill, and the “include system apps”
  toggle lives **inside** it as a trailing icon button: outlined when
  off, **filled when on — the user's own explicit, single sanctioned
  exception to item 9**, encoded in the scan test's allowlist.
- **Item 11 — header/session:** the app bar is now a minimal brand row
  (28 dp logo, app name, no actions). The session controls moved —
  handlers and gates unchanged, relocation only — into a titled
  “Recovery session” card directly below the header, visible only
  while a session is active, carrying the remaining time and the same
  Renew / End actions.
- **Item 12 — restriction explanations:** every one of the **74**
  restrictions in the catalog (the platform's full key vocabulary on
  API 36, the recommended set, and the Samsung/Knox extras) has a
  plain-language explanation in **both** Arabic and English — what it
  blocks, why it is useful, and any honest side effect — behind an
  info button on each Restrictions row (the switch itself still
  toggles normally), shown in the Phase E centered Card. Explanations
  live in one shared source keyed by restriction id; a test pins total
  coverage in both locales, and any future key falls back to a generic
  explanation rather than a blank.
- **Item 13 — not-owner card navigation:** on the Restrictions
  screen, the not-yet-provisioned card previously pushed the setup
  wizard as a pop-up page; it now **switches to the Config tab**
  (where provisioning lives) via a controller tab request the shell
  consumes — the dialog/page-push path is removed entirely, the
  card's explanatory text is unchanged, and navigation is ungated.
  The card exists in exactly one placement (verified by search); it
  is not a shared widget.

## Build record

The first clean release build of the combined tree failed Kotlin
compilation on three defects, all fixed and rebuild-verified:
(1) two teardown-v2 references qualified `allRestrictionKeys()` with
a non-existent `SystemRestrictions` object name (the catalog lives on
`DeviceOwnerManager` itself); (2) the status-bar policy verification
called a non-existent `getStatusBarDisabled()` — the platform getter
is `isStatusBarDisabled()` (signature verified against the SDK);
(3) LiteRT 2.2.0's Kotlin-API module carries a newer Kotlin metadata
version than this project's compiler — the module's compiler options
now skip the metadata version check, with the reason recorded inline
(the feature uses only the stable Java-facing `org.tensorflow.lite`
surface, the same API the original compiles against).

## Verification

- `flutter analyze` → **“No issues found!”**
- `flutter test` → **149/149 passed** (105 at v1.0.5 baseline; +44
  across the audit regression tests and the v1.0.6 feature/polish
  pins).
- Release build: versionName **1.0.6** / versionCode **7**; Azm /
  عزم labels verified in the APK badging; the content-inspection
  model (17,355,548 bytes, stored uncompressed) and its license
  notice are present in the APK assets, with the LiteRT runtime
  libraries for all three ABIs.
- Device-only verification remains outstanding (stated, not claimed):
  the amended removal flow on a real device, content detection on real
  content, and native seal refusal at attempt time.
