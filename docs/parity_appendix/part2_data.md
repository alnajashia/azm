# Parity Audit — Part 2 of 5: Data Layer + Models (READ-ONLY)

> **Scope:** original `data/` (19 files in scope; `DeviceOwnerRepository.kt` excluded — Part 1)
> and `models/` (11 files) vs. the rebuild's data layer.
> **Reference (REF):** `reference/dechainer-zip/dechainer-1.12.0/app/src/main/java/io/github/warleysr/dechainer/`
> (citations below are `data/…` / `models/…` relative to that root).
> **Ours (OUR):** `project/android/app/src/main/kotlin/io/github/alnajashia/dominanter/data/SettingsStore.kt` (cited `SettingsStore.kt`),
> `…/data/TimeModels.kt` (`TimeModels.kt`), `project/lib/data/config_store.dart` (`config_store.dart`),
> `project/lib/data/privileged_channel.dart` (`privileged_channel.dart`), `project/lib/domain/focus.dart` (`focus.dart`),
> `project/lib/app_controller.dart` (`app_controller.dart`). Where the data layer's counterpart necessarily lives in
> `…/deviceowner/DeviceOwnerManager.kt` it is cited as `DeviceOwnerManager.kt` (DOM).
> **Classifications:** EQUIVALENT / PARTIAL / MISSING / DEFERRED-DOCUMENTED (feature) / EXCLUDED-DOCUMENTED (feature).
> Findings **not** present in `project/docs/COMPLIANCE_AUDIT.md` are marked **NEW**.
> Method: full source read of every in-scope file on both sides; storage names, key names, JSON shapes,
> defaults and edge cases compared literally.

---

## 1. Models

### 1.1 `models/TimeLimit.kt` (L1–30) vs `TimeModels.kt:14–29`
| Member | REF | OUR | Verdict |
|---|---|---|---|
| `dailyMinutes=0`, `weeklyMinutes: List<Int>?=null` | `TimeLimit.kt:11` | `TimeModels.kt:14` | identical |
| `isPerDay`, `isSet`, `minutesFor(day)`, `todayMinutes()` | `TimeLimit.kt:12–18` | `TimeModels.kt:15–19` | identical |
| `NONE`, `daily()`, `perDay()` (requires size == 7) | `TimeLimit.kt:20–28` | `TimeModels.kt:21–27` | identical |

**EQUIVALENT** — verbatim port.

### 1.2 `models/TimeWindow.kt` (L1–47) vs `TimeModels.kt:32–64`
`contains()` (midnight-spanning), `minutesUntilEnd()`, `formatted()`, private `segments()`, and the
`intersect(a,b)` companion (empty list = identity) are line-for-line identical
(REF `TimeWindow.kt:5–45` ↔ OUR `TimeModels.kt:33–62`). **EQUIVALENT**.

### 1.3 `models/TimeWindows.kt` (L1–49) vs `TimeModels.kt:66–96`
Fields, `isPerDay`, `isSet`, `windowsFor`, `todayWindows`, `NONE/daily/perDay`, and the per-day-aware
`intersect` are identical (REF `TimeWindows.kt:11–47` ↔ OUR `TimeModels.kt:66–94`).
**PARTIAL (trivial):** REF convenience helpers `isNotEmpty()` / `isEmpty()` (`TimeWindows.kt:19–20`) have no
counterpart in `TimeModels.kt` — callers must use `isSet` directly. No behavioural consequence found. **NEW** (wording-level).

### 1.4 `models/AppGroup.kt` (L1–9) vs `TimeModels.kt:98–104` + Dart `AppGroupModel`
Kotlin model is field-identical: `id, name, packageNames=∅, timeLimit=NONE, timeWindows=NONE`
(REF `AppGroup.kt:3–9` ↔ OUR `TimeModels.kt:98–104`). Dart mirror `AppGroupModel`
(`privileged_channel.dart:274–339`) flattens limit/windows into
`dailyMinutes/weeklyMinutes/dailyWindows/weeklyWindows` with `fromMap/toMap/copyWith` incl.
`clearWeeklyMinutes/clearWeeklyWindows` flags — a transport shape, semantically complete.
**EQUIVALENT** (but see §2.3 for repository-level differences).

### 1.5 `models/AppItem.kt` (L1–17) vs Dart `InstalledApp` (`privileged_channel.dart:95–134`)
| REF field (`AppItem.kt:5–16`) | OUR | Note |
|---|---|---|
| `name` | `label` (`privileged_channel.dart:98`) | rename only |
| `packageName`, `isSystem`, `isHidden=false`, `isUninstallBlocked=false`, `isSuspended=false` | same names/defaults (`privileged_channel.dart:97–111`) | ✔ |
| `icon: Drawable` | **ABSENT** | inherently non-transferable over a channel; by design |
| `timeLimit: TimeLimit = NONE` (L12) | **ABSENT from `InstalledApp`** | fetched separately via `getAppEnforcement()` → `AppEnforcement` (`privileged_channel.dart:609–622`, model L244–272) |
| `reopeningSeconds: Int = 0` (L13) | **ABSENT from `InstalledApp`** | present on `AppEnforcement.reopenSeconds` (`privileged_channel.dart:249`) |
| `timeWindows: TimeWindows = NONE` (L14) | **ABSENT from `InstalledApp`** | present on `AppEnforcement.dailyWindows/weeklyWindows` (L250–251) |
| `hasExplicitContent: Boolean = false` (L16) | `hasExplicitContentRating: bool?`, **always `null`** | Kotlin emitter hard-codes `null`: `DeviceOwnerManager.kt:86` ("F20 is not ported… reserved"). EXCLUDED-DOCUMENTED (F20), consistent with COMPLIANCE_AUDIT F20 |

**PARTIAL** — the unified per-app view the original exposes in one object is split across two channel
calls in ours (`listInstalledApps` + `getAppEnforcement`); no field is ultimately unreachable except
`icon` (by design) and the F20 rating (excluded).

### 1.6 `models/BlockedList.kt` (L1–7) vs `config_store.dart:18–32`
`id/title/sites` identical; Dart adds `toJson/fromJson/copyWith` with the same JSON keys
(`config_store.dart:24–31`). REF `sites` is required (no default); Dart defaults `sites` to `const []`
and `title` to `''` on decode — more forgiving, no data loss. **EQUIVALENT**.

