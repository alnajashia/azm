# Parity Audit — Part 3 of 5: Runtime Services
## Notifications, focus service, block activities, NSFW

> **Mode:** READ-ONLY audit. No project code was edited.
> **Reference (source of truth):** `reference/dechainer-zip/dechainer-1.12.0/app/src/main/java/io/github/warleysr/dechainer/` (DeChainer v1.12.0)
> **Ours:** `project/` (Dominanter)
> **Context cross-checked (verified, not copied):** `project/docs/COMPLIANCE_AUDIT.md`, `analysis/DECHAINER_FEATURES.md` (F1–F34).
> Findings **not** present in the compliance audit are marked **NEW**.
>
> **Classification legend:** `EQUIVALENT` · `PARTIAL` · `MISSING` · `DEFERRED-DOCUMENTED (F#)` · `EXCLUDED-DOCUMENTED (F#)`
>
> Short path aliases used in citations:
> - `REF/notifications/…`, `REF/activities/…`, `REF/data/…`, `REF/DechainerAccessibilityService.kt` = original tree above
> - `OUR/accessibility/BlockActivity.kt`, `OUR/accessibility/DominanterAccessibilityService.kt` = `project/android/app/src/main/kotlin/io/github/alnajashia/dominanter/…`
> - `OUR/AndroidManifest.xml` = `project/android/app/src/main/AndroidManifest.xml`
> - `REF/AndroidManifest.xml` = original `app/src/main/AndroidManifest.xml`

---

## 0. Executive summary — the whole runtime-notification layer is absent

The original has a complete native runtime layer around the Accessibility Service:
two notification objects (`FocusNotifier`, `UsageWarningNotifier`), one foreground
service (`FocusService`), four broadcast receivers (`FocusReceiver`,
`FocusSystemReceiver`, `FocusScheduleReceiver`, `UsageWarningDismissReceiver`,
`ApkUpdateResultReceiver`), an exact-alarm phase engine (`data/FocusMode.kt`,
546 lines), a schedule engine (`data/FocusScheduleManager.kt`), and eight
dedicated block/gate activities.

Ours has **none of the notification/service/receiver layer**:

- Grep over `project/android/app/src/main/kotlin/` for `Notification`,
  `startForeground`, `AlarmManager`: **0 hits** in the channel handler
  (`channel/PrivilegedChannelHandler.kt` — no `focus`/`notification` method at
  all, confirmed by grep returning nothing) and no hits anywhere except the
  Accessibility Service's own dynamic `BroadcastReceiver` for screen/time
  events (`OUR/accessibility/DominanterAccessibilityService.kt:87-95`) and
  `DominanterApplication`'s package-change receiver.
- `OUR/AndroidManifest.xml` declares **no** `<service>` except the
  Accessibility Service (`OUR/AndroidManifest.xml:112-123`) and **no**
  notification/focus/boot receiver at all (only
  `DominanterDeviceAdminReceiver` at :80-90 and
  `DominanterPolicyUpdateReceiver` at :92-100), yet it still requests
  `RECEIVE_BOOT_COMPLETED` (:15), `SCHEDULE_EXACT_ALARM` (:17-18),
  `USE_EXACT_ALARM` (:19), `FOREGROUND_SERVICE` (:20) and
  `FOREGROUND_SERVICE_SPECIAL_USE` (:21) — permissions with no consumer
  (compliance audit gap **G3**).
- The original manifest declares every one of these components:
  `UsageWarningDismissReceiver`, `FocusReceiver`, `FocusScheduleReceiver`,
  `ApkUpdateResultReceiver` (all `exported=false`), `FocusService` with
  `foregroundServiceType="specialUse"` + the special-use subtype property,
  and `FocusSystemReceiver` (`exported=true`) for
  `BOOT_COMPLETED / MY_PACKAGE_REPLACED / TIME_SET / TIMEZONE_CHANGED`
  (`REF/AndroidManifest.xml:132-166`).

What ours *does* have is a consolidated native block screen
(`OUR/accessibility/BlockActivity.kt`, 148 lines, 5 variants + a native
`AccessibilityRequestActivity` in the same file) driven by the Accessibility
Service, plus purely in-Dart focus/impulse timers. The block-screen half is
largely equivalent; the notification/focus-runtime half is missing/deferred.

| Original file | Classification | F |
|---|---|---|
| `notifications/ApkUpdateResultReceiver.kt` | EXCLUDED-DOCUMENTED | F29 |
| `notifications/FocusNotifier.kt` | DEFERRED-DOCUMENTED (no FGS/notification in v1) | F25 |
| `notifications/FocusReceiver.kt` (+ `FocusSystemReceiver`) | MISSING (consequence of F25 deferral; boot resync itself undocumented as a separate gap) | F25 |
| `notifications/FocusReminderNotifier.kt` | DEFERRED-DOCUMENTED | F25 |
| `notifications/FocusScheduleReceiver.kt` | DEFERRED-DOCUMENTED | F25 |
| `notifications/FocusService.kt` | DEFERRED-DOCUMENTED | F25 |
| `notifications/UsageWarningDismissReceiver.kt` | DEFERRED-DOCUMENTED (inseparable from F12) | F12 |
| `notifications/UsageWarningNotifier.kt` | DEFERRED-DOCUMENTED — config exists, **nothing fires it** | F12 |
| `activities/AccessibilityRequestActivity.kt` | EQUIVALENT (minor diffs, §10) | F28 |
| `activities/BlockedWordActivity.kt` | PARTIAL (see **NEW** blur diff, §11) | F14/F15 |
| `activities/FocusReminderActivity.kt` | DEFERRED-DOCUMENTED | F25 |
| `activities/LockScreen.kt` | PARTIAL (see §13 deep dive; **NEW** diffs) | F21/F25/F29/F32 |
| `activities/NsfwContentBlockedActivity.kt` | DEFERRED-DOCUMENTED | F16 |
| `activities/OutsideTimeWindowActivity.kt` | EQUIVALENT | F10 |
| `activities/ReopeningLimitActivity.kt` | DEFERRED-DOCUMENTED + dead variant in ours (G1) | F11 |
| `activities/TimeUpActivity.kt` | EQUIVALENT (minor diffs, §17) | F9 |
| `utils/NsfwContentDetector.kt` + `nsfw_model.tflite` | DEFERRED-DOCUMENTED — detector, model, pipeline all absent | F16/F17 |

---

## 1. `notifications/ApkUpdateResultReceiver.kt` — EXCLUDED-DOCUMENTED (F29)

