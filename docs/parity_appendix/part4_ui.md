# Parity Audit — Part 4 of 5: UI Screens + ViewModels (Behavioral Mapping)

**Date:** 2026-11-09 · **READ-ONLY audit — no project code was edited.**
**Source of truth:** DeChainer v1.12.0 Jetpack Compose sources at
`reference/dechainer-zip/dechainer-1.12.0/app/src/main/java/io/github/warleysr/dechainer/`
(cited as bare filenames, e.g. `AppsTab.kt:131`).
**Ours:** Flutter/Dart at `project/lib/` (cited as `lib/...` paths with line numbers).
**Context docs (verified against, not copied):** `project/docs/COMPLIANCE_AUDIT.md` (cited **CA**) and `analysis/DECHAINER_FEATURES.md` (cited **DF**, F-numbers).
**NEW** = a gap/behavior difference found by this audit that is **not** disclosed in CA or DF. This matters most where CA claims a feature "Implemented, device-untested" — several such claims are overstated at the user-behavior level (see §0).

**Method:** the comparison unit is *behavior* — controls, validations, dialogs, gating, state logic — not code shape. Classifications: **EQUIVALENT** / **PARTIAL** (missing pieces named) / **MISSING** / **DEFERRED-DOCUMENTED** (F-number) / **EXCLUDED-DOCUMENTED**. Out of scope (part 5): Recovery*, ApkUpdateDialog, ChallengeRunner, PendingChange UI.
Own cross-checks by the coordinator: `AppController.lastEvent` is written (`lib/app_controller.dart:61`) and never read anywhere; theme selector is genuinely wired (`lib/ui/config_tab.dart:192-204` → `setThemeMode`, `lib/app_controller.dart:114`); focus-schedules tile is an honestly disabled placeholder (`lib/ui/impulse_focus_screens.dart:624-626`).

---

## 0. Headline results

1. **No screen or ViewModel in scope is fully EQUIVALENT.** Every non-deferred item is PARTIAL.
2. **Worst single divergence:** the Dart `AppRestrictionsScreen` is a *different feature in effect* from the original — a raw editor of currently-set key/values, with none of the original's declared-restrictions model, draft/Save flow, search, filters, type editors (choice/multi-select/bundle/bundle-array), or clear-all — and it exposes the `URLBlocklist` key the original deliberately hides (§5). CA F4 calls it simply "Implemented, device-untested" — **overstated, NEW**.
3. **Recovery-gate regressions (all NEW, none in CA):** group member removal is *completely ungated* (§3); reopening-cooldown decrease is not gated (§2d); per-app/group windows loosening is computed on daily windows only while saved weekly windows can be silently dropped (§2e); tightening limits/windows gets no 5-second undo (§2d); the entire Impulse config screen has *no session gating on any edit* (§16); keyboard shuffle→normal is ungated (§4); focus duration/app changes are ungated (§21).
4. **Dead / inert Dart controls exist** — consolidated in §28. Worst: the group-limit editor's reopening-cooldown field is displayed, editable, and silently discarded on save.
5. **Documented deferrals check out as genuinely absent, not stubbed:** F18 (§1), F26 (§19), F16/F17 (§13), focus schedules (§24), Tetris (§16/§22).

### Classification summary

| Item | Class | Item | Class |
|---|---|---|---|
| ActivityBlockerScreen (F18) | DEFERRED-DOCUMENTED | UsageWarningScreen (F12) | PARTIAL (delivery deferred-doc.) |
| AppsTab | PARTIAL | VisualBlockingScreen (F16/F17) | DEFERRED-DOCUMENTED |
| AppGroupDialogs | PARTIAL | AppPickerDialog (common) | PARTIAL (degraded, re-implemented 4×) |
| AppManagementDialogs | PARTIAL | FocusGroupPickerDialog | MISSING (UI) + dead model field |
| AppRestrictionsScreen (F4) | PARTIAL — different feature in effect | FocusRestrictionsDialog | MISSING (UI) + dead effect path |
| BlockedWordsScreen | PARTIAL | FocusScheduleDialog | DEFERRED-DOCUMENTED (labelled tile) |
| BrowserRestrictionsScreen (F5) | PARTIAL | FocusSessionCard | PARTIAL |
| ColorFilterScreen (F26) | DEFERRED-DOCUMENTED | NoDeviceOwnerPrivileges | PARTIAL (near-equivalent) |
| ConfigTab | PARTIAL | UsageLimitsOverview | PARTIAL |
| FocusModeScreen (F25) | PARTIAL | Theme (Color/Theme/Type) | PARTIAL — deliberate documented redesign |
| ImpulseLockScreen (F21) | PARTIAL | ViewModels (12) | 3 DEFERRED-DOCUMENTED, 9 PARTIAL, 0 EQUIVALENT |

---

# A. screens/tabs/

## 1. ActivityBlockerScreen.kt — F18 — **DEFERRED-DOCUMENTED**

Original controls/behaviors:
- Header "Blocked activities" + **Add** IconButton `ActivityBlockerScreen.kt:50-56`.
- Blocked list rows: class-name text + **Delete** IconButton; delete via `recoveryGate.run{…}` — *always* session-gated, not loosening-conditional `:60-72`.
- **Add dialog**: `OutlinedTextField` (activity-name hint), Confirm/Cancel; Confirm acts only if `isNotBlank()`, via `recoveryGate.change(loosening=false)` `:90-117`.
- "Accessed activities" section: live log grouped by package via `viewModel.getGroupedAccessedActivities()` `:74-86`.
- `ActivityLogAccordion`: app icon (32dp), appName, packageName, expand/collapse chevron `:122-152`; each logged className row has a **Copy** button → clipboard `:154-176`.
- `RecoveryGateDialog(recoveryGate)` mounted `:119`.

Dart: **ABSENT** — grep `blockedActivit*/accessedActivit*` in `lib/` = 0 hits. Only a disabled placeholder tile `lib/ui/config_tab.dart:176-180` ("Activity blocker / Blocking specific activity screens ships in v1.1."), rendered `enabled:false` at `lib/ui/common.dart:333-339` — an honestly-labelled non-control, **not** a dead control. Documented: CA §2 F18 "Deferred v1.1" and CA **G1** (native service enforces `SettingsStore.blockedActivities()` and keeps the accessed-activities log, but there is no setter, channel method, or UI — half-wired native). Every control above is missing-by-deferral, not a new gap.

## 2. AppsTab.kt — **PARTIAL** (F8/F9/F10 core present; several semantics NEW-missing)

### 2a. Shell / list
| Behavior | Original | Dart | Verdict |
|---|---|---|---|
| NoDeviceOwner gate | `if(!isDeviceOwner) NoDeviceOwnerPrivileges else AppsScreen` `AppsTab.kt:76-80` | No `isDeviceOwner` check anywhere in `lib/ui/apps_tab.dart` (grep 0); tab always calls `listInstalledApps` (`apps_tab.dart:47`) and shows generic `ErrorView` `:117-119` | **MISSING — NEW.** Effect: non-owner gets an error/retry loop, not the explanatory redirect. (CA documents this state only for RestrictionsTab, F3.) |
| Search (name or package, case-insensitive) | `AppsTab.kt:131-140,114-115` | `apps_tab.dart:80-87,65-72` | EQUIVALENT |
| Overflow menu: "Show system apps" checkbox, "Manage groups", "Suspension logs" | `AppsTab.kt:141-176` | No overflow menu; system apps = always-visible `SwitchListTile` `:89-96`; Groups = always-visible `ListTile` `:97-110`; **suspension-logs shortcut ABSENT** (logs only via `lib/ui/config_tab.dart:163-169`) | PARTIAL — NEW |
| System-app filtering | Client-side *with exceptions*: system apps hidden **unless** hidden/uninstall-blocked/has limit/has windows/in restricted group `AppsTab.kt:109-113` | Server-side flag only: `listInstalledApps(includeSystem:_includeSystem)` `:47` — a restricted system app is invisible with switch off; with it on, *all* system apps flood in | PARTIAL, effect differs — NEW |
| Sort: restricted apps (limit/windows/group) first | `AppsTab.kt:119-121` | No sorting; channel order `:65-72,128-149` | MISSING — NEW |
| Group filter chips ("All" + per-group `FilterChip`, only if groups exist) | `AppsTab.kt:179-201,116-117` | ABSENT (grep confirms) | MISSING — NEW |
| Loading | spinner `AppsTab.kt:205-208` | `LoadingView` `:119` + pull-to-refresh `:126-127` (extra, harmless); stale list per CA G2 | EQUIVALENT (+DOC G2) |
| App icon | real bitmap 40dp `AppsTab.kt:461-467` | Generic `Icon(Icons.android)` for every app `apps_tab.dart:134` | PARTIAL (cosmetic) — NEW |

### 2b. AppRow content
- Original: name, packageName, **group label** `AppsTab.kt:413-419`, **app limit + used** `:421-428`, **group limit + group used** `:430-437`, **effective windows (group ∩ app)** summary `:439-450`, **explicit-content (18+) badge** `:452-458`, status chips Blocked/Protected/Suspended `:469-493`.
- Dart row (`apps_tab.dart:133-146`): label, package, text-joined `system · hidden · suspended · uninstall blocked`, per-app used-today only (`_usage?.packages`, `:132,142`).
  - Group label: **MISSING — NEW**. Group limit/used: **MISSING** (channel parses `UsageToday.groups`, `lib/data/privileged_channel.dart:198-218`, but no UI reads it — dead data, §28).
  - Effective-windows summary: **MISSING — NEW**. Status badges: PARTIAL-equivalent (same facts, plain subtitle text).
  - Explicit-content badge: **EXCLUDED-DOCUMENTED** (CA F20). Dart parses `hasExplicitContentRating` (`privileged_channel.dart:103,112,121`) but never renders it and Kotlin always emits `null` — dead *field*, not a dead control.

### 2c. AppActionDialog wiring (see also §4)
Original dialog (`AppsTab.kt:509-595`), 7 rows: **Group** (current group name) `:554-558`, **Set time limit** `:559-563`, **Time windows** `:564-568`, **Manage app restrictions** `:569-573`, divider, **Suspend/Unsuspend** `:577-581`, **Prevent/Allow uninstall** `:582-586`, **Block/Unblock** (hide) `:587-591`. Hide/uninstall/suspend each `recoveryGate.change(loosening = currentOnState)`, then dialog **dismisses** (`AppsTab.kt:218-254`; duplicate host `AppManagementDialogs.kt:36-73`). ManageRestrictions first fetches available restrictions, **filters out `URLBlocklist`**, and if empty shows a **"No restrictions available" AlertDialog** instead of navigating (`AppsTab.kt:244-252`; `AppManagementDialogs.kt:62-71,105-116`).

Dart `AppManagementSheet` (`apps_tab.dart:162-335`): Suspended/Hidden/Uninstall-blocked as 3 `SwitchListTile`s `:238-285`, gated via `_toggleProtection` (ON = tightening + 5s undo, OFF = `runLoosening`) `:194-224` — EQUIVALENT in effect, except the sheet **stays open** showing natively-verified state instead of dismissing (a difference, arguably better). Time limit `:287-298`, Windows `:299-309`, Managed restrictions `:310-322` present.
- **Group assignment row: MISSING** — no group row, no current-group display, no picker entry (§3). **NEW** (CA F13 claims "groups CRUD" without noting this).
- **No-restrictions pre-check/dialog: MISSING** — Dart always navigates; §5's screen then conflates "app declares none" with "none set yet". **NEW.**
- ⚠️ **Dead guard:** `bool _busy=false` at `apps_tab.dart:174` is read to disable all three switches (`:242,261,274`) but **never assigned in this class** (only assignments in the file are in `AppRestrictionsScreen` at `:856,864`). Switches are never busy-disabled; rapid double-toggles unguarded. **NEW** (§28).

### 2d. TimeLimitDialog + reopening (see also §10)
Original `TimeLimitDialog` (`AppsTab.kt:620-659`) = `TimeLimitEditor` + reopening section. Editor detail in §10. Reopening `SecondInputField` (`AppsTab.kt:736-780`): **−15/+15 buttons** (minus clamps ≥0), digits-only field, **no upper clamp**. Confirm loosening test: `isLooserLimit(old,new) || reopeningSeconds < oldReopening` (`AppsTab.kt:260-266`; `AppManagementDialogs.kt:79-86`).

Dart (`apps_tab.dart:405-528`): free-text minutes; invalid/empty silently parses to `0` = *no limit* via `_parse` `:448`; clamped `0..1440` on Save `:508-520` (original wheels cap at 23h59 = 1439 and cannot produce invalid values). Reopen field plain text, clamped `0..86400` `:492-499,508`; **no −15/+15 steppers** — PARTIAL, NEW.
- ⚠️ **Gate bypass — NEW, serious:** `_editLimit` computes loosening from `Loosening.isLooserLimit(...)` **only** (`apps_tab.dart:348-353`) and ignores `result.reopen`. *Decreasing the reopening cooldown alone no longer requires a recovery session.* (Cooldown *enforcement* is DEFERRED-DOCUMENTED, CA F11, and the field is honestly labelled `:496` — the *gate* regression is not documented.)
- ⚠️ **Tightening loses the 5-second undo — NEW:** original `change(loosening=false)` schedules with a 5s undo snackbar (`RecoveryGate.kt:58-68`, cited via part-5 file only as behavioral reference); Dart `_editLimit`/`_editWindows` tightening branches just `save()` (`apps_tab.dart:366-372,393-399`). Only the three protection toggles get undo in Dart.