### 1.7 `models/SuspensionLogEntry.kt` (L1–23) vs `TimeModels.kt:106–120` + Dart (`privileged_channel.dart:364–390`)
- `SuspensionReason` has the same 8 values in the same order:
  REF `SuspensionLogEntry.kt:5–14` (`UNSUPPORTED_BROWSER, TORRENT_APP, RATED_18_PLUS, VISUAL_BLOCKING,
  IMPULSE_LOCK, FOCUS_MODE, ACCESSIBILITY_DISABLED, MANUAL`) ↔ OUR `TimeModels.kt:106–114`. REF carries a
  `titleResId` per value (UI string resource); ours has none (Dart renders the raw `reason` string,
  `privileged_channel.dart:377`). REF decode fallback for unknown reason = `MANUAL`
  (`SuspensionLogRepository.kt:107–111`) ↔ OUR `SuspensionReason.fromName` → `MANUAL` (`TimeModels.kt:116–119`). ✔
- Entry fields `id (UUID default), packageName, appName, timestamp (ms), reason, details?`
  (REF `SuspensionLogEntry.kt:16–23`) ↔ Dart `SuspensionLogEntry` (`privileged_channel.dart:364–390`,
  `timestampMs` + `timestamp` getter). **EQUIVALENT** (repository differences in §2.8).

### 1.8 `models/UsageAlertStage.kt` (L1–10) vs Dart `UsageWarningStage` (`config_store.dart:68–90`)
REF: `UsageAlertStage(id: String, minutesBefore: Float, type: UsageAlertType = SOUND, vibrationCount: Int = 1)`,
`UsageAlertType { SILENT, SOUND, VIBRATE }` (`UsageAlertStage.kt:3–10`).
OUR Dart: `UsageWarningStage(minutesBefore: double, type, vibrationCount = 0)` (`config_store.dart:70–78`).
- **NEW — `id` field dropped entirely** (no `id` in the Dart class or its JSON, `config_store.dart:80–89`).
  Stages in ours are therefore not individually addressable/stable across edits the way the original's are.
- **NEW — enum wire values differ in case:** REF serialises `type.name` = `SILENT/SOUND/VIBRATE`
  (`UsageWarningSettings.kt:64`); ours serialises Dart `type.name` = `silent/sound/vibrate`
  (`config_store.dart:81`). Internally consistent in ours, but the stored JSON is **not** schema-compatible
  with the original's `usage_warning_prefs/stages` format despite the same store+key names (see §2.9).
- **NEW — defaults differ:** `vibrationCount` default 1 (REF) vs 0 (OUR, `config_store.dart:74`);
  unknown-type fallback on decode: REF → `SOUND` (`UsageWarningSettings.kt:45–49`), OUR → `silent`
  (`config_store.dart:84–87`).
**PARTIAL.**

### 1.9 `models/FocusSchedule.kt` (L1–49) — no counterpart
REF: `FocusSchedule(id=UUID, daysOfWeek: Set<Int> /*1=Mon..7=Sun*/, hour, minute, enabled=true)` with
`formattedTime()` (L17) and `nextTriggerMillis(now)` (L23–48: today-if-later, else earliest
`TemporalAdjusters.next(dow)` within 7 days; `null` if disabled/no days).
OUR: **no `FocusSchedule` type exists** in Kotlin or Dart (grep `FocusSchedule` over `project/lib` +
`project/android`: only the prefs-name constant `PREFS_FOCUS_SCHEDULES`, `SettingsStore.kt:51`).
**DEFERRED-DOCUMENTED (F25 schedules)** — COMPLIANCE_AUDIT F25 states "no schedules in v1";
the orphaned allowlist entry is its G1 note on `focus_schedules_prefs`.

### 1.10 `models/ColorFilterMode.kt` (L1–34) + `models/ColorFilterScope.kt` (L1–32) — no counterpart
REF Mode: `GRAYSCALE, NIGHT_LIGHT, EXTRA_DIM, INVERSION`; `isAvailable` gates `EXTRA_DIM` on
API ≥ S **and** system bool `config_reduceBrightColorsAvailable` (`ColorFilterMode.kt:13–25`);
`available` companion (L20). REF Scope: `DEVICE, EXCEPT_APPS, ONLY_APPS`, `appliesTo(pkg, excluded, only)`
(L8–13), `Coverage` data class (L31) and the `isLoosening(from,to)` transition matrix (L17–28).
OUR: no colour-filter type, key or function anywhere in the data layer (or elsewhere; COMPLIANCE_AUDIT
F26 verified absence). **DEFERRED-DOCUMENTED (F26).**

---

## 2. Data repositories / stores

### 2.1 `data/AppTimeLimits.kt` (L1–52) vs `SettingsStore.kt:78–106`
Storage is a literal match: REF `PREFS_NAME="app_limits"` (Int/pkg), `WEEKLY_PREFS_NAME="app_weekly_limits"`
(CSV of 7/pkg), a package lives in at most one file (`AppTimeLimits.kt:14–15,33–43`) ↔ OUR
`PREFS_APP_LIMITS/PREFS_APP_WEEKLY_LIMITS` (`SettingsStore.kt:35–36`) and `setTimeLimit` clears the other
file first (`SettingsStore.kt:84–97`), same write order and same `>0`-or-remove rule for daily.
`read` precedence (weekly wins) identical (`AppTimeLimits.kt:17–20` ↔ `SettingsStore.kt:78–82`);
`decodeWeekly` requires exactly 7 ints (REF `AppTimeLimits.kt:47–51` ↔ OUR `decodeWeeklyLimit`,
`SettingsStore.kt:102–106`).
- **PARTIAL (minor):** REF `readAll()` (`AppTimeLimits.kt:22–31`) returns only entries with `isSet`
  true; OUR has no `readAll` — `limitedPackages()` (`SettingsStore.kt:99–100`) returns **all keys**
  in both files unfiltered, and per-package reads go through `timeLimitFor`. Any stale non-positive
  entry would be enumerated by ours but filtered by the original. **NEW.**
- Improvement (deliberate, documented in code): decode failures are logged in ours
  (`SettingsStore.kt:27–30` header) where REF fails silently.
