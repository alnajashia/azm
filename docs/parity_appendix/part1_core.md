# Parity Audit — Part 1 of 5: Core Native Layer + Build Config

**Method:** function-by-function comparison, read in full on both sides.
**Reference (source of truth):** `~/workspace/dominater-rebuild/reference/dechainer-zip/dechainer-1.12.0/` (byte-identical to commit `29822c0`).
**Ours:** `~/workspace/dominater-rebuild/project/`.
**Path legend:** `REF/…` = `reference/dechainer-zip/dechainer-1.12.0/app/src/main/java/io/github/warleysr/dechainer/…`; `OURS/…` = `project/android/app/src/main/kotlin/io/github/alnajashia/dominanter/…`; `DART/…` = `project/lib/…`.
**Classifications:** EQUIVALENT / PARTIAL / MISSING / DEFERRED-DOCUMENTED (F-item) / EXCLUDED-DOCUMENTED (F20/F29/F34).
**NEW** = finding not present in `project/docs/COMPLIANCE_AUDIT.md` (incl. its gaps G1–G4). Unmarked findings are consistent with that audit.

---

## 1. `DechainerAccessibilityService.kt` (REF, 1,546 lines) → `accessibility/DominanterAccessibilityService.kt` (OURS, 508 lines)

Header of ours declares the v1 scope honestly (OURS `accessibility/DominanterAccessibilityService.kt:22-54`).

### 1.1 Lifecycle

| Original unit (REF) | Ours (OURS) | Class | Notes |
|---|---|---|---|
| `onServiceConnected()` `:479-572` — init 14 prefs stores, register prefs listener on 10 stores, `updateForbiddenPatterns/VisualBlocking/UsageWarningSettings`, colour-filter observer + sync, un-suspend controlled pkgs, `restoreNsfwSuspensions()`, `syncImpulseSuspension()`, `FocusMode.sync()`, clear `DISALLOW_INSTALL_APPS`, `ApkUpdateInstaller.restoreUnknownSourcesRestrictionsIfIdle()`, register package + screen receivers, DEBUG hatch receiver | `onServiceConnected()` `DominanterAccessibilityService.kt:119-154` — `SettingsStore.init`, `resetUsageIfNewDay`, listener on 7 watched stores, `updateForbiddenPatterns`, screen receiver, un-suspend controlled, clear `DISALLOW_INSTALL_APPS` | PARTIAL | Missing-by-design pieces: NSFW restore (F16/F17 DEFERRED), impulse sync (F21 — see §1.6), Focus sync (F25 partial), colour filters (F26 DEFERRED), APK-installer restore (F29 EXCLUDED), DEBUG receiver (F34 EXCLUDED), package receiver (F6/F19/F20 — §1.2). Core restore semantics (un-suspend + clear install restriction) EQUIVALENT. Ours wraps the `clearUserRestriction` in try/catch (`:146-150`); original calls it unguarded (`REF:530-534`) — ours is more defensive, behaviour same when owner. |
| `onUnbind()` `:574-627` — unregister receivers/listeners/observer, release colour filters + night-light overlay, drop NSFW/impulse release timers, `stopTrackingAndSave()`, close TFLite detector on its dispatcher, then if `!disablingService`: lockdown (suspend controlled + `DISALLOW_INSTALL_APPS` + launch `AccessibilityRequestActivity`) | `onUnbind()` `:156-197` — unregister (each `runCatching`), `stopTrackingAndSave()`, lockdown gated on `SettingsStore.consumeIntentionalAccessibilityDisable()` (the `prepareServiceDisable()` equivalent, persisted + 1-shot, `data/SettingsStore.kt:432-450`), plus emits an `accessibilityStatus` event (`:186-189`) | PARTIAL (core EQUIVALENT) | Lockdown (F28) logic matches: same suspend set source, same restriction, same request activity. Missing: colour/NSFW/impulse timer teardown (features deferred). Difference: original checks the in-memory `disablingService` flag only (`REF:400-460`); ours also accepts a persisted timestamped arm within a window (`SettingsStore.kt:445-449`) — strictly more forgiving after process death. |
| `onInterrupt()` `:629-633` — removes block + windowEnd + warnTick callbacks | `onInterrupt()` `:199-202` — removes block + windowEnd callbacks | EQUIVALENT | warnTick absent because F12 deferred. |
| Companion: `isRunning`/`disablingService`/`checkingRating` Compose state, `prepareServiceDisable()`, `accessedActivities` + `addLog()` cap 100 (`:400-477`) | Companion `:96-117`: `ActivityLog`, `accessedActivities` (plain `MutableList`, synchronized), `addLog()` same dedupe/move-to-front/cap-100; running state moved to `DominanterState.accessibilityServiceRunning` (`data/SettingsStore.kt:466-478`) | EQUIVALENT (log itself: see G1) | `checkingRating` absent (F20 EXCLUDED). Log has no reader — already documented as gap **G1** in COMPLIANCE_AUDIT §4. |

### 1.2 Broadcast receivers inside the service

| Original unit (REF) | Ours | Class | Notes |
|---|---|---|---|
| `packageReceiver` `:158-223` — on `ACTION_PACKAGE_ADDED`: `AppRepository.reapplyHiddenIfNeeded`, browser check → apply restrictions or suspend `UNSUPPORTED_BROWSER`, torrent check → suspend `TORRENT_APP`, async Play-Store rating fetch → suspend `UNSUPPORTED_BROWSER`/`RATED_18_PLUS`, cache rating | ABSENT in service; `DominanterApplication` package receiver only emits an event (§2) | DEFERRED/EXCLUDED-DOCUMENTED | Browser/torrent watchers = F6/F19 DEFERRED v1.1; rating fetch = F20 EXCLUDED. **NEW detail:** `reapplyHiddenIfNeeded` (`REF data/AppRepository.kt:147-165`) has **no counterpart anywhere in ours** (grep: 0 hits in Kotlin+Dart): an app that was hidden and is then updated/reinstalled is **not** re-hidden by any code path in ours. The original re-applies `setApplicationHidden(true)` (with the same false→true retry) from this receiver. This sub-behaviour is not named in COMPLIANCE_AUDIT (F6 row covers only suspension-on-install). **NEW** |
| `screenReceiver` `:227-249` — SCREEN_OFF: stash `lastForegroundPackage`, `stopTrackingAndSave(screenOff=true)`, clear current; **SCREEN_ON: `syncColorFilters()` + resume tracking the stashed package** (reset `sessionStartTime`, `checkDateReset()`, `startTracking`); TIME/TZ_CHANGED → colour sync | `screenReceiver` `DominanterAccessibilityService.kt:87-95` — SCREEN_OFF → `stopTrackingAndSave(screenOff=true)`; TIME/TZ_CHANGED → `checkDateReset()`. SCREEN_ON is **registered** in the filter (`:135`) but has **no branch** in `onReceive` | PARTIAL — **NEW** | Ours never resumes tracking on screen-on. Recovery depends on the launcher/app emitting a fresh `TYPE_WINDOW_STATE_CHANGED` after unlock; if it doesn't, the foreground app's session restarts only at the next window change, and time used between unlock and that event is unaccounted (fail-open direction). Original also differs on TIME_CHANGED: it does **not** call `checkDateReset()` there (only colour sync, `:247`); ours calls `checkDateReset()` — ours is stricter, harmless. Colour sync = F26 DEFERRED. |
| `colorFilterObserver` `:251-255` + `syncColorFilters()` `:1139-1165` + `onColorFilterForegroundChanged()` `:1167-1182` + `NightLightOverlay` | ABSENT | DEFERRED-DOCUMENTED | F26, per COMPLIANCE_AUDIT §2/F26. |
| DEBUG_INSTALL receiver (registered `:551-571`, `BuildConfig.DEBUG` only): sets `disablingService`, auto-session pref, lifts unknown-sources restriction, stops FocusService, `disableSelf()` | ABSENT | EXCLUDED-DOCUMENTED | F34, per COMPLIANCE_AUDIT §2/F34. |