### 2e. TimeWindowsDialog (see also §11)
Dart `TimeWindowsEditor` (`apps_tab.dart:530-610`) is **daily only** (title literally "Allowed windows (daily)" `:570`) — per-weekday per-app windows are PARTIAL/DOC-DOCUMENTED (CA F10).
- ⚠️ **Potential silent data loss — NEW:** the sheet loads enforcement including `weeklyWindows` (`privileged_channel.dart:618-621`), but `_editWindows` opens the editor with `current.dailyWindows` only (`apps_tab.dart:379`), computes loosening on daily windows only (`:382-385`), and saves via `setTimeWindows(dailyWindows: result)` (`:387`), whose channel implementation omits `weeklyMinutes/weeklyWindows` keys when null (`privileged_channel.dart:644-652`). An app that already has per-weekday windows can have them replaced/dropped by a daily-only save, with no loosening check on the weekly part.

## 3. AppGroupDialogs.kt — **PARTIAL** (rename, group windows, per-app picker, member-removal gate missing — mostly NEW)

Originals:
- **GroupsManagementDialog** `:54-115`: list (tap → select/edit); row = name, `group_apps_count`, limit summary (primary colour), windows summary (tertiary) `:70-99`; empty state `:66-67`; **New group** `:103-108`; Close as confirm `:111-113`.
- **CreateGroupDialog** `:117-145`: name field; **Confirm disabled while name blank** `:137`; passes `name.trim()`.
- **GroupTimeLimitDialog** `:147-171`: `TimeLimitEditor` only — **no reopen field**.
- **EditGroupDialog** `:173-317`: **editable name field (rename)** `:195-201`; **Time-limit button** → GroupTimeLimitDialog `:205-213,282-292`; **Time-windows button** → TimeWindowsDialog `:214-221,294-304`; Members header + **Add** → `AppPickerDialog` `:223-234,306-316`; member rows icon+name+**remove (Close)** `:238-260`; empty-members text `:235-236`; **Delete group** (error colour) inside dialog `:262-267`; Save applies `name.trim().ifBlank{group.name}` `:271-275`. Save gate: loosening = looser limit **OR** looser windows **OR** `!packageNames.containsAll(oldPackages)` (member removal loosens) (`AppManagementDialogs.kt:166-175`; dup `AppsTab.kt:349-358`); **Delete always gated** `recoveryGate.run{deleteGroup}` `:178-181`; **Create ungated** (`AppsTab.kt:337-338`).
- **AppGroupPickerDialog** `:319-367`: title = app name; **"No group" radio row** `:333-342`; one radio row per group `:343-354`; **New group** `:355-360`; Close `:363-365`. Selection gate: leaving current group = loosening (`AppManagementDialogs.kt:124-128`).
- Member picker is the shared `AppPickerDialog` (§23).

Dart counterpart = `GroupsScreen` (`apps_tab.dart:614-805`), a full screen reached from the Apps-tab ListTile, not a dialog:
- List rows: name + "`N apps · limit …`" subtitle `:777-781` — **windows summary MISSING** (NEW); limit shown is today's weekday value if weekly `:780`.
- Create: AppBar **+** `:762` → name dialog `:650-675`. Validation differs: Create **always enabled**; blank/whitespace name silently aborts in `_create` after the dialog closes (`:663-670`) vs original's disabled Confirm — PARTIAL, NEW (no feedback either way in Dart).
- Per-group `PopupMenuButton` {Edit members, Edit limit, Delete group} `:782-798`; row tap = Edit members `:799`.
  - **Rename: MISSING entirely** — no UI anywhere in `lib/` edits `AppGroupModel.name` after creation (model supports it, `privileged_channel.dart:320-330`). **NEW** — CA F13 "groups CRUD" overstates this.
  - **Group time windows: MISSING entirely** — no windows editor, display, or save path for groups in Dart, despite `AppGroupModel.dailyWindows/weeklyWindows` existing (`privileged_channel.dart:281-291,310-318`). `_save`→`setGroups(groups)` (`apps_tab.dart:641-648`) round-trips loaded windows, but they can never be viewed or changed. **NEW, major** (CA F10/F13 do not flag this; IMPLEMENTATION_STATUS §6 mentions only per-app daily-only).
  - **Delete:** Dart gates with `runLoosening` unconditionally `:786-791` — EQUIVALENT.
  - **Edit limit:** reuses per-app `TimeLimitEditor` `:722-754`, gate on limit only `:732-753` — but see dead control below.
  - **Edit members:** `CheckboxListTile` list over `widget.apps` `:677-720` — **no search, no system-app filter, no sorting, no icons** vs `AppPickerDialog` — PARTIAL, NEW.
  - ⚠️ **Gate bypass — NEW, serious:** `_editMembers` calls `_save(...)` **directly with no recovery gate at all** (`apps_tab.dart:715-720`). Removing an app from a group strips the group's limit/windows from it — a loosening the original explicitly gates (above). The removal direction is entirely unprotected in Dart.
- 🔴 **DEAD CONTROL — serious:** the group-limit flow invokes `TimeLimitEditor` with `reopenSeconds: 0` (`apps_tab.dart:728`) and the returned `result.reopen` is **never used** (`:731-748` builds the saved group from daily/weekly only). The visible "Reopening cooldown, seconds (stored; enforcement is v1.1)" field (`:492-499`) in the *group* editor is fully inert — typing a value and pressing Save silently discards it. The original group dialog has no such field (`AppGroupDialogs.kt:147-171`). (Per-app, the same field *is* wired: `apps_tab.dart:354-360`.)
- **AppGroupPickerDialog equivalent: MISSING** — no per-app "assign to group" UI; membership is managed only inversely from GroupsScreen. **NEW.**

## 4. AppManagementDialogs.kt — **PARTIAL** (as a host)

Not a screen: the shared dialog host (`selectedApp` → AppActionDialog + TimeLimit/TimeWindows/NoRestrictions/GroupPicker/GroupsManagement/CreateGroup/EditGroup + `RecoveryGateDialog` `:185`), invoked from `SuspensionLogsScreen.kt:170-175` — so in the original, **tapping an app in the suspension log re-opens full app management there** — and duplicated inline in `AppsTab.kt:218-368`.
- Dart has **no equivalent host reuse**: Dart `SuspensionLogsScreen` (`lib/ui/config_screens.dart:609ff`) offers search + gated clear only; log rows do not open `AppManagementSheet`. **MISSING — NEW** (cross-screen behavior; also §9).
- Gate formulas originating here were checked individually: hide/uninstall/suspend `change(loosening=current)` `:40-51`; time-limit `isLooserLimit || reopen↓` `:79-86`; windows `isLooserWindows` `:94-100`; group-pick `leaving` `:124-128`; group-save triple-loosening `:166-175`; group-delete `run` `:178-181`; create ungated `:151-159`. Dart matches all **except**: reopen↓ term (§2d), group-save member-removal term (§3), per-app group pick (absent, §3).

## 5. AppRestrictionsScreen.kt — F4 — **PARTIAL, the largest behavioral divergence in this audit (largely NEW)**

CA F4 marks this "Implemented, device-untested" with evidence only that the channel round-trips. Behaviorally, the Dart screen is a different feature in effect.

Original:
- Data model: loads **available (manifest-declared) restrictions** via `getAvailableRestrictions`, **`URLBlocklist` filtered out**, plus current bundle `AppRestrictionsScreen.kt:155-161`; one `ManagedRestrictionState` per declared entry, `isManaged = current.containsKey(key)` `:163-165,46-56`. Defaults when unmanaged: boolean → `true`/`selectedState`, string → `selectedString`, integer → `entry.intValue`, multi-select → `allSelectedStrings` `:52-75`; BUNDLE children and BUNDLE_ARRAY items recursive `:80-107`; `writeToBundle` writes only managed entries; integer unparseable → key omitted `:109-141`.
- Auto-`onBack()` if the app declares no restrictions `:196-199`.
- Header card: icon, name, **`• activeCount/total`** (primary if >0), monospace package, **Clear-all (Refresh)** icon button, error colour `:206-269`.
- Search matches **title, key, or description**, case-insensitive `:167,175-194,271-330`, with clear (✕) button `:316-328`.
- Filter chips: **All / Active (count) / Default (count)** `:332-355`.
- Empty states distinguish "no matching restrictions for *query*" vs "no restrictions available for *app*" `:359-373`.
- Cards (`ManagedRestrictionCard` `:446-594`): title (fallback = key), monospace key, **isManaged Switch** `:460-486`; description truncated at **120 chars with See more/See less** `:489-520`; value editors only when managed, by type: BOOLEAN = **Enabled/Disabled segmented buttons** `:529-549`; CHOICE = radio list (label + monospace value if different) `:550-556,596-642`; STRING = text field `:557-565`; INTEGER = **digits-only filtered** field `:566-576`; MULTI_SELECT = checkbox list `:577-583,644-698`; BUNDLE = recursive inset cards `:584-586,700-714`; BUNDLE_ARRAY = numbered item cards with **delete-item** + **Add item** `:587-589,716-764`.
- **Draft/apply model**: nothing persists until bottom **Save restrictions** `:389-412`, which rebuilds the bundle, **explicitly preserves an existing `URLBlocklist`** `:392-395`, writes with `merge=false`, gates via `isLooserRestrictions(current, bundle)`, then `onBack()`.
- **Clear-all confirmation dialog** `:415-439` — Confirm (error colour) sets every `isManaged=false` **in the draft only**; still unsaved until Save.
- `RecoveryGateDialog` `:441`.

Dart `AppRestrictionsScreen` (`apps_tab.dart:809-980`):
- Loads **only currently-set values**: `getApplicationRestrictions(packageName)` `:834-847`. It **never fetches declared/available restrictions** (channel `listRestrictionCapableApps`, `privileged_channel.dart:555-560`, is used only by BrowserRestrictionsScreen, `config_screens.dart:44`). **Every declared-but-unset restriction is invisible.** Adding one requires knowing the exact key string and using **Add key** (AppBar `+` `:948`, dialog `:919-940`), whose hint literally suggests `URLBlocklist` — the one key the original deliberately hides here.
- List: one `ListTile` per *set* entry, title = key, subtitle = `value.toString()` `:962-977`. **No header card, no active/total count, no search, no All/Active/Default filters, no description display/expansion, no empty-vs-no-match distinction.** Empty text conflates the cases: "No managed restrictions are set for this app. Add keys the app declares…" `:955-961`.
- Editing: bool → Switch in row **saves immediately** `:968-972,875-878`; other types → generic text dialog (`_editValue` `:880-917`), single field "Value (comma-separated for lists)", **Remove key**/Cancel/Save. Lists = comma-split/trim/drop-empty `:909-910`; numerics = `int.tryParse ?? keep-as-string` `:911-912` (**type can silently change int→String**; original filters non-digits at input); nested Bundle/BundleArray values have **no editor** — rendered as `Map.toString()` and editing flattens them to a string. **CHOICE and MULTI_SELECT enumerations are entirely absent.**
- **No draft model, no Save button, no Clear-all**: every edit goes through `_save` → `setApplicationRestrictions(..., merge:false)` immediately `:849-873`. Effect: the original user can stage, review, clear-all, or abandon (back without Save); the Dart user cannot — a bool toggle persists the instant it is tapped. Per-key **Remove key** is the only clearing path.
- Gate: `_save` computes `Loosening.isLooserRestrictions(old, next)` and routes loosening through `runLoosening` `:849-872` — EQUIVALENT for the edits that exist, including key removal.
- `URLBlocklist` handling differs in effect: Dart's `next` map derives from the current map, so an existing blocklist survives *incidental* saves, but it is **visible, editable, and deletable** on this screen, whereas the original hides and force-preserves it. **NEW.**
- Busy state here *is* wired (`_busy` set `:856,864`; disables Add/taps/switches `:948,971,974`) — unlike §2c.


## 6. BlockedWordsScreen.kt — F14/F15 — **PARTIAL** (gaps NEW; CA claims F14/F15 only "Implemented, device-untested")