**EQUIVALENT** for read/write of a single package; PARTIAL only on bulk enumeration.

### 2.2 `data/AppTimeWindows.kt` (L1–105) vs `SettingsStore.kt:110–182`
Literal match: `app_time_windows` / `app_weekly_time_windows` (`AppTimeWindows.kt:12–13` ↔
`SettingsStore.kt:37–38`); JSON shape `[{"s":…,"e":…}]` minutes-of-day (REF encode `AppTimeWindows.kt:30–39`
↔ OUR `encodeWindowArray` `SettingsStore.kt:152–158`); weekly = JSON array of exactly 7 day-arrays
(REF `AppTimeWindows.kt:50–71` ↔ OUR `SettingsStore.kt:160–182`); `read` weekly-wins precedence
(REF L73–76 ↔ OUR L110–114); `write` mutual-exclusion clearing identical (REF L89–104 ↔ OUR L116–131);
corrupt JSON → empty (REF L23–25) / null-weekly (REF L45–47), ours same outcomes plus a log line
(`SettingsStore.kt:144–147,172–175`). `readAll` has the same unfiltered-keys caveat as §2.1
(OUR `windowedPackages()`, `SettingsStore.kt:133–134`). **EQUIVALENT** (bulk-enumeration caveat as §2.1).

### 2.3 `data/AppGroupRepository.kt` (L1–151) vs `SettingsStore.kt:186–254` + channel (`PrivilegedChannelHandler.kt:280–286`)
Storage: REF `app_groups` prefs, key `groups`, JSON array (L19–20) ↔ OUR `PREFS_GROUPS`/`KEY_GROUPS`
(`SettingsStore.kt:39,55`). JSON per group: `id, name, packages[], limit, weeklyLimit?, windows[], weeklyWindows?`.
- **NEW — encode divergence:** REF **always** writes `"limit"` and adds `"weeklyLimit"` when per-day
  (`AppGroupRepository.kt:109–110`). OUR writes **either** `"weeklyLimit"` **or** `"limit"`, never both
  (`SettingsStore.kt:198–205`), and likewise `weeklyWindows` XOR `windows` (L206–211) where REF always
  writes `"windows"` plus optional `"weeklyWindows"` (L111–112). Consequence: data written by ours in
  per-day mode would crash the *original's* decoder (`obj.getInt("limit")`, `AppGroupRepository.kt:143`)
  and lose **all** groups; the original's format decodes fine in ours. Internal-only risk (different
  applicationId, no shared data), but the schema is not the mirror the code claims.
- Decode: REF `getInt("limit")` throws → whole list lost (L118–150); OUR uses `optInt("limit", 0)`
  (`SettingsStore.kt:245`) — strictly more forgiving. Weekly size-7 validation identical
  (REF L136–138 ↔ OUR L237–239). Legacy daily-only groups decode in both. ✔
- **Repository API missing:** REF offers granular, invariant-preserving operations —
  `createGroup` (UUID, L42–46), `deleteGroup` **which also deletes the group's `group_usage_stats`
  entry** (L48–51), `renameGroup` (L53), `setGroupTimeLimit` (L55–56), `setGroupTimeWindows` (L58–59),
  `setGroupPackages` / `setPackageGroup` enforcing **one-group-per-app** by stripping the package from
  every other group (L61–84), `getGroupForPackage` (L39–40), `getGroupUsage` (L86–89), plus a
  `@Volatile` in-memory cache (L23–37). OUR Kotlin exposes only whole-list `groups()` / `saveGroups()`
  (`SettingsStore.kt:186–215`) and `groupForPackage()` (L217–218); the channel replaces the entire list
  verbatim (`PrivilegedChannelHandler.kt:281–286` → `SettingsStore.saveGroups`). Therefore in ours:
  (a) the one-group-per-app invariant is **not enforced in the data layer at all** — it depends entirely
  on Dart UI discipline in `setGroups` (`privileged_channel.dart:661–666`); (b) **deleting a group does
  not delete its `group_usage_stats` entry** — orphaned usage survives (OUR `SettingsStore.kt` has
  `groupUsageMs/addGroupUsage` L280–285 but no per-group delete); (c) no cache (perf only).
  (a) and (b) are **NEW**.
**PARTIAL.**

### 2.4 `data/AppRepository.kt` (L1–241) vs `DeviceOwnerManager.kt` (enumeration/DPM) + `SettingsStore.kt` + `privileged_channel.dart`
REF is a singleton aggregating PackageManager + DPM + five prefs files, with an app cache
(`AppRepository.kt:42–58,98–102`). Function-by-function:

| REF function | OUR counterpart | Verdict |
|---|---|---|
| `getApps(forceRefresh)` / `loadAppsFromSystem()` (L46–96): `MATCH_UNINSTALLED_PACKAGES`, excludes own pkg, per-pkg DPM probes degrade to `false`, sorted by lowercase name, merges limits (via AppTimeLimits), reopen (`reopen_times`), windows, `hasExplicitContent` from `app_ratings` | `DeviceOwnerManager.listInstalledApps` (`DeviceOwnerManager.kt:90–…`): same flags (`GET_META_DATA or MATCH_UNINSTALLED_PACKAGES`, L98–100), own-pkg excluded (L101), probes degrade to false but additionally gated on `owner &&` (L106–108) — without Device Owner the original still attempted probes; fields reduced per §1.5; **no cache** (every call re-enumerates; COMPLIANCE_AUDIT G2 already notes the Dart list can go stale) | PARTIAL |
| `invalidateCache()` / `updateCachedApp()` (L98–108) | ABSENT (no cache exists to invalidate) | PARTIAL (arch. difference) |
| `setAppHidden()` (L110–145): Android-14 false→true retry; **persists to `hidden_apps_prefs/hidden_packages` only on success**, invalidates cache on failure | Retry ported (`DeviceOwnerManager.kt:140–158`); success verified by re-read; hidden set written via `SettingsStore.setHiddenPackage` (`SettingsStore.kt:338–345`, same prefs/key L46,56) | EQUIVALENT (Part 1 owns DPM detail) |
| `reapplyHiddenIfNeeded()` (L147–165) | Not in the data layer of ours (no `reapplyHidden` symbol in `SettingsStore.kt`/`DeviceOwnerManager.kt` grep) | MISSING in this layer (may live in Part 1/4 scope) **NEW** |
| `getApp(pkg)` (L167–169) | No single-app fetch; Dart filters `listInstalledApps` results | PARTIAL (trivial) |
| `setAppSuspended()` (L171–177): DPM + cache + **logs `MANUAL` on suspend** | Channel `setAppSuspended` with explicit `reason` param (`privileged_channel.dart:496–513`); logging done by Kotlin call sites (COMPLIANCE_AUDIT F27) | EQUIVALENT (shape differs) |
| `setUninstallBlocked()` (L179–182) | `PrivilegedChannel.setUninstallBlocked` (`privileged_channel.dart:515–519`) | EQUIVALENT |
| `setAppTimeLimit/getAppTimeLimits` (L184–189) | `SettingsStore.setTimeLimit/timeLimitFor` (§2.1); no bulk getter | PARTIAL (see §2.1) |
| `getAppUsage(pkg, inMinutes)` from `internal_usage_stats` Long ms (L191–195) | `SettingsStore.usageMs/allUsage` (`SettingsStore.kt:270–278`); surfaced as aggregate `getUsageToday` (`privileged_channel.dart:591–592`), no per-package minutes conversion | EQUIVALENT (storage), PARTIAL (surface) |
| `setAppReopenTime/getAppReopenTime` on `reopen_times` (L197–206): `>0` put else remove | `SettingsStore.reopenSeconds/setReopenSeconds` (`SettingsStore.kt:292–298`), same prefs (`PREFS_REOPEN`, L43), same rule | EQUIVALENT (enforcement deferred F11 — documented) |
| `setAppTimeWindows` (L208–211) | §2.2 | EQUIVALENT |
| `getApplicationRestrictions` / `setApplicationRestrictions(merge)` (L213–226) | `DeviceOwnerManager.kt:329–358` incl. merge semantics (L335–341) + verified re-read; Dart `privileged_channel.dart:536–554` | EQUIVALENT (stronger: verification) |
| `getAvailableRestrictions(pkg)` via `RestrictionsManager.getManifestRestrictions`, metadata pre-check (L228–240) | `DeviceOwnerManager.listRestrictionCapableApps` (`DeviceOwnerManager.kt:362–416`): iterates all apps, returns declared keys, optional `requiredKeys` all-of filter (L404) | EQUIVALENT for the capability question; per-package single query ABSENT (not needed by any Dart caller) |

Also: REF daily-reset of usage counters is the service's `checkDateReset()`; OUR data-layer equivalent
is `SettingsStore.resetUsageIfNewDay(today)` using a **new** `usage_meta/date` key
(`SettingsStore.kt:42,58,259–266`) — a store the original does not have (it tracked the date inside the
service). Storage addition, behaviourally equivalent. **NEW** (benign).

### 2.5 `data/BrowserRestrictionsManager.kt` (L1–150) — split / PARTIAL
REF responsibilities:
1. `getPossibleBrowsers()` (L15–64): two-pass intent resolution — `CATEGORY_APP_BROWSER`, then
   BROWSABLE http/https handlers **excluding deep-link-only apps** (filters with only specific data
   authorities, L51–55). `isBrowser(pkg)` (L66–68).
2. `getPossibleTorrentApps()` / `isTorrentApp()` (L70–112): magnet-scheme handlers + explicit
   `application/x-bittorrent` MIME / `.torrent` path / magnet scheme in filter, rejecting wildcards.
3. `supportsRestrictions(pkg)` (L114–122): manifest declares **both** `URLBlocklist` and
   `ForceGoogleSafeSearch`.