### 1.3 Prefs-change listener — **NEW behavioural gap**

| Original (REF) | Ours (OURS) | Class |
|---|---|---|
| `prefsListener` `:257-306` dispatches **per store**: limit/weekly-limit change for the *current* package → remove block callback + `startTracking(current)`; window prefs → remove both callbacks + `startTracking`; groups prefs → same; blocked-words → `updateForbiddenPatterns()`; visual/usage-warning/security prefs → respective syncs (incl. `impulse_block_active` → `syncImpulseSuspension()`) | `prefsListener` `DominanterAccessibilityService.kt:82-84`: **every** change in any of the 7 watched stores calls only `updateForbiddenPatterns()`. Limit/window/group stores are watched (`:74-80` `watchedPrefs`) but their changes trigger **no re-tracking** | **PARTIAL — NEW** |

Consequence: editing the current foreground app's time limit, window, or its group's limit/windows **while that app is in front** does not re-arm `blockRunnable`/`windowEndRunnable` in ours; the old deadline (or absence of one) stays in force until the next package switch. In the original the new limit applies immediately. COMPLIANCE_AUDIT F9/F10/F13 rows do not mention this. (Word-pattern refresh on any change is a superset of the original's words-only refresh — harmless.)

### 1.4 Event handling (`onAccessibilityEvent`)

| Original unit (REF) | Ours (OURS) | Class | Notes |
|---|---|---|---|
| `onAccessibilityEvent` `:635-747`: own-package early return; TEXT_CHANGED/CONTENT_CHANGED → `checkActiveBlocking()`; WINDOW_STATE_CHANGED → skip systemui/IME, package-change → `stopTrackingAndSave`, `pendingLeaves.remove`, reset session, `checkDateReset`, `startTracking`, NSFW warm-up; home-screen check flushes `pendingLeaves`→`lastClosedTimes`; Activity class → `addLog` + blocked-activity BACK | `:216-262`: same skeleton minus NSFW warm-up, minus pending-leaves/home flush | PARTIAL | Core dispatch EQUIVALENT. Missing: reopening bookkeeping (F11 DEFERRED) and its `HomeScreenDetector` dependency (§8). Blocked-activity branch reads `SettingsStore.blockedActivities()` on every event (`:255`) vs original constructing `getSharedPreferences` per event (`REF:677-683`) — same semantics, ours cheaper. Enforcement is dead in practice (no setter) — documented G1. |
| Passive branch (`else if` CONTENT_CHANGED) `:691-746`: NSFW scan, one-shot rating fetch per package (`checkingRating` guard), then passive word match → BACK + `showBlockedActivity` | `:242-261`: passive word match → BACK + `showBlockedWordActivity` only | PARTIAL | Word path EQUIVALENT; NSFW = F16 DEFERRED; rating fetch = F20 EXCLUDED. |
| `buildScreenText(event)` `:749-767`: `event.text` + walk of **`event.source`** subtree, no length cap, trimmed | `buildScreenText` `:264-286`: `event.text` + walk of **`rootInActiveWindow`**, capped at `MAX_SCREEN_TEXT = 64_000` (`:97`) | PARTIAL — **NEW** | Different node source: for events whose source window is not the active root (popups, dialogs, split-screen), ours scans the active window's text instead of the event's window. The 64k cap is an ours-only safeguard (original unbounded). Not mentioned in COMPLIANCE_AUDIT F15 row. |
| `showBlockedActivity(word)` `:768-787`: launches `BlockedWordActivity` via `serviceScope.launch { withContext(Main) }` | `showBlockedWordActivity` `:340-350`: launches `accessibility/BlockActivity.kt` `VARIANT_BLOCKED_WORD` directly | EQUIVALENT | Same singleInstance/noHistory presentation contract via manifest (§10). |
| `checkActiveBlocking()` `:1249-1281` + `extractEditableFieldsTextAndFocus()` `:1237-1247` — check field text only when typing *ends* | `:322-338` + `:308-320` — line-for-line same logic | EQUIVALENT | F14 nuance preserved (COMPLIANCE_AUDIT F14 concurs). |
| `checkForbiddenWord` `:1227-1235` + pattern build `:350-377`: regex `(?<![\p{L}\p{N}_])word(?![\p{L}\p{N}_])`, IGNORE_CASE (Unicode letter/digit lookarounds) | `checkForbiddenWord` `:299-304` + `wordPattern` `:296-297`: regex `\b` + escaped word + `\b`, IGNORE_CASE | PARTIAL — **NEW** | `\b` is ASCII-oriented: for words bounded by non-ASCII letters/digits (e.g. Portuguese text, F33's locale) `\b` can match **inside** a longer word where the original's `\p{L}` lookaround would not (false positives), and behaves differently for words starting/ending with non-word characters. Same divergence applies to passive patterns (built by the same `wordPattern`). Not mentioned in COMPLIANCE_AUDIT F14/F15 rows. |

### 1.5 Usage accounting, limits, windows (F9/F10/F13)

| Original unit (REF) | Ours (OURS) | Class | Notes |
|---|---|---|---|
| `TrackingConfig` + `trackingConfigFor(pkg)` `:1283-1297`: group from `AppGroupRepository`, app windows/limit resolved to *today* (daily/weekly), windows = group ∩ app | `trackingConfigFor` `:360-375` via `SettingsStore.groupForPackage/timeWindowsFor/timeLimitFor` + `TimeWindow.intersect` (`data/TimeModels.kt:50-64`) | EQUIVALENT | Same "group adds a cap, doesn't replace" semantics. |
| `startTracking(pkg)` `:1299-1348`: window check → block outside / post `windowEndRunnable` at window end; compute app+group remaining from `usagePrefs`/`groupUsagePrefs`; block if reached; post `blockRunnable` at min remaining; `scheduleUsageWarning(...)`; reopening check → `executeBlocking(reopening=true)` | `startTracking` `:377-417`: identical window + remaining + block-runnable flow | PARTIAL | Missing tail: usage-warning scheduling (F12 DEFERRED — config-only per COMPLIANCE_AUDIT F12) and reopening check (F11 DEFERRED). Core F9/F10 EQUIVALENT. |
| `scheduleUsageWarning` `:1350-1373`, `stageMillis` `:1375`, `tickUsageWarning` `:1377-1432`, `cancelActiveUsageWarning` `:344-348`, `updateUsageWarningSettings` `:336-342` (staged notifications via `UsageWarningNotifier`) | ABSENT (settings stored Dart-side only, `DART data/config_store.dart:202-225`) | DEFERRED-DOCUMENTED | F12. COMPLIANCE_AUDIT F12 already states notifications are never fired. |
| `stopTrackingAndSave(screenOff)` `:1440-1463`: removes 3 callbacks; if leaving (not screen-off) and app has reopen interval and none running → record `pendingLeaves[pkg]=now`; adds session millis to app/group usage prefs | `stopTrackingAndSave` `:419-434`: removes 2 callbacks; adds session millis via `SettingsStore.addUsage/addGroupUsage` (`data/SettingsStore.kt:272-285`) | PARTIAL | Accounting EQUIVALENT. Missing `pendingLeaves` write (F11 DEFERRED). Note ours sets `currentPackage=null` when `screenOff` at `:433`; original does it in the receiver (`REF:233`) — same net effect. |
| `executeBlocking(reopening, remainingSeconds, outsideWindow)` `:1465-1514`: stop+save, cancel usage warnings, pick display name/limit (group blamed only if group reached ∧ app not), launch `OutsideTimeWindowActivity`/`ReopeningLimitActivity`/`TimeUpActivity` | `executeBlocking(outsideWindow)` `:436-474`: same name/limit selection logic, launches `BlockActivity` with `VARIANT_OUTSIDE_WINDOW`/`VARIANT_TIME_UP` | PARTIAL | Limit/window paths EQUIVALENT. Reopening variant exists in `BlockActivity.kt:47-48,105` but has no caller (documented G1/F11). Warning cancellation moot (F12). |
| `checkDateReset()` `:1522-1532`: on date change, `clear()` both usage prefs, cancel/reset warnings | `checkDateReset()` `:501-507` → `SettingsStore.resetUsageIfNewDay(today)` (`data/SettingsStore.kt:259-267`, date kept in `usage_meta` store) | EQUIVALENT | Mechanism differs (stored-date vs in-memory `lastCheckDate` — ours keeps both, `:65` + store) but effect matches; channel `getUsageToday` reports the stored date honestly (`channel/PrivilegedChannelHandler.kt:405-419`). |
| `getRemainingSecondsToReopen` `:1534-1545` + `lastClosedTimes`/`pendingLeaves` (`:81-85`) | ABSENT (only `SettingsStore.reopenSeconds/setReopenSeconds`, `data/SettingsStore.kt:292-300`, storage-only) | DEFERRED-DOCUMENTED | F11, per COMPLIANCE_AUDIT F11. |
| `getControlledPackages()` `:1211-1225`: target ∪ passive ∪ limit keys ∪ weekly-limit keys ∪ reopen keys ∪ window keys ∪ weekly-window keys ∪ restricted-group packages | `SettingsStore.controlledPackages()` `data/SettingsStore.kt:452-463`: word targets + passive + `limitedPackages()` (daily+weekly keys, `:99-100`) + `windowedPackages()` (daily+weekly, `:133-134`) + reopen + group packages (groups with limit **or windows** set) | EQUIVALENT | Same union. |
| `suspendPackages/suspendPackage` `:1184-1209`: no try/catch; if admin inactive return; `setPackagesSuspended`; log with optional `details` | `suspendPackages` `:476-488`: same admin gate; **try/catch swallows DPM failure silently**; logs via `SettingsStore.logSuspension` without `details` | PARTIAL — **NEW** (minor) | In the lockdown path a throwing `setPackagesSuspended` is silently ignored in ours (original would propagate/crash the unbind). Fail-closed intent unchanged, but a failed lockdown suspension leaves no trace in ours. `details` parameter of the original's log call is dropped in the service path (the store supports it, `SettingsStore.kt:349`). |

### 1.6 NSFW / visual blocking (REF `:789-1083`) and impulse sync (REF `:1085-1137`)

| Original unit | Ours | Class |
|---|---|---|
| `warmUpNsfwDetector` `:789-804`, `maybeScanForNsfwContent` `:806-905` (2 s throttle, in-flight flag, screenshot, per-region crops), `findNsfwMediaRegions` `:907-973` (class/text/description signals + geometric fallback), `cropToBitmap` `:975-1001`, `executeNsfwBlocking` `:1003-1037` (suspend+unsuspend, or escalation), `scheduleNsfwSuspensionRelease` `:1039-1055`, `restoreNsfwSuspensions` `:1057-1068`, `showNsfwBlockedActivity` `:1070-1083`, `updateVisualBlockingSettings` `:308-334` | All ABSENT; no TFLite dep, no model asset (§10) | DEFERRED-DOCUMENTED — F16/F17 (COMPLIANCE_AUDIT concurs; absence verified there). Note: ours' accessibility config still declares `canTakeScreenshot="true"` (§10) although nothing uses it. |
| `syncImpulseSuspension` `:1085-1115`, `releaseImpulseSuspension` `:1117-1132`, `isHeldByOtherBlock` `:1134-1137` — service-side suspend/release of impulse apps, cross-guarded against NSFW/focus holds, re-applied on connect and on `impulse_block_active` pref change | ABSENT in service; impulse suspensions are applied/released by the Dart UI process via channel `setAppSuspended` | PARTIAL — documented | F21 partial already recorded in COMPLIANCE_AUDIT F21 (service-side sync absent; process-alive dependency). Cross-hold guard (`isHeldByOtherBlock`) has no analogue anywhere in ours. |

---

## 2. `DechainerApplication.kt` (REF, 89 lines) → `DominanterApplication.kt` (OURS, 91 lines)

| Original unit (REF) | Ours (OURS) | Class | Notes |
|---|---|---|---|
| `getInstance()` companion `:22-28` (lateinit) | `:26-33` (@Volatile nullable, throws if early) | EQUIVALENT | |
| `onCreate` `:40-81`: Timber plant (DEBUG), HiddenApiBypass exemptions (API≥P, try/catch), package receiver registration, warm `AppRepository.getApps()`, `DeviceOwnerRepository.restoreStuckUserSetupComplete()`, `releaseOrphanedColorFilters()`, `FocusMode.sync()` | `onCreate` `:56-90`: `SettingsStore.init`, HiddenApiBypass (same guard/try-catch, `Log.e` instead of Timber), package receiver, cold-start repair on a raw `Thread` | PARTIAL | Repair (S7) EQUIVALENT in effect. Missing: colour-filter orphan release (F26 DEFERRED), Focus sync (F25 partial, documented). App-list warm-up replaced by on-demand channel reads. |
| `packageChangeReceiver` `:32-37`: on ADDED/REMOVED/FULLY_REMOVED/REPLACED → `AppRepository.invalidateCache()` + async reload | `packageChangeReceiver` `:35-54`: emits `packageChanged` event via `DominanterState.eventSink` | PARTIAL — documented G2 | No Dart handler consumes it; no app-list cache exists to invalidate (COMPLIANCE_AUDIT G2). Behavioural consequence is the same one G2 states (stale Apps tab), so not marked NEW. |
| `releaseOrphanedColorFilters()` `:84-88` | ABSENT | DEFERRED-DOCUMENTED | F26. |

---

## 3. `DechainerDeviceAdminReceiver.kt` (REF, 16 lines) → `deviceowner/AdminReceiver.kt` (OURS, 30 lines) + `data/DeviceAdmin.kt` (REF, 18 lines)

| Original | Ours | Class | Notes |
|---|---|---|---|
| `DechainerDeviceAdminReceiver` `:9-16`: `onEnabled`/`onDisabled` → super only | `DominanterDeviceAdminReceiver` `AdminReceiver.kt:13-21`: identical empty overrides | EQUIVALENT | |
| `DeviceAdmin` object `data/DeviceAdmin.kt:10-17`: shared `component` + `policyManager` from Application singleton | No singleton; `DeviceOwnerManager.adminComponent(context)` / `dpm(context)` `deviceowner/DeviceOwnerManager.kt:31-36` build them per call from a `Context` | EQUIVALENT | Same component semantics; ours avoids the Application-singleton coupling. |

---

## 4. `DechainerPolicyUpdateReceiver.kt` (REF, 81 lines) → `DominanterPolicyUpdateReceiver` (OURS, `AdminReceiver.kt:23-29`)

| Original (REF) | Ours | Class | Notes |
|---|---|---|---|
| Extends `android.app.admin.PolicyUpdateReceiver` (@RequiresApi 34/UPSIDE_DOWN_CAKE, `:19-20`); `onPolicySetResult` `:22-30` and `onPolicyChanged` `:32-40` both log policy id, package (`EXTRA_PACKAGE_NAME`), target user, and decoded result code (`describeResult` `:61-69`, `describeTargetUser` `:71-78`); on `APPLICATION_HIDDEN_POLICY` it calls `AppRepository.invalidateCache()` (`:52-58`) because the authoritative result can contradict `setApplicationHidden`'s synchronous return | A plain `android.content.BroadcastReceiver` whose `onReceive` is an empty no-op (`AdminReceiver.kt:24-29`), registered in ours' manifest with the same two intent-filter actions and `BIND_DEVICE_ADMIN` (§10) | PARTIAL — **NEW** | COMPLIANCE_AUDIT §4.1 only verified the class *exists* for the manifest entry. Two real losses: (1) **no logging/observability** of authoritative policy results — the original's stated purpose; (2) it does **not** extend `PolicyUpdateReceiver`, so the API-34+ policy-update delivery contract (which targets the admin's `PolicyUpdateReceiver` subclass) is not implemented — the no-op body would discard the callbacks even if delivered. Mitigant: ours has no app cache to invalidate (state is re-read live via DPM in `DeviceOwnerManager`), so the *cache-invalidation* half of the original's purpose is moot by design; the *diagnostic* half is simply gone. |

---

## 5. `security/SecurityManager.kt` (REF, 399 lines) → split across `security/RecoveryStore.kt` (OURS, 99 lines), `DART domain/recovery.dart`, `DART data/config_store.dart`, `SettingsStore` generic stores

The original is one companion-object API over `security_prefs`/`recovery_prefs`. Ours deliberately splits it: code material in Kotlin (hashed), session/gate logic in pure Dart, config in JSON via the channel's allowlisted generic stores (`channel/PrivilegedChannelHandler.kt:352-367`, `data/SettingsStore.kt:386-416`).

### 5.1 Session & recovery code

| Original (REF SecurityManager.kt) | Ours | Class | Notes |
|---|---|---|---|
| `sessionEndTime`, `isSessionActive()` `:64-66`, `startSession()` (10 min) `:68-70`, `renewSession()` `:73-75`, `endSession()` `:77-79` (Compose state, in-memory) | `DART domain/recovery.dart:135-188` `RecoverySession` (10-min, in-memory, `start/renew/end/isActive/remaining`) | EQUIVALENT | Both die with the process, by design (COMPLIANCE_AUDIT F23). |
| `generateRecoveryCode(length=16)` `:335-340` (SecureRandom, A–Z pool `:48`) | `RecoveryStore.generateCode()` `security/RecoveryStore.kt:47-53` (same pool/length) | EQUIVALENT | |
| `getRecoveryCode()` `:342-344` — returns **plaintext** from `recovery_prefs`; `saveRecoveryCode()` `:350-354` stores plaintext; `isRecoveryCodeSet()` `:346-349` | `RecoveryStore.setCode/verifyCode/isSet` `:60-87`: salted PBKDF2WithHmacSHA256 (210k iters, 16-byte salt) in dedicated `recovery_secure` store; **no getter by design** | PARTIAL — documented deviation | ARCH §7.1 deviation, recorded in COMPLIANCE_AUDIT F24. Functional consequence: code can be verified but never re-displayed. Ours additionally normalizes (strip spaces, uppercase, `:90`) and validates format on set (`:62-64`) — original accepts any string. |
| `validateRecoveryCode(input, stored)` `:356-360` — plain equality, **but returns true unconditionally while a session is active** | `RecoveryStore.verifyCode` `:76-87` — constant-time hash compare only; session bypass lives in the Dart gate (`domain/recovery.dart`, `app_controller.dart`) | EQUIVALENT | Layering differs, net gate behaviour matches (F23 tests cover the Dart side). |
| `startForcedRemoval` `:362-369`, `cancelForcedRemoval` `:371-376`, `getForcedRemovalRemainingTime` `:378-398` — persisted accumulated elapsed; **every read folds `elapsedRealtime` delta into the accumulator and persists it**, so progress survives process death and is computed on demand | `DART domain/recovery.dart:196-226` `ForcedRemoval` + `config_store.dart:227-235` persistence; progress advances only by caller-supplied ticks while the app process runs | PARTIAL — documented | COMPLIANCE_AUDIT F2 already records the alive-only limitation ("can run long, never short"). |
| `consumeDebugAutoStartSession` `:81-92`, `suspendUnknownSourcesRestrictionForDebugInstall` `:94-109`, `consumeDebugRestoreUnknownSourcesRestriction` `:111-124` (all `BuildConfig.DEBUG`-gated) | ABSENT | EXCLUDED-DOCUMENTED | F34. |

### 5.2 Impulse lock (F21)

| Original | Ours | Class | Notes |
|---|---|---|---|
| Constants `:52-54` (min 15 / max 360 / default 60 min) | `recovery.dart:232-234` + `config_store.dart` `ImpulseConfig` | EQUIVALENT | |
| `get/setImpulseAction` `:243-251` — **default `TIMER_ONLY`** | `DART data/config_store.dart:36-68`: `ImpulseConfig.action` **defaults to `timerAndSuspend`** (`:38`, and `fromJson` orElse `timerAndSuspend` `:53-56`) | PARTIAL — **NEW** | Fresh installs in ours suspend the picked apps by default; the original only timed the lock unless the user opted into suspension. Not noted in COMPLIANCE_AUDIT F21. |
| `get/setImpulseDurationMinutes` `:254-266` (clamped 15–360) | `ImpulseConfig.durationMinutes` + clamp in `ImpulseLock.start` (`recovery.dart:245-251`) | EQUIVALENT | |
| `get/setImpulseSuspendedApps` `:269-277`; `get/set/clearActiveImpulseSuspension` `:284-301` (configured vs actually-suspended lists kept separate) | `ImpulseConfig.suspendApps` (configured list only); **no "active suspension" record** | PARTIAL | The configured/active distinction is lost; release acts on the current configured list via the UI (compounds the F21 process-alive partial already documented). |
| `startImpulseBlock` `:303-312` — persists start RTC **and** start elapsedRealtime + duration; `getImpulseBlockRemainingTime` `:314-333` — dual-clock resistance: elapsed wins, RTC only after reboot detection, auto-clears `impulse_block_active` on expiry; remaining is computable **at any time, in any process** (the service reads it) | `ImpulseLock` `recovery.dart:229-276`: persisted *remaining* duration decremented by caller ticks | PARTIAL — documented in part | Clock-tamper resistance is equivalent in spirit, but the original's remaining-time is derivable after process death/reboot from persisted timestamps; ours freezes while the process is dead (COMPLIANCE_AUDIT F21 covers the suspension side; the timer-side contrast is stated there as "same alive-only limitation as F2"). The native service never sees impulse state in ours (see §1.6). |

### 5.3 Challenges / misc config

| Original | Ours | Class | Notes |
|---|---|---|---|
| `ChallengeType` enum `:18-20` (MATH, WORDS, TETRIS, READING) | `DART domain/challenges.dart:14` same four; Tetris `isAvailableInV1 == false` (`:25`) | EQUIVALENT / Tetris DEFERRED-DOCUMENTED (F22a) | |
| `getAccessChallenges` `:169-180` — stored set sorted by ordinal; **legacy migration**: unset set falls back to `impulse_lock_mode` (`NORMAL`→[MATH], `HARD`→[WORDS], else **empty**); `setAccessChallenges` `:182-188` also deletes the legacy key | `DART data/config_store.dart:126-136`: stored JSON names; **default when unset is `[math]`**; no `impulse_lock_mode` migration | PARTIAL — **NEW** (minor) | Only affects upgrades from the original app / legacy prefs (impossible across applicationIds in practice) and the no-challenge-configured case: original can require *no* challenge, ours always requires at least Math. |
| `get/setTetrisMinutes` `:190-199` (clamp 1–15, default 3), `is/setTetrisSoundEnabled` `:201-209` (default true) | ABSENT | DEFERRED-DOCUMENTED | F22a (Tetris). Settings have no consumer while Tetris is deferred. |
| `ReadingSource` enum `:28-30` (BIBLE, QURAN, QUOTES, CUSTOM); `get/setReadingSource` `:211-219` (default BIBLE); `get/setReadingCount` `:225-233` (default 5, min 1) | ABSENT — no source or count setting anywhere in Dart (grep `reading_source`/`readingCount`: 0 hits) | PARTIAL — **NEW** | F22 row of COMPLIANCE_AUDIT documents the *corpus* substitution but not the loss of source selection (incl. the original's Bible/Quran/Quotes sources) and passage-count configuration. Ours' reading challenge uses its sample set + custom phrases only. |
| `get/setCustomReadingPassages` `:236-241` (JSON list of {text, source}) | `config_store.dart:138-147` custom phrases (plain string list, no per-phrase source attribution) | PARTIAL (minor) | Phrases ported; the `source` field per passage is dropped. |
| `is/setShuffleKeyboardEnabled` `:126-134` (`shuffle_keyboard`, default false) | `config_store.dart:149-154` same key/default via generic store | EQUIVALENT | (Keyboard UI itself is outside part 1 scope.) |
| `is/setBlockTorrentsEnabled` `:136-144` (`block_torrents`, default false) | ABSENT (no key, no UI) | DEFERRED-DOCUMENTED | F19 consumer/setting pair; COMPLIANCE_AUDIT F19 verifies detection code absent. |

---

## 6. `data/DeviceOwnerRepository.kt` (REF, 466 lines) → `shizuku/ShizukuProvisioning.kt` (OURS, 391) + `deviceowner/DeviceOwnerManager.kt` (OURS, 484) + `shizuku/ShizukuGateway.kt` (OURS, 179)

The original mixes provisioning (Shizuku) and runtime DPM in one object; ours splits along the ARCH §1.3 line. Runtime-DPM methods whose original home is `AppRepository.kt`/`SystemRestrictions.kt` (other audit parts) live in `DeviceOwnerManager` and are noted where they complete a Repository row.

| Original (REF DeviceOwnerRepository.kt) | Ours | Class | Notes |
|---|---|---|---|
| `isDeviceOwner()` `:31` | `DeviceOwnerManager.isDeviceOwner` `DeviceOwnerManager.kt:42-43`; channel `isDeviceOwner` also returns `isAdminActive` (`PrivilegedChannelHandler.kt:139-142`) | EQUIVALENT | |
| `isShizukuInstalled()` `:33-39` (package probe, catch NameNotFound) | `ShizukuGateway.isInstalled` `ShizukuGateway.kt:97-102` | EQUIVALENT | |
| `installShizuku()` `:41-51` — `market://details?id=moe.shizuku.privileged.api` intent, web fallback on `ActivityNotFoundException` | ABSENT in Kotlin and Dart (grep `market://`: 0 hits) | MISSING — **NEW** (minor) | No "install Shizuku" action exists in ours; the Setup screen can only describe the state. Not mentioned in COMPLIANCE_AUDIT (its F30 note covers only the setup-guide URL). |
| `openShizukuSetupGuide()` `:53-60` — opens `https://shizuku.rikka.app/guide/setup/` | ABSENT (text instructions instead) | PARTIAL — documented | COMPLIANCE_AUDIT F30 states this plainly (no URL-launcher dep). |
| `checkShizukuPermission()` `:62-65` (pre-V11 → false; `checkSelfPermission`) | `ShizukuGateway.hasPermission` `ShizukuGateway.kt:106-112` (same + try/catch) | EQUIVALENT | Permission *request* (code 911, listener verifies code, removed on cleanup) in `ShizukuGateway.kt:47-56,159-172` — fixes over the original documented in COMPLIANCE_AUDIT S2. |
| `getUserId()` `:67` (`myUid()/100000`) | `ShizukuProvisioning.userId()` `ShizukuProvisioning.kt:39` | EQUIVALENT | |
| `withShizukuDevicePolicyManager` `:70-87` (reflective `mService` swap, restore in finally, exceptions swallowed on restore) | `ShizukuProvisioning.withShizukuDevicePolicyManager` `:109-130` — same structure **plus `synchronized(provisioningLock)`** | EQUIVALENT (+fix) | Serialisation is an ours-only hardening (the swap mutates a shared framework object). |
| `forceUpdateUserSetupComplete` `:90-101`, `setActiveAdminCompat` `:104-131`, `setDeviceOwnerCompat` `:134-183` (reflective overload resolution 2-arg → 3-arg → legacy) | `ShizukuProvisioning.kt:132-140`, `:143-170`, `:173-213` — near-verbatim ports | EQUIVALENT | |
| `bypassUserSetupComplete` `:185-192` (get must be "1", put "0", exit-code checked, refresh) | `:48-56` | EQUIVALENT | Command #1/#2. |
| `restoreUserSetupComplete` `:194-197` | `:59-62`; invoked from `finally` in `provisionDeviceOwner` `:248-250` | EQUIVALENT | Command #3. |
| `refreshUserSetupComplete` `:199-207` (runCatching + Timber.w) | `:64-72` (runCatching + Log.w) | EQUIVALENT | |
| `restoreStuckUserSetupComplete` `:209-217` (binder + permission gate; setup=="0" ∧ provisioned=="1" → restore) | `:80-87`, called from `DominanterApplication.onCreate` (§2) | EQUIVALENT | Commands #4/#5 (COMPLIANCE_AUDIT S7; note its table's row #5 mislabels the call site as `refreshUserSetupComplete` — the `device_provisioned` read is in `restoreStuckUserSetupComplete`, `ShizukuProvisioning.kt:83-85`). |
| `processDeviceOwnerPrivileges(remove)` `:220-264` — remove: `clearDeviceOwnerApp` if admin active, return ""; grant: bypass → binder path → `dpm set-device-owner` shell fallback (unchecked listener) → finally restore → on success `ColorFilterController.grantPermissionViaShizuku` (i.e. `pm grant … WRITE_SECURE_SETTINGS`, `REF data/ColorFilterController.kt:48-59`) | Split: `provisionDeviceOwner` `ShizukuProvisioning.kt:224-266` (requireGranted gate; already-owner short-circuit; binder path; shell fallback **exit-code-checked**, throws `SHELL_FAILED`; finally restore; throws `PROVISIONING_FAILED` if still not owner; then best-effort `grantWriteSecureSettings` reported in `commandOutput`) + `DeviceOwnerManager.removeDeviceOwner` `DeviceOwnerManager.kt:54-65` (requireOwner; `clearDeviceOwnerApp`; **verified by re-read**, throws if still owner) | EQUIVALENT (+fixes) | All documented in COMPLIANCE_AUDIT S6/F1/F2. Behavioural tightening: original remove path silently no-ops when admin inactive; ours throws `DPM_NOT_OWNER`. Original returns raw command output as its only failure signal; ours throws typed errors. |
| `setPrivateDNS(host)` `:266-268` / `getPrivateDNS()` `:270-274` (raw DPM calls, result code returned to caller) | `DeviceOwnerManager.setPrivateDns/getPrivateDns` `:452-483`: validates hostname, maps result code (`PRIVATE_DNS_SET_NO_ERROR` required, else `DPM_FAILED`), returns {mode, hostname} | EQUIVALENT (+fix) | No unset/off method on either side (COMPLIANCE_AUDIT F7 partial). |
| `getAllAccountsViaShizuku()` `:276-304` (`dumpsys account`, regex `Account {name=…, type=…}`, returns (type,name) pairs; errors only logged) | `ShizukuProvisioning.diagnostics()` `:287-296` — same command/regex via `execShellChecked` (throws on failure) | EQUIVALENT | Command #8. |
| `getAppNameFromAccountType(ctx, type)` `:306-322` — resolves an account type to its authenticator app's label via `AccountManager.authenticatorTypes` | ABSENT (diagnostics payload carries raw `type`+`name` only, `ShizukuProvisioning.kt:292-295`; Dart model `DART data/privileged_channel.dart:162-186` does not resolve labels) | MISSING — **NEW** (minor) | Diagnostics show raw account-type strings (e.g. `com.google`) instead of app names. Not in COMPLIANCE_AUDIT. |
| `getCurrentDeviceOwner()` `:324-355` (`dpm list-owners`, parse `admin=` component, null on any failure) | `diagnostics()` `:306-318` — same parse; failure of the command throws instead of returning null | EQUIVALENT | Command #9. |
| `getExtraUsersInfo()` `:357-381` (`pm list users`, `UserInfo{id:name:…}`, skips id 0) | `diagnostics()` `:298-304` — same regex/filter | EQUIVALENT | Command #10. |
| `getAccessibilityServices()` `:383-399` / `isAccessibilityGranted()` `:401-403` (substring `.DechainerAccessibilityService`) | `getEnabledAccessibilityServices()` `ShizukuProvisioning.kt:331-334` / `isAccessibilityServiceListed()` `:336-341` (same substring on own class name) | EQUIVALENT | Command #11. (Channel-side `isAccessibilityEnabled` uses stricter ComponentName comparison, `PrivilegedChannelHandler.kt:396-402`.) |
| `changeAccessibilityPermission(grant)` `:405-465` — read list; grant: append own component; **revoke: replace the whole list with `'null'`** (wiping every other app's accessibility service); then `settings put … accessibility_enabled 1`; on grant also `grantPermissionViaShizuku` (= `pm grant WRITE_SECURE_SETTINGS`) | `setAccessibilityEnabled(ctx, enabled)` `:352-390` — arms intentional-disable guard before revoke; read-modify-write **preserving other services**, `'null'` only if the list becomes empty; both puts exit-code-checked; **verified by re-read**, throws on mismatch; on enable also attempts `grantWriteSecureSettings` | PARTIAL — deliberate fix | Commands #12/#13. The revoke-wipes-everything behaviour of the original is intentionally **not** reproduced (documented in the function KDoc, `:343-351`). COMPLIANCE_AUDIT S9 describes the read-modify-write but does not call out that the original's revoke semantics were destructive; the deviation itself is recorded in code. Arming the F28 guard has no original counterpart at this call site (original relied on `prepareServiceDisable()` being called by UI code before `disableSelf`-adjacent flows). |

---

## 7. `utils/ShizukuRunner.kt` (REF, 111 lines) → `shizuku/ShizukuRunner.kt` (OURS, 145 lines)

| Original (REF) | Ours (OURS) | Class | Notes |
|---|---|---|---|
| `ProcessResult(exitCode, output, error)` `:25-29` | `ProcessResult` `ShizukuRunner.kt:47-51` | EQUIVALENT | |
| `exec(vararg)` `:32-68` — binder null/dead → null; pre-V11 → null; single spaced arg → `sh -c`; stderr drained on a side thread, stdout on caller thread; `waitFor()`; **any exception → null** | `exec(vararg, timeoutMs)` `:66-73` + `run()` `:109-144` — same null contract, same `sh -c` rule, **both streams drained concurrently** on a cached executor, **30 s timeout** → destroy + `TIMEOUT` exception (`:126-134`) | EQUIVALENT (+fixes) | Fixes are the documented §5.4 set (COMPLIANCE_AUDIT §3 preamble). One residual: if the process times out, ours throws instead of returning null — callers see `TIMEOUT`, intended. |
| `command(String, CommandResultListener, lineBundle)` `:70-109` — streaming listener with partial-output callbacks; **drains stdout fully before stderr (pipe-deadlock risk); success ⇔ stderr blank; `waitFor()` result ignored (exit code never surfaced)** | No streaming variant. `execShell` `:81-82` (synchronous, full result) and `execShellChecked` `:99-104` (throws `SHELL_FAILED` with exit code); `execChecked` `:90-96` likewise for argv form | PARTIAL — deliberate fix | The streaming/partial-callback capability (`lineBundle`) has **no counterpart**: no caller in ours needs incremental output (all 13 commands are short). The exit-code blindness — the original's central flaw — is removed, as documented. Classification PARTIAL only for the dropped streaming API surface. |
| `CommandResultListener` interface `:13-23` | ABSENT (replaced by return values + `PrivException`) | PARTIAL — deliberate | See above. |

---

## 8. `utils/HomeScreenDetector.kt` (REF, 60 lines) → ABSENT in ours

| Original (REF) | Ours | Class | Notes |
|---|---|---|---|
| `HomeScreenDetector` `:17-59`: `isHomeScreen(event, root)` `:21-33` (package must be a home package; reject class names containing "Recents"; reject Launcher3 recents via localized `accessibility_recent_apps` label, cached per pkg+locale `:44-56`; reject visible `id/overview_panel` node), `homePackages()` `:37-42` (default HOME intent resolution, fallback to all launchers minus Settings) | No class, no equivalent logic anywhere in ours (grep `HomeScreenDetector`/`overview_panel`: 0 hits) | DEFERRED-DOCUMENTED (F11) — **NEW** naming | Its **only** consumer in the original is the service's pending-leaves flush (`REF DechainerAccessibilityService.kt:666-670`), which exists solely to timestamp app closes for the reopening cooldown. Since F11 enforcement is deferred (COMPLIANCE_AUDIT F11/G1), the detector is moot in v1 — but COMPLIANCE_AUDIT never names it; any F11 implementation must port this detector too, including its Quickstep/Launcher3 recents edge cases, or reopen timestamps will also fire when the user merely visits recents. |

---

## 9. Channel surface for part 1 — `channel/PrivilegedChannelHandler.kt` (OURS, 496) ↔ `DART data/privileged_channel.dart` (701)

(COMPLIANCE_AUDIT §4.1 verified exact 39/39 method parity; re-verified here by reading the full dispatch `PrivilegedChannelHandler.kt:109-371` against the Dart client `privileged_channel.dart:452-701` — no drift found. Part-1-relevant notes only:)

| Item | Finding | Class |
|---|---|---|
| Error mapping | Every dispatch failure → `PrivException` taxonomy or wrapped `INTERNAL` (`PrivilegedChannelHandler.kt:99-107`); Dart `_invoke` rethrows as `PrivilegedException` with code/message/details (`privileged_channel.dart:426-450`). No fake-success path in part-1 methods. | EQUIVALENT |
| `getShizukuState` never-throws contract | Kotlin catches and degrades to `notRunning` + diagnostic (`:380-393`); matches `ShizukuGateway.state()`'s own never-throws design (`ShizukuGateway.kt:116-126`). | EQUIVALENT |
| Event types emitted by part-1 Kotlin | `shizukuBinderReceived/Dead`, `shizukuPermissionResult` (`ShizukuGateway.kt:38-56`), `deviceOwnerChanged` (`PrivilegedChannelHandler.kt:121,133`), `packageChanged` (`DominanterApplication.kt:47-50`), `accessibilityStateChanged` **and** `accessibilityStatus` (service `:204-213` vs `:186-189`) | PARTIAL — documented G2 (incl. the dual accessibility event names). |
| Blocked-activities channel method | None exists (no `get/setBlockedActivities` in dispatch or Dart) — confirms G1 from the channel side. | MISSING — documented G1 |

---

## 10. Build config & manifest

### 10.1 Gradle

| Item | Original (REF) | Ours | Class | Notes |
|---|---|---|---|---|
| App id / namespace | `io.github.warleysr.dechainer` (`app/build.gradle.kts:16,21`) | `io.github.alnajashia.dominanter` (`android/app/build.gradle.kts:8,29`) | EQUIVALENT (by design) | New applicationId is the project's founding decision. |
| compileSdk / minSdk / targetSdk | 36 (release train) / 30 / 36 (`app/build.gradle.kts:17-26`) | 36 / 30 / 36, pinned explicitly (`android/app/build.gradle.kts:11,30-31`) | EQUIVALENT | |
| versionCode / versionName | **23 / "1.12.0"** (`app/build.gradle.kts:25-26`) | **1 / "1.0.0"** (pubspec `version: 1.0.0+1` via `flutter.versionCode/Name`, `android/app/build.gradle.kts:32-33`) | PARTIAL | Expected for a v1.0.0 rebuild, but strictly a downgrade in versionCode terms vs the original's 23 — relevant only if the same applicationId were ever reused (it is not). |
| Java/Kotlin target | VERSION_21 (`app/build.gradle.kts:88-91`) | VERSION_21 (`android/app/build.gradle.kts:16-23`) | EQUIVALENT | |
| AGP / Kotlin plugin | AGP **8.13.2**, Kotlin **2.4.10** (`gradle/libs.versions.toml:2,5`) | AGP **8.9.1**, Kotlin **2.1.0** (`android/settings.gradle.kts`, plugins block) | PARTIAL — **NEW** (minor) | Ours builds with a notably older toolchain than the original's catalog. No user-visible effect today; matters for keeping up with Android 16 APIs (e.g. the real `PolicyUpdateReceiver` contract, §4). Not flagged in COMPLIANCE_AUDIT. |
| Version catalog | `gradle/libs.versions.toml` (full catalog) | None — versions inline in `android/app/build.gradle.kts` / `settings.gradle.kts` | EQUIVALENT | Flutter template structure. |
| Shizuku | `dev.rikka.shizuku:api:13.1.5` + `:provider:13.1.5` (toml `:24`, app deps) | Identical coordinates inline (`android/app/build.gradle.kts`, dependencies block) | EQUIVALENT | COMPLIANCE_AUDIT S5. |
| HiddenApiBypass | 4.3 (toml) | 4.3 (inline) | EQUIVALENT | |
| Timber 5.0.1 | `implementation` | ABSENT — `android.util.Log` used throughout ours | EQUIVALENT | Logging only. |
| Jsoup 1.23.1 | `implementation` | ABSENT | EXCLUDED-DOCUMENTED | F20 (Play-Store scraping) only consumer. |
| LiteRT 2.2.0 + `nsfw_model.tflite` asset (17 MB) + `noCompress "tflite"` + jniLibs excludes | present | ABSENT (no dep, no asset) | DEFERRED-DOCUMENTED | F16. |
| Biometric | `androidx.biometric:1.4.0-alpha07` + biometric-compose | No native dep; Dart `local_auth: ^3.0.1` (pubspec) | EQUIVALENT (by design) | F32 via Flutter plugin, per COMPLIANCE_AUDIT F32. |
| Compose stack, appcompat, lifecycle, material-icons | `implementation` | ABSENT (Flutter UI; `cupertino_icons` only) | EQUIVALENT (by design) | |
| `org.json:20260814` | `implementation` | ABSENT — platform `org.json` used (`SettingsStore`, channel handler) | EQUIVALENT | Android framework bundles org.json. |
| kotlinx-coroutines | Used by original service/Application (scopes) — via lifecycle/compose transitives | No coroutines dep; ours uses `Handler`, executors, raw `Thread` | EQUIVALENT | |
| Test deps | JUnit, Robolectric 4.16.1, MockK, Kotest, coroutines-test, Espresso, compose-test (`app/build.gradle.kts` test blocks; `testOptions.unitTests.isIncludeAndroidResources=true`) | `flutter_test` only (pubspec dev_deps); **no Kotlin/JVM unit-test infrastructure at all** | PARTIAL | All 41 tests are Dart-side; no native test harness exists to port the original's Robolectric-style tests to (device-testing gap is documented globally; the missing JVM test setup itself is not called out in COMPLIANCE_AUDIT). |
| Release build | `isMinifyEnabled=true`, `isShrinkResources=true`, proguard files (`app/build.gradle.kts:47-86`) | Release: **no minify, no shrinkResources, no proguard** (`android/app/build.gradle.kts` buildTypes) | PARTIAL | The absence of minify/shrink vs the original's release config is **NEW** detail: ours' release APK ships unobfuscated/unshrunk (50 MB largely Flutter engine + unshrunk resources). |
| NDK abiFilters | `arm64-v8a, armeabi-v7a, x86_64` (`app/build.gradle.kts:28-30`) | Flutter defaults (no explicit abiFilters; `ndkVersion = flutter.ndkVersion`) | PARTIAL (minor) | Flutter default also covers x86 for emulators; ABI set not pinned to the original's. |
| `androidResources` | `noCompress "tflite"`, **`localeFilters += ["en","pt"]`** | ABSENT | PARTIAL (minor) | Locale filtering not replicated (F33 is in-app chrome translation; APK carries all Flutter locales). tflite part moot (F16). |
| `dependenciesInfo.includeInApk=false` | present | ABSENT | PARTIAL (cosmetic) | Dependency metadata is included in ours' APK; original excluded it. |

### 10.2 AndroidManifest.xml

| Item | Original (REF `app/src/main/AndroidManifest.xml`) | Ours (`android/app/src/main/AndroidManifest.xml`) | Class | Notes |
|---|---|---|---|---|
| Permissions (15) | INTERNET, ACCESS_NETWORK_STATE, QUERY_ALL_PACKAGES, PACKAGE_USAGE_STATS, USE_BIOMETRIC, POST_NOTIFICATIONS, VIBRATE, WRITE_SECURE_SETTINGS, RECEIVE_BOOT_COMPLETED, SCHEDULE_EXACT_ALARM (maxSdk 32), USE_EXACT_ALARM, FOREGROUND_SERVICE, FOREGROUND_SERVICE_SPECIAL_USE | **Identical set, identical order/attributes** | EQUIVALENT | Unused-in-v1 permissions (FGS/alarms/boot) already flagged as G3. |
| `<queries>` | VIEW http, VIEW https | VIEW http, VIEW https, **+ PROCESS_TEXT text/plain** (Flutter template) | EQUIVALENT (+extra) | |
| Application attrs | `allowBackup=true`, `dataExtractionRules=@xml/data_extraction_rules`, `fullBackupContent=@xml/backup_rules`, `localeConfig=@xml/locales_config`, `supportsRtl=true`, theme `Theme.Dechainer`, label from strings | Only `label="Dominanter"`, `name=.DominanterApplication`, `icon` — **no allowBackup (defaults true), no backup-rules refs, no localeConfig, no supportsRtl** | PARTIAL — **NEW** (minor) | Original's backup XMLs are the untouched AOSP templates (all rules commented out), so effective backup exposure is similar (full backup allowed both sides) — but ours doesn't declare the rule files at all, and per-app locale config (en/pt) is absent; F33 language selection is purely in-app in ours. |
| MainActivity | `.activities.MainActivity`, exported, MAIN/LAUNCHER, no taskAffinity | `.MainActivity` (Flutter), exported, **adds `taskAffinity=""`**, singleTop, LaunchTheme/NormalTheme meta | EQUIVALENT | taskAffinity difference is a Flutter-template artifact; original reserved empty affinity for block activities. |
| Block activities (7): TimeUp, ReopeningLimit, BlockedWord, NsfwContentBlocked, OutsideTimeWindow, AccessibilityRequest, FocusReminder — all singleInstance/excludeFromRecents/noHistory/taskAffinity="", most showOnLockScreen | **One** `BlockActivity` (variants timeUp/outsideWindow/blockedWord/reopening/generic) + `AccessibilityRequestActivity`, same flags, showOnLockScreen on BlockActivity | PARTIAL | Variant consolidation is by design; missing activities map to deferred features: Reopening (F11), Nsfw (F16), FocusReminder (F25). |
| DeviceAdmin receiver | `.DechainerDeviceAdminReceiver`, exported, BIND_DEVICE_ADMIN, `@xml/device_admin_policies`, DEVICE_ADMIN_ENABLED filter | `.deviceowner.DominanterDeviceAdminReceiver`, identical declaration | EQUIVALENT | |
| PolicyUpdate receiver | `.DechainerPolicyUpdateReceiver` with DEVICE_POLICY_SET_RESULT + DEVICE_POLICY_CHANGED filters | `.deviceowner.DominanterPolicyUpdateReceiver`, identical filters | PARTIAL | Declaration matches; implementation doesn't (§4). |
| Other receivers | UsageWarningDismiss (F12), Focus (F25), FocusSchedule (F25), ApkUpdateResult (F29), FocusSystem (BOOT_COMPLETED/MY_PACKAGE_REPLACED/TIME_SET/TIMEZONE_CHANGED — F25) | All ABSENT | DEFERRED/EXCLUDED-DOCUMENTED | F12/F25 deferred, F29 excluded. Note the manifest still *requests* RECEIVE_BOOT_COMPLETED with no receiver (G3). |
| FocusService (FGS, specialUse, with PROPERTY_SPECIAL_USE_FGS_SUBTYPE) | declared | ABSENT | DEFERRED-DOCUMENTED | F25 native FGS (COMPLIANCE_AUDIT F25/G3). |
| ShizukuProvider | `rikka.shizuku.ShizukuProvider`, `${applicationId}.shizuku`, INTERACT_ACROSS_USERS_FULL | Identical | EQUIVALENT | COMPLIANCE_AUDIT S4 (verified in built APK). |
| Accessibility service | `.DechainerAccessibilityService`, BIND_ACCESSIBILITY_SERVICE, exported=false, `@xml/accessibility_service_config` | `.accessibility.DominanterAccessibilityService`, identical | EQUIVALENT | |

### 10.3 res/xml

| File | Original | Ours | Class | Notes |
|---|---|---|---|---|
| `device_admin_policies.xml` | 7 legacy policies (limit-password, watch-login, reset-password, force-lock, wipe-data, expire-password, disable-keyguard-features) | Byte-equivalent policy list (`android/app/src/main/res/xml/device_admin_policies.xml`) | EQUIVALENT | |
| `accessibility_service_config.xml` | eventTypes textChanged+windowState+windowContent, flags includeNotImportantViews+retrieveInteractiveWindows, timeout 100, `feedbackSpoken`, canRetrieveWindowContent, **canTakeScreenshot=true**, settingsActivity = original MainActivity | Same except **`feedbackGeneric`** instead of `feedbackSpoken`, settingsActivity = ours' MainActivity, canTakeScreenshot retained | PARTIAL — **NEW** (minor) | Feedback-type change is user-visible for TalkBack users (spoken vs generic feedback). canTakeScreenshot=true is retained although its only consumer (F16) is deferred. |
| `backup_rules.xml`, `data_extraction_rules.xml` | Present (AOSP templates, no active rules) | ABSENT | PARTIAL (minor) | See §10.2 application attrs. |
| `locales_config.xml` (en, pt) | Present + `android:localeConfig` | ABSENT | PARTIAL (minor) | F33 handled in-app instead of per-app locales. |

---

## 11. Part-1 verdict summary

- **Faithful core:** provisioning (all 13 commands, reflection path, bypass/restore), Shizuku state/permission (911), DPM owner ops with verify-by-reread, time limits/windows accounting, active word blocking, F28 lockdown, recovery-code flow (with the documented PBKDF2 deviation) — EQUIVALENT or EQUIVALENT-with-documented-fixes.
- **Documented absences confirmed real:** F6/F11/F12/F16/F17/F19/F26 code genuinely absent (not stubbed); F20/F29/F34 genuinely excluded.
- **NEW findings (not in COMPLIANCE_AUDIT):** prefs-listener no longer re-arms tracking on limit/window/group edits (§1.3); SCREEN_ON tracking resume missing (§1.2); hidden-app re-apply on reinstall missing (§1.2); word-regex `\b` vs Unicode lookarounds (§1.4); `buildScreenText` source difference (§1.4); PolicyUpdateReceiver is a plain no-op BroadcastReceiver, not a `PolicyUpdateReceiver` (§4); impulse default action is TIMER_AND_SUSPEND vs original TIMER_ONLY (§5.2); challenge-selection default/migration differs (§5.3); reading source/count settings absent (§5.3); `installShizuku()` and `getAppNameFromAccountType()` missing (§6); HomeScreenDetector unnamed in prior audit (§8); older AGP/Kotlin (§10.1); release minify/shrink absent (§10.1); manifest backup/locale attrs absent (§10.2); accessibility feedback type changed (§10.3); service `suspendPackages` silently swallows DPM failure (§1.5).