**Original — what it does.** Manifest-declared (`exported=false`) broadcast
receiver for the silent APK self-update/downgrade installer
(`REF/notifications/ApkUpdateResultReceiver.kt:11`). Three actions
(`:13-16`): install result, uninstall result, downgrade-uninstall result.
`onReceive` dispatches downgrade/install (`:19-24`). On downgrade-uninstall
success it commits the staged downgrade session, otherwise aborts it, then
toasts failure (`:26-39`). On install result it abandons any
`STATUS_PENDING_USER_ACTION` session ("nobody is going to confirm it, so the
session would otherwise stay open forever", `:47-50`), calls
`ApkUpdateInstaller.onInstallFinished` (`:51`), and — critically — if a
supposed *update* turns out to be a **fresh install of a new app, it
uninstalls it again** and toasts `apk_update_new_app` (`:54-62`); signature
conflicts and failures get distinct toasts (`:63-66`).

**Lifecycle/trigger.** `PackageInstaller` session callbacks created by
`REF/data/ApkUpdateInstaller.kt:346-401` (PendingIntents to this receiver).
The entry point is unauthenticated, from the lock screen (see §13).

**Ours.** Absent, deliberately: grep for `PackageInstaller` in `project/`
returns 0 hits; no `REQUEST_INSTALL_PACKAGES`/`REQUEST_DELETE_PACKAGES`
permission in `OUR/AndroidManifest.xml`; no counterpart receiver, installer,
or lock-screen affordance. Compliance audit F29 row confirms the absence and
the rationale (unauthenticated install surface = security liability).

**Classification: EXCLUDED-DOCUMENTED (F29).** Note the receiver cannot be
ported without the installer; there is no orphaned half-port here.

---

## 2. `notifications/FocusNotifier.kt` — DEFERRED-DOCUMENTED (F25)

**Original — what it does.** Singleton object
(`REF/notifications/FocusNotifier.kt:29`), 235 lines, owner of *all* focus
notification behaviour:

- Channels: `focus_timer` (IMPORTANCE_LOW, silent, no vibration, no badge)
  created lazily in `ensureChannels()`; the legacy `focus_alert` channel is
  actively deleted (`:30-31`, `ensureChannels` body).
- Status notification ID `STATUS_ID = 0x0F0C05` (`:33`).
- `showStatus()` (`:88-93`): no-ops unless `FocusMode.isActive()`, rebuilds
  the status notification **and ensures `FocusService` is running**
  (`FocusService.ensureRunning`, `:92`).
- `buildStatus()`: custom `RemoteViews` layout with phase title
  (Focus *n* of *N* / Short break / Long break / Waiting / "Paused: …"),
  a live countdown **chronometer** anchored at
  `elapsedRealtime() + remainingMillis`, and a progress bar; ongoing,
  silent, `VISIBILITY_PUBLIC`, content intent to `MainActivity`.
- Notification **actions that need no recovery code** (`:182-189` and
  `buildStatus` tail): WAITING → *Start focus* + *End session*; paused →
  *Resume*; break → *Skip break*. Dismissal is intercepted: the delete
  intent fires `FocusReceiver.ACTION_REPOST` (`:169`), so swiping it away
  just re-posts it.
- `alertPhaseEnded()`: sound (default notification/alarm ringtone, capped
  at `SOUND_MAX_MS = 5_000` ms via a main-looper Handler) and/or vibration
  (pattern `0,300,200,300`), each independently toggleable in `FocusMode`
  settings.
- `cancel()` (`:202`): stops `FocusService` and cancels `STATUS_ID`.
- `buildPlaceholder()`: a minimal silent notification so a foreground-service
  start that finds no session can still call `startForeground()` before
  stopping (avoids `ForegroundServiceDidNotStartInTimeException`).

**Triggers.** `FocusMode.applyState()` calls `FocusNotifier.showStatus()`
after every phase/state change (`REF/data/FocusMode.kt` `applyState`, and
call sites at `FocusMode.kt:119,144,155,314`); `FocusNotifier.cancel()` from
`FocusMode.stop()` (`FocusMode.kt:277`); `alertPhaseEnded()` from
`FocusMode.sync()` on phase expiry (`FocusMode.kt:294` — line in the
numbered `sync` excerpt: `FocusNotifier.alertPhaseEnded(ctx)`).

**Ours.** **ABSENT.** No Kotlin notification code exists at all (grep:
0 hits for `Notification` under `project/android/.../kotlin/`). There is no
channel method for focus notifications (`PrivilegedChannelHandler.kt`
contains no `focus`/`Notification` symbol). The Dart focus screen
(`lib/ui/impulse_focus_screens.dart:347-445`) renders an in-app timer ring
only while the screen exists; phase-end produces no sound, no vibration, no
system notification, and there are no notification actions. The focus screen
itself discloses this in-UI (`impulse_focus_screens.dart`, note under the
controls: *"the countdown runs while this app is alive. The native
foreground-service timer of the original is not part of this version"*).

**Classification: DEFERRED-DOCUMENTED (F25)** — audit F25 row: "no native
foreground service and no schedules in v1".
**NEW detail:** the audit does not separately record the loss of
phase-end **sound/vibration alerts** or of the **notification actions**
(start/resume/skip-break/end-from-notification, dismiss-to-repost). Those
are distinct user-visible behaviours, not implied by "no FGS".

---

## 3. `notifications/FocusReceiver.kt` (+ `FocusSystemReceiver`) — MISSING (F25 consequence)

**Original — what it does.** Two receivers in one file
(`REF/notifications/FocusReceiver.kt`, 56 lines):

- `FocusReceiver` (`:10`) handles six app actions (constants at file end):
  - `ACTION_PHASE_END` — the exact-alarm callback: `goAsync()`, then
    `FocusMode.sync(context)`, holding the async handle for
    `FocusNotifier.SOUND_KEEP_ALIVE_MS` (5 s) so the phase-end sound can
    finish (`:13-18`).
  - `ACTION_START_FOCUS` — only honoured in `WAITING` phase.
  - `ACTION_SKIP_BREAK` → `FocusMode.skipBreak()`.
  - `ACTION_RESUME` → `FocusMode.resume()`.
  - `ACTION_STOP` — only honoured in `WAITING` ("anywhere but WAITING,
    ending needs the recovery code").
  - `ACTION_REPOST` → `FocusMode.sync()` (re-posts the status notification).
- `FocusSystemReceiver` (second class in the same file): on
  `BOOT_COMPLETED`, `MY_PACKAGE_REPLACED`, `TIME_CHANGED`,
  `TIMEZONE_CHANGED`, `TIME_SET` → `FocusMode.sync(context)` **and**
  `FocusScheduleManager.reschedule(context)`. Declared `exported=true`
  with that intent-filter in `REF/AndroidManifest.xml:157-166`.
  `FocusReceiver` itself is declared `exported=false`
  (`REF/AndroidManifest.xml:136-138`).

**Ours.** **ABSENT.** No receiver of either kind; `OUR/AndroidManifest.xml`
has no boot/time intent-filter anywhere, despite requesting
`RECEIVE_BOOT_COMPLETED` (`OUR/AndroidManifest.xml:15`). Nothing re-arms or
re-syncs anything after reboot, update, or clock change — for focus *or*
schedules. (The Accessibility Service does register a *dynamic* receiver
for `SCREEN_OFF/TIME_CHANGED/TIMEZONE_CHANGED`, but only to reset its
daily usage date: `OUR/accessibility/DominanterAccessibilityService.kt:87-95,119-155` registration — it does not touch focus state, which does not
exist natively.)

**Classification: MISSING** as a direct consequence of the documented F25
deferral. **NEW:** the compliance audit's G3 notes the unused boot
*permission*, but no audit row records that the original's boot/update/
clock-change **resync behaviour** (`FocusSystemReceiver`) is a separate
lost guarantee: in the original, a reboot mid-focus-phase is a non-event;
in ours there is no focus state to resync (see §18).

---

## 4. `notifications/FocusReminderNotifier.kt` — DEFERRED-DOCUMENTED (F25)

**Original — what it does.** Object
(`REF/notifications/FocusReminderNotifier.kt:19`), 85 lines. Owns the
scheduled-session reminder notification: channel `focus_schedule_reminder`
(IMPORTANCE_HIGH, vibration pattern `0,400,200,400`), fixed ID
`NOTIFICATION_ID = 0x0F0C20`. `showReminder(context, activityIntent,
snoozeCount)` builds a `PRIORITY_MAX` / `CATEGORY_ALARM` notification with a
**full-screen intent** to `FocusReminderActivity` (so it breaks through the
lock screen), auto-cancel, and vibrates immediately if focus vibration is
enabled. `cancel()` cancels the ID — called by `FocusReminderActivity`
on open (`REF/activities/FocusReminderActivity.kt:46`).

**Trigger.** `FocusScheduleManager.launchReminder()`
(`REF/data/FocusScheduleManager.kt:59-75`): posts this notification *and*
tries to start the activity directly, falling back to the full-screen
intent if the background start is blocked (`:70-74`).

**Ours.** **ABSENT.** No schedules, no reminder notification, no
full-screen intent anywhere. The Dart focus screen carries a labelled
placeholder tile instead: `UnavailableTile` "Focus schedules & reminders —
Scheduled auto-start sessions are not in this version"
(`lib/ui/impulse_focus_screens.dart:623-627`).

**Classification: DEFERRED-DOCUMENTED (F25).**

---

## 5. `notifications/FocusScheduleReceiver.kt` — DEFERRED-DOCUMENTED (F25)

**Original — what it does.** Broadcast receiver
(`REF/notifications/FocusScheduleReceiver.kt:10`), 44 lines, declared
`exported=false` (`REF/AndroidManifest.xml:140-142`). Two actions:

- `ACTION_SCHEDULE_TRIGGER` (`:13-22`): re-arms the next schedule
  (`FocusScheduleManager.reschedule`), then — unless a focus phase is
  already running — launches the reminder with `snoozeCount = 0`.
- `ACTION_SNOOZE_TRIGGER` (`:24-35`): reads `EXTRA_SNOOZE_COUNT`; if focus
  started in the meantime, cancels the snooze; otherwise re-launches the
  reminder with the incremented count.

**Trigger.** Exact alarms (`RTC_WAKEUP`, `setExactAndAllowWhileIdle` when
permitted) armed by `FocusScheduleManager.reschedule()` /
`scheduleSnooze()` (`REF/data/FocusScheduleManager.kt:18-52`), with
request codes `0x0F0C10`/`0x0F0C11` and a fixed 5-minute snooze delay
(`SNOOZE_DELAY_MILLIS`, `FocusScheduleManager.kt:16`).

**Ours.** **ABSENT** — no receiver, no alarm, no schedule storage consumer.
Note the half-presence: `SettingsStore.PREFS_FOCUS_SCHEDULES =
"focus_schedules_prefs"` exists and the store is in the generic-settings
allowlist (`OUR/.../data/SettingsStore.kt:51,392`), i.e. Dart can persist
schedule-shaped JSON that **nothing native ever reads** — the same
dead-plumbing pattern as audit gap G1, applied to F25 schedules.
**NEW** (audit G1 covers this pattern for F18/F11 only).

**Classification: DEFERRED-DOCUMENTED (F25).**

---

## 6. `notifications/FocusService.kt` — DEFERRED-DOCUMENTED (F25) — full comparison in §18

**Original — what it does.** A real foreground service
(`REF/notifications/FocusService.kt:20`), 126 lines, declared with
`foregroundServiceType="specialUse"` (`REF/AndroidManifest.xml:148-155`).
Its *only* job is cosmetic-but-essential: the notification progress bar
does not animate itself, so the service re-posts it. A main-looper
`Handler` tick (`:22-40`):

1. calls `FocusMode.syncIfDue()` (phase expiry is *also* checked here, not
   only by the alarm),
2. stops itself if there is no session,
3. ticks every 60 s while WAITING/paused, otherwise re-posts the status
   notification (only while the screen is interactive) at an interval of
   `phaseDuration / 300` steps, min 1 s.

`onStartCommand` **always** calls `startForeground()` first — with the real
status notification or `FocusNotifier.buildPlaceholder()` — because
skipping it after a `startForegroundService()` call crashes with
`ForegroundServiceDidNotStartInTimeException` (`:45-68`); returns
`START_STICKY`. `ensureRunning()` (`:102-115`) restarts ticking on the live
instance or calls `startForegroundService()`; `stopForDebugInstall()` is a
deliberate hatch that keeps the service down so a debug install is not
blocked (used by the Accessibility Service, `REF/DechainerAccessibilityService.kt:560`).

**Ours.** **ABSENT.** No service class, no manifest `<service>` for focus,
no `startForeground` call anywhere. See §18 for the full behavioural
comparison against our Dart-timer approach.

**Classification: DEFERRED-DOCUMENTED (F25)** (audit F25 row + gap G3).

---

## 7. `notifications/UsageWarningDismissReceiver.kt` — DEFERRED-DOCUMENTED (F12)

**Original — what it does.** 18-line receiver
(`REF/notifications/UsageWarningDismissReceiver.kt`): on receive, extracts
`EXTRA_KEY` / `EXTRA_STAGE_ID` and calls
`UsageWarningNotifier.markDismissed(context, key, stageId)` (`:13-17`).
It is the delete-intent target of every usage-warning notification
(`UsageWarningNotifier.kt` deleteIntent construction), i.e. **swiping a
warning away is remembered** (`usage_warning_state` prefs) so that stage
does not re-alert for that app/group today. Declared `exported=false`
(`REF/AndroidManifest.xml:132-134`).

**Ours.** **ABSENT** — inseparable from §8: there are no warning
notifications to dismiss.

**Classification: DEFERRED-DOCUMENTED (F12).**

---

## 8. `notifications/UsageWarningNotifier.kt` — DEFERRED-DOCUMENTED (F12): config exists, nothing fires it

**Original — what it does.** Object
(`REF/notifications/UsageWarningNotifier.kt:23`), 207 lines. Staged
pre-expiry warnings for app/group time limits:

- Three channel families chosen per stage type (`:24-33`): `usage_warning_silent`
  (IMPORTANCE_LOW, no sound/vibration), `usage_warning_sound`
  (IMPORTANCE_DEFAULT), and per-count `usage_warning_vibrate_<n>`
  (IMPORTANCE_DEFAULT, generated vibration pattern of *n* × 250 ms pulses
  with 150 ms pauses, `buildVibrationPattern`).
- Persistent shown/dismissed bookkeeping in `usage_warning_state`
  SharedPreferences: `hasBeenShown / markShown / isDismissed / markDismissed
  / reset / resetAll` (`:99-127` region), keyed `shown_<key>:<stageId>` /
  `dismissed_<key>:<stageId>` (`:205-206`).
- `showOrUpdate(context, key, stage, displayName, remainingMillis,
  thresholdMillis)` (`:129-202`): no-ops if notifications are disabled;
  builds a custom `RemoteViews` warning with remaining time formatted
  `m:ss`, and a progress bar whose colour bucket flips at fraction
  ≥ 0.5 (ok) / ≥ 0.2 (warning) / below (critical) (`BUCKET_*` constants);
  content intent → `MainActivity`; delete intent →
  `UsageWarningDismissReceiver`; `notify()` under a stable per-(key,stage)
  ID (`notificationIdFor`, `:184-201`).

**Who fires it in the original — the Accessibility Service, on a 2 s-class
tick.** The chain is entirely inside
`REF/DechainerAccessibilityService.kt`:

1. `startTracking()` computes app/group remaining time and calls
   `scheduleUsageWarning(pkg, config, appRemaining, groupRemaining)`
   (`DechainerAccessibilityService.kt:1344`).
2. `scheduleUsageWarning` (`:1350-1375`): picks the app key or the group
   key (whichever limit is closer), and either posts `warnTickRunnable`
   for when the farthest stage is entered, or ticks immediately.
3. `tickUsageWarning()` (`:1377-1465`): recomputes remaining from
   `elapsedRealtime` session time; cancels the notification at ≤ 0;
   selects the entered stage (`usageWarningStages.lastOrNull { remaining
   <= stageMillis(it) }`); on stage change cancels the previous stage's
   notification; if not dismissed, calls
   `UsageWarningNotifier.showOrUpdate(...)` (`:1420-1433`, call at `:1426`)
   and re-arms the tick.
4. Cleanup: `executeBlocking()` cancels all stage notifications for the
   app and its group (`:1474-1475`); the date-change path calls
   `cancelActiveUsageWarning()` + `UsageWarningNotifier.resetAll()`
   (`:1527-1529`); a settings toggle-off cancels the active warning
   (`:293-347`).
Stages themselves come from `data/UsageWarningSettings.kt` (defaults:
15 min silent, 5 min sound, 1 min vibrate×1, 0.5 min vibrate×3 — per
`DECHAINER_FEATURES.md` F12).

**What fires it in ours — nothing.** This is the audit's F12 finding,
re-verified here at the firing site:

- There is **no** `UsageWarningNotifier` counterpart, no notification code,
  and no warning tick in `OUR/accessibility/DominanterAccessibilityService.kt`
  (its `startTracking` at `:377-417` schedules only `blockRunnable` and
  `windowEndRunnable`; its header at `:22-52` explicitly lists *"staged
  usage warnings (F12…)"* among the deliberately-absent v1 effects).
- The *configuration* half exists in Dart: `lib/data/config_store.dart`
  `getUsageWarnings/setUsageWarnings` with the original's defaults,
  persisted via generic settings, with an editor in
  `lib/ui/config_screens.dart` (per audit F12 row). A user can therefore
  edit warning stages that will never produce a notification — the UI does
  not fire, queue, or simulate them.
- No channel method bridges the gap: `PrivilegedChannelHandler.kt` has no
  warning/notification method.

**Classification: DEFERRED-DOCUMENTED (F12)** — editor + storage are v1;
delivery is v1.1 (audit F12 row, confirmed at both the notifier site and
the firing site).

---

## 9. Consolidated manifest comparison (components)

| Component | Original (`REF/AndroidManifest.xml`) | Ours (`OUR/AndroidManifest.xml`) |
|---|---|---|
| Block activities | 6 separate activities, each `showOnLockScreen=true` (except AccessibilityRequest), `singleInstance`, `excludeFromRecents`, `noHistory`, `taskAffinity=""` (`:54-109`) | 1 consolidated `BlockActivity` (`:64-71`) + `AccessibilityRequestActivity` (`:72-79`), same launch flags incl. `showOnLockScreen=true` on BlockActivity only |
| `FocusReminderActivity` | declared (`:101-109`) | **absent** |
| `FocusService` (FGS specialUse) | declared (`:148-155`) | **absent** |
| `FocusReceiver`, `FocusScheduleReceiver`, `UsageWarningDismissReceiver`, `ApkUpdateResultReceiver` | declared, `exported=false` (`:132-146`) | **absent** |
| `FocusSystemReceiver` (boot/update/time) | declared, `exported=true` (`:157-166`) | **absent** |
| Permissions for the above | `POST_NOTIFICATIONS`, `VIBRATE`, `RECEIVE_BOOT_COMPLETED`, `SCHEDULE_EXACT_ALARM`(≤32), `USE_EXACT_ALARM`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SPECIAL_USE` | **Identical list requested** (`OUR/AndroidManifest.xml:11-21`) with **no consuming component** (audit G3) |

---

## 10. `activities/AccessibilityRequestActivity.kt` — EQUIVALENT (F28)

**Original.** `ComponentActivity` (`REF/activities/AccessibilityRequestActivity.kt:20`),
Compose full-screen explanation ("Attention" + `accessibility_request_message`)
with one button that opens `Settings.ACTION_ACCESSIBILITY_SETTINGS`
(`:21-58`). It does **not** finish after opening settings, and has an empty
`onResume()` override (`:61-63`). Launched by the original Accessibility
Service on unintended disable (`REF/DechainerAccessibilityService.kt:621`),
as part of the F28 lockdown. Manifest: no `showOnLockScreen`
(`REF/AndroidManifest.xml:94-100`).

**Ours.** Native `Activity` in the same file as BlockActivity
(`OUR/accessibility/BlockActivity.kt:111-148`): title/body from
`strings.xml` (`a11y_request_title/body`, `res/values/strings.xml:19-21` —
the body additionally explains that controlled apps were suspended and
installs blocked), one button opening
`Settings.ACTION_ACCESSIBILITY_SETTINGS` with `FLAG_ACTIVITY_NEW_TASK`,
then `finish()` (`BlockActivity.kt:113-147`). Launched from the service's
`onUnbind` lockdown path after suspending controlled packages and adding
`DISALLOW_INSTALL_APPS` (`OUR/accessibility/DominanterAccessibilityService.kt:156-197`).
Manifest flags match the original (`OUR/AndroidManifest.xml:72-79`, no
`showOnLockScreen`).

**Differences (minor):** (a) ours finishes after opening Settings, the
original stays alive underneath; (b) ours is programmatic views vs Compose;
(c) ours is only reachable via the lockdown path — same as the original.
**Classification: EQUIVALENT.**

---

## 11. `activities/BlockedWordActivity.kt` — PARTIAL (F14/F15)

**Original.** `ComponentActivity` (`REF/activities/BlockedWordActivity.kt:38`)
with `FLAG_KEEP_SCREEN_ON` (`:40-44`). Compose screen (`:55-90`):
`NoAdultContent` icon, "blocked word" headline + description, then the
offending word **blurred by default (8 dp blur)** with an eye
(`RemoveRedEye`) toggle to reveal it, and a *Close* button →
`finishAfterTransition()`. Extras: `word` (force-unwrapped, `:47`).
Launched by the original service for both active and passive hits
(`REF/DechainerAccessibilityService.kt:772`). Manifest:
`showOnLockScreen=true` (`REF/AndroidManifest.xml:70-77`).

**Ours.** The `blockedWord` variant of the consolidated BlockActivity:
service `showBlockedWordActivity(word)` (`OUR/accessibility/DominanterAccessibilityService.kt:340-350`)
starts `BlockActivity` with `VARIANT_BLOCKED_WORD` + `EXTRA_WORD`, from both
the active path (`checkActiveBlocking`, `:322-338`) and the passive path
(`onAccessibilityEvent`, `:216-262`). Rendering
(`OUR/accessibility/BlockActivity.kt:44-45`): title `block_word_title`,
body `block_word_body` = *"The word “%1$s” is blocked in this app."*
(`strings.xml:11-12`). The only action is **Go to home screen**
(`goHome()`, `BlockActivity.kt:85-95`); Back is intercepted to the same
`goHome()` (`:80-83`).

**Differences:**
- **NEW — the word is shown in plain text.** The original deliberately
  blurs it behind an explicit reveal toggle; ours interpolates it
  unblurred into the body string (`strings.xml:12`). For a content-blocking
  product this defeats the purpose of the blur (the blocked term is
  displayed on the block screen itself).
- **NEW — no `FLAG_KEEP_SCREEN_ON`** (ours' BlockActivity never sets it;
  every original block activity sets it in `onCreate`).
- Dismissal semantics differ (shared with §16/§17): original *Close*
  finishes back toward the previous task; ours always goes HOME. Ours is
  stricter (no path back into the blocked app from the screen itself), but
  it is a behavioural difference, not a port.
- Presentation: `errorContainer` theming/iconography of the original is
  replaced by a plain programmatic layout (shared with all variants).

**Classification: PARTIAL.**

---

## 12. `activities/FocusReminderActivity.kt` — DEFERRED-DOCUMENTED (F25)

**Original.** `ComponentActivity` (`REF/activities/FocusReminderActivity.kt:41`),
197 lines. On create: cancels the reminder notification
(`FocusReminderNotifier.cancel`, `:46`), sets `setShowWhenLocked(true)` +
`setTurnScreenOn(true)` (API 27+, window flags below) and
`FLAG_KEEP_SCREEN_ON` (`:48-59`). Reads `EXTRA_SNOOZE_COUNT` (`:61`).
Compose screen (`:88-197`): hourglass icon, reminder title/description, and
three outcomes wired in `onCreate` (`:63-79`):

- **Start** → `FocusScheduleManager.cancelSnooze()` + `FocusMode.startFocus()` + finish;
- **Snooze** (shown while `snoozeCount < 2`) → `scheduleSnooze(count + 1)` (5 min) + finish;
- **"Cannot start now"** (shown at `snoozeCount >= 2`, replacing Snooze) →
  `cancelSnooze()` + finish.

So a scheduled reminder can be snoozed at most twice before the only
secondary action left is dismissal.

**Ours.** **ABSENT** — no activity, no schedule engine behind it (see
§4/§5); only the labelled v1.1 tile in the Dart focus screen
(`impulse_focus_screens.dart:623-627`).

**Classification: DEFERRED-DOCUMENTED (F25).**

---

## 13. `activities/LockScreen.kt` — PARTIAL (F21/F25/F29/F32) — deep dive

**Original.** Not an Activity: a `@Composable LockScreen(onAuthenticated)`
hosted by `MainActivity` (`REF/activities/LockScreen.kt:58`;
`DECHAINER_FEATURES.md` §"LockScreen.kt: Not an Activity"). 396 lines.
Design, in the file's own header comment (`:51-56`): authentication is
deliberately **not** triggered on open, because the panic button must stay
one tap away; challenges are *not* part of opening the app (they gate the
recovery session instead). Contents, top to bottom:

1. **Impulse (panic) button** — big red `BigActionButton` (104 dp,
   `Icons.Filled.Warning`, error colours), shown **only if Device Owner**,
   pre-auth (`:199-218`). Tapping calls
   `SecurityManager.startImpulseBlock(context)` immediately. While an
   impulse block is active the button is replaced by `ImpulseCountdown`
   (errorContainer card, `h:mm:ss` or `mm:ss`, up to the configurable
   6 h) (`:186-190`, `:358-396`).
2. **Focus session card** — `FocusSessionCard(status, gate, compact=true)`
   rendered **pre-auth, in both states** (impulse active or not)
   (`:176-184`, used at `:189,222`): the user can see and operate the
   focus session (start/resume/skip-break free; pause/end via the
   recovery gate passed in) without unlocking the app.
3. **"Access app"** — `SmallActionButton` → `launchAuthentication()`
   (`:97-125,158-167`): `BiometricManager.canAuthenticate(BIOMETRIC_STRONG)`
   → biometric prompt; else `DEVICE_CREDENTIAL` → credential prompt; else
   (nothing enrolled) → **proceeds without authentication** (explicit
   fallback, `:120-124`). Success → `onAuthenticated()`; errors surface
   as `authError` text under the buttons.
4. **"View usage limits"** — quiet button (Device Owner only) →
   full-screen `UsageLimitsOverview` with its own `BackHandler`
   (`:139-156,168-174`): the complete limits/windows overview, pre-auth,
   read-only.
5. **APK update** — quiet button (Device Owner only, and only when
   unknown-sources is restricted, `apkUpdatesAvailable`, `:69`) →
   `ApkUpdateIntroDialog` → system document picker for
   `application/vnd.android.package-archive` → `ApkUpdateDialog`
   (`:241-255`). **No authentication** — by design only APKs of
   already-installed apps pass the installer (F29).
6. **1-second polling loop** (`LaunchedEffect`, `:127-135`): every second
   refreshes `SecurityManager.getImpulseBlockRemainingTime()` (native,
   elapsed-realtime based) and calls `FocusMode.syncIfDue(context)` +
   re-reads the focus status — i.e. the lock screen itself helps drive
   focus phase transitions while it is on screen.

**Ours.** `lib/ui/lock_screen.dart` (231 lines), a Flutter `Scaffold`
shown by the app shell when `StartupState.locked`:

1. **Panic button** — `FilledButton.icon` with errorContainer colours
   (`lock_screen.dart:189-203`, `_panic()` at `:74-103`): starts the
   Dart impulse lock via `controller.startImpulseLock(...)` and, for the
   `timerAndSuspend` action, suspends the configured apps through the
   channel (`setAppSuspended(..., reason: 'IMPULSE_LOCK')`). Shown
   regardless of Device Owner state (the original hides it when not
   owner). While active, replaced by a `GradientCard` tile with the
   remaining time (`:176-188`) — text only, refreshed by a **30 s**
   ticker (`:37-40`), not 1 s, and the remaining time itself only
   advances via `AppController`'s 30 s ticker while the process is alive
   (`lib/app_controller.dart:72-94`; `ImpulseLock.tick` in
   `lib/domain/recovery.dart:249-253` decrements a stored duration by
   measured deltas — fail-safe direction, never shorter, but frozen
   while dead; the original's `SecurityManager` accounting is native
   elapsed-realtime and survives process death).
2. **Usage overview** — top-5 packages by today's usage, from
   `channel.getUsageToday()` + labels from `listInstalledApps()`
   (`lock_screen.dart:52-72,205-220`). Read-only and pre-auth like the
   original, but **NEW:** it is a usage *ranking*, not the original's
   limits overview — configured limits and allowed windows (the thing a
   user at the lock screen wants to check: "when can I use X again?")
   are not shown anywhere on ours' lock screen.
3. **"Access app"** — `FilledButton.icon` (fingerprint) → `_access()`
   (`lock_screen.dart:105-164,221-227`): `local_auth` 3.0.1;
   `isDeviceSupported() == false` → explanatory dialog ("nothing to
   authenticate against… entry is allowed — exactly as the original")
   then `controller.unlock()`; `authenticate(localizedReason: 'Unlock
   Dominanter', biometricOnly: false, persistAcrossBackgrounding: true)`;
   `PlatformException` codes `NotEnrolled/NotAvailable/PasscodeNotSet`
   → same documented fallback unlock. This matches the original's
   three-way logic (strong biometric → device credential → open
   fallback) at the level `local_auth` exposes it.
   **Difference:** the original distinguishes BIOMETRIC_STRONG from
   DEVICE_CREDENTIAL explicitly and reports prompt errors inline;
   `local_auth` collapses the first two, and ours additionally unlocks
   silently (no dialog) on the `PlatformException` fallback path.
4. **Focus card — **NEW: ABSENT.**** Ours' lock screen has no focus
   section at all: no status, no start/resume/skip, no gated pause/end.
   A user in a focus session who lands on the lock screen cannot see or
   operate it without fully authenticating and navigating to the Focus
   tab. The compliance audit's F25 row covers the focus *engine*; the
   lock-screen card is a distinct pre-auth surface and is not mentioned
   in the audit.
5. **APK update — ABSENT**, deliberately (F29, §1).
6. **No focus driving:** ours' lock screen never calls anything like
   `syncIfDue` — there is no native focus state to sync (§18).

**Authentication summary.** Both gates are *app-entry* gates only —
neither locks the device, and in both, loosening actions remain behind
the recovery session, not this gate. The material differences are:
panic-button visibility (owner-only vs always), countdown fidelity
(native elapsed-realtime, 1 s refresh vs Dart tick-decrement, 30 s
refresh, frozen while the process is dead), the missing focus card, and
the reduced usage overview.

**Classification: PARTIAL** (core F32 gate + F21 panic equivalent in
shape; F29 excluded-documented; focus card and limits overview missing —
**NEW**).

---

## 14. `activities/NsfwContentBlockedActivity.kt` — DEFERRED-DOCUMENTED (F16)

**Original.** `ComponentActivity` (`REF/activities/NsfwContentBlockedActivity.kt:29`)
with `FLAG_KEEP_SCREEN_ON`. Reads `EXTRA_SUSPENDED_MINUTES` (`:24-27,40`).
Compose screen (`:53-80`): `NoAdultContent` icon on `errorContainer`,
"NSFW content blocked" headline, and body that either states the
suspension duration (`nsfw_content_blocked_suspended`, when
`suspendedMinutes > 0`) or the plain description; *Close* →
`finishAfterTransition()`. Launched by the service's
`executeNsfwBlocking()` after suspend/unsuspend or escalation
(`REF/DechainerAccessibilityService.kt:1003-1073`, `showNsfwBlockedActivity`
call sites at `:1064,1071` region — grep: `putExtra(EXTRA_SUSPENDED_MINUTES, …)` at `:1073`).

**Ours.** **ABSENT** — no NSFW variant in BlockActivity (variants are
`timeUp / outsideWindow / blockedWord / reopening / generic`,
`OUR/accessibility/BlockActivity.kt:102-106`), no screen, no caller.
`BlockActivity.VARIANT_GENERIC` is **not** a counterpart: nothing passes
NSFW extras and no classification ever occurs (§19).

**Classification: DEFERRED-DOCUMENTED (F16).**

---

## 15. `activities/OutsideTimeWindowActivity.kt` — EQUIVALENT (F10)

**Original.** `ComponentActivity` (`REF/activities/OutsideTimeWindowActivity.kt:30`),
`FLAG_KEEP_SCREEN_ON`. Extras: `appName`, `windows` (formatted strings)
(`:36-40`). Compose screen (`:48-81`): `Schedule` icon on
`errorContainer`, title, "…can only be used during" description naming
the app, each allowed window listed in bold primary text, *Close* →
`finishAfterTransition()`. Launched by the original service's
`executeBlocking(outsideWindow = true)` (`REF/DechainerAccessibilityService.kt:1496-1513`).

**Ours.** `VARIANT_OUTSIDE_WINDOW` (`OUR/accessibility/BlockActivity.kt:39-43`):
title `block_outside_window_title`, body `block_outside_window_body` =
*"%1$s can only be used during:\n%2$s"* with the windows joined by
newlines (`strings.xml:9-10`). The service populates exactly the same
extras (`EXTRA_APP_NAME`, `EXTRA_WINDOWS` as formatted strings) in
`executeBlocking(outsideWindow = true)` (`OUR/accessibility/DominanterAccessibilityService.kt:436-474`).
Differences are the shared BlockActivity ones (§11): no
`FLAG_KEEP_SCREEN_ON`, plain layout instead of themed Compose, and
*Go to home screen* instead of *Close*→finish (stricter).
**Classification: EQUIVALENT.**

---

## 16. `activities/ReopeningLimitActivity.kt` — DEFERRED-DOCUMENTED (F11) + dead variant (G1)

**Original.** `ComponentActivity` (`REF/activities/ReopeningLimitActivity.kt:35`),
`FLAG_KEEP_SCREEN_ON`. Extras: `appName`, `limit` = cooldown seconds
(`:41-45`). Compose screen (`:53-90`): `FrontHand` icon on
`secondaryContainer`, "app reopening" headline, and a **live countdown
description**: a `LaunchedEffect` rewrites the text every second
(`{seconds}` counting down from `limit`) and **auto-closes the activity
when the countdown reaches 1** (`:60-70`); a manual *Close* button also
exists. Enforcement lives in the original service: `reopenPrefs` +
`lastClosedTimes` on `elapsedRealtime`, `getRemainingSecondsToReopen()`
(`REF/DechainerAccessibilityService.kt:1534-1544`), checked in
`startTracking` — reopening too soon calls
`executeBlocking(reopening = true, remainingSeconds = …)` which launches
this activity (`:1347-1348`, `:1496-1511`).

**Ours.** The screen *shell* exists — `VARIANT_REOPENING` renders
`block_reopening_title/body` ("…can be reopened in %2$d seconds.",
`OUR/accessibility/BlockActivity.kt:47-48`, `strings.xml:13-14`) — but:

- **Nothing ever launches it.** The service never reads `reopenSeconds`
  (storage exists: `SettingsStore.reopenSeconds()` at
  `OUR/.../data/SettingsStore.kt:292`, written via channel
  `setTimeLimit(reopenSeconds)` in `PrivilegedChannelHandler.kt`), and
  `executeBlocking` has no reopening branch
  (`OUR/accessibility/DominanterAccessibilityService.kt:436-474`). This is
  audit gap **G1**.
- **NEW (behavioural, beyond G1):** even if launched, ours' variant is a
  static text snapshot — no per-second countdown and no auto-close —
  where the original's screen *is* the cooldown timer.

**Classification: DEFERRED-DOCUMENTED (F11)** for enforcement;
the unlaunched variant is dead code per G1.

---

## 17. `activities/TimeUpActivity.kt` — EQUIVALENT (F9)

**Original.** `ComponentActivity` (`REF/activities/TimeUpActivity.kt:29`),
`FLAG_KEEP_SCREEN_ON`. Extras: `appName`, `limit` (minutes) (`:35-39`).
Compose screen (`:47-70`): `TimerOff` icon on `errorContainer`,
"app limit reached" headline, body from `time_limit_reached(limit,
appName)`, *Close* → `finishAfterTransition()`. Launched by
`executeBlocking()` (`REF/DechainerAccessibilityService.kt:1496-1513`),
which substitutes the **group's** name/limit when the group limit was
the one reached (`:1485-1494`).

**Ours.** `VARIANT_TIME_UP` (`OUR/accessibility/BlockActivity.kt:37-38`):
title `block_time_up_title`, body `block_time_up_body` = *"%1$s has
reached its limit of %2$d minutes for today."* (`strings.xml:7-8`).
Ours' `executeBlocking()` reproduces the group-substitution logic
(`OUR/accessibility/DominanterAccessibilityService.kt:436-474`: if the
group limit was reached and the app limit was not, display name/limit
become the group's). Same shared diffs as §15 (no keep-screen-on, plain
layout, Go-home instead of Close).
**Classification: EQUIVALENT.**

---

## 18. Deep dive — `FocusService` + the original focus engine vs our Dart-timer approach (F25)

### 18.1 How the original works (all native, all persisted)

State lives in `FocusMode` (`REF/data/FocusMode.kt`, object, 546 lines),
in `focus_prefs` SharedPreferences. A session is **data, not a process**:

- Phase machine: `FOCUS → SHORT_BREAK / LONG_BREAK → WAITING` (or back to
  `FOCUS` when auto-start is on); `WAITING` is a real phase — after a
  break without auto-start, nothing is suspended until the user starts
  the next focus (`FocusMode.kt:47-54`, `FocusCycle.next` at `:530-544`).
- Persisted keys (`FocusMode.kt:77-86`): `phase`, `phase_start_rtc`,
  `phase_start_elapsed`, `phase_duration`, `phase_boot_count`,
  `paused_remaining`, `pause_releases`, `completed_focus`,
  `active_suspension`, `active_restrictions` — the last two record what
  was *actually* suspended/restricted, so release acts on reality even
  if the config changed mid-session (`getActiveSuspension`, and
  `stop()`/`sync()` releasing from those keys).
- **Dual-clock deadline** (`FocusMode.kt:340-367`): on phase start it
  stores both wall-clock (`System.currentTimeMillis()`) and
  `elapsedRealtime()` starts plus the `Settings.Global.BOOT_COUNT`.
  `remainingMillis()`: same boot → elapsed-realtime arithmetic (clock
  changes cannot shorten a phase); different boot → recompute from the
  wall clock and re-anchor elapsed/boot-count. The file header states
  this contract verbatim (`FocusMode.kt:23-27`).
- **Exact alarm per phase** (`FocusMode.kt:482-505`): `scheduleAlarm()`
  arms `ELAPSED_REALTIME_WAKEUP` (`setExactAndAllowWhileIdle` when
  permitted) to `FocusReceiver.ACTION_PHASE_END`; `applyState()` —
  called on every transition — re-applies suspension + restrictions,
  re-arms the alarm, and re-posts the notification
  (`FocusMode.kt:281-320` region: `sync()`, `applyState()`).
- **Pause has two flavours** (`FocusMode.kt:47` region, `pause(context,
  releaseApps)`): pausing stores `paused_remaining` and a
  `pause_releases` flag — pause-with-release (apps come back) is a
  loosening gated behind the recovery code; pause-without-release keeps
  apps suspended. `resume()` re-anchors both clocks from the stored
  remainder.
- **Notification-permission self-grant:** `startFocus()` calls
  `grantNotificationPermission()` (`FocusMode.kt:508+`), which uses
  Device Owner `setPermissionGrantState()` juggling so the FGS
  notification can post on API 33+.
- `FocusService` (§6) only keeps the progress bar moving and double-checks
  `syncIfDue()`; it is **not** the timer. The timer is prefs + alarm +
  receivers.

### 18.2 How ours works (Dart-only, in-memory)

- The phase model is a faithful *arithmetic* port: `lib/domain/focus.dart`
  `FocusSession` (178 lines) mirrors the defaults (25/5/15, 4 cycles,
  `:13-75`), derives remaining time from a stored `phaseStartedAt`
  instant (`remainingAt`, `:105-112`), and advances on
  `isPhaseCompleteAt` (`:112`). Pause stores `pausedRemaining` (`:154-161`).
- But the session object lives **only** in a widget `State` field:
  `_FocusModeScreenState._session` (`lib/ui/impulse_focus_screens.dart:349`),
  created fresh as **idle** on every screen load
  (`_load()`, `:366-380`: `_session = FocusSession(config: config)`).
  Only the *config* is persisted (`lib/data/config_store.dart:173-180`,
  `getFocusConfig/setFocusConfig`). **NEW:** the audit says the countdown
  "runs only while the app process is alive"; the stronger fact is that
  the session is not persisted *anywhere* — leaving and re-entering the
  Focus screen, or any process restart, discards a running session
  outright (phase, completed cycles, paused remainder all reset to idle).
- Phase transitions happen only in `_onTick()` — a 1-second
  `Timer.periodic` owned by the screen's State (`impulse_focus_screens.dart:359,436-445`) —
  which calls `session.advance()` and then `_syncEffects()` (`:402-434`):
  suspend/unsuspend via `channel.setAppSuspended(..., reason: 'FOCUS_MODE')`
  and apply/clear user restrictions, from the **UI process**.
- Effects bookkeeping is a single boolean `_effectsApplied` in the same
  State (`:355,402-434`) — there is no equivalent of the original's
  persisted `active_suspension`/`active_restrictions`, so if the process
  dies mid-focus-phase, **nothing knows apps were suspended by focus**
  and nothing will release (or re-apply) them on next launch; release
  depends on the user re-opening the Focus screen and ending a session
  that the app believes is idle. (Impulse-lock suspensions have the same
  UI-process property — audit F21 row.)
- **NEW — phase-model divergences inside the Dart port itself:**
  (a) there is **no WAITING phase** — `FocusPhase` is
  `{idle, focus, breakTime, longBreak, paused, done}` (`focus.dart:11`);
  after a break, `advance()` goes straight back to `focus`
  (`nextPhase`, `:126-140`), i.e. auto-start is hard-wired on, whereas
  the original defaults to WAITING unless auto-start is configured.
  (b) `resume()` **always re-enters the focus phase** with the paused
  remainder (`focus.dart:163-176`, with an in-code comment admitting the
  paused-from phase is not retained) — pausing during a break and
  resuming silently converts the break remainder into focus time; the
  original resumes the same phase.
  (c) There is no pause-with/without-release distinction: ours' Pause
  button is recovery-gated but does **not** change suspension state at
  all (the gated closure only swaps the session object,
  `impulse_focus_screens.dart:545-555` region) — suspensions stay applied
  while "paused", and `_syncEffects` is not called, so the original's
  gated *release* flavour has no counterpart.
  (d) `FocusConfig` has no sound/vibration/auto-start settings at all
  (`focus.dart:13-75`) — the original's are first-class prefs
  (`FocusMode.kt:70-72`).

### 18.3 Survival matrix

| Event | Original | Ours |
|---|---|---|
| App process killed mid-focus | Session survives (prefs); alarm still fires `ACTION_PHASE_END`; `sync()` advances phase, re-applies/releases suspension + restrictions, re-posts notification, plays sound/vibration | **Session lost.** `_session` was in-memory; suspensions applied by the dead UI process are orphaned (no record, no release, no re-apply) |
| Device reboot mid-focus | `FocusSystemReceiver` on `BOOT_COMPLETED` → `FocusMode.sync()` + schedule reschedule; deadline recomputed from wall clock via boot-count check (`FocusMode.kt:347-367`); alarm re-armed by `applyState()` | **Nothing.** No boot receiver; focus config persists but no session existed persistently; orphaned suspensions persist until manually changed |
| App updated (`MY_PACKAGE_REPLACED`) | Same resync path as reboot | Nothing |
| Clock / timezone changed | Elapsed-realtime deadline is immune within a boot; `FocusSystemReceiver` resyncs on `TIME_SET/TIMEZONE_CHANGED` | Dart `DateTime`-based `remainingAt` (`focus.dart:105-112`) shifts with the wall clock — moving the clock forward can end a phase early while the screen is alive. (**NEW:** the focus model does not inherit the impulse lock's tick-decrement protection, `recovery.dart:227-253`) |
| Screen off / app backgrounded | FGS + alarm continue; notification keeps counting (chronometer) | 1 s ticker is a Dart `Timer` in a widget State — stops when the screen State is disposed; while merely backgrounded it is at the mercy of the Flutter process; no notification exists |
| User swipes away the status notification | Delete intent → `ACTION_REPOST` re-posts it | No notification to swipe |
| Phase ends while user is elsewhere | Alarm → `sync()` → next phase + alert sound/vibration + suspension swap, all without opening the app | Phase ends only when the Focus screen is open and its ticker fires |

**Classification: PARTIAL at the feature level / DEFERRED-DOCUMENTED for
the native engine (F25).** The Dart model is an honest, disclosed
approximation (in-UI note, `impulse_focus_screens.dart` Focus screen note;
audit F25 row), but the survival properties above are the original's
core anti-bypass guarantee for focus mode, and none of them hold in ours.

---

## 19. `utils/NsfwContentDetector.kt` + the `.tflite` asset — DEFERRED-DOCUMENTED (F16/F17)

**Original detector.** `REF/utils/NsfwContentDetector.kt` (94 lines):
wraps a MobileNetV2-based classifier via LiteRT `Interpreter`
(`org.tensorflow.lite.Interpreter`, 2 threads).

- Model: `MODEL_PATH = "models/nsfw_model.tflite"` (`:22`), memory-mapped
  from assets (`loadModelFile`, `:41-49`).
- I/O contract (`:57-82`): input 224×224 RGB float32 normalised to [0,1]
  (`INPUT_SIZE = 224`, `:23`); output softmax over 5 labels in Keras
  alphabetical order — `LABELS = [drawings, hentai, neutral, porn, sexy]`
  (`:25`), `PORN_INDEX` exposed. Buffers are pre-allocated and reused;
  class is explicitly not thread-safe — callers must serialise.
- `unsafeScore(scores, categories)` (`:84-92`): sums the softmax scores
  of the configured category set — the value compared against the user's
  threshold.
- `close()` releases the interpreter (`:92-94` region).

**Original model asset — verified on disk:**
`reference/dechainer-zip/dechainer-1.12.0/app/src/main/assets/models/nsfw_model.tflite`
exists, **17,355,548 bytes** (17 MiB, `stat`-verified during this audit).

**Original pipeline around it** (for completeness — the detector is inert
without it): the Accessibility Service warms the detector up when a
target package comes to the foreground (`REF/DechainerAccessibilityService.kt:664-665,783-797`),
throttles scans (`maybeScanForNsfwContent`, `:799-890`: scan-in-flight
flag + interval), first finds candidate media regions by walking the
node tree (`findNsfwMediaRegions`, `:892-975+`: class-name keywords,
description/text vocabulary, Reddit post-card patterns, geometric
fallback), takes an Accessibility screenshot (`takeScreenshot`,
`:823-887`), crops regions, classifies each on a dedicated
single-thread dispatcher, and on `unsafeScore > threshold` calls
`executeNsfwBlocking(pkg)` (`:1003-1072`): suspend-then-immediately-
unsuspend (force-close) by default, or — with escalation on (F17) —
`VisualBlockingSuspensionTracker.registerBlock` counting blocks in a
sliding window (defaults 5 blocks / 15 min ⇒ 30 min suspension, per
`DECHAINER_FEATURES.md` F17), persisted suspension deadlines with
`restoreNsfwSuspensions()` on service reconnect (`:98-111` region of the
excerpt / grep: tracker created at `:499`, restore called at `:526`),
then shows `NsfwContentBlockedActivity` (§14).

**Ours — total absence, verified:**
- No `.tflite` file anywhere under `project/` (find: 0 hits); no
  `android/app/src/main/assets/` directory; no Flutter `assets:` section
  in `pubspec.yaml`.
- No TFLite/LiteRT dependency: `android/app/build.gradle.kts` dependencies
  are only Shizuku API/provider and HiddenApiBypass (grep
  `implementation` → 3 lines); `pubspec.yaml` has no ML package.
- No detector, scan, screenshot, region-finding, or tracker code:
  `DominanterAccessibilityService.kt` header lists *"the NSFW TFLite
  pipeline (F16/F17, v1.1)"* among deliberately-absent v1 items
  (`:44-52`); grep for `nsfw|tflite` over Dart/Kotlin/Gradle/YAML returns
  only that header comment and the never-produced
  `SuspensionReason.VISUAL_BLOCKING` consideration in the audit.
- No placeholder screen (§14).

**Classification: DEFERRED-DOCUMENTED (F16/F17)** — audit rows F16/F17,
confirmed at the asset, dependency, code, and service-header levels.

---

## 20. Channel-handler surface for this scope

`PrivilegedChannelHandler.kt` (496 lines) contains **no** method touching
focus sessions, notifications, warnings, schedules, or reminders (grep for
`focus|Focus|notification|Notification`: 0 hits). Everything focus-related
in ours flows through generic primitives from Dart:

- `setAppSuspended` / `applyUserRestriction` / `clearUserRestriction` —
  used by `impulse_focus_screens.dart:_syncEffects()` (`:402-434`);
- `getSetting`/`setSetting` generic stores — used to persist the focus
  *config*, the usage-warning *config*, and the unread
  `focus_schedules_prefs` (§5);
- `getUsageToday` — used by the lock screen overview (§13).

Consequence: there is no native focus state for the channel to expose,
which is why no other surface (lock screen, notification, receiver) can
observe or drive a session. In the original, `FocusMode` *is* the shared
native state and the UI, notification, alarm, and receivers are all views
over it.

---

## 21. **NEW** findings index (not in `COMPLIANCE_AUDIT.md`)

1. **Focus session is not persisted at all in ours** — only its config
   is; the session is a widget-State field recreated as idle on every
   Focus-screen load (`impulse_focus_screens.dart:349,366-380`;
   `config_store.dart:173-180`). Stronger than the audit's "countdown
   runs while the app is alive" (§18.2).
2. **Lock screen has no focus card** — the original's pre-auth
   `FocusSessionCard` (start/resume/skip free, pause/end gated) has no
   counterpart in `lib/ui/lock_screen.dart` (§13).
3. **Lock-screen overview is reduced** — top-5 usage ranking instead of
   the original's full limits/windows `UsageLimitsOverview` (§13).
4. **Blocked word is displayed unblurred** in ours' block screen body
   (`strings.xml:12`); the original blurs it behind a reveal toggle
   (§11).
5. **Dart focus-model divergences:** no WAITING phase (auto-start
   hard-wired), `resume()` always re-enters FOCUS regardless of the
   paused-from phase, no pause-releases distinction, no
   sound/vibration/auto-start config (`lib/domain/focus.dart:11,126-176`)
   (§18.2).
6. **Focus remaining time is wall-clock based** (`focus.dart:105-112`) and
   therefore clock-change-sensitive, unlike both the original's
   dual-clock deadline and ours' own impulse-lock tick-decrement model
   (§18.3).
7. **Phase-end sound/vibration alerts and notification actions**
   (start/resume/skip/end/repost-on-dismiss) are lost behaviours not
   itemised in the audit's F25 row (§2).
8. **`focus_schedules_prefs` is writable-but-unread dead storage** in
   ours — the G1 dead-plumbing pattern applied to F25 schedules (§5).
9. **Shared BlockActivity diffs not itemised in the audit:** no
   `FLAG_KEEP_SCREEN_ON` on any block screen; *Close→finish* replaced by
   *Go to home screen* (stricter, but different); the `generic` variant
   has no original counterpart (§11/§15/§17).
10. **Original `FocusMode.grantNotificationPermission()`** (DPM
    permission-grant juggling so the focus FGS notification can post)
    has no counterpart and is not mentioned in the audit (§18.1).