4. `applyRestrictions(installed)` (L124–149): reads `browser_prefs/blocked_lists_json`, unions all
   lists' `sites`, builds Bundle `{URLBlocklist: StringArray, ForceGoogleSafeSearch: true (only if
   installed)}`, applies to **every possible browser** with **`merge = true`**.

OUR:
- (3) is EQUIVALENT: `listRestrictionCapableApps(requiredKeys)` (`DeviceOwnerManager.kt:362–416`,
  all-of filter L404) driven from Dart with exactly `['URLBlocklist','ForceGoogleSafeSearch']`
  (`lib/ui/config_screens.dart:44–46`).
- (1) **MISSING**: no intent-based browser detection exists in ours; the UI's "browsers" are simply the
  restriction-capable apps. Any browser that handles web intents but declares no managed restrictions
  is invisible to ours (the original at least enumerated it, and F6's watcher used `isBrowser`).
- (2) **DEFERRED-DOCUMENTED (F19)** — no torrent detection (COMPLIANCE_AUDIT F19).
- (4) **PARTIAL — NEW semantic differences:** ours persists lists identically
  (`ConfigStore.getBlockedLists/setBlockedLists`, `config_store.dart:184–198`, same store/key/shape) but
  applies from the UI as `{'URLBlocklist': sites, 'ForceGoogleSafeSearch': true}` with
  **`merge: false`** (`lib/ui/config_screens.dart:141–142,161`) to **capable apps only**, always forcing
  SafeSearch. Differences vs REF: (i) merge=false **wipes any other managed restrictions** the browser
  already had, where REF merged; (ii) target set differs (capable-only vs all detected browsers);
  (iii) REF only sets `ForceGoogleSafeSearch` when `installed=true`, ours always sets it.
**PARTIAL overall.**

### 2.6 `data/SystemRestrictions.kt` (L1–83) vs `DeviceOwnerManager.kt:234–281`
- `recommendedKeys` — the same 4 `UserManager.DISALLOW_*` constants (REF `SystemRestrictions.kt:7–12` ↔
  OUR `recommendedRestrictionKeys`, `DeviceOwnerManager.kt:235–240`). ✔
- `additionalKeys` — the same 7 OEM/Knox strings (REF L15–23 ↔ OUR `DeviceOwnerManager.kt:242–252`). ✔
- Key discovery by reflection over static String fields named `DISALLOW_*/ALLOW_*/ENSURE_*`
  (REF L25–47 ↔ OUR `allRestrictionKeys()`, `DeviceOwnerManager.kt:254–269`), `otherKeys`/`allKeys`
  ordering (recommended first, rest sorted, distinct) reproduced (OUR L269,277–281). ✔
- **MISSING helpers (NEW):** REF `restrictionFieldNames` value→field-name map is used by
  `resourceNamesFor(key)` / `resourceNameFor(key)` (L58–70), `resolveStringRes(context,key)` (L72–77)
  (finds a human-readable string resource for a key, incl. `no_`↔`disallow_` aliasing) and
  `normalizeForSearch(text)` (L79–82, NFD diacritic-stripping for search). Ours returns only
  `{key, active, recommended}` (`DeviceOwnerManager.kt:277–281`; Dart `UserRestriction`,
  `privileged_channel.dart:136–147`) — **no label/description field and no search normalisation**
  exists in the data layer, so the restrictions UI can only show raw key strings.
**PARTIAL** (enumeration EQUIVALENT; presentation helpers MISSING).

### 2.7 `data/FocusMode.kt` (L1–546) + `data/FocusCycle` (L528–546) vs `focus.dart` + `config_store.dart:175–180`
REF is a **native, persisted, self-syncing** state machine on `focus_prefs` with individual typed keys:
config keys `focus_minutes` (25, clamp 5–120), `short_break_minutes` (5, 1–30), `long_break_minutes`
(15, 5–60), `cycles_before_long_break` (4, 2–8), `auto_start_focus=false`, `sound_enabled=true`,
`vibration_enabled=true`, `suspended_apps`/`suspended_groups`/`focus_restrictions` StringSets
(`FocusMode.kt:29–86,91–176`); session keys `phase, phase_start_rtc, phase_start_elapsed,
phase_duration, phase_boot_count, paused_remaining, pause_releases, completed_focus,
active_suspension, active_restrictions` (L77–86). Behaviour: `startFocus/skipBreak/pause(releaseApps)/
resume/stop` (L223–278), idempotent `sync()` advancing expired phases (L281–298), remaining time from
**elapsedRealtime + RTC + boot-count** so clock changes/reboots can't shorten a phase (L348–367),
claim/release bookkeeping so it never releases apps suspended by impulse/visual features (L370–480),
phase-end exact alarm (L488–501), DPM grant of its own `POST_NOTIFICATIONS` (L508–525).
`FocusCycle.next` (L528–546): FOCUS→(completed+1 ≥ cycles ? LONG_BREAK : SHORT_BREAK);
breaks→ FOCUS if autoStart else **WAITING**; LONG_BREAK completion resets completed to 0.

OUR is a **pure-Dart, UI-process** model:
- Config: one JSON blob under a single key `config` in `focus_prefs`
  (`config_store.dart:108,175–180`) with shape `{focusMinutes, breakMinutes, longBreakMinutes,
  cyclesBeforeLongBreak, suspendApps[], suspendGroups[], restrictions[]}` (`focus.dart:32–52`) —
  **a completely different storage schema** from REF's typed keys (no cross-compat; also note REF key
  `short_break_minutes` vs ours renamed concept `breakMinutes`).
- **NEW — config fields with no home:** `auto_start_focus`, `sound_enabled`, `vibration_enabled`
  (REF `FocusMode.kt:70–72,122–135`) appear **nowhere** in `FocusConfig` (`focus.dart:13–30`) or
  anywhere in `project/lib` (grep: no `autoStart`/`soundEnabled`). Auto-start is effectively hard-wired
  ON (see phases below), and phase-end sound/vibration alerts do not exist.
- Phases: REF `{FOCUS, SHORT_BREAK, LONG_BREAK, WAITING}` (`FocusMode.kt:47–54`) vs OUR
  `FocusPhase {idle, focus, breakTime, longBreak, paused, done}` (`focus.dart:11`). **WAITING is
  MISSING**: `advance()` from any break always enters `focus` (`focus.dart:130–135,142–152`), i.e. the
  original's "break ended, nothing suspended until user starts next focus (when auto-start is off)"
  state cannot be represented. Pause is a *phase* in ours but a *flag over* the current phase in REF
  (`FocusMode.kt:186,193–196`).
- **NEW — `resume()` changes phase:** REF `resume()` re-anchors the *same* phase with its remaining
  time (L246–260). OUR `FocusSession.resume()` **always re-enters `FocusPhase.focus`**, discarding a
  paused break (acknowledged in its own comment, `focus.dart:163–175`). A paused break therefore
  becomes focus time in ours.
- **NEW — cycle counting differs at the margins:** REF resets `completed_focus` when a LONG_BREAK
  finishes or is skipped (`FocusMode.kt:232,325,542–543`); OUR `nextPhase` uses
  `completed % cyclesBeforeLongBreak == 0` (`focus.dart:127–129`) and `advance()` never resets the
  counter (L149–150) — cadence is equivalent for uninterrupted runs but diverges after a skipped
  long break.
- **Timing basis:** REF remaining = elapsedRealtime-anchored, RTC only across reboot, boot-count
  checked (L348–364) — wall-clock manipulation cannot shorten a phase. OUR remaining =
  `phaseDuration − now.difference(phaseStartedAt)` on **wall-clock `DateTime` only**
  (`focus.dart:105–110`); moving the device clock forward ends a focus phase early. **NEW** for focus
  specifically (the analogous impulse/forced-removal limitation *is* documented in
  `app_controller.dart:5–11`, but that note does not mention focus).
- **Session persistence:** REF session state lives in `focus_prefs` and is re-synced by alarms,
  receivers and process start (`sync()` L281). OUR `FocusSession` is **not persisted at all** —
  `ConfigStore` has no session accessors (only `getFocusConfig/setFocusConfig`,
  `config_store.dart:175–180`); the session exists only in UI memory. Process death loses the running
  session (COMPLIANCE_AUDIT F25 documents "countdown runs only while the app process is alive" and
  no FGS/schedules; the claim/release cross-feature bookkeeping of REF L370–480 is likewise absent —
  ours suspends/releases via the UI's `_syncEffects`, per audit F25).
- Clamps: REF clamps every duration/cycles value on **both read and write** (L91–119). OUR
  `FocusConfig.fromJson` applies **no clamping** (`focus.dart:42–52`) — out-of-range values persist
  verbatim. **NEW.**
**PARTIAL** (defaults 25/5/15/4 match exactly, `focus.dart:15–18` ↔ `FocusMode.kt:33,37,41,45`;
core cycle works; the differences above are material).

### 2.8 `data/SuspensionLogRepository.kt` (L1–120) vs `SettingsStore.kt:349–381,418–427`
Storage identical: `suspension_logs_prefs` / `logs`, JSON array of
`{id, packageName, appName, timestamp, reason, details?}` (REF encode L80–94 ↔ OUR entry construction
`SettingsStore.kt:363–370`); newest-first (REF L61 ↔ OUR L371); dedupe same package+reason within
5 s against the most recent matching entry (REF L40–43 ↔ OUR L355–356); app label resolved via
PackageManager with package-name fallback (REF L45–51 ↔ OUR L357–362); `clearLogs` removes the key
(REF L72–78 ↔ OUR L379–381); unknown reason → `MANUAL` on decode (REF L107–111 ↔ `TimeModels.kt:117–118`).
- **NEW — cap differs:** REF `MAX_LOGS = 100` (`SuspensionLogRepository.kt:13`) vs OUR
  `MAX_LOGS = 500` (`SettingsStore.kt:60`). COMPLIANCE_AUDIT F27 mentions ours' 500 cap but not that
  the original's is 100.
- REF keeps a synchronized in-memory cache (L15–27); ours re-reads prefs per call and returns raw
  `JSONObject`s (`readLogs`, `SettingsStore.kt:418–427`) — perf/representation only.
**EQUIVALENT** except the cap (PARTIAL, minor).

### 2.9 `data/UsageWarningSettings.kt` (L1–70) vs `config_store.dart:200–223`
Storage: REF `usage_warning_prefs`, keys `enabled`/`stages` (`UsageWarningSettings.kt:12–14`) ↔ OUR
same store/key names via generic settings (`config_store.dart:109,202–222`). Stage JSON keys
`{id, minutes, type, vibrationCount}` in REF (L58–69); ours writes `{minutes, type, vibrationCount}`
— **no `id`** (§1.8).
- Defaults stages are numerically identical: 15 SILENT / 5 SOUND / 1 VIBRATE×1 / 0.5 VIBRATE×3
  (REF `defaultStages()` L21–26 ↔ OUR `defaultUsageWarningStages`, `config_store.dart:94–99`).
- **NEW — `enabled` default is inverted:** REF `DEFAULT_ENABLED = true` (`UsageWarningSettings.kt:16`);
  OUR `getUsageWarnings` computes `enabled = (await getSetting(...) == true)` (`config_store.dart:202–203`),
  i.e. **false when never written**. A fresh install of ours has warnings OFF until the user opens and
  saves the screen; the original has them ON.
- **NEW — seeding behaviour differs:** REF `loadOrSeedStages` **persists** the defaults on first load
  (L28–33); ours returns defaults unpersisted (L216). Also REF decode of corrupt JSON → defaults (L53–55)
  and empty-string → empty list (L37); ours: unparseable/missing → defaults (L204–216), but a stored
  empty list round-trips as empty. ✔ mostly.
- **NEW — validation constants absent:** REF `MIN_MINUTES_BEFORE=0.1`, `MAX_MINUTES_BEFORE=180`,
  `MAX_VIBRATION_COUNT=10` (`UsageWarningSettings.kt:17–19`) have no counterpart in `config_store.dart`
  or the channel; stage values are stored unclamped.
- Delivery (notifier/receiver) is out of this layer; storage-side classification only.
  (COMPLIANCE_AUDIT F12 already documents that notifications are not fired — DEFERRED v1.1 delivery.)
**PARTIAL** (storage shape/defaults mostly match; enabled-default inversion is the substantive bug).

### 2.10 `data/VisualBlockingSettings.kt` (L1–35) — no counterpart
Constants inventoried: prefs `visual_blocking_prefs`; keys `enabled, target_packages, categories,
threshold, suspend_enabled, suspend_block_count, suspend_window_minutes, suspend_duration_minutes`
(L11–24); defaults: targets `{com.reddit.frontpage}`, categories `{hentai, porn, sexy}`,
threshold `0.5f`, suspend count 5 / window 15 min / duration 30 min (L26–31);
`SELECTABLE_CATEGORIES` = detector labels minus `"neutral"` (L34).
OUR: nothing in the data layer (no store, key or Dart model). **DEFERRED-DOCUMENTED (F16/F17)** —
COMPLIANCE_AUDIT F16/F17 verified absence, no placeholder.

### 2.11 `data/VisualBlockingSuspensionTracker.kt` (L1–114) — no counterpart
Class (not object) on prefs `visual_blocking_suspensions`, keys `hits_<pkg>` (CSV of wall-clock hit
timestamps) and `until_<pkg>` (Long deadline) (L109–113). API: `registerBlock(pkg, requiredHits,
windowMinutes, now)` — sliding-window filter, `takeLast(hitsNeeded)`, fires + clears counter at
threshold (L34–56); `clearBlocks` (L58); `startSuspension(pkg, durationMinutes) → deadline`, also
clears hits (L65–76); `endSuspension` clears both keys (L84–87); `isSuspended(pkg, now)` (L89–90);
`activeSuspensions()` incl. expired (L93–101). Deadlines are wall-clock deliberately (survive reboot,
clock-backwards fails safe, L19–21).
OUR: ABSENT entirely. **DEFERRED-DOCUMENTED (F17)** (depends on F16).

### 2.12 `data/ColorFilterSettings.kt` (L1–117) + `data/ColorFilterController.kt` (L1–156) — no counterpart
Settings: prefs `color_filter_prefs`; keys `enabled`, `modes` (StringSet of mode names),
`windows_<MODE>`, `scope_<MODE>`, `excluded_apps_<MODE>`, `only_apps_<MODE>`,
`night_light_overlay_intensity` (default 5, max 60), `night_light_temperature` (default 3200; presets
1800/2000/2500/2700/3200/4000), `extra_dim_level` (default 50), legacy key `windows`
(`ColorFilterSettings.kt:12–31`). Behaviour: `migrate()` copies legacy shared windows into every
mode lacking its own, then deletes the legacy key (L34–42); defaults: enabled=false, modes={GRAYSCALE},
scope=DEVICE (L21,44,49–52); `scheduledModes/modesToApply/dependsOnForegroundApp/scheduledWindows/
millisUntilNextBoundary` scheduling math (L82–116).
Controller: writes `Settings.Secure` keys `accessibility_display_daltonizer_enabled/_daltonizer`
(mode `"0"` = monochromacy), `accessibility_display_inversion_enabled`, `night_display_activated/
_color_temperature`, `reduce_bright_colors_activated/_level` (L17–23,63–83); saves user's originals in
`color_filter_state` (`saved_keys` + `previous_<key>`) and restores on `release()` (L30–32,85–128);
`hasPermission` = `WRITE_SECURE_SETTINGS` held (L45–46); `grantPermissionViaShizuku` via
`pm grant … WRITE_SECURE_SETTINGS` (L48–59); night-temperature clamped to platform range (L131–135);
`platformNightLight` from `config_nightDisplayAvailable` (L40); `observedUris` for tamper reversion (L42–43).
OUR: no counterpart in the data layer or elsewhere (COMPLIANCE_AUDIT F26 grep-verified absence).
The prerequisite `grantWriteSecureSettings` channel method *does* exist in ours (documented in the
audit's Shizuku table), but no colour-filter store/controller consumes it.
**DEFERRED-DOCUMENTED (F26).**

### 2.13 `data/FocusScheduleStorage.kt` (L1–84) + `data/FocusScheduleManager.kt` (L1–95) — no counterpart
Storage: prefs `focus_schedules_prefs`, key `schedules`, JSON `[{id, days:[…], h, m, en}]`
(`FocusScheduleStorage.kt:10–11,50–83`); CRUD `getSchedules/saveSchedules/addOrUpdateSchedule/
deleteSchedule/toggleSchedule`, every mutation calls `FocusScheduleManager.reschedule` (L13–48).
Manager: single exact alarm for the earliest enabled schedule's `nextTriggerMillis`
(`SCHEDULE_ALARM_REQUEST_CODE=0x0F0C10`), `setExactAndAllowWhileIdle` when permitted else inexact
(L18–38); 5-minute snooze alarm (`0x0F0C11`, `SNOOZE_DELAY_MILLIS=300_000`) (L16,40–57);
`launchReminder` via full-screen-intent notification + direct activity start (L59–75).
OUR: the prefs file name exists only as an allowlisted generic store
(`SettingsStore.kt:51,392–395`) that **nothing reads or writes** (grep: no Dart or Kotlin user) —
exactly COMPLIANCE_AUDIT G1's observation. No storage, no alarm, no model (§1.9).
**DEFERRED-DOCUMENTED (F25 schedules).**

### 2.14 `data/ReadingPassages.kt` (L1–423) — corpus comparison only (no text reproduced)
REF structure: `ReadingPassage(text, source)` (L7); `BuiltInPassage(textEn, sourceEn, textPt, sourcePt)`
with `resolve(portuguese)` (L10–18); `ReadingLibrary` (L31–54) with `passages(ctx, source, portuguese)`,
`availableCount(ctx, source)`, `pick(ctx, portuguese)` = shuffled take of the configured count.
Corpus: **60 built-in passages — 20 BIBLE (L55–177), 20 QURAN (L178–300), 20 QUOTES (L301–423) — each in
two languages (EN + PT)**, i.e. 120 texts, drawn from named published translations (header L20–30).
Source selection and count are settings: `reading_source` (default `BIBLE`) and `reading_count`
(default 5, min 1) in `security_prefs` (original `SecurityManager.kt:181–204`); CUSTOM source reads
`reading_custom_passages` as a JSON array of **`{text, source}` objects** (`SecurityManager.kt:209–229`).
OUR (`lib/domain/challenges.dart:134–193`, `config_store.dart:138–147`):
- `ReadingPassage(title, text)` (L136–141) — field named `title`, no `source`/attribution field.
- `samplePassages`: **5 passages, English only, originally written for the rebuild** (L143–185;
  header L7–9 and COMPLIANCE_AUDIT F22 document the deliberate non-copying of the corpus).
- **NEW — no source selection and no count setting:** nothing in ours reads/writes `reading_source`
  or `reading_count` (grep over `project/lib`: 0 hits); `ReadingChallenge.requiredPassages` is a
  constructor parameter defaulting to 5 (L188–193), matching REF's *default* count only.
- **NEW — custom-passage schema differs under the same key:** REF `reading_custom_passages` =
  `[{"text":…,"source":…}]`; OUR `getCustomReadingPhrases/setCustomReadingPhrases` store a JSON
  array of **plain strings** (`config_store.dart:138–147`) in the same `security_prefs` key. The two
  formats cannot read each other's data.
**PARTIAL** (mechanic equivalent; corpus size/approach and settings surface reduced — corpus decision
documented, settings/schema gaps NEW).

### 2.15 `data/PlayStoreRatingFetcher.kt` (L1–98) — EXCLUDED-DOCUMENTED (F20), API inventoried
`AppRatingInfo(packageName, title?, contentRating?, descriptorLines, descriptorsAvailable,
hasExplicitContent, hasUnrestrictedInternet=false)` (L8–16). `fetch(packageName)` (L30–81): Jsoup GET
`https://play.google.com/store/apps/details?id=<pkg>&hl=en&gl=BR`, desktop-Chrome UA (L23–25),
15 s timeout (L33–36); rating extracted from `application/ld+json` `contentRating` (L41–52), falling
back to `span[itemprop=contentRating]` (L55) then the content-rating image's sibling box (L57–62);
descriptors via `extractContentRatingDescriptors` (L83–97); `hasExplicitContent` = any descriptor
containing `Nudity`/`Explicit Sex`/`Sexual Content` (L20,65–67); `hasUnrestrictedInternet` similarly (L21,68–70).
Downstream cache `app_ratings` (Boolean/pkg) lives in the service/AppRepository (§2.4).
OUR: no fetcher, no Jsoup-equivalent, no network code; the only trace is the reserved always-`null`
`hasExplicitContentRating` (§1.5). **EXCLUDED-DOCUMENTED (F20)** — matches COMPLIANCE_AUDIT F20 and
ARCHITECTURE rationale (brittle HTML scrape, no official API).