Original controls/behaviors:
- Collapsible **Active** and **Passive** sections with info-dialog tooltip `BlockedWordsScreen.kt:45,103,267-315` (`SectionHeader`: expand arrow + `Info` → `AlertDialog`).
- Active: "Apply to apps" row, count/`no_apps`, **Select apps** button `:55-70`. "Blocked words list" header + edit icon `:71-85`; **read-only** 256dp field, placeholder + "one word per line" `:88-99`.
- Active edit dialog: editable field; Confirm computes `loosening=!wordSet(new).containsAll(wordSet(old))` (`wordSet` = trim/non-blank/set `:431`) → `recoveryGate.change(loosening)` `:198-228`.
- Active app picker: multi-select `AppSelectionDialog` `:162-184,318-431` — search by name/package `:326,350`, **Show system apps** overflow-menu checkbox `:327,360-378`, loading spinner, app icons, checkboxes; Confirm: `loosening=!selected.containsAll(old targets)` → gated `:168-175`.
- Passive: per-package row — icon, app name, non-blank word count, **Edit** and **Delete**; delete = `recoveryGate.run{updatePassiveWords(pkg,"")}` (always gated) `:118-147`.
- Passive: **Add app** button → single-select dialog (same search/system/loading dialog) → immediately opens that app's edit dialog `:148-160,186-196`. Passive edit dialog: same field/loosening logic `:229-262`.

Dart counterpart `lib/ui/config_screens.dart:251-498`:
- Equivalent core: active words ListTile + edit dialog `_editWords:287-331` (loosening `saved.length<old.length || !old.every(saved.contains)` `:318` ≈ original), target-apps ListTile + picker `_pickTargets:333-382`, passive rows + edit `_editPassive:384-430` with same loosening calc `:416`.
- **Missing/different in effect (NEW):**
  1. No collapsible sections, no info/tooltip dialogs, no read-only preview field — only count + `take(5)` preview `:447-460`.
  2. Target picker: bare `CheckboxListTile` list over `listInstalledApps()` — **no search, no system-apps filter, no icons, no loading state** `:340-365`.
  3. **Target loosening bug:** Dart `loosening = result.length < old.length` only `:371` — removing A and adding B at equal count is treated as free tightening; original gates via `containsAll`.
  4. **Passive delete ABSENT** — passive rows have only edit `:467-476`; a list can only be emptied via edit-save.
  5. **Passive Add crippled:** "Add per-app list" `:478-492` does not open a picker — it auto-picks `candidates.first`, where candidates are *only* active target apps not yet listed, and snackbars "Add target apps above first" if none. Original allows **any** installed app, independent of active targets. (VM-level restatement §29.3.)
  6. No app icons in passive rows.
- Dead controls: none (Add is wired, to the restricted logic above).

## 7. BrowserRestrictionsScreen.kt — F5 (+F6) — **PARTIAL** (gaps NEW; CA claims F5 "Implemented")

Original controls/behaviors:
- "Allowed browsers" card: **all** possible browsers (`BrowserRestrictionsManager.getPossibleBrowsers()` intent query), icon/name/package `BrowserRestrictionsScreen.kt:59-105`.
- Unsupported warning (red) if `!supportsRestrictions(pkg)` (requires both `URLBlocklist`+`ForceGoogleSafeSearch`) `:68,88-95`.
- Row click: unsupported → `AlertDialog(no_restrictions_available)` `:47,168-180`; supported → `navigateToAppRestrictions(AppItem…)` (F4 editor) `:72-86`.
- Per-browser **Switch** `checked=!isSuspended`, optimistic flip, `recoveryGate.change(loosening=checked, onCancel=revert){suspendApp(pkg,!checked)}` `:107-125`.
- "Blocked sites" header + **Add** icon → create dialog `:130-147`.
- Each list: `BlockedListAccordion` `:150-160,240-288` — title, site count, **Edit**, **Delete** (`recoveryGate.run{removeList}`), expand/collapse revealing every site.
- Edit/create dialog: Title + Sites (minLines 5) `:183-238`; Confirm **only saves if `title.isNotBlank()`** `:215` (dialog closes regardless, silently discarding blank); edit loosening = `!newSites.containsAll(oldSites)` → gated `:217-224`.

Dart counterpart `lib/ui/config_screens.dart:19-249`:
- Equivalent core: blocklist CRUD (`_editList:75-134`; delete via `_saveLists(loosening:true):224-234`); edit-loosening `!existing.sites.every(saved.sites.contains)` `:125-126` ≈ original.
- **Missing/different (NEW unless noted):**
  1. Browser list is **text bullets only** for *capable* browsers (`listRestrictionCapableApps(requiredKeys:[URLBlocklist,ForceGoogleSafeSearch]):44-48`, rendered `:215` as `• label (pkg)`). **No icons, no suspend Switch, no row-click to the F4 editor, no unsupported-browser warning or dialog.** Non-supporting browsers are not shown at all; explanatory text `:209-214` defers them to "v1.1 auto-suspension". F6 auto-suspension is **DEFERRED-DOCUMENTED**, but the loss of the switch/navigation/warning on this screen is not disclosed under F5. (VM-level: the browser-list *source* itself changed — §29.4.)
  2. **Blank-title validation missing:** Save always pops `BlockedList(title:titleC.text.trim(),…)` `:104-118` — an empty-title list is persisted; original discards it.
  3. Lists are flat `ListTile`s `:228-236` — **no accordion/site expansion**; sites invisible except count.
  4. **Extra, effect-different "Apply blocklists to browsers" button** `:239-242`, `_applyToBrowsers:136-180`: pushes merged bundle `merge:false` to *capable* browsers only, always `ForceGoogleSafeSearch:true`, loosening checked only against the **first** browser. Original `BrowserRestrictionsManager.applyRestrictions()` uses `merge:true`, sets SafeSearch only when installed, and applies to all possible browsers. Dart's `merge:false` can wipe a browser's other managed restrictions. Related VM diff: original `saveOrUpdateList`/`removeList` **auto-apply immediately**; Dart save/delete only persists and applying is a separate manual step (§29.4).
  5. Add entry point moved to AppBar `:187` (cosmetic).
- Dead controls: none; Apply button is correctly disabled when `_browsers` empty `:239`.

## 8. RestrictionsTab.kt — **PARTIAL** (gaps NEW; CA F3 claims draft/apply parity, notes none of these)

Original (`RestrictionsTab.kt`): NoDeviceOwner gate `:33-40` (see §26); two `RestrictionAccordion`s — Recommended `defaultExpanded=true`, Other `defaultExpanded=false, showSearch=true` `:47-65`; Apply button `:73-97` `enabled=hasPendingChanges()`, routed via `recoveryGate.change(isLoosening())`. Accordion `:104-198`: header Checkbox = select-all over **filtered** keys (`toggleAllDrafts(filteredKeys)`, `:147`), expand/collapse chevron, search field normalizing label **and** key (`SystemRestrictions.normalizeForSearch`, `:120-133,172-182`). Item `:200-244`: Checkbox, human label + raw-key subtitle, **"Active" badge when applied** (`isApplied`, `:225-244`).

Dart (`lib/ui/restrictions_tab.dart`): draft/apply + gate-if-any-clear `:83-104` (loosening = "any toClear", vs original VM `isLoosening()` — equivalent effect), No-owner state `:107-135` (§26).
Missing/different — all **NEW**:
- No accordions/collapse; both sections always expanded `:173-181`.
- **No select-all/toggle-all** checkbox (VM-level §29.10).
- Search is global (both sections, `:137-149`) and **matches raw key only** (`r.key.toLowerCase().contains`, `:68-74`; `UserRestriction` has no label field, `privileged_channel.dart:136-147`) — original searches localized label + key, in "Other" only.
- Rows show **raw key as title** (`SwitchListTile`, `:186-195`) — no human label, no key subtitle, **no "Active" badge**; only a "Changed — not applied yet" subtitle.
- Switch instead of Checkbox (cosmetic). Apply button hidden until dirty (`:183-195`) vs original always-visible-but-disabled — behaviorally near-equivalent.

## 9. SuspensionLogsScreen.kt — F27 — **PARTIAL** (gaps NEW; CA documents search + gated clear only)