### 2.16 `data/ApkUpdateInstaller.kt` (L1–406) — EXCLUDED-DOCUMENTED (F29), API inventoried
Object on `security_prefs` staging keys `apk_update_restore_restrictions / _uninstall_blocked /
_suspended / _hidden` (L28–32); intent extras `EXTRA_PACKAGE / EXTRA_IS_DOWNGRADE /
EXTRA_DOWNGRADE_SESSION_ID` (L24–26). Sealed `Inspection` (L44–56): `Update(file, packageName, label,
icon, installedVersion, newVersion, isDowngrade=false)`, `NewApp`, `Invalid`.
Public API: `isUnknownSourcesRestricted(ctx)` (L63–…), `inspect(ctx, uri)` — copies the picked APK to
`cacheDir/apk_update/`, rejects not-installed packages as `NewApp` (L76–106); `install(ctx, update)` —
`PackageInstaller` full-install session, downgrade path via uninstall-first when needed (L108–162);
`commitDowngradeSession` (L163), `abortDowngradeSession` (L177), `onInstallFinished` (L183),
`requestDowngrade` (internal, reflective `installFlags`, L196–…), `isFreshInstall` (L340),
`uninstall(ctx, pkg)` via result receiver (L345), `restoreUnknownSourcesRestrictionsIfIdle` (L333).
Private machinery: `liftUnknownSourcesRestrictions` (temporarily clears the unknown-sources restriction
set ± `DISALLOW_UNINSTALL_APPS`, recording them for restore, L357–…), `savePreDowngradeState` /
`restorePreDowngradeState` (preserves uninstall-blocked/suspended/hidden across the downgrade
uninstall+reinstall, L246–316), `restoreUnknownSourcesRestrictions` (L317), `needsUninstallForDowngrade`
(system/updated-system/debuggable analysis, L221–245), `installedInfo` (L374).
OUR: **no counterpart whatsoever** — no `PackageInstaller` use, no `apk_update` staging, no
restore-state keys (COMPLIANCE_AUDIT F29 grep-verified absence). **EXCLUDED-DOCUMENTED (F29)**
deliberate security decision (unauthenticated lock-screen installer not reproduced).

---

## 3. Cross-cutting storage-schema verdict

| Prefs file | REF owner | OUR | Schema match |
|---|---|---|---|
| `app_limits` / `app_weekly_limits` | AppTimeLimits | SettingsStore L35–36 | ✔ identical (Int / CSV-7) |
| `app_time_windows` / `app_weekly_time_windows` | AppTimeWindows | SettingsStore L37–38 | ✔ identical (`[{s,e}]`) |
| `app_groups` (`groups`) | AppGroupRepository | SettingsStore L39,55 | ⚠ decode-compatible one way; encode drops the always-present `limit`/`windows` keys (§2.3) **NEW** |
| `internal_usage_stats` / `group_usage_stats` | Service/AppRepository | SettingsStore L40–41 | ✔ identical (Long ms); ours adds `usage_meta/date` **NEW** (benign) |
| `reopen_times` | AppRepository | SettingsStore L43 | ✔ identical |
| `hidden_apps_prefs` (`hidden_packages`) | AppRepository | SettingsStore L46,56 | ✔ identical |
| `suspension_logs_prefs` (`logs`) | SuspensionLogRepository | SettingsStore L47,57 | ✔ shape identical; cap 100 → 500 **NEW** |
| `browser_prefs` (`blocked_lists_json`) | BrowserRestrictionsManager | config_store.dart:107,185 | ✔ identical |
| `usage_warning_prefs` (`enabled`,`stages`) | UsageWarningSettings | config_store.dart:109,202–222 | ⚠ stage JSON loses `id`, type case differs, `enabled` default inverted (§2.9) **NEW** |
| `focus_prefs` | FocusMode (typed keys) | config_store.dart:108 (`config` JSON) | ✘ completely different schema (§2.7) |
| `focus_schedules_prefs` (`schedules`) | FocusScheduleStorage | allowlist only, unused | ✘ no data ever stored (DEFERRED F25) |
| `visual_blocking_prefs` / `visual_blocking_suspensions` | VisualBlocking* | — | ✘ absent (DEFERRED F16/F17) |
| `color_filter_prefs` / `color_filter_state` | ColorFilter* | — | ✘ absent (DEFERRED F26) |
| `security_prefs` (`reading_custom_passages`) | SecurityManager | config_store.dart:139 | ⚠ same key, different JSON shape (objects vs strings) (§2.14) **NEW** |
| `security_prefs` (`access_challenges`) | SecurityManager (StringSet) | config_store.dart:127 (JSON String) | ⚠ same key, different stored type (noted for Part 3; flagged here because ConfigStore is in this scope) **NEW** |