Original (`SuspensionLogsScreen.kt`): search field filtering appName/packageName/**localized reason title** `:41-61,78-87`; clear IconButton `enabled=logs.isNotEmpty()` `:88-97`; empty state icon+text `:102-131`; list items keyed by id with **app icon** (fallback Android icon), appName, packageName, **`dd/MM/yyyy HH:mm` date**, reason as errorContainer `SuggestionChip` `:179-262`; **tapping an item/chip opens `AppManagementDialogs` for that app** `:129-141`; clear = plain confirm AlertDialog, **not recovery-gated** `:147-169`.

Dart (`lib/ui/config_screens.dart:609-700`): search (`:637-672`, matches raw `reason` string, not a localized title), gated clear (`:643-656`), empty view, rows.
Differences — **NEW**:
- **Clear is stricter than the original**: Dart requires a recovery session (`runLoosening`, `:648-655`); original requires only the confirm dialog.
- **Row tap does nothing** — ListTiles have no `onTap`; the original's open-app-management behavior is **MISSING** (also §4). This is an inert row vs the original, §28.
- No app icon, no reason chip; reason is a raw enum-name string in the subtitle.
- Timestamp printed as raw `DateTime.toString()` (`${l.timestamp}`, ~`:683`) vs `dd/MM/yyyy HH:mm` formatting.
- Extra: `details` appended to subtitle (no original counterpart in this screen).

## 10. TimeLimitEditor.kt — **PARTIAL** (editor-UX gaps NEW; CA F9/F10 do not discuss editor UX)

Original (`TimeLimitEditor.kt`): per-day Switch `:96-117`; enabling per-day seeds all days from daily **only if days still uniform** (`changePerDay`, `:80-87`); day chips ordered by locale first-day-of-week, showing short name + current value subtext/"—" `:118-135` (DayChip `:161-196`); `DurationWheels` hours 0–23 / minutes 0–59 `:227-258`, recreated per day/mode via `key(...)` `:139`; summary text "None" or bold formatted limit with full day-name prefix `:142-155`; `timeLimitSummary()` `:55-66` used by rows. **No reopen field in this file** (it lives in the dialog host, §2d).

Dart (`lib/ui/apps_tab.dart:405-528`): `SegmentedButton` Daily/Per-weekday `:462-470`; per-weekday = **7 simultaneous numeric TextFields**, Mon-first fixed order `:471-495` (no day-chip/wheel interaction; all days visible at once — functionally equivalent coverage of values); values silently `clamp(0,1440)` on Save `:510-525` vs original's wheel-bounded 0–23h59 (and §2d: invalid text → 0 = unlimited, no error).
Missing/different — **PARTIAL, NEW**:
- No wheels, no day chips with per-day value subtexts, no selected-day summary line, no locale week-start.
- Per-day seeding: Dart initializes weekday controllers from `weekly?[i] ?? dailyMinutes` at construction `:438-445` — approximates the seed rule but is not the uniform-check-on-toggle semantics.
- Dart-only addition: reopening-cooldown TextField `:490-498` labelled "stored; enforcement is v1.1" — **DEFERRED-DOCUMENTED** (CA F11). **Dead in group reuse:** `GroupsScreen._editGroupLimit` passes `reopenSeconds:0` and discards `result.reopen` (§3, §28).

## 11. TimeWindowsEditor.kt — **PARTIAL** (validation divergence NEW; daily-only headline DOC)

Original (`TimeWindowsEditor.kt`): dialog `:115-313` with per-day Switch + day chips `:161-215` (seeding rule `:95-104`); window rows with delete **disabled for `lockedWindows`** `:224-240`; add-form default **18:00–22:00** with `TimeOfDayWheels` `:139-144,242-291`; validation: `start==end` → inline error, and **confirm / day-switch / per-day toggle all first call `commitPendingWindow()`, which blocks on the error** `:145-159,294-308`; "Add another window" label while form open `:294`; duplicate windows de-duped `:155`; daily-only overload `:315-333`. `lockedWindows` is really used by `ColorFilterScreen.kt:229`.

Dart (`lib/ui/apps_tab.dart:530-612`): daily-only list, delete buttons, add via two sequential `showTimePicker`s (defaults **07:00 / 21:00**, `:545-567`).
- Per-weekday windows in the per-app editor: **MISSING** — DEFERRED/PARTIALLY DOCUMENTED (CA F10: "per-app editor UI edits daily windows only"; store/channel/group model support weekly). Weekly-loss risk on save: §2e.
- `lockedWindows`: **ABSENT** in `lib/` (grep 0) — relevant only to deferred colour modes (F26). **NEW (detail).**
- **Validation divergence — NEW:** equal start/end is **silently coerced to end+1 min** (`apps_tab.dart:562-567`) instead of an error that blocks confirm.
- No pending-form commit semantics, no inline error text, no day-name heading, no de-duplication. **NEW.**

## 12. UsageWarningScreen.kt — F12 — **PARTIAL** (stage-editor gaps NEW; delivery DEFERRED-DOCUMENTED)

Original (`UsageWarningScreen.kt`): enable Switch with **POST_NOTIFICATIONS flow** — on enable (API 33+) launches permission request; result sets `enabled=granted`; `permissionDenied` shows error supporting text; on entry, if enabled without permission, denied state shown `:40-98`. Stages sorted descending by minutes `:118`; empty-stages error text `:108-117`; Add-stage button `enabled=viewModel.enabled` `:134`. Stage row `:144-240`: minutes TextField validated by regex `^\d{0,3}([.,]\d{0,2})?$`, comma→dot, accepted only if in `0.1..180` (`UsageWarningSettings.kt:17-18`; screen `:158-175`); type `SingleChoiceSegmentedButtonRow` SILENT/SOUND/VIBRATE `:186-205`; vibration-count field **only for VIBRATE**, digits, ≤2 chars, accepted only `1..10` `:212-235`; delete IconButton `:176`.

Dart (`lib/ui/config_screens.dart:501-607`): defaults match the original (`lib/data/config_store.dart:99-105`). Switch `:572-577` + stage rows are **display-only ListTiles with a delete button** `:582-595`; Add appends a fixed `UsageWarningStage(10, silent)` `:597-605`.
- **Per-stage editing of minutes, type, and vibration count: MISSING** — added stages are immutable except by deletion. **NEW** (CA F12 documents only that notifications aren't fired; VM-level §29.11.)
- **No notification-permission request, no denied state** (grep in screen: 0 hits). **NEW.**
- No descending sort, no empty-stages message, Add not disabled when master switch off. **NEW.**
- Gate divergence: Dart routes disable/removing stages through `runLoosening` `:522-540`; the original screen has no recovery gate. **NEW.**
- Delivery: no native notifier — **DEFERRED-DOCUMENTED** (CA F12: editor+storage v1, delivery v1.1; Dart copy at `:578-581` admits this).

## 13. VisualBlockingScreen.kt — F16/F17 — **ABSENT in Dart — DEFERRED-DOCUMENTED**

Original controls (`VisualBlockingScreen.kt`): explanation `:42-49`; enable Switch, `enabled = enabled||accessibilityActive`, turning **off** is loosening-gated, error text if accessibility inactive `:54-79`; target-apps row + Select button → `AppPickerDialog` in **draft+confirm** mode, confirm gated by `isLooserSet` `:82-100,255-285`; category checkboxes for `SELECTABLE_CATEGORIES` (drawings/hentai/porn/sexy, labels `:348-354`), deselect gated `:104-140`; threshold Slider 0–1 with % label, committed only `onValueChangeFinished`, raising = loosening, cancel restores draft `:143-185`; escalation Checkbox (gated) `:188-210` + three `NumberSettingField`s — block count (loosening if ↑), window minutes (loosening if ↓), duration minutes (loosening if ↓) — digits-only, ≤4 chars, commit on focus-loss/Done, parsed value must be ≥1 else revert `:213-252` (`NumberSettingField` `:286-346`); summary line with all three values `:243-252`. Defaults 5 blocks / 15 min / 30 min (`VisualBlockingSettings.kt:29-31`, DF:126).

Dart: grep `visual|nsfw|tflite` in `lib/` (excluding a theme doc-comment): **0 hits — no screen, no placeholder, no settings UI at all**. Classification **DEFERRED-DOCUMENTED** (CA F16/F17 "Deferred v1.1… no placeholder screen"; DF:125-126). Note: even the *settings* (categories/threshold/escalation numbers) — portable pure config needing no classifier — are missing; the documented deferral covers the whole feature, not just the TFLite pipeline. There is not even a Config row for it (§14, item 4). VM surface: §29.12.

## 14. ConfigTab.kt — **PARTIAL** (hub; DNS-host and dialog-stripping gaps NEW)

Original rows in order (`ConfigTab.kt`): Device-Owner badge (green Granted / red Not Granted) → `setup_device_owner` `:93-108`; DNS → owner-check snackbar else dialog `:110-128`; Browser restrictions → nav `:130-135`; **Advanced blocking Switch** (accessibility running; requires `Shizuku.pingBinder()` else snackbar; gated `change(loosening=!checked){prepareServiceDisable();changeAccessibilityPermission}`) `:139-159`; Blocked activities → nav gated on advanced-blocking snackbar `:161-176`; Visual blocking → same gate `:178-193`; Blocked words → same gate `:195-210`; **Block torrents Switch** (enabling without accessibility → snackbar; gated) `:212-232`; Language → dialog `:234-241`; Impulse lock `:243-248`; Focus mode `:252-257`; Usage warnings `:261-266`; Colour filters → nav (ungated) `:270-277`; Suspension logs `:279-284`; Keyboard type (shows Normal/Shuffled) → dialog `:286-299`; Change recovery code (`recoveryGate.run{RecoveryGenerateDialog}`) `:301-313`; Forced removal (trailing live remaining/"Active", refreshed 60s) `:315-341`.
- **DNS dialog** `:514-630`: presets `Cloudflare=family.cloudflare-dns.com`, `AdGuard=family.adguard-dns.com`, `CleanBrowsing=adult-filter-dns.cleanbrowsing.org` `:522-524`; Custom radio + host field, regex `^([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}$` `:538-540`, inline invalid error `:590-596`, Apply disabled if no selection/invalid-custom/loading `:609`, spinner while applying; apply wrapped in `recoveryGate.run`, 15s timeout, `PRIVATE_DNS_SET_NO_ERROR`→close, `HOST_NOT_SERVING`→specific error else generic `:443-475`.
- **Language dialog** `:633-685`: en/pt radios + Apply/Cancel → `LocaleUtils.setLocale`.
- **Keyboard dialog** `:688-746`: Normal/Shuffled radios with descriptions; Apply: `loosening=(was shuffled && !new shuffle)` → gated.
- **Forced-removal dialogs** `:343-435`: Start (explanatory, Confirm→`startForcedRemoval`, no gate); Cancel (Confirm→`cancelForcedRemoval`); Finish (text + **mandatory confirmation checkbox enables Confirm** → `removeDeviceOwner()`+`Activity.recreate()`; the dialog's own Cancel button calls `cancelForcedRemoval`).

Dart counterpart `lib/ui/config_tab.dart`:
- Present: Setup/Device Owner tile `:102-115` (subtitle text, **no Granted/Not-Granted badge**); Private DNS `:116-126`; Browser restrictions `:128-134`; Blocked words `:135-141`; Impulse `:142-148`; Focus `:149-155`; Usage warnings `:156-162`; Suspension logs `:163-169`; Language `:182-188`; Change recovery code `:207-228` (via `ensureRecoverySession` → `RecoveryWizard(isRegeneration:true)` ≈ original gate, arguably equivalent); forced removal `:248-310`.
- **Differences in effect:**
  1. **DNS presets wrong (NEW):** Dart `config_tab.dart:19-23` — `Cloudflare Family: security.cloudflare-dns.com` (original: `family.cloudflare-dns.com`), `CleanBrowsing: security-filter-dns.cleanbrowsing.org` (original: `adult-filter-dns.cleanbrowsing.org`); AdGuard matches. Different endpoints, not just labels.
  2. **DNS flow stripped (NEW; CA F7 notes only "cannot be unset"):** `_editDns:311-365` — preset rows tap-to-apply immediately (no radio/Apply state), custom via separate "Use custom" button; **no recovery gate, no loading state, no 15s timeout, no result-code error mapping**. Validation `isValidHostname:25-33` differs: allows single-label hosts and uppercase, requires no dot/TLD≥2 (original regex requires both, lowercase only). Non-owner tap is silently `null` `:125` vs original explanatory snackbar.
  3. **Advanced-blocking Switch ABSENT from Config** — accessibility toggle relocated to Setup screen (`lib/ui/setup_screen.dart:177-192`). Blocked-words navigation is **ungated** in Dart (opens without accessibility; original snackbars and blocks) `:135-141`.
  4. **Visual blocking row ABSENT entirely** (no tile). F16 DEFERRED-DOCUMENTED and CA notes "no placeholder screen" — consistent, but a Config-row loss vs the original.
  5. **Activity blocker row** → disabled `UnavailableTile` `:176-181` = F18 DEFERRED-DOCUMENTED (+CA G1).
  6. **Block torrents Switch ABSENT** (grep `torrent` in `lib/` = 0 hits). F19 DEFERRED-DOCUMENTED, but the original's Config switch has no labelled placeholder in Dart.
  7. **Keyboard type row ABSENT from Config.** Shuffle toggle relocated to the Impulse screen (`lib/ui/impulse_focus_screens.dart:273-285`) as a plain `SwitchListTile` with **no recovery gate in either direction** — the original gates shuffle→normal as loosening. Ungated loosening in effect. **NEW.**
  8. **Language:** `SimpleDialog` tap-to-commit `:367-386` (no radio draft/Apply; tapping outside is the only cancel) vs original draft+Apply/Cancel; persists setting + partial chrome only (F33 partial, documented in CA).
  9. **Forced-removal dialogs stripped (NEW; CA F2 documents only the alive-only timer):** Dart shows a non-clickable status tile + direct Wrap buttons Start/Cancel/Finish `:260-308` — **no start-confirmation dialog, no cancel-confirmation dialog, no finish confirmation checkbox**. Finish calls `removeDeviceOwner()` directly. Start handler also calls `forced.start()` twice (`setForcedRemoval(forced.start()); _c.forcedRemoval=forced.start()`) with two different instants.
  10. **Extra in Dart (not in original):** "Remove Device Owner now" tile `:229-247` (recovery-gated immediate removal — the original reaches removal inside Config only via the finish-forced-removal flow; the in-session path exists in DF F2) and **Theme SegmentedButton** (System/Light/Dark) `:189-206`, wired to `AppController.setThemeMode` — functional, not dead, but a non-parity addition.
  11. Colour modes tile: §15 (F26 deferred-documented).

## 15. ColorFilterScreen.kt — F26 — **MISSING / DEFERRED-DOCUMENTED**

Original controls/behaviors (all in `ColorFilterScreen.kt`): explanation text `:70-77`; 15s polling `refresh()` `:59-66`; master **Enable Switch** `:82-135` (supporting text = accessibility-required error / locked-with-active-windows / on / off; switch disabled unless `enabled || (accessibilityActive && !grantingPermission)`; enabling: permission granted → enable, else if `!Shizuku.pingBinder()` → snackbar `shizuku_not_running`, else `grantPermission{}` → failure snackbar; disabling: `recoveryGate.run{if(!updateEnabled(false)) showLocked()}`); Modes section + empty-modes error `:140-165`; per-mode row (Grayscale/Night Light/Extra Dim/Inversion icons+descriptions, whole-row clickable **Checkbox**) `:150-167,262-293` (selecting = `recoveryGate.change(loosening=false)`, deselecting = `recoveryGate.run` + locked check); Night Light only: **TemperaturePicker** chips `1800,2000,2500,2700,3200,4000K` (default 3200) `:168,412-425` (+`ColorFilterSettings.kt:25`); **StrengthSlider intensity** (max 60, `ColorFilterSettings.kt:23`) only if `!platformNightLight` `:176-187`; Extra Dim only: **StrengthSlider** 0–100% `:188-197` (sliders commit only on `onValueChangeFinished`, gated via `recoveryGate.run(onCancel=restore draft)`, locked → restore + snackbar `:381-410`); per selected mode: **ModeWindows** — window list, active markers, no-windows error, **Edit windows** → `TimeWindowsDialog` (locked windows protected; confirm gated by `!isOnlyAdding`) `:198-202,226-243,294-323`; per selected mode: **ModeScope** — radio `DEVICE / EXCEPT_APPS / ONLY_APPS`, selected-app count / empty-errors, **Select apps** → `AppPickerDialog`, saved *on dismiss* via gated `saveCoverage` `:204-211,246-262,325-379`; snackbars for locked/Shizuku/permission failures `:47-54,219-224`.

Dart: **ABSENT after grep of `lib/`** — no screen, no mode/temperature/slider/window/scope code. Only the disabled tile at `lib/ui/config_tab.dart:170-175` ("Colour modes — Scheduled grayscale / night light / extra dim ship in v1.1…"; `UnavailableTile` itself is `enabled:false`, `lib/ui/common.dart:321-343` — an honest placeholder, not a fake control). CA confirms F26 Deferred v1.1, "no colour-filter code in service or Dart" — classification matches documentation. Minor note: the tile omits **Inversion** from its list, though the original has 4 modes. VM surface (incl. the VM-level "locked window" concept a v1.1 port must reproduce): §29.5.


## 16. ImpulseLockScreen.kt — F21 — **PARTIAL**

Original controls/behaviors (`ImpulseLockScreen.kt`):
- Explanation text + locked row shown when no recovery session; tapping it opens the gate `:37-56`.
- Challenge multi-select (Checkbox rows, `OptionRow multiple=true` `:64-103`, row impl. `:393-411`): MATH/WORDS/TETRIS/READING, each with title+description; **all controls `enabled=sessionActive` only** — no session = nothing editable.
- Inline per-challenge settings when selected: TETRIS → duration slider 1–15 min `:229-251` (constants `SecurityManager.kt:45-47`); READING → source radio list BIBLE/QURAN/QUOTES/CUSTOM `:253-280`; CUSTOM → passage list with per-item delete `:287`, empty-list error text, Add button `:302`; reading-count slider `READING_MIN_COUNT..available`, shown only if `available>MIN` `:313-335`.
- `AddPassageDialog` `:340-376`: multi-line text (minLines 3) + single-line source fields; **Confirm disabled unless `text.isNotBlank()`** `:367`.
- Action radio: TIMER_ONLY / TIMER_AND_SUSPEND `:106-133`.
- Duration slider 15–360 min, 15-min steps, formatted headline + min/max labels `:136-175` (`SecurityManager.kt:41-43`).
- Suspend-apps row **only when action==TIMER_AND_SUSPEND** `:178-209`: count/"no apps", Select button → `AppPickerDialog` with *immediate* toggles (no draft), red warning if accessibility not running `:200-207`.

Dart counterpart `lib/ui/impulse_focus_screens.dart:19-338`:
- Duration slider `:201-218` — 15–360, `divisions:23` (=15-min steps) — EQUIVALENT.
- Action radios `:220-232` — EQUIVALENT. Suspend-apps picker `:118-156` (draft + Save/Cancel) — PARTIAL: row always visible (not conditional on action); **no accessibility-inactive warning anywhere in the screen**; picker is the degraded AppPicker (§23); draft-vs-immediate toggle behavior differs from the original's Impulse usage.
- Challenges: CheckboxListTiles for all 4 types `:246-274` — PARTIAL, major: (i) **no session gating at all** — duration/action/challenges/apps all save immediately via `_saveConfig`/direct store writes (`:88-95,209-232,250-274`); the only gate in the file is stopping an active lock (`:100`) and Focus pause/end. The original disables everything without a session. **NEW.** (ii) Forced non-empty: deselecting the last challenge re-adds `math` (`:262`) — the original has no such floor in this screen. **NEW.**
- Tetris: checkbox present but `onChanged:null` + "v1.1… skipped, never simulated" `:250-273` (`lib/domain/challenges.dart:14-25`) — **DEFERRED-DOCUMENTED** (CA F22a).
- Tetris duration slider: **ABSENT** (grep `tetrisMinutes` in `lib/`: 0 hits) — moot while Tetris is deferred, but config parity missing; DF:131 lists 1–15/default 3. **NEW (detail).**
- Reading source selection (Bible/Quran/Quotes/Custom radios): **ABSENT** (grep `ReadingSource|bible|quran` in `lib/ui`: 0 hits). Dart instead uses a small original sample set + custom phrases (`lib/domain/challenges.dart:145-183`). Corpus-not-copied is **documented** (CA F22); source-picker + reading-count slider absence is **NEW**.
- Reading count: fixed `requiredPassages=5` (`lib/domain/challenges.dart:195`) = original default (`SecurityManager.kt:50`) but not user-configurable — PARTIAL/NEW.
- Custom passages: `_editPhrases` `:285-338` — one bulk newline TextField, no per-item delete, **no source field, no blank-text validation beyond filtering empty lines** — PARTIAL/NEW.
- Dart-only extras (not in the original screen): Start/Stop lock buttons on the config screen `:176-199` (original starts only from the lock-screen panic button); shuffled-keypad SwitchListTile `:273-285` (see §14 item 7 — ungated vs original).
- Effect difference (documented): suspension applied/released by the UI process, timer alive-only (CA F21 Partial) vs original service-side `syncImpulseSuspension()` (DF:130).

## 17. FocusModeScreen.kt — F25 — **PARTIAL** (core documented; most gaps NEW)

Original controls/behaviors (`FocusModeScreen.kt` + common dialogs):
- Explanation `:55-60`; `FocusSessionCard` `:61-68` (§25); sliders via `MinutesSlider/SettingSlider:429-511` — commit only on release, draft reverts on gate-cancel:
  - Focus **5–120 min, step 5** (`FocusMode.kt:31-32`), loosening = decrease `:71-82`
  - Short break **1–30, step 1** (`:35-36`), loosening = increase `:83-94`
  - Long break **5–60, step 5** (`:39-40`), loosening = increase `:95-106`
  - Cycles **2–8, step 1** (`:43-44`), loosening = decrease `:107-121`
- Switches: **Auto-start** (gated `loosening=!checked`) `:124-139`; **Sound** (ungated) `:140-149`; **Vibration** (ungated) `:150-159`.
- Apps picker row + Groups picker row, both **disabled + error text if not Device Owner** `:162-215`; pickers gated by `isLooserSet(old,new)` on confirm (`AppPickerDialog:336-357`, `FocusGroupPickerDialog:358-374`).
- Restrictions row, same owner-gating `:217-246`; `FocusRestrictionsDialog` gated by `isLooserSet` `:375-391`.
- Schedules: Add button `:248-270`; empty text or list rows showing formatted time + days summary (All/Weekdays/Weekend/names) `:272-335`; per-schedule **enable Switch** (gated `loosening=!checked`), **Delete** (always `recoveryGate.change(loosening=true)`), row-click edits. `FocusScheduleDialog` (§24): time wheels, day chips, Weekdays/All quick chips, **Save disabled if no days selected** + warning.
- Session card gating: §25.

Dart counterpart `lib/ui/impulse_focus_screens.dart:340-695`, model `lib/domain/focus.dart`. CA F25 documents only: no native FGS, **no schedules**, alive-only countdown. The following are **NEW/undisclosed**:
1. **Ranges/steps wrong:** Dart `_durationRow:633-660` is a ±1 stepper, default `min:1,max:180` for focus/break/long-break `:587-601`, cycles `min:1,max:12` `:602-608`. Dart permits e.g. focus 1 or 180 min, cycles 1 or 12 — values the original clamps away (`FocusMode.kt:92-118`).
2. **All duration/app saves ungated:** `_saveConfig:387-397` writes directly; the original gates every loosening direction above. Removing suspended apps via the picker `:613-622` is likewise ungated vs the original `isLooserSet` gate.
3. **Auto-start, Sound, Vibration switches ABSENT** — no fields in `FocusConfig` (`focus.dart:13-31`), no UI (grep 0 hits). Not mentioned in CA.
4. **Groups picker ABSENT; Restrictions picker ABSENT** (§24, dead plumbing below).
5. **No Device-Owner gating** on the app picker: the original disables buttons + shows `focus_requires_device_owner` error; the Dart picker always opens (the native call fails later via snackbar in `_syncEffects`).
6. **Schedules:** replaced by disabled `UnavailableTile` `:623-627` — DEFERRED-DOCUMENTED (CA F25 partial). All schedule CRUD/day/time validation therefore absent, consistently with that note.
7. **Session-card semantics differ:** Dart phases idle/focus/break/longBreak/paused/done (`focus.dart:11`) — **no WAITING phase**. Buttons `:520-575`: Start (free ✓), Skip break (free, non-focus only ✓), **Pause always recovery-gated** `:545-553` (the original's plain pause is free; only long-press releasing pause is gated — §25), End recovery-gated + `_syncEffects` release ✓-ish, Resume free ✓. No long-press distinction, no notification-permission request. Alive-only note explicit in UI `:577-583` (documented).
8. `_syncEffects:403-437` does apply/clear `config.restrictions` and suspend apps by phase — wired, but see below.
- 🔴 **Dead/unreachable plumbing (NEW):** `FocusConfig.suspendGroups` (`focus.dart:20,29,38,48-49,60,69`) is persisted but **never edited by any UI and never consumed** — `_syncEffects` never expands groups to packages; always empty in practice. `FocusConfig.restrictions` (`focus.dart:21,30,39,50-51,61,70`) *is* consumed by `_syncEffects:416,426`, but **no UI ever sets it** — always empty unless written externally. Restrictions-during-focus therefore can never occur through the app, despite the code path existing (same pattern as CA gap G1, but for F25). This also makes CA F25's evidence line ("applies/clears user restrictions by phase") materially overstated at the user-behavior level.

## 18. SuspensionLogsScreen — covered as §9 (tabs scope).

## 19. ColorFilterScreen — covered as §15 (listed here to preserve the scope checklist order of the original tree: ActivityBlocker §1, AppGroupDialogs §3, AppManagementDialogs §4, AppRestrictions §5, AppsTab §2, BlockedWords §6, BrowserRestrictions §7, ConfigTab §14, FocusMode §17, ImpulseLock §16, RestrictionsTab §8, SuspensionLogs §9, TimeLimitEditor §10, TimeWindowsEditor §11, UsageWarning §12, VisualBlocking §13).

---

# B. screens/common/

## 20. AppPickerDialog.kt → no shared Dart widget — **PARTIAL (degraded, re-implemented 4×)**

Original (`AppPickerDialog.kt:36-154`): search field filtering name/package `:58-66,67-77`; overflow menu with "Show system apps" checkbox toggle, system apps hidden by default `:78-97`; loading spinner `:99-110`; rows with **app icon**, bold name, package, Checkbox `:112-140`; Confirm = `onConfirm ?: onDismiss`, Cancel button only when `onConfirm != null` `:142-154`.

Dart: no `AppPicker` widget exists. Ad-hoc `AlertDialog + CheckboxListTile` copies at `lib/ui/impulse_focus_screens.dart:118-156` & `:660-702`, `lib/ui/config_screens.dart:~330-390` (blocked-words targets), `lib/ui/apps_tab.dart:~672-712` (group members). Missing in **all** copies — **NEW** (not itemized in CA):
- **No search field** in any picker.
- **No system-apps toggle** in pickers (the Apps *tab* has an include-system switch, `apps_tab.dart:89-97`, but picker lists come from a single `listInstalledApps()` load with default filtering).
- No app icons; package name shown only in the group-members copy (`apps_tab.dart:690`).
- No loading state inside pickers.
Behavior note: the original's Impulse usage is immediate-toggle, Visual usage draft+confirm; Dart uniformly uses draft+Save — a behavior change for Impulse (§16).

## 21. FocusGroupPickerDialog.kt → **MISSING (UI) / dead model field**

Original (`FocusGroupPickerDialog.kt:31-106`): draft-selection dialog; empty-groups message `:44-50`; rows: Checkbox + group name + "N apps" count `:52-90`; Confirm returns draft set / Cancel discards `:96-106`. Used from `FocusModeScreen.kt:359-365` with a loosening check on confirm.

Dart: **no group picker, no groups row** anywhere in `lib/ui/impulse_focus_screens.dart`. `FocusConfig.suspendGroups` exists in the model (`lib/domain/focus.dart:20,29,38-49,60-70`) but **nothing sets it and `_syncEffects` never reads it** (`impulse_focus_screens.dart:403-435` handles only `suspendApps` + `restrictions`) — **DEAD plumbing, NEW** (CA G1 mentions the unused `focus_schedules_prefs` allowlist, not `suspendGroups`; CA F25 claims groups under F13, not focus-group suspension). See §17 and §28.

## 22. FocusRestrictionsDialog.kt → **MISSING (UI) / dead effect path**

Original (`FocusRestrictionsDialog.kt:38-147`): explanation text; search (label+key, normalized) `:52-66,80-90`; draft Checkbox list of all `SystemRestrictions.allKeys` with label+key `:94-135`; Confirm/Cancel `:137-147`.

Dart: **no dialog/row to edit focus restrictions anywhere** (grep 0 UI hits). Yet `_syncEffects` applies/clears `config.restrictions` on phase change (`impulse_focus_screens.dart:416-431`) — since the list can only ever be the default `[]` (`lib/domain/focus.dart:21`), that loop is **unreachable-in-effect DEAD code, NEW** (§28).

## 23. FocusScheduleDialog.kt → **MISSING — DEFERRED-DOCUMENTED (labelled)**

Original (`FocusScheduleDialog.kt:42-189`): create/edit dialog; `TimeOfDayWheels` time (default 08:00), day chips Mon–Sun (default Mon–Fri), quick chips "Weekdays"/"All days" `:104-120`, empty-days error warning + **Save `enabled=selectedDays.isNotEmpty()`** `:154-180`.

Dart: only an `UnavailableTile` "Focus schedules & reminders — Scheduled auto-start sessions are not in this version" (`impulse_focus_screens.dart:623-628`; tile impl. `lib/ui/common.dart:321-340`, `enabled:false` by design). No CRUD, no schedule model in Dart. **DEFERRED-DOCUMENTED** (CA F25 Partial: "no… schedules in v1 (labelled v1.1 tile)").

## 24. FocusSessionCard.kt → Dart focus card — **PARTIAL**

Original (`FocusSessionCard.kt`): usable **pre-auth on the lock screen** and in-app, in Full and Compact variants `:71-119,154-223,225-281`. Actions by state: Start (also from WAITING), Resume, Skip-break (breaks only), Pause, End. Gating nuance `:62-70,92-118`: start/resume/skip-break **free**; plain Pause free (apps stay suspended); **long-press Pause = releasing pause, gated** (haptic + long-press detection via interaction source `:283-302`); End gated **except in WAITING**. `rememberFocusStarter` `:40-57`: after start, requests POST_NOTIFICATIONS if not granted and shows a status notification on grant. Phase title "Focus n of N"/break/long-break/waiting + "(Paused)" prefix `:123-136`; CountdownRing fraction = remaining/duration, countdown text **rounded up** `:138-152,304-312`; cycle progress "x of N"; hint text switches between hold-pause hint and end-requires-code `:214-222`. Compact: 76dp ring or Timer icon, title, subtitle (focus minutes when idle / cycle progress), icon buttons `:225-281`.

Dart: GradientCard + `FocusTimerRing` (`lib/ui/common.dart:241-318`; progress = remaining fraction, red/blue by break — presentation equivalent), Start `:524-535`, Skip break `:537-549`, Pause `:550-553`, End `:554-562`, Resume `:564-573`, completed-periods text, alive-only disclaimer `:575-582` (all in `lib/ui/impulse_focus_screens.dart`).
Differences — **NEW** unless noted:
- **No lock-screen presence**: `lib/ui/lock_screen.dart` contains only the panic button + usage top-5 + Access — the original exposes the full focus card pre-auth (DF:178-180). **MISSING there.**
- **No Compact variant** anywhere.
- **Pause is always recovery-gated** in Dart; the original's short-press pause is free. **Long-press releasing pause: MISSING** — Dart pause never calls `_syncEffects`, so apps stay suspended (matches only the free pause's effect).
- End gated whenever running (no WAITING concept; Dart `idle` ≈ WAITING but holds no session) — near-equivalent.
- **Resume divergence**: `FocusSession.resume()` always re-enters the **Focus** phase with the paused remainder, discarding the paused-from phase (`lib/domain/focus.dart:165-178`, self-documented "v1 simplification") — the original resumes the same phase.
- No POST_NOTIFICATIONS request on start (cf. §12).
- Phase label is generic "Focusing/Break/Long break/Paused" with a separate "Cycle n of N" label (`impulse_focus_screens.dart:466-505`) vs the original's combined counted title; `formatClock` (`lib/ui/common.dart:224-230`) truncates instead of rounding up, so the ring can read 00:00 before the phase flips.
- No native FGS countdown — DEFERRED-DOCUMENTED (CA F25, G3).

## 25. NoDeviceOwnerPrivileges.kt → inline in Dart — **PARTIAL (near-equivalent)**

Original (`NoDeviceOwnerPrivileges.kt:24-47`): centered ElevatedCard, "not device owner" text, TextButton with Settings icon navigating to `"config"` `:37-45`.

Dart: shield icon, title, explanatory text ("restrictions are not faked without it"), FilledButton "Open Setup" pushing the **Setup screen** (`lib/ui/restrictions_tab.dart:107-135`). Behaviorally equivalent-or-better; differences: not a reusable widget (only RestrictionsTab has it — other DPM-dependent Dart screens surface `ErrorView`/friendly `DPM_NOT_OWNER` copy, `lib/ui/common.dart:39-42`; note AppsTab does not even do this, §2a), and the destination is Setup rather than the Config tab. **NEW (minor).** CA F3 documents that the Dart state exists.

## 26. UsageLimitsOverview.kt → Dart lock-screen usage list — **PARTIAL**

Original (`UsageLimitsOverview.kt`): full-screen pre-auth overview with back/close header `:47-72`; loading spinner `:74-78`; empty message `:80-90`; **Groups section then Apps section**, each entry sorted by usage fraction desc `:92-102` (`loadOverview` `:204-246`); LimitCard `:114-192`: icon (group → Group-icon placeholder), name, detail (group = member app names; app = its group name), **progress bar (red when reached)**, "used of limit" + "reached"/"X remaining" texts. Only apps/groups with **today's limit > 0** appear; per-weekday limits use today's value `:209,228-245`.

Dart lock screen (`lib/ui/lock_screen.dart:52-72,205-222`): top-5 packages by raw usage ms from `getUsageToday()`, label + duration only.
Missing — **NEW** (CA mentions only that the lock screen contains "a read-only usage overview"):
- Not limit-scoped: shows **any** used app, not only limited apps/groups; no groups section at all.
- No limit totals, no progress bars, no reached/remaining indicators, no icons/details, no close/back header, no loading or empty states (silently hidden on error/empty, `lock_screen.dart:68-72` — by design there, but a behavior difference).


---

# C. ui/theme/ (brief, per scope)

## 27. Color.kt / Theme.kt / Type.kt → `lib/theme.dart` — **PARTIAL, deliberate redesign (documented)**

- Original palette (`Color.kt:5-74`): full Material-3 light+dark schemes, primary green `#2C6A45` / dark `#95D5A8`, secondary burnt-orange `#8E4D2F`, tertiary ochre `#7A590C`, warm off-white surfaces (`#F6FBF3` bg / `#FFF8F0` surface light; `#0F1511`/`#16130B` dark).
- Original `Theme.kt:92-125`: `DechainerTheme(darkTheme=isSystemInDarkTheme(), dynamicColor=false)` — dynamic color **supported but default-off**, Android 12+ gate `:103-110`; static schemes otherwise. `Type.kt:1-4`: `Typography()` — stock Material defaults, no custom font/weights.
- Dart `lib/theme.dart:19-182`: hand-built schemes, primary red `#D90429`/`#E5383B`, blue `#1D3557`/`#2563EB`, neutral near-black dark surfaces `#0A0A0C` (documented rationale: avoid seed-tint wash, `theme.dart:1-16`); **no dynamic-color equivalent at all**; typography = platform base with display/headline/title weights raised to w700–w800 (`theme.dart:63-73`) vs the original's untouched defaults; plus redesign-only components (hero gradient, pill nav, `lib/ui/pill_nav.dart`) with no original counterpart. Theme *selection* (system/light/dark) is a Dart-only addition, wired via `lib/ui/config_tab.dart:189-206` (§14 item 10); the original follows system only.
- Classification: palette/typography divergence is a **user-directed, documented redesign** (CA §1 "The redesign itself is presentation-only") — EXCLUDED-by-decision for color identity; the **absence of dynamic color** is the only functional delta and is consistent with the original's default (`dynamicColor=false`). Not a NEW gap beyond noting it.


---

# D. Dead / inert Dart controls — consolidated (serious first)

| # | Item | Citation | Status |
|---|---|---|---|
| 1 | 🔴 **Group-limit editor's Reopening cooldown field** — displayed, editable, value silently discarded on Save (editor invoked with `reopenSeconds:0`, `result.reopen` never used). Original group dialog has no such field. | `lib/ui/apps_tab.dart:722-748` (esp. `:728`), field `:492-499`; original `AppGroupDialogs.kt:147-171` | **DEAD CONTROL — NEW** (§3). Per-app use of the same field *is* wired (`apps_tab.dart:354-360`). |
| 2 | 🔴 **`FocusConfig.suspendGroups`** — persisted/serialized, no picker ever sets it, `_syncEffects` never consumes it. Focus can never suspend group members. | `lib/domain/focus.dart:20-70`; `lib/ui/impulse_focus_screens.dart:403-435` | **DEAD plumbing — NEW** (§17, §21) |
| 3 | 🔴 **`FocusConfig.restrictions` effect loop** — `_syncEffects` applies/clears it every phase change, but no UI can populate it; always `[]` in practice. Restrictions-during-focus unreachable through the app. | `impulse_focus_screens.dart:416-431`; `focus.dart:21` | **DEAD-in-effect — NEW** (§17, §22); CA F25 evidence overstates this |
| 4 | 🟡 **Usage-warning stage rows** — no editor exists for minutes/type/vibration count; "Add stage" hardcodes (10 min, silent). Rows are display+delete only. | `lib/ui/config_screens.dart:582-605` | **PARTIAL-DEAD — NEW** (§12) |
| 5 | 🟡 **Suspension-log rows** — no `onTap`; the original opens full app management for that app. | `lib/ui/config_screens.dart:~675-690`; original `SuspensionLogsScreen.kt:129-141` | **INERT vs original — NEW** (§9) |
| 6 | 🟡 **AppManagementSheet `_busy` guard** — read to disable the three protection switches, never assigned in that class; toggles never disabled during an in-flight apply. | `lib/ui/apps_tab.dart:174,242,261,274` | **DEAD guard — NEW** (§2c) |
| 7 | ⚪ **`AppController.lastEvent`** — event stream is listened to and stored, never read by any UI; `packageChanged`/`accessibilityStatus` events therefore have no effect (CA G2 documents the event mismatch; the never-read field itself is the Dart-side mechanism). | `lib/app_controller.dart:44,61` | Dead state — DOC-adjacent (G2) |
| 8 | ⚪ Dead *data* (not controls): `UsageToday.groups` parsed, never displayed (group usage missing from rows, §2b); `InstalledApp.hasExplicitContentRating` parsed, never rendered (EXCLUDED-DOCUMENTED, CA F20); `CapableApp.declaredKeys` parsed, never shown/used in UI; `getUsageToday(packageName:)` argument never passed by any caller; `PrivilegedChannel.shizukuRequestCode` never referenced. | `lib/data/privileged_channel.dart:198-215,103-121,150-158,590,409` | Dead data — mostly NEW except F20 |
| 9 | ⚪ `FocusPhase.done` — never produced by `FocusSession.advance`/`end`, yet the UI handles it. | `lib/domain/focus.dart:11`; `impulse_focus_screens.dart:473,483,509` | Dead branch — NEW (minor) |
| — | **Not** dead (honest non-controls, do not count against parity): Tetris checkbox `onChanged:null`, labelled v1.1 (`impulse_focus_screens.dart:250-273`, DEFERRED-DOCUMENTED CA F22a); `UnavailableTile`s for activity blocker / colour modes / focus schedules (`lib/ui/common.dart:321-343`, `enabled:false` by design, documented CA F18/F25/F26); per-app reopen field labelled "stored; enforcement is v1.1" (`apps_tab.dart:496`, CA F11). | — | Honest placeholders |

---

# E. Recovery-gate regressions — consolidated (all NEW, none in CA)

The original's rule (DF F23/F24): loosening requires a recovery session/challenge; tightening is free with a 5-second undo. Dart regressions found in this part:

1. **Group member removal: no gate at all** — `_editMembers` → `_save` directly (`apps_tab.dart:715-720`); original gates via the triple-loosening formula incl. `!containsAll(old)` (`AppManagementDialogs.kt:166-175`). §3.
2. **Reopening-cooldown decrease: gate term missing** — `_editLimit` checks `isLooserLimit` only (`apps_tab.dart:348-353`); original adds `|| reopeningSeconds < old` (`AppsTab.kt:260-266`). §2d.
3. **Weekly windows can be loosened/dropped unchecked** — loosening computed on daily windows only while a save can drop weekly windows (`apps_tab.dart:379-387`; `privileged_channel.dart:644-652`). §2e.
4. **Tightening limits/windows: no 5-second undo** — Dart tightening branches save immediately (`apps_tab.dart:366-372,393-399`); only protection toggles have undo. §2d.
5. **Impulse config screen: no session gating on any edit** — original disables all controls without a session (`ImpulseLockScreen.kt:64-103`); Dart saves everything immediately (`impulse_focus_screens.dart:88-95,209-274`). §16.
6. **Focus durations/apps: ungated loosening** — `_saveConfig` writes directly (`impulse_focus_screens.dart:387-397,613-622`); original gates each loosening direction and picker changes via `isLooserSet`. §17.
7. **Keyboard shuffle→normal: ungated** — plain `SwitchListTile` (`impulse_focus_screens.dart:273-285`); original gates that direction (`ConfigTab.kt:688-746`). §14.
8. **Blocked-words target swap at equal count: ungated** — Dart `loosening = result.length < old.length` (`config_screens.dart:371`); original uses `containsAll`. §6.
9. **Focus Pause: over-gated (inverse regression)** — Dart always gates Pause (`impulse_focus_screens.dart:545-553`); original plain pause is free, only the releasing long-press pause is gated. §24. (Also: suspension-log clear and usage-warning disable are *stricter* than the original — gated where the original is not: §9, §12. These fail safe but are behavior differences.)

---

# F. viewmodels/ (all 12) → Dart equivalents

**Global effect difference:** Kotlin VMs load in `init`, persist *immediately per operation* to their own `SharedPreferences`, and are Compose-reactive. Dart has no VM layer — state is split between `AppController` (`lib/app_controller.dart:24-138`; only startup/session/language/impulse/forced-removal), per-screen `State` fields (re-loaded on every screen entry, lost on dispose), `ConfigStore` JSON blobs (`lib/data/config_store.dart`), and typed channel models (`lib/data/privileged_channel.dart`). Equivalent for single-screen flows; divergent for cross-screen/persisted state (Focus §29.7, Navigation §29.9). VM citations: `K/<Name>ViewModel.kt`.

## 29.1 ActivityBlockerViewModel — **DEFERRED-DOCUMENTED** (F18, CA §2/G1)
- State/ops: `blockedActivities: MutableStateList<String>` `K/ActivityBlockerViewModel.kt:24`, loaded sorted from `activity_blocker_prefs/blocked_activities` `:26-35`; `addBlockedActivity` (blank/dup guard) `:37`, `removeBlockedActivity` `:44`, `saveBlockedActivities()` `:50`; `getGroupedAccessedActivities()` `:13-18,55-71` (groups the service `accessedActivities` by package, resolves label/icon, sorts by appName).
- Dart: all ABSENT — no state, store key, or channel method; only the labelled tile `lib/ui/config_tab.dart:176-180`. CA G1 already documents the half-wired native side. No NEW VM gap. (Screen: §1.)

## 29.2 AppsViewModel — **PARTIAL**
State: `apps` `K/AppsViewModel.kt:20`, `isLoading:23`, `groups:26`; `init{loadApps,loadGroups}:29`. Dart state: `_AppsTabState{_apps,_error,_includeSystem,_query,_usage}` `lib/ui/apps_tab.dart:26-31`; `_GroupsScreenState{_groups,_error}` `:622-625`; `isLoading` ≡ `_apps==null` sentinel.
| Op (Kotlin) | Dart |
|---|---|
| `loadApps():34` (IO, catch→`emptyList`) | `_load()` `apps_tab.dart:41-61` via `listInstalledApps(includeSystem:)` `privileged_channel.dart:520` — diff: Dart surfaces error+retry instead of empty list |
| `blockApp:48`, `suspendApp:59`, `setUninstallBlocked:70` | `_toggleProtection` + channel setters `apps_tab.dart:194-285`, `privileged_channel.dart:529,536,551` — EQUIVALENT (state re-read natively) |
| `setAppTimeLimit:81`, `setAppTimeWindows:98/103` | `_editLimit/_editWindows` `apps_tab.dart:337-403`; channel `:618,637` — PARTIAL: per-app windows editor daily-only (CA F10) |
| `getAppUsage(pkg):86` | No per-package call; bulk `getUsageToday()` `apps_tab.dart:50,132` — display-equivalent |
| `setAppReopenTime:90`/`getAppReopenTime:94` | Folded into `AppEnforcement.reopenSeconds`/`setTimeLimit(reopenSeconds:)` `privileged_channel.dart:282,618-633`, editor `apps_tab.dart:448,505-518` — storage EQUIVALENT, enforcement DEFERRED-DOCUMENTED (F11) |
| `loadGroups:107`, `createGroup:113`, `deleteGroup:119`, `setGroupTimeLimit:129`, `setGroupPackages:143`, `setPackageGroup:148` | Whole-list model `getGroups/setGroups` `privileged_channel.dart:652,660`; `_load/_save/_create` `apps_tab.dart:632-675`; delete `:786-792`; limit `_editGroupLimit:722-755`; packages `_editMembers:677-720` (= both ops) — EQUIVALENT as ops (gate/UI gaps: §3) |
| `renameGroup(groupId,name):124` | **ABSENT — NEW.** GroupsScreen menu (`apps_tab.dart:782-797`) has members/limit/delete only; `AppGroupModel.copyWith(name:)` `privileged_channel.dart:325` never called with `name` |
| `setGroupTimeWindows:134/139` | **ABSENT in UI — NEW.** Model fields + `copyWith` support it (`privileged_channel.dart:270-350`) but GroupsScreen has no windows editor; `_editGroupLimit` also discards the editor's reopen value (`apps_tab.dart:730,738-748`) |
| `groupFor(pkg):111` | ABSENT as lookup; membership only via group list — minor, **NEW** |
| `getGroupUsage(groupId):153` | **ABSENT — NEW.** `UsageToday.groups` parsed (`privileged_channel.dart:198-215`) but never read (dead data, §28 #8) |

## 29.3 BlockedWordsViewModel — **PARTIAL** (minor)
State: `blockedWordsText:24` (StringSet joined `\n`), `targetPackages:27`, `apps:30`, `passiveWordsMap:33`, `isLoadingApps:36` `K/BlockedWordsViewModel.kt`. Dart: `BlockedWordsState{words,targetPackages,passiveWords}` `privileged_channel.dart:355-375`; screen state `lib/ui/config_screens.dart:258-262`.
- `loadPassiveWords():44` + `loadApps():106` → `_load()` `config_screens.dart:269-282` (`getBlockedWords()`+`listInstalledApps()`, `privileged_channel.dart:668`) — EQUIVALENT.
- `updateWords(text):55` → `_editWords()` `:287-331` → `setBlockedWords(...)` — EQUIVALENT.
- `updatePassiveWords(pkg,text):67` (empty→remove key) → `_editPassive(pkg)` `:384-428` → `setPassiveWords` `privileged_channel.dart:674` — EQUIVALENT for existing lists.
- `toggleAppSelection:86`, `updateTargetPackages(set):99` → `_pickTargets()` `:333-382` — EQUIVALENT.
- Passive-list creation for an arbitrary package: **PARTIAL — NEW** (§6 item 5): "Add per-app list" only offers `candidates.first` of *targetPackages not yet listed* (`config_screens.dart:483-497`).

## 29.4 BrowserRestrictionsViewModel — **PARTIAL**
State: `browsers:19`, `blockedLists:22` `K/BrowserRestrictionsViewModel.kt`; persistence `browser_prefs/blocked_lists_json` `:38-46,87-99` — identical key/schema in Dart `BlockedList` `lib/data/config_store.dart:19-33,183-195`.
- `loadBrowsers():30` — `getPossibleBrowsers()` (intent `ResolveInfo`s) ∩ installed apps → **DIFFERENT SOURCE — NEW at VM level:** Dart `_load()` `config_screens.dart:38-61` uses `listRestrictionCapableApps(requiredKeys:['URLBlocklist','ForceGoogleSafeSearch'])` `privileged_channel.dart:555`. Result = policy-capable browsers only (CA F5 documents the capability requirement, not this list-source substitution). Screen consequences: §7 item 1.
- `loadBlockedLists()/parseJsonToList:38,47` → `ConfigStore.getBlockedLists()` `config_store.dart:183-195` — EQUIVALENT.
- `saveOrUpdateList(id?,title,sitesString):64` — upsert **+ `manager.applyRestrictions()` immediately** → Dart `_editList()+_saveLists()` `config_screens.dart:62-134` — **effect diff, NEW:** save only persists; applying is a separate manual step (`_applyToBrowsers():136-179`, button `:241-245`). Deleting a list likewise no longer auto-applies.
- `removeList(id):80` (+ auto-apply) → delete icon → `_saveLists(where id!=, loosening:true)` `config_screens.dart:225-232` — persist-equivalent, no auto-apply.

## 29.5 ColorFilterViewModel — **DEFERRED-DOCUMENTED** (F26, CA §2)
State (all ABSENT in Dart): `enabled:30`, `modes:33`, `windowsByMode:36`, `coverageByMode:40`, `nightLightIntensity:44`, `nightLightTemperature:47`, `extraDimLevel:50`, `permissionGranted:53`, `grantingPermission:56`, `filtersApplied:59`, `apps:62`, `isLoadingApps:65`, `minuteOfDay:68` `K/ColorFilterViewModel.kt`. Ops (all ABSENT): `windows/coverage/activeWindows(mode):70,72,74`; `isLocked(mode)/lockedWindows/activeWindows:77-85` — **note for a v1.1 port: the VM-level lock concept (active window ∧ no recovery session) must be ported too, not just the filter effect**; `refresh():87`; `updateEnabled:93`/`updateMode:101` (return `false` when locked); `updateNightLightIntensity:110`/`Temperature:118`/`ExtraDimLevel:126`; `isOnlyAdding:134`; `updateWindows:137` (must retain locked windows); `isLoosening:145`/`updateCoverage:148`; `loadAppsIfNeeded:160` (lazy); `grantPermission(cb):169`. Only surviving piece: `grantPermission`'s prerequisite — `grantWriteSecureSettings` on the Setup screen `lib/ui/setup_screen.dart:193-218`. Dart otherwise: labelled tile `lib/ui/config_tab.dart:165-171`; no `color_filter_prefs` handling in `config_store.dart`. Documented deferral, not a new gap. (Screen: §15.)

## 29.6 DeviceOwnerViewModel — **PARTIAL**
State: `shizukuPermission:20` (init `pingBinder() && checkShizukuPermission()`), `isDeviceOwner:23`, permission-result listener `:25-28` (ignores `requestCode`) `K/DeviceOwnerViewModel.kt`. Dart: `_SetupScreenState{_shizuku,_isOwner,_isAdmin,_a11y,_loading,_busy,_provisionOutput,_diagnostics}` `lib/ui/setup_screen.dart:23-33` — state is *re-fetched*, not held reactively in a controller.
| Op | Dart |
|---|---|
| `addShizukuListener:30`/`removeShizukuListener:34`, `isShizukuPermissionGranted:38` | Event subscription in `initState/dispose` `setup_screen.dart:39-57` + `getShizukuState()` `privileged_channel.dart:474` (5-state `ShizukuStatus:75-98`) — EQUIVALENT/superior (CA S1/S2: listener verifies 911, is removed) |
| `isDeviceOwner():40`, `processDeviceOwnerPrivileges:50`, `removeDeviceOwner():48` | `isDeviceOwner()` `privileged_channel.dart:492`; `provisionDeviceOwner():488` (`setup_screen.dart:145`); `removeDeviceOwner():490` in `lib/ui/config_tab.dart:235,291` — EQUIVALENT |
| `isShizukuInstalled():42` | Folded into `ShizukuState.notInstalled` — EQUIVALENT |
| `installShizuku():44` | **ABSENT — NEW:** the `notInstalled` card is text-only (`setup_screen.dart:297-302`), no install action |
| `openShizukuSetupGuide():46` | ABSENT — **documented** (CA F30: text instructions instead of URL) |
| `setPrivateDNS:64`/`getPrivateDNS:66` | `setPrivateDns/getPrivateDns` `privileged_channel.dart:565,568`, UI `lib/ui/config_tab.dart:63-85,311-365` — EQUIVALENT except unset/off absent (CA F7, documented). UI-level DNS gaps: §14 |
| `getAllAccountsViaShizuku:68`, `getCurrentDeviceOwner:73`, `getExtraUsersInfo:75` | Combined `getProvisioningDiagnostics()` `privileged_channel.dart:500`, view `setup_screen.dart:370-408` — EQUIVALENT |
| `getAppNameFromAccountType(ctx,type):70` | **ABSENT — NEW:** diagnostics render raw `a['type']` (`setup_screen.dart:387`), never resolve to an app name |
| `changeAccessibilityPermission(grant):77` | `setAccessibilityEnabled/isAccessibilityEnabled` `privileged_channel.dart:577,580`, UI `setup_screen.dart:59-85,185-195` — EQUIVALENT |
| `getApplicationRestrictions:79`/`setApplicationRestrictions(merge=false):82` | `privileged_channel.dart:540,546`; UI `apps_tab.dart:834-872` — EQUIVALENT as ops (screen behavior: §5) |
| `getAvailableRestrictions(pkg):85` (`List<RestrictionEntry>`) | **ABSENT — NEW:** `AppRestrictionsScreen` never fetches declared entries; users type keys manually (`_addKey` `apps_tab.dart:919-941`; empty-state text `:958-965`). This is the VM-level root of the §5 divergence |
Polling diff (documented, CA S1): original setup UI polled `pingBinder()`/500 ms; Dart is event + pull-refresh only.

## 29.7 FocusModeViewModel — **PARTIAL** (schedules/FGS DEFERRED-DOCUMENTED, F25)
State: `focusMinutes:25`, `shortBreakMinutes:28`, `longBreakMinutes:31`, `cyclesBeforeLongBreak:34`, `autoStartFocus:37`, `soundEnabled:40`, `vibrationEnabled:41`, `suspendedApps:44`, `selectedGroupIds:47`, `focusRestrictions:50`, `schedules:53`, `status:56`, `apps:59`, `groups:62`, `isLoadingApps:65` `K/FocusModeViewModel.kt`. `init:68-77`: `loadApps()` + **1s loop `FocusMode.syncIfDue()+refreshStatus()` forever**. Dart model: `FocusConfig{focusMinutes,breakMinutes,longBreakMinutes,cyclesBeforeLongBreak,suspendApps,suspendGroups,restrictions}` `lib/domain/focus.dart:13-30` (persisted, `config_store.dart:175-181`); `FocusSession{phase,phaseStartedAt,phaseDuration,completedFocusPeriods,pausedRemaining}` `focus.dart:77-95`.
| Op | Dart |
|---|---|
| `updateFocusMinutes:79`/`ShortBreak:84`/`LongBreak:89`/`Cycles:94` | `_durationRow` steppers → `_saveConfig(copyWith…)` `impulse_focus_screens.dart:387-400,581-632,633-660` — EQUIVALENT as ops (bounds/steps/gating differ: §17) |
| `updateAutoStartFocus:100`, `updateSoundEnabled:110`, `updateVibrationEnabled:105` | **ABSENT entirely — NEW:** no fields in `FocusConfig`, no UI, no persistence |
| `updateSuspendedApps:115`, `toggleAppSelection:127` | `_pickApps()` `:661-702` → `copyWith(suspendApps:)` — EQUIVALENT |
| `updateSelectedGroupIds:121`, `refreshGroups:167` (+`groups` state) | **DEAD — NEW:** `suspendGroups` persisted/round-tripped but never set from UI, never used in effects (§28 #2) |
| `updateFocusRestrictions:133`, `toggleRestrictionSelection:138` | **DEAD-EFFECTIVE — NEW:** `restrictions` consumed by `_syncEffects:416,426` but never set from UI → always `[]` (§28 #3) |
| `addOrUpdateSchedule:144`/`deleteSchedule:149`/`toggleSchedule:154`/`refreshSchedules:159` | ABSENT — DEFERRED-DOCUMENTED (labelled tile `impulse_focus_screens.dart:624-628`; `focus_schedules_prefs` allowlisted but unused — CA G1) |
| `refreshStatus:163`, `status` (persisted `FocusMode.getStatus`, `syncIfDue`) | **PARTIAL — NEW:** session is *screen-local, in-memory only*: `_session` `impulse_focus_screens.dart:347-353`, recreated `idle` in `_load():368-383`; 1s ticker only while the screen is mounted `:356-367,436-446`. No `FocusSession` persistence in `ConfigStore`/`AppController`; leaving/disposing the screen loses a running session and its effects-sync state (`_effectsApplied:353`). CA F25 documents "alive-only countdown", not screen-local/non-persisted status |
| `loadApps:172` (apps+groups) | `_load():368` loads apps only |
| Phase machine | `FocusSession.start/advance/pause/resume/end` `focus.dart:114-178` — EQUIVALENT, except `FocusPhase.done` `focus.dart:11` never produced yet UI handles it (§28 #9); resume-phase divergence §24 |

## 29.8 ImpulseLockViewModel — **PARTIAL** (Tetris DEFERRED-DOCUMENTED)
State: `challenges:27`, `tetrisMinutes:30`, `readingSource:33` (BIBLE/QURAN/QUOTES/CUSTOM), `storedReadingCount:37` + derived `availableReadings:42`/`readingCount:46` (clamped to available), `customPassages:List<ReadingPassage{text,source}>:39`, `action:49`, `durationMinutes:52`, `suspendedApps:55`, `apps:58`, `isLoadingApps:61` `K/ImpulseLockViewModel.kt`. Persistence per-op via `SecurityManager` (`security_prefs`). Dart: `ImpulseConfig{action,durationMinutes,suspendApps}` JSON blob `lib/data/config_store.dart:36-66,159-165` + separate keys for challenges/phrases/shuffle `:125-157`; screen state `lib/ui/impulse_focus_screens.dart:26-33`; live lock `AppController.impulseLock` `lib/app_controller.dart:47,116-126` + `lib/domain/recovery.dart:229-268` (30s measured ticker, `app_controller.dart:74-94` — alive-only, CA F21 documented).
| Op | Dart |
|---|---|
| `toggleChallenge(type):68` | Checkbox list `impulse_focus_screens.dart:249-281` → `setChallengeSelection` (empty→force `math`) — EQUIVALENT for math/words/reading; tetris checkbox disabled `:267-281` |
| `updateTetrisMinutes:75` (clamp 1–15) | ABSENT — DEFERRED-DOCUMENTED (F22a; `ChallengeType.tetris.isAvailableInV1==false` `lib/domain/challenges.dart:25`) |
| `updateReadingSource:81`, `updateReadingCount:86` (clamp `1..availableReadings`), `availableReadings/readingCount` | **ABSENT — NEW:** no source/count state anywhere in Dart. `ReadingChallengeView` always uses `samplePassages + customPhrases` with fixed `requiredPassages=5` (`lib/ui/challenges_ui.dart:162-191,297-300`; `lib/domain/challenges.dart:188-205`). CA F22 documents only the uncopied corpus — not the missing source-selection/count-clamping state |
| `addCustomPassage(text,source):92` (blank guard), `removeCustomPassage(index):99` | **PARTIAL — NEW (minor):** bulk plain-text edit only, `_editPhrases()` `impulse_focus_screens.dart:297-338` → `setCustomReadingPhrases(List<String>)`. No per-passage `source` attribution (Dart passages are bare strings, titled `'Your phrase'` `challenges_ui.dart:185-187`); removal only by deleting a line |
| `updateAction:105`, `updateDurationMinutes:110` (clamp 15–360) | Radio tiles + slider `impulse_focus_screens.dart:196-230` → `_saveConfig` — EQUIVALENT |
| `toggleAppSelection:119` | `_pickSuspendApps():113-157` — EQUIVALENT |
| `loadApps:126` | `_load():50-69` — EQUIVALENT |
| Extra in Dart (not in this VM) | `shuffleKeyboard` `config_store.dart:152-157`, UI `impulse_focus_screens.dart:282-296`; panic execution in `lib/ui/lock_screen.dart:76-105` |

## 29.9 NavigationViewModel — **PARTIAL**
Kotlin: `stack:MutableStateList<String>={"restrictions"}:9` (private), `selectedAppForRestrictions:AppItem?:10`, `selectedTab():12`, `navigateTo(screen):14` (root tabs `restrictions/apps/config` *clear* the stack, others push), `navigateToAppRestrictions(app):21` (stores app + pushes `app_restrictions`), `goBack():26` (pop if size>1 else `false`) `K/NavigationViewModel.kt`. Dart: no VM — `_AppShellState._index:int=0` `lib/main.dart:89`, `IndexedStack` + pill bar `:94-137`; sub-screens via imperative `Navigator.push`.
- `selectedAppForRestrictions` — ABSENT as shared state; equivalent-by-construction: app passed as widget arg (`AppManagementSheet{app}` `apps_tab.dart:152-167`; `AppRestrictionsScreen{packageName,label}` `:809-820`).
- `navigateTo/goBack` — Flutter `Navigator` handles pushed screens; tab switching is `setState(_index)` `main.dart:111`. No explicit stack, no `goBack():Boolean` equivalent.
- **Default tab differs — NEW:** the original starts on `restrictions` (`:9,12`); Dart `_index=0` is the *extra* **Setup/Status** tab (`main.dart:94-99`: Setup, Restrictions, Apps, Config) — Restrictions is index 1. CA does not cover navigation.
- **State-retention diff:** the original stack model destroys/recreates on root navigation; `IndexedStack` *preserves* all tab `State` — generally favourable, but combined with §29.7 it means Focus state survives tab switches yet not screen-pop/process death.

## 29.10 RestrictionsViewModel — **PARTIAL**
State: `draftRestrictions:MutableStateMap:13`, `appliedRestrictions:MutableStateMap:16`, `recommendedKeys:18`/`otherKeys:19`/`allKeys:20` (private), `resourceNameFor(key):22` `K/RestrictionsViewModel.kt`. Dart: `_RestrictionsTabState{_restrictions:List<UserRestriction>{key,active,recommended}, _draft:Map<String,bool>, _notOwner,_applying,_query}` `lib/ui/restrictions_tab.dart:23-30` — `r.active` serves as `appliedRestrictions` (functionally equivalent).
| Op | Dart |
|---|---|
| `loadRestrictions():28` (no-op if not Device Owner; draft=applied) | `_load():39-62` → `listUserRestrictions()` `privileged_channel.dart:532`; not-owner → dedicated state `:106-134` — EQUIVALENT |
| `toggleDraft(key,enabled):45` | Inline `setState(()=>_draft[r.key]=v)` `restrictions_tab.dart:176-196` — EQUIVALENT |
| `toggleAllDrafts(keys,enabled):49`, `isAllDraftsEnabled(keys):69` | **ABSENT — NEW:** no select-all/clear-all control or section-header toggle (§8) |
| `applyChanges():55` | `_apply():78-104` — EQUIVALENT at VM level |
| `hasPendingChanges():71` (VM-level pending state) | `_dirty` getter `restrictions_tab.dart:64-68` — EQUIVALENT |
| `isLoosening():76` | No named equivalent; implicit in `_apply:82-86` (`toClear.isNotEmpty` → session required, and refusal aborts the *whole* apply including tightenings) — behavior noted |
| `resourceNameFor:22`, `recommendedKeys/otherKeys` | `recommended` flag from native `UserRestriction.recommended` `privileged_channel.dart:137-147`; sections hardcoded `'Recommended'/'Other'` `restrictions_tab.dart:157-158`. `resourceNameFor` **ABSENT — NEW (minor):** keys displayed raw (`Text(r.key)` `:188`) |

## 29.11 UsageWarningViewModel — **PARTIAL** (delivery DEFERRED-DOCUMENTED, F12)
State: `enabled:19` (default `UsageWarningSettings.DEFAULT_ENABLED=true`), `stages:List<UsageAlertStage{id:UUID,minutesBefore,type,vibrationCount}>:24` (seeded via `loadOrSeedStages`); `persist():53` `K/UsageWarningViewModel.kt`. Dart: `UsageWarningStage{minutesBefore,type,vibrationCount}` — **no `id`** — `lib/data/config_store.dart:70-92`; defaults `15 silent / 5 sound / 1 vibrate×1 / 0.5 vibrate×3` `:94-99`; `getUsageWarnings/setUsageWarnings` `:202-224`; screen state `lib/ui/config_screens.dart:508-514`.
| Op | Dart |
|---|---|
| `updateEnabled(value):27` | Switch → `_save(v,_stages!)` `config_screens.dart:554-580` — EQUIVALENT **except default:** Dart `getUsageWarnings` returns `enabled=false` when unset (`config_store.dart:203`: `== true`); the original defaults **true** — first-run state differs, **NEW** |
| `addStage():32` — minutes = `min(existing)/2` floored at `0.1`, type `SOUND`, new UUID | **DIFFERENT — NEW:** Dart appends fixed `UsageWarningStage(minutesBefore:10, type:silent)` `config_screens.dart:590-600` regardless of existing stages |
| `removeStage(id):37` | Delete-by-index `config_screens.dart:584-589` — user-equivalent |
| `updateStageMinutes(id,m):41`, `updateStageType(id,t):45`, `updateStageVibrationCount(id,c):49` | **ABSENT — NEW:** stages are display-only ListTiles (`:581-589`, no `onTap`/editor). CA F12 calls this screen an "editor" and documents only the missing notification delivery — not that existing stages cannot be edited at all (§12) |
| Seeding | Dart returns defaults *without persisting* until first `_save` (`config_store.dart:216-217` vs `loadOrSeedStages`) — minor |

## 29.12 VisualBlockingViewModel — **DEFERRED-DOCUMENTED** (F16+F17, CA §2)
State (all ABSENT in Dart): `enabled:24` (default false), `targetPackages:27` (default `{com.reddit.frontpage}`), `selectedCategories:33` (default `{hentai,porn,sexy}`), `threshold:Float:39` (default 0.5), `suspendEnabled:44`, `suspendBlockCount:49` (default 5), `suspendWindowMinutes:57` (default 15), `suspendDurationMinutes:65` (default 30), `apps:73`, `isLoadingApps:76` `K/VisualBlockingViewModel.kt`. Ops (all ABSENT): `updateEnabled:83`, `updateTargetPackages:88`, `toggleAppSelection:93`, `toggleCategory:100`, `updateThreshold:107`, `updateSuspendEnabled:112`, `updateSuspendBlockCount:122`/`updateSuspendWindowMinutes:127`/`updateSuspendDurationMinutes:132` (VM nuance for a v1.1 port: in-memory value accepts 0 while typing, persists only if `>=1`), `loadApps:137`. Dart: zero references — no screen, no `visual_blocking_prefs` in `config_store.dart`, no placeholder (verified, CA F16/F17). The suspend-escalation trio is the F17 VM surface. (Screen: §13.)

### ViewModel summary

| ViewModel | Class |
|---|---|
| ActivityBlocker | DEFERRED-DOCUMENTED (F18/G1) |
| Apps | PARTIAL — NEW: `renameGroup`, group windows editor, `getGroupUsage`/`groupFor` |
| BlockedWords | PARTIAL — NEW: passive-list creation restricted to first unlisted target app |
| BrowserRestrictions | PARTIAL — NEW: browser-list source changed; save/remove no longer auto-applies |
| ColorFilter | DEFERRED-DOCUMENTED (F26) |
| DeviceOwner | PARTIAL — NEW: `installShizuku`, `getAppNameFromAccountType`, `getAvailableRestrictions` |
| FocusMode | PARTIAL — NEW: `autoStart/sound/vibration` absent; `suspendGroups`+`restrictions` dead; session non-persisted/screen-local. Schedules/FGS DEFERRED-DOCUMENTED |
| ImpulseLock | PARTIAL — NEW: `readingSource/readingCount/availableReadings` absent; custom passages lose `source`. Tetris DEFERRED-DOCUMENTED |
| Navigation | PARTIAL — NEW: default tab is Setup not Restrictions; no stack/`selectedApp` state |
| Restrictions | PARTIAL — NEW: `toggleAllDrafts/isAllDraftsEnabled`, `resourceNameFor` absent |
| UsageWarning | PARTIAL — NEW: stage minutes/type/vibration uneditable, `addStage` semantics differ, default `enabled` true→false, no stage `id`. Delivery DEFERRED-DOCUMENTED |
| VisualBlocking | DEFERRED-DOCUMENTED (F16/F17) |

No `EXCLUDED-DOCUMENTED` ViewModel exists (excluded features F20/F29/F34 have no VM among the 12), and no VM is fully `EQUIVALENT` or fully `MISSING` — every non-deferred VM is PARTIAL for the reasons itemised above.

---

*End of Part 4. Cross-references: native/service parity (parts 1–3), recovery/challenges/lock-screen flows (part 5). All NEW findings above are candidates for CA §6-style gap entries (G5+) if the parent audit adopts them.*