**Every original stored field has a home in ours?** No. Fields with **no home anywhere** in the rebuild's
data layer: focus `auto_start_focus`, `sound_enabled`, `vibration_enabled` and all ten native focus
session keys (§2.7); usage-warning stage `id` (§1.8); all colour-filter keys (§2.12); all
visual-blocking keys (§2.10–2.11); focus-schedule entries (§2.13); reading `reading_source` /
`reading_count` (§2.14). Of these, only the colour/visual/schedule absences are documented (as whole
features); the focus config trio, warning-stage `id`, and reading settings are **NEW** gaps inside
features the audit counts as implemented.

---

## 4. Summary counts (this part)

| Classification | Files/models |
|---|---|
| EQUIVALENT | TimeLimit, TimeWindow, AppGroup (model), BlockedList, SuspensionLogEntry/Reason, AppTimeLimits (single-pkg), AppTimeWindows |
| PARTIAL | TimeWindows (trivial), AppItem, UsageAlertStage, AppGroupRepository, AppRepository, BrowserRestrictionsManager, SystemRestrictions, FocusMode, SuspensionLogRepository (cap), UsageWarningSettings, ReadingPassages |
| MISSING (in-layer) | `AppRepository.reapplyHiddenIfNeeded`, SystemRestrictions label/search helpers, BrowserRestrictionsManager browser detection |
| DEFERRED-DOCUMENTED | FocusSchedule + FocusScheduleStorage/Manager (F25), ColorFilterMode/Scope/Settings/Controller (F26), VisualBlockingSettings (F16), VisualBlockingSuspensionTracker (F17), torrent detection (F19) |
| EXCLUDED-DOCUMENTED | PlayStoreRatingFetcher (F20), ApkUpdateInstaller (F29) |
