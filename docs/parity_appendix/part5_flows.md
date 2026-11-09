# Parity Audit — Part 5 of 5: Challenges, Recovery Gate, Setup Flow, Misc Utils, Original Tests

**Method:** read-only, function-by-function. Every claim cites `file:line` on BOTH sides.
Reference root (REF): `reference/dechainer-zip/dechainer-1.12.0/app/src/main/java/io/github/warleysr/dechainer/`
Ours root (OUR): `project/`
Classifications: EQUIVALENT / PARTIAL / MISSING / DEFERRED-DOCUMENTED / EXCLUDED-DOCUMENTED.
Findings **not** present in `project/docs/COMPLIANCE_AUDIT.md` are marked **NEW**.
No project code was edited by this audit.

---

## 1. `screens/challenges/ChallengeScreens.kt` — Math challenge

### Original behavior spec
- Exactly **5 problems** (`val totalProblems = 5`, REF `screens/challenges/ChallengeScreens.kt:66`).
- **Addition only.** Both operands `Random.nextInt(10, 99)` = **10..98** (REF `ChallengeScreens.kt:61-62`); prompt is always `"$num1 + $num2 ="` (REF `ChallengeScreens.kt:78`).
- Correct answer advances; on the 5th correct answer `onSuccess()` fires (REF `ChallengeScreens.kt:98-106`).
- **A wrong answer resets the whole challenge**: `isError = true; problemIndex = 0` and both operands are regenerated (REF `ChallengeScreens.kt:107-112`). The full set of 5 must be solved consecutively.

### Ours
- Count matches: `requiredProblems = 5` (OUR `lib/domain/challenges.dart:48`).
- **Operator drift **NEW**:** generator randomly picks among **4 operations** — addition `12 + nextInt(88)` = 12..99, subtraction 30..119 − 5.., multiplication 3..12 × 3..12, division (OUR `lib/domain/challenges.dart:66-82`). The original has no subtraction/multiplication/division and a different addition range (10..98 vs 12..99).
- **Reset drift **NEW** (numeric/behavioral defect):** `MathChallenge.submit()` returns `false` on a wrong answer and **keeps** `_solved` (OUR `lib/domain/challenges.dart:89-94`). The original zeroes progress. Ours is strictly weaker friction than the original.
- The shipped test actually pins the *drifted* behavior only vacuously: it submits one wrong answer at `_solved == 0` and asserts `solved == 0` (OUR `test/challenges_test.dart:266-268`), which cannot distinguish reset-vs-keep.

### Classification: **PARTIAL** (count equivalent; operators, operand ranges, and wrong-answer semantics all differ)

---

## 2. `screens/challenges/ChallengeScreens.kt` — Words challenge

### Original behavior spec
- Pool `COMMON_WORDS`: ~190 **five-letter** lowercase words (REF `ChallengeScreens.kt:133-141`).
- Sequence pre-generated as `List(48)` random draws (REF `ChallengeScreens.kt:146`), but the pass condition and the on-screen counter are **32 words**: `"${currentIndex + 1} / 32"` (REF `ChallengeScreens.kt:162`), success when `currentIndex + 1 >= 32` (REF `ChallengeScreens.kt:188`).
- Interaction is **per-keystroke, not per-word submission**: input is lowercased and truncated to the target length; the word auto-advances the instant the input equals the target (REF `ChallengeScreens.kt:178-196`). Letters are colored correct/incorrect live in both the target display and a `VisualTransformation` (REF `ChallengeScreens.kt:164-176, 198-211`).
- **There is no failure/reset path at all**: a mistyped letter simply does not advance; the user must correct it in place. `currentIndex` never decreases.

### Ours
- Required count matches: `requiredWords = 32` (OUR `lib/domain/challenges.dart:99`).
- **Pool drift **NEW**:** `defaultWordPool` has only **24 words**, of mixed length 5–10 letters (`patience`, `discipline`, …) (OUR `lib/domain/challenges.dart:109-114`) vs the original's ~190 five-letter words.
- **Interaction drift **NEW**:** whole-word submission via a "Check" button (OUR `lib/ui/challenges_ui.dart:99-122`); no per-letter live coloring, no auto-advance on exact type.
- **Invented penalty **NEW** (defect):** on a wrong submission `WordsChallenge.submit()` sets `_index = 0` — "a mistake restarts the streak" (OUR `lib/domain/challenges.dart:128-137`). The original has no streak and no reset; ours punishes a typo on word 31 by discarding all 31 words, a materially harsher behavior the original never had. The domain comment ("as in the original") and the test name ("a mistake restarts the streak", OUR `test/challenges_test.dart:287-303`) both assert this is original behavior — it is not.

### Classification: **PARTIAL** (32-word count equivalent; pool, input model, and failure semantics differ; streak-reset is an undocumented invention)

---

## 3. `screens/challenges/ReadingChallenge.kt` + `data/ReadingPassages.kt`

### Original behavior spec
- Paced reveal computed per word: `WORD_BASE_MS = 300`, `LETTER_MS = 45` per letter/digit, `SHORT_PAUSE_MS = 250` after `, ; : — -`, `LONG_PAUSE_MS = 500` after `. ! ?`, `LEAD_IN_MS = 600` before the first word (REF `screens/challenges/ReadingChallenge.kt:29-33, 43-56`). A 5-letter word therefore occupies ≈ 300 + 5×45 = **525 ms** plus any punctuation pause. Words fade unread → reading (primary) → read over `SETTLE_MS = 350` (REF `ReadingChallenge.kt:36, 96-112`).
- The "Next/Finish" button is **disabled until the timed reveal of the current passage completes** (`enabled = finished`, REF `ReadingChallenge.kt:148-156`); the user advances manually, passage by passage.
- Passage selection: `ReadingLibrary.pick()` returns `all.shuffled().take(getReadingCount().coerceAtMost(all.size))` (REF `data/ReadingPassages.kt:50-53`). Count default **5**, minimum **1**, no maximum besides library size (REF `security/SecurityManager.kt:49-50, 196-199`).
- Sources are user-configurable: `ReadingSource { BIBLE, QURAN, QUOTES, CUSTOM }` (REF `security/SecurityManager.kt:26-29`), ~20 passages each for BIBLE/QURAN/QUOTES, each passage bilingual EN/PT and resolved by the current locale's language (REF `data/ReadingPassages.kt:24-47`; REF `ReadingChallenge.kt:62-64`). CUSTOM passages are objects `{text, source}` (attribution string) stored as JSON (REF `security/SecurityManager.kt:229-247`).
- Edge case: if the picked list is empty (CUSTOM with no phrases), the challenge **succeeds immediately** (REF `ReadingChallenge.kt:66-70`).

### Ours
- Count default matches: `requiredPassages = 5` (OUR `lib/domain/challenges.dart:193`); the runner always uses the default — `ReadingChallengeView` is constructed without a count (OUR `lib/ui/challenges_ui.dart:276-279`).
- **Timing drift **NEW**:** flat `wordInterval = 450 ms` per word regardless of word length or punctuation (OUR `lib/domain/challenges.dart:195`; timer at OUR `lib/ui/challenges_ui.dart:190-199`). A 5-letter word is revealed in 450 ms vs the original's ~525 ms; a 10-letter word in 450 ms vs ~750 ms; sentence-final pauses (500 ms) do not exist. Ours reads uniformly ~15–40 % faster.
- **Interaction drift:** auto-advance on a `Timer.periodic` with no per-passage gate/button (OUR `lib/ui/challenges_ui.dart:190-199`) vs the original's finish-gated manual "Next".
- **Source/count configurability MISSING **NEW** (beyond the documented corpus decision):** there is no reading-source selection and no count setting anywhere in ours — `ImpulseLockScreen` exposes only custom-phrase editing (OUR `lib/ui/impulse_focus_screens.dart:286-290, 296-338`). The original exposes source radio options, a count slider capped at the source's available count, and a custom-passage editor with separate text + attribution fields (REF `screens/tabs/ImpulseLockScreen.kt:253-340`). Ours stores custom phrases as bare strings (OUR `lib/data/config_store.dart:138-148`) — the attribution field is dropped.
- **Pool semantics drift:** ours always plays the 5 bundled samples first and *appends* custom phrases to the same pool, cycling with `% passages.length` if more passages are required than exist (OUR `lib/domain/challenges.dart:207`; OUR `lib/ui/challenges_ui.dart:183-189`). The original's CUSTOM source *replaces* the library, selection is shuffled, and the count is capped at the library size (no repeats). The empty-custom-list instant-success edge case cannot occur in ours because the sample pool is never empty.
- Corpus itself: 5 original sample passages (OUR `lib/domain/challenges.dart:144-176`) vs ~60 bilingual passages — **documented decision, not a defect** (COMPLIANCE_AUDIT F22 note). The drifts above are separate from that decision.

### Classification: **PARTIAL** (default count 5 equivalent; pacing formula, advance model, source/count configuration, custom-passage schema, and selection semantics differ)

---

## 4. `screens/challenges/TetrisChallenge.kt` + `TetrisSounds.kt`

### Original behavior spec (for the record)
- Full game: board **8 × 20** (REF `screens/challenges/TetrisChallenge.kt:52-53`), 7-bag randomizer (REF `TetrisChallenge.kt:165-168`), gravity `max(200, 1000 − (level−1)×50)` ms (REF `TetrisChallenge.kt:154-155`), **10 lines per level** (REF `TetrisChallenge.kt:58`), lock delay **500 ms** with max **15** lock resets (REF `TetrisChallenge.kt:59-60`), wall kicks `0, −1, +1, −2, +2` (REF `TetrisChallenge.kt:224-231`), ghost piece, hold-less next preview.
- Pass condition is **survived play time**, not score: `requiredMillis = minutes × 60_000` and played time accumulates only while the user has interacted within the last **8 s** (`IDLE_TIMEOUT_MS = 8_000`, REF `TetrisChallenge.kt:55, 330-367`). Top-out does not fail the challenge; the board clears and play continues (REF `TetrisChallenge.kt:278-282`).
- Duration configurable **1–15 min, default 3** (REF `security/SecurityManager.kt:45-47, 160-171`).
- Sound: 8 synthesized effects (MOVE/ROTATE/LOCK/HARD_DROP/CLEAR/CLEAR_BIG/LEVEL_UP/TOP_OUT) generated as WAV at 22 050 Hz, played via `SoundPool` only in `RINGER_MODE_NORMAL`, toggle persisted as `tetris_sound` default **true** (REF `screens/challenges/TetrisSounds.kt:18-61`; REF `security/SecurityManager.kt:173-183`).

### Ours
- No Tetris implementation. `ChallengeType.tetris` exists, `isAvailableInV1 == false` (OUR `lib/domain/challenges.dart:23-26`); the runner filters it out and prints an explicit "skipped — it was not simulated" notice (OUR `lib/ui/challenges_ui.dart:246-262`); the selection checkbox is disabled with a v1.1 note (OUR `lib/ui/impulse_focus_screens.dart:254-272`). Consequently the original's Tetris minutes (1–15, default 3) and sound settings have no counterpart either.
- One residual inconsistency: the tetris *config* checkbox is disabled, yet a stored config containing tetris (e.g. written by `ConfigStore` defaults or future versions) is silently skipped at run time — behavior is honest (notice shown) but the challenge then provides less friction than configured.

### Classification: **DEFERRED-DOCUMENTED** (F22 partial — matches COMPLIANCE_AUDIT row F22a)

---

## 5. `screens/common/ChallengeRunner.kt`

### Original behavior spec
- Runs the configured list **sequentially in list order**; `ChallengeScaffold` shows "step i / N" when N > 1 and a persistent **Give up** button that aborts the whole sequence via `onGiveUp` (REF `screens/common/ChallengeRunner.kt:16-37`; REF `screens/challenges/ChallengeScreens.kt:23-56`).
- Tetris receives its minutes from `SecurityManager.getTetrisMinutes(context)` at run time (REF `ChallengeRunner.kt:29-32`).
- The list comes from `SecurityManager.getAccessChallenges()`: stored set sorted by enum ordinal; when nothing is stored, a legacy fallback maps `impulse_lock_mode == "NORMAL"` → `[MATH]`, `"HARD"` → `[WORDS]`, otherwise **empty list** (REF `security/SecurityManager.kt:139-152`). An empty list is a legitimate configuration: `RecoveryGate.confirm()` then starts the session with no challenges (REF `screens/common/RecoveryGate.kt:71-77`).

### Ours
- Sequential runner in enum order: `ChallengeRunnerView` sorts by `type.index` and advances on completion (OUR `lib/ui/challenges_ui.dart:238-267`) — equivalent ordering.
- **Give-up affordance differs:** the original's scaffold-level Give up aborts mid-challenge; ours has only the gate dialog's **Cancel** button, which remains visible during challenges (OUR `lib/ui/recovery_ui.dart:474-479`). Net effect (abort possible) is similar, but there is no per-challenge give-up control inside the runner itself. PARTIAL (minor).
- **Empty-selection drift **NEW**:** ours makes an empty challenge set **impossible**: `ConfigStore.getChallengeSelection()` defaults to `[math]` when unset *and* coerces an empty stored result back to `[math]` (OUR `lib/data/config_store.dart:125-135`), and the settings UI re-adds Math if the user unchecks the last challenge (OUR `lib/ui/impulse_focus_screens.dart:262-264`: `if (next.isEmpty) next.add(ChallengeType.math)`). The original permits "code only, no challenges". Ours is stricter — safe direction, but a real behavioral difference not noted in the audit.

### Classification: **PARTIAL**

---

## 6. `screens/common/PendingChange.kt` — 5-second undo + loosening calculus

### Original behavior spec
- `UNDO_WINDOW_MS = 5000` (REF `screens/common/PendingChange.kt:18`).
- **Deferred-apply semantics:** `schedule()` shows an indefinite snackbar and the `action` runs **only after** the 5 s timeout elapses (or the snackbar is otherwise dismissed); tapping Undo invokes `onUndo` and the action **never runs** (REF `PendingChange.kt:26-37`). Dismissing a currently-shown snackbar commits its pending change immediately, so changes never overlap (REF `PendingChange.kt:27-28`).
- Loosening calculus (REF `PendingChange.kt:40-81`):
  - `isLooserLimit`: per-day effective cap, `0` = unbounded (REF `PendingChange.kt:42-45`).
  - `isLooserWindows` (list form): **per-minute coverage** over all 1440 minutes — loosening iff any minute is allowed by the new windows and not by the old; empty list = always allowed (REF `PendingChange.kt:48-51`). A `TimeWindows` overload applies it per weekday (REF `PendingChange.kt:53-56`).
  - `isLooserRestrictions` (Bundle): Boolean true→not-true; String non-empty→empty/missing; Number non-zero→0/missing; Array new-set not ⊇ old-set; nested Bundle recursion; key missing in new bundle counts via the null path (REF `PendingChange.kt:58-79`).
  - `isLooserSet`: `!new.containsAll(old)` (REF `PendingChange.kt:81`).

### Ours
- Window length matches: `undoWindow = Duration(seconds: 5)` (OUR `lib/domain/recovery.dart:116`).
- **Apply-order inversion **NEW** (core defect):** `PendingChange.run()` **applies first**, records `_appliedAt`, and `undo()` afterwards calls `revert()` (OUR `lib/domain/recovery.dart:131-145`). Consequences the original does not have: (a) the tightening is live during the 5 s window; (b) undo depends on a compensating revert succeeding — the original's undo is free because nothing happened yet; (c) process death inside the window leaves the change applied in ours, un-applied in the original. The audit's F23 row describes ours as "tightening free (5 s undo)" without noting the inversion.
- **Session interaction drift:** original `RecoveryGate.change()` routes tightening through `PendingChange` **only when no session is active**; with an active session tightening applies immediately with no undo offer (REF `screens/common/RecoveryGate.kt:58-67`; pinned by `RecoveryGateTest`, §14). Ours `runTighteningWithUndo()` always applies + offers undo regardless of session state (OUR `lib/ui/recovery_ui.dart:505-530`).
- `isLooserLimit`: **EQUIVALENT** (same cap semantics, 0 = unbounded, per-day max comparison; OUR `lib/domain/recovery.dart:28-46`).
- **`isLooserWindows` drift **NEW** (defect):** ours compares **total allowed minutes only** (OUR `lib/domain/recovery.dart:56-68`). Counterexample: old `[(480,720)]` (08:00–12:00) → new `[(1200,1440)]` (20:00–24:00) has equal total minutes → ours returns `false` (not loosening, applies without a session), while the original's coverage test returns `true` (minutes 1200–1439 are newly allowed). A same-length window *move* therefore bypasses the recovery gate in ours. Ours also has no per-weekday windows overload in this function.
- **`isLooserRestrictions` drift **NEW**:** ours (OUR `lib/domain/recovery.dart:85-104`) (a) treats any numeric **decrease** as loosening (`newV < oldV`), where the original only treats →0/missing as loosening — over-strict, safe direction; (b) compares lists **by length only**, where the original compares set containment — replacing `['a','b']` with `['c','d']` is loosening in the original, neutral in ours (gate bypass, unsafe direction); (c) **does not implement the String case at all** — a non-empty string restriction cleared to `''`/absent-with-key-present is loosening in the original (REF `PendingChange.kt:66-68`) and undetected in ours; (d) no nested-map recursion.
- `isLooserSet`: no standalone counterpart; set-shrink checks are inlined at call sites as length comparisons (e.g. OUR `lib/ui/config_screens.dart:161-162, 320-321`), which inherit the length-vs-containment weakness in (b).

### Classification: **PARTIAL** (5 s constant equivalent; apply/undo mechanics inverted; windows and restrictions calculus materially weaker than the original)

---

## 7. `security/SecurityManager.kt` — session, code generation, forced removal (recovery core)

### Original behavior spec
- Session: `startSession()` sets `sessionEndTime = now + 10 × 60 × 1000` ms (REF `security/SecurityManager.kt:63-65`); `renewSession()` restarts the 10 min **only if still active** (REF `SecurityManager.kt:68-71`); state is in-memory Compose state; `MainActivity.onDestroy()` calls `endSession()` (REF `activities/MainActivity.kt:253-256`).
- Code: `generateRecoveryCode(length = 16)` from `CHAR_POOL = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"` using `SecureRandom` (REF `SecurityManager.kt:39, 334-338`). Stored **plaintext** in `recovery_prefs/recovery_code` (REF `SecurityManager.kt:340-353`). `validateRecoveryCode()` returns `true` unconditionally while a session is active, else exact string equality (REF `SecurityManager.kt:356-360`).
- Forced removal: target **48 h** accumulated (`48L × 60 × 60 × 1000`, REF `SecurityManager.kt:394`); accumulation is **elapsedRealtime-based and persisted incrementally** — every `getForcedRemovalRemainingTime()` call folds `now − lastElapsed` into `forced_removal_accumulated` and re-stamps `forced_removal_last_elapsed`, so progress survives process death and reboot (post-reboot `elapsedRealtime` resets, handled by the `now >= lastElapsed ? diff : now` branch) (REF `SecurityManager.kt:362-397`).
- Defaults pinned here: impulse 15/360/60 min (REF `SecurityManager.kt:41-43`), Tetris 1/15/3 min (REF `SecurityManager.kt:45-47`), reading count default 5 / min 1 (REF `SecurityManager.kt:49-50`), impulse action default `TIMER_ONLY` (REF `SecurityManager.kt:255-258`), shuffle keyboard default `false` (REF `SecurityManager.kt:124-127`).

### Ours
- Session duration **equivalent**: `RecoverySession(duration = Duration(minutes: 10))`, renew only when active, in-memory only (OUR `lib/domain/recovery.dart:148-190`). Top-bar countdown + renew + end exist (OUR `lib/ui/recovery_ui.dart:537-574`), mirroring REF `activities/MainActivity.kt:138-160`.
- Code format **equivalent**: Kotlin `RecoveryStore.generateCode()` — 16 chars, A–Z, `SecureRandom` (OUR `android/.../security/RecoveryStore.kt:44-50`); channel surface `generateRecoveryCode` / `setRecoveryCode` / `verifyRecoveryCode` / `isRecoveryCodeSet` (OUR `android/.../channel/PrivilegedChannelHandler.kt:225-238`; OUR `lib/data/privileged_channel.dart:593-605`).
- Storage: **deliberate, documented deviation** — salted PBKDF2WithHmacSHA256, 210 000 iterations, 16-byte salt, constant-time compare, dedicated `recovery_secure` store, no plaintext and no code getter (OUR `RecoveryStore.kt:29-99`). Consequence (documented): the code can never be re-displayed. Matches COMPLIANCE_AUDIT F24 / ARCH §7.1.
- **Normalization drift (minor, **NEW**):** ours strips spaces and uppercases before hashing/verifying (`RecoveryStore.normalize`, OUR `RecoveryStore.kt:83-84`), so grouped entry "XXXX XXXX…" verifies. The original compares the already-filtered input by exact equality; its UI pre-filters to A–Z uppercase (REF `screens/common/RecoveryConfirmDialog.kt:52-55`), making the net user-visible behavior effectively the same.
- Forced removal total **equivalent**: `ForcedRemoval.total = Duration(hours: 48)` (OUR `lib/domain/recovery.dart:208-216`).
- **Forced-removal accounting drift (documented, restated precisely):** ours advances only by deltas measured by a 30 s Dart ticker **while the app process is alive** (OUR `lib/app_controller.dart:77-97`); the original folds in elapsed time on every read, including time the process was dead. Ours can therefore take unboundedly longer than 48 h of wall time (never shorter — fail-safe direction). COMPLIANCE_AUDIT F2 already records this.
- **Impulse default-action drift **NEW**:** original default `ImpulseAction.TIMER_ONLY` (REF `SecurityManager.kt:255-258`); ours `ImpulseConfig` defaults to `ImpulseAction.timerAndSuspend` in both the constructor and the JSON fallback (OUR `lib/data/config_store.dart:36-56`). With a fresh install and no apps picked the observable effect is identical (empty suspend list), but the stored default differs and diverges as soon as apps are picked for another purpose.

### Classification: **PARTIAL** (session + code format equivalent; storage deviation documented; forced-removal accounting documented-weaker; impulse default differs)

---

## 8. `screens/common/RecoveryGate.kt` + `RecoveryConfirmDialog.kt`

### Original behavior spec
- `RecoveryGate.run()`: executes immediately when **no code is set** or a session is active; otherwise stashes the action and shows the code dialog (REF `screens/common/RecoveryGate.kt:47-56`).
- `change(loosening)`: loosening → `run()`; tightening → immediate if session active, else `PendingChange.schedule()` (REF `RecoveryGate.kt:58-67`).
- **Order is code FIRST, challenges SECOND:** `confirm(code)` validates the code; only on success, if challenges are configured and no session is active, `isChallenging = true` and the challenge dialog runs; `challengesDone()` then starts the session and invokes the pending action (REF `RecoveryGate.kt:69-87`). Dismissal/give-up invokes `pendingCancel` (rollback of optimistic UI) and clears state (REF `RecoveryGate.kt:89-97`).
- Code entry: input filtered to A–Z uppercase, max 16; Confirm enabled only at exactly 16 chars; error text on mismatch (REF `screens/common/RecoveryConfirmDialog.kt:44-84`). If a session is already active the dialog auto-confirms without UI (REF `RecoveryConfirmDialog.kt:35-38`).
- Shuffle keyboard (opt-in): a **4×4 grid containing exactly one correct cell** — the true next character of the stored code plus 15 distinct random other letters — **reshuffled after every tap** and after backspace (REF `RecoveryConfirmDialog.kt:93-118, 155-195`). This design requires plaintext access to the stored code.

### Ours
- **Order inverted **NEW** (headline defect):** `ensureRecoverySession()` / `_RecoveryGateDialog` run the challenges **first** and only then show code entry — the dialog's own text says "Challenges complete. Enter your recovery code…" (OUR `lib/ui/recovery_ui.dart:337-345, 395-470`). The original never spends challenge effort before the code is proven, and — more importantly — in the original a wrong code means challenges never run; in ours an attacker/bot can grind challenges without knowing the code, and a legitimate user who mistypes after completing challenges must redo them. COMPLIANCE_AUDIT F22/F23 do not note the inversion.
- Session-active shortcut equivalent: `ensureRecoverySession` returns `true` immediately when active (OUR `lib/ui/recovery_ui.dart:342-352`).
- No-code-set shortcut: unreachable in ours by construction (the app is gated into the setup wizard until a code exists, OUR `lib/main.dart:56-67`), whereas the original's gate passes actions through pre-setup. Equivalent net posture, different mechanism.
- Code format checks equivalent: 16 A–Z after normalization (OUR `lib/ui/recovery_ui.dart:23-27`; OUR `RecoveryStore.kt:88-91`).
- **Shuffle keypad drift **NEW**:** ours shows **all 26 letters, shuffled once** in `initState`, never reshuffled per tap (OUR `lib/ui/recovery_ui.dart:59-135`). The original's 4×4 single-correct-cell, reshuffle-per-tap design is absent — and is in fact **unimplementable** in ours, because it requires knowing the expected character at each position, i.e. plaintext (or a per-position oracle) that the PBKDF2 design deliberately destroys. This coupling (F24 deviation ⇒ shuffle-keyboard redesign) is not noted in the audit. Ours is arguably no weaker (full alphabet always present), but it is not the original behavior.
- Cancel semantics: original `pendingCancel` rolls back optimistic UI updates on dismiss (REF `RecoveryGate.kt:47, 89-92`). Ours has no optimistic-update/rollback pairing in the gate: `runLoosening` simply does not run the action on cancel (OUR `lib/ui/recovery_ui.dart:483-497`), and tightening undo is handled by the (inverted) `PendingChange` mechanism of §6. PARTIAL.

### Classification: **PARTIAL** (gate coverage equivalent in scope; challenge/code order inverted; shuffle keyboard redesigned; rollback model differs)

---

## 9. `screens/common/RecoveryCodeWizard.kt` + `RecoveryGenerateDialog.kt` + `screens/setup/SetupRecovery.kt`

### Original behavior spec
- Wizard has **4 steps** (`STEP_COUNT = 4`: Intro → Write → Confirm → Store) with a step indicator and Back handling (REF `screens/common/RecoveryCodeWizard.kt:74-79, 96-99`).
  - *Intro*: explains the 4-step process; always advanceable.
  - *Write*: code hidden behind a **Reveal** button; the "I wrote it" checkbox is **disabled until revealed**; advance requires `revealed && written` (REF `RecoveryCodeWizard.kt:101-106, 300-326`).
  - *Confirm*: re-type filtered to A–Z, advance requires `typed == code` exactly (REF `RecoveryCodeWizard.kt:103, 356-398`).
  - *Store*: storage guidance (keep away from the phone, findable, no photos/digital copies; when replacing, destroy the old copy); advance requires the `stored` checkbox (REF `RecoveryCodeWizard.kt:104, 400-424`).
- The code is generated **once** per wizard instance via `rememberSaveable { SecurityManager.generateRecoveryCode() }` (REF `RecoveryCodeWizard.kt:93`) and displayed ungrouped, monospace, letter-spacing 2 sp (REF `RecoveryCodeWizard.kt:328-354`).
- First-run path: `SetupRecovery` is just the wizard whose `onFinish` calls `SecurityManager.saveRecoveryCode` (REF `screens/setup/SetupRecovery.kt:12-18`).
- Regeneration path: `RecoveryGenerateDialog` is a **full-screen, non-dismissible** dialog (`dismissOnBackPress = false`, `dismissOnClickOutside = false`) with `replacing = true` (REF `screens/common/RecoveryGenerateDialog.kt:17-31`), entered from Config only through `recoveryGate.run { … }` (REF `screens/tabs/ConfigTab.kt:304-305`).

### Ours
- Wizard has **2 steps**: (0) code displayed immediately in a `GradientCard`, grouped 4-4-4-4 via `groupCode()`, with a single "written on paper" checkbox gating Continue; (1) re-type and Store (OUR `lib/ui/recovery_ui.dart:155-322`). The code is fetched once from the native generator in `initState` (OUR `lib/ui/recovery_ui.dart:180-199`) — generation-once is equivalent.
- **Missing steps **NEW**:** no Intro step and no Store step — the storage-placement guidance and its confirmation checkbox, and the reveal-before-write gating, are absent. The intro text is compressed into one paragraph (OUR `lib/ui/recovery_ui.dart:230-236`) which does state the code cannot be shown again. The re-type-to-confirm gate itself is equivalent: save is refused unless the typed code equals the generated one (OUR `lib/ui/recovery_ui.dart:201-210`).
- Regeneration: ours is a normally-pushed, back-navigable screen; `isRegeneration` changes only the title (OUR `lib/ui/recovery_ui.dart:161-168, 224-228`), and entry is gated by `ensureRecoverySession` (OUR `lib/ui/config_tab.dart:211-230`) — gating equivalent, non-dismissibility **not** reproduced (user can back out mid-wizard; harmless because nothing is stored until final save, but a behavior difference).
- Grouped display (4-4-4-4) vs original ungrouped: cosmetic, and input normalization (§7) makes grouped re-typing work.

### Classification: **PARTIAL** (core loop — generate → paper → re-type → store-hash — equivalent; two of four steps and reveal gating missing)

---

## 10. `screens/common/ApkUpdateDialog.kt` (F29)

### Original behavior spec
- Lock-screen, **unauthenticated** flow (entry only when unknown-sources installs are restricted): intro dialog → file picker → `ApkUpdateInstaller.inspect()` → states NewApp / Invalid / Update; Update shows installed vs new version and installs (incl. downgrade) on confirm; temp file deleted on dismiss/cancel (REF `screens/common/ApkUpdateDialog.kt:36-149`; entry at REF `activities/LockScreen.kt:67-74, 167-174, 240-252`).

### Ours
- Absent entirely: no `PackageInstaller` usage, no install permissions, lock screen exposes no APK entry (verified in COMPLIANCE_AUDIT F29; OUR `lib/ui/lock_screen.dart` contains only panic/overview/auth per its structure).

### Classification: **EXCLUDED-DOCUMENTED** (deliberate security exclusion, ARCH §7 — not a defect)

---

## 11. Setup flow — `screens/setup/SetupDeviceOwnerPrivileges.kt` + `SetupDeviceOwnerComponents.kt`

### Original behavior spec (order matters)
- State machine, evaluated in this exact priority (REF `screens/setup/SetupDeviceOwnerPrivileges.kt:40-57`):
  1. `isDeviceOwner()` → **remove** card; removal is wrapped in `recoveryGate.run { … }` (REF `SetupDeviceOwnerPrivileges.kt:43-46`).
  2. Shizuku not installed → card with **Install Shizuku** action (`market://details?id=moe.shizuku.privileged.api`, Play-web fallback) (REF `SetupDeviceOwnerPrivileges.kt:59-67`; REF `data/DeviceOwnerRepository.kt:42-53`).
  3. Installed, binder dead → card with **Setup Shizuku** action opening `https://shizuku.rikka.app/guide/setup/` (REF `SetupDeviceOwnerPrivileges.kt:69-77`; REF `data/DeviceOwnerRepository.kt:55-61`).
  4. Running, permission missing → card whose button calls `Shizuku.requestPermission(911)` (REF `SetupDeviceOwnerPrivileges.kt:79-87, 94`).
  5. Granted → grant content (below).
- Liveness: a `LaunchedEffect` loop **polls every 500 ms**, re-checking installed (until true) and `Shizuku.pingBinder()` (until true) (REF `SetupDeviceOwnerPrivileges.kt:23-33`).
- Grant content blockers, in order (REF `SetupDeviceOwnerPrivileges.kt:96-139`):
  - **Extra users present → non-dismissible `UserWarningDialog`** (`onDismissRequest = {}`) linking to user settings; provisioning is unreachable (REF `screens/setup/SetupDeviceOwnerComponents.kt:119-142`).
  - **Another app is already Device Owner → `ExistingOwnerDialog`**, non-dismissible, whose only button **exits the process** (`exitProcess(0)`) (REF `SetupDeviceOwnerComponents.kt:144-176`).
  - Otherwise the grant card; its description text changes when accounts are detected ("accounts detected, N") using `dumpsys account` via Shizuku (REF `SetupDeviceOwnerPrivileges.kt:99-103, 124-132`).
- Provisioning call: `DeviceOwnerRepository.processDeviceOwnerPrivileges()` — bypass `user_setup_complete` (checks the `put` exit code), reflective `setDeviceOwner` via Shizuku-wrapped DPM, fallback `dpm set-device-owner` shell command, restore `user_setup_complete` in `finally`, verify `isDeviceOwnerApp` (REF `data/DeviceOwnerRepository.kt:227-280`). Non-blank shell output is surfaced in a `CommandResultDialog` (REF `SetupDeviceOwnerPrivileges.kt:52-57`; REF `SetupDeviceOwnerComponents.kt:55-84`).
- `MainActivity.onCreate` additionally calls `restoreStuckUserSetupComplete()` to repair a setup flag left at 0 by an interrupted provisioning (REF `activities/MainActivity.kt:56-58`; REF `data/DeviceOwnerRepository.kt:216-225`).

### Ours
- Five-state machine `notInstalled → notRunning → preV11 → noPermission → granted` rendered as one status card with state-specific text; **permission request button only in the `noPermission` state** (OUR `lib/ui/setup_screen.dart:270-409`); request code 911 preserved natively (OUR `android/.../shizuku/ShizukuGateway.kt:26`).
- **Install action MISSING **NEW**:** the `notInstalled` card is text-only ("Install Shizuku … from the Play Store or its official site") with **no button** — the only actionable card is `noPermission` (OUR `lib/ui/setup_screen.dart:364-372`). The original deep-links to the store listing.
- **Setup-guide action differs (documented):** `notRunning` shows text instructions; no guide URL is opened (COMPLIANCE_AUDIT F30 notes this).
- **Polling MISSING **NEW**:** no 500 ms poll; state refreshes on screen init, on channel events (`shizukuBinderReceived/Dead`, `shizukuPermissionResult`, `deviceOwnerChanged`, `accessibilityStateChanged`), and on pull-to-refresh (OUR `lib/ui/setup_screen.dart:39-52, 96-99`). Liveness is event-driven — arguably cleaner, but a state change that produces no event (e.g. Shizuku installed while on the screen) is only picked up manually.
- **Blockers downgraded to information **NEW** (defect):** accounts / extra users / current owner are fetched only when the user taps "Run diagnostics" and are displayed as lists; **nothing blocks the "Become Device Owner" button** except `shizuku.state != granted` (OUR `lib/ui/setup_screen.dart:130-160, 207-268`). With extra users present the original makes provisioning unreachable; ours attempts it and fails at the DPM layer. The non-dismissible dialogs and the exit-process behavior have no counterpart.
- Extra states: ours adds `preV11` and `unknown` (OUR `lib/ui/setup_screen.dart:305-317`); the original folds pre-V11 into the permission check returning false (`checkShizukuPermission`, REF `data/DeviceOwnerRepository.kt:63-66`), i.e. it shows the permission card for an old server. Ours is more informative here — an improvement, noted for completeness.
- Removal placement differs: the original's setup screen *is* the removal surface (gate-wrapped). Ours shows owner status only on the setup screen; removal lives in Config (in-session immediate + forced removal, OUR `lib/ui/config_tab.dart:233-246`) — gate-equivalent, different location.
- Command output: ours renders `pathUsed` + `commandOutput` inline as selectable text after provisioning (OUR `lib/ui/setup_screen.dart:143-160`) vs the original's modal `CommandResultDialog` — functionally equivalent.
- Ours additionally surfaces two things the original setup screen does not: the Accessibility enable toggle and the WRITE_SECURE_SETTINGS grant (OUR `lib/ui/setup_screen.dart:164-205`). (In the original, accessibility is enabled via Shizuku from elsewhere in setup/config; not a parity loss for F30's state machine, but the screens are not 1:1.)
- `restoreStuckUserSetupComplete` equivalent: not identifiable in ours from the Dart setup screen; provisioning internals are covered by Part 2 of this audit — flagged here only as "no counterpart found in Part 5 scope".

### Classification: **PARTIAL** (state order and 911 equivalent; install/guide actions, polling, and both hard blockers missing or downgraded)

---

## 12. `activities/MainActivity.kt` + `viewmodels/NavigationViewModel.kt`

### Original behavior spec
- Single activity, string-keyed screen stack: roots `restrictions / apps / config`; sub-screens `setup_device_owner, activity_blocker, browser_restrictions, blocked_words, visual_blocking, impulse_lock, focus_mode, usage_warning, color_filters, suspension_logs, app_restrictions` (REF `activities/MainActivity.kt:185-245`). `NavigationViewModel` keeps a stack; navigating to a root clears it; `goBack()` pops (REF `viewmodels/NavigationViewModel.kt:8-32`). `BackHandler` is enabled whenever the current screen is not a root (REF `MainActivity.kt:72-76`).
- Gating order in the content area: **no recovery code → `SetupRecovery` only**; else **not authenticated → `LockScreen`**; else the tab content (REF `MainActivity.kt:217-245`). Bottom navigation is rendered only when a code is set **and** authenticated (REF `MainActivity.kt:165`).
- Session chrome: when a session is active the top bar shows remaining mm:ss, a **renew** button and an **end-session (logout)** button, ticking every 1 s (REF `MainActivity.kt:79-87, 138-160`).
- Post-auth side effect: after authentication, if usage warnings are enabled and Android ≥ 13, it requests `POST_NOTIFICATIONS` when not granted (REF `MainActivity.kt:90-108`).
- Startup hooks: consumes the F34 debug auto-session and debug restriction-restore, and calls `ApkUpdateInstaller.restoreUnknownSourcesRestrictionsIfIdle` (REF `MainActivity.kt:55-58`). `onDestroy` ends the session (REF `MainActivity.kt:253-256`).
- **Deep links / intents: none.** `MainActivity` reads no intent extras, actions, or data; the manifest gives it only `MAIN/LAUNCHER` (REF `activities/MainActivity.kt` whole file; REF `app/src/main/AndroidManifest.xml:49-52`).

### Ours
- Routing mirrors the gate order: `loading → needsRecoverySetup (wizard only) → locked (LockScreen) → unlocked (AppShell)` driven by `isRecoveryCodeSet` (OUR `lib/main.dart:56-67`; OUR `lib/app_controller.dart:53-72`). **EQUIVALENT** in posture.
- Tabs: **4** — Status/Setup first, then Restrictions, Apps, Config (OUR `lib/main.dart:96-137`). The original has 3 roots with setup reached from Config; ours promotes Setup to a root tab (documented redesign decision; the original's `setup_device_owner` sub-screen route has no direct equivalent — Config pushes a second copy of the setup screen, OUR `lib/ui/config_tab.dart:107-110`).
- Sub-screens: standard `Navigator.push` routes from Config (OUR `lib/ui/config_tab.dart:84-86`) instead of the original's string stack + root-clearing semantics; system back behavior follows Flutter's navigator, not the original's "back disabled at roots" handler. PARTIAL (minor, UX-level).
- Session chrome: `SessionChip` with remaining time + Renew + End (OUR `lib/ui/recovery_ui.dart:537-574`) — equivalent; tick cadence is the session's own 1 s ticker (OUR `lib/domain/recovery.dart:182-190`).
- **POST_NOTIFICATIONS request MISSING **NEW**:** the permission is declared in the manifest (OUR `android/app/src/main/AndroidManifest.xml:11`) but no runtime request exists anywhere in Dart or Kotlin (grep: 0 hits outside the manifest). The original's post-auth conditional request (REF `MainActivity.kt:90-108`) has no counterpart; on Android 13+ usage-warning notifications (F12) would be silently undeliverable until the user grants the permission from system settings.
- F34 debug hooks: absent — **EXCLUDED-DOCUMENTED** (see §15). The F29 idle-restore hook is moot (F29 excluded).
- Session end on destroy: ours ends the session by process death (in-memory `RecoverySession`); there is no explicit `onDestroy` hook in the Flutter host activity (OUR `android/.../MainActivity.kt:20-45` only registers channels/Shizuku listeners). Equivalent outcome.
- Deep links: none in ours either (host activity is a stock `FlutterActivity`; manifest `MAIN/LAUNCHER` only) — **EQUIVALENT**.

### Classification: **PARTIAL** (gate order + session chrome equivalent; tab structure redesigned-documented; notification-permission request missing)

---

## 13. Misc utils — `utils/LocaleUtils.kt`, `utils/NightLightOverlay.kt`

### LocaleUtils
- Original: `setLocale()` uses `LocaleManager.applicationLocales` on API 33+, `AppCompatDelegate.setApplicationLocales()` below; `getLocale()` mirrors it (REF `utils/LocaleUtils.kt:12-30`). It drives **whole-app** locale (en/pt via `res/xml/locales_config.xml`), and the reading challenge picks PT passages from the active locale (REF `ReadingChallenge.kt:62-64`).
- Ours: language is a stored preference (`security_prefs/language`, en/pt) (OUR `lib/data/config_store.dart:236-243`); translation is hand-rolled chrome strings (`AppStrings`, used by tabs/lock/session chip) with most screens English-only — the Config language dialog itself discloses this (OUR `lib/ui/config_tab.dart:366-390`). No OS per-app locale is set, and reading passages are **always the English samples** regardless of the language preference (**NEW** detail: original PT users get PT passages; ours has no PT passages at all).
- Classification: **PARTIAL** (documented in COMPLIANCE_AUDIT F33 as chrome-only; passage-language coupling not noted there).

### NightLightOverlay
- Original: accessibility-service overlay view (`TYPE_ACCESSIBILITY_OVERLAY`, non-touchable), tint from Tanner Helland blackbody approximation — temperature clamped 1000–6600 K, intensity 0–100 → alpha up to `MAX_ALPHA = 220`, fixed red 185, green scaled 116/184 (REF `utils/NightLightOverlay.kt:14-64`). This is the rendering half of F26 colour modes.
- Ours: no counterpart in the Kotlin tree (no `NightLightOverlay`, no overlay window in `DominanterAccessibilityService`); colour modes are an explicit v1.1 tile (OUR `lib/ui/config_tab.dart:174-179`).
- Classification: **DEFERRED-DOCUMENTED** (F26).

---

## 14. Focus-cycle behavior (scope-adjacent: `lib/domain/focus.dart` impulse/focus parts)

### Original behavior spec
- Defaults/bounds (`data/FocusMode.kt`): focus **25** (range **5–120**), short break **5** (range **1–30**), long break **15** (range **5–60**), cycles **4** (range **2–8**) (REF `data/FocusMode.kt:31-45, 91-115`).
- Cycle machine (`FocusCycle.next`, REF `data/FocusMode.kt:528-545`): FOCUS → SHORT_BREAK, or LONG_BREAK when the completed count reaches the cycle length; SHORT_BREAK/LONG_BREAK → **WAITING** unless `autoStartFocus` is on, in which case → FOCUS; LONG_BREAK completion **resets the completed count to 0**.

### Ours
- Defaults match exactly: 25 / 5 / 15 / 4 (OUR `lib/domain/focus.dart:13-20`).
- **Bounds drift **NEW** (numeric defect):** the domain model clamps nothing, and the editor rows use generic bounds — durations min 1 / max 180 for all three, cycles min **1** / max **12** (OUR `lib/ui/impulse_focus_screens.dart:606-680`). Original: focus ≤ 120, short break ≤ 30, long break ≤ 60, cycles ∈ [2, 8]. Ours permits e.g. a 180-minute break and a 1-cycle "long break every time".
- **WAITING phase + autoStartFocus MISSING:** ours `advance()` always moves break → focus (OUR `lib/domain/focus.dart:129-155`); there is no waiting state and no auto-start setting. A finished break silently starts the next focus period (and its suspensions via `_syncEffects`) — the original parks in WAITING by default.
- Completed-count reset: ours never resets `completedFocusPeriods` (OUR `lib/domain/focus.dart:144-147`); phase *selection* stays correct because it uses modulo arithmetic (`(completed+1) % cycles`), but the counter grows unboundedly and the cycle label in the UI (`Cycle X of N`, OUR `lib/ui/impulse_focus_screens.dart:483-490`) is derived from it with a clamp. PARTIAL (minor).
- Pause/resume: ours `resume()` always re-enters the **focus** phase even if paused during a break — the file itself flags this as a v1 simplification (OUR `lib/domain/focus.dart:165-177`).

### Classification: **PARTIAL**

---

## 15. Impulse lock flows (F21, scope-adjacent)

- Duration bounds/default **equivalent**: 15–360 min, default 60 (REF `security/SecurityManager.kt:41-43, 237-253`; OUR `lib/domain/recovery.dart:232-244`); the settings slider granularity matches too — original 15-minute steps (REF `screens/tabs/ImpulseLockScreen.kt:138-149`), ours `divisions: 23` over 15..360 = 15-minute steps (OUR `lib/ui/impulse_focus_screens.dart:205-215`).
- Config-screen gating drift **NEW**: in the original, **all** Impulse Lock settings (challenge selection, action, duration, app picker) are `enabled = sessionActive` — visible but inert without a session, with a lock banner that opens the gate (REF `screens/tabs/ImpulseLockScreen.kt:47-56, 64-186`). Ours applies **no session gating at all** to impulse/challenge/shuffle/custom-phrase settings (OUR `lib/ui/impulse_focus_screens.dart:74-78, 240-290` save immediately). Changing the challenge set or shortening the impulse duration — both loosening-relevant — requires no code in ours. (Duration *shortening* is a loosening of a protection the original edits only inside a session.)
- **Early-stop addition **NEW**:** the original impulse block has **no stop path** — the lock screen shows a countdown only, and expiry is computed from elapsedRealtime (REF `activities/LockScreen.kt:199-204, 357-396`; REF `security/SecurityManager.kt:303-332`). Ours adds a **Stop** button gated by a recovery session (OUR `lib/ui/impulse_focus_screens.dart:97-112, 179-199`). A code holder in the original still cannot shorten an impulse block; in ours they can.
- **Expiry release gap **NEW** (defect):** the original tracks the *actually suspended* set separately (`impulse_active_suspension`, REF `security/SecurityManager.kt:285-301`) so release acts on what was suspended even if config changed mid-block, and its remaining-time getter clears the active flag on expiry. Ours releases the **current config's** `suspendApps` on manual stop (OUR `lib/ui/impulse_focus_screens.dart:100-110`), and the 30 s ticker that detects natural expiry (`AppController._tick`, OUR `lib/app_controller.dart:82-97`) **never unsuspends anything** — apps suspended by an impulse lock that expires naturally stay suspended until a manual stop or another flow releases them.
- Timer accounting: ours ticks down only while the process is alive (documented for F21 in the audit); the original's dual-clock (RTC + elapsedRealtime) remaining-time computation (REF `security/SecurityManager.kt:303-332`) has no equivalent.

### Classification: **PARTIAL**

---

## 16. Forced removal & danger zone (Config)

- Original: a single Config row whose dialog depends on state — not started → start dialog (with explanatory text); in progress → **cancel** dialog; remaining == 0 → finish dialog gated by an explicit **confirmation checkbox** before `removeDeviceOwner` runs; finishing also calls `cancelForcedRemoval` to clear state (REF `screens/tabs/ConfigTab.kt:311-330, 340-435`).
- Ours: Start / Cancel / Finish buttons under a progress bar (OUR `lib/ui/config_tab.dart:248-307`). Differences: **no confirmation dialogs and no checkbox** on any of the three actions — Start and Cancel are one tap (original: dialog-confirmed), Finish is one tap (original: checkbox-confirmed). The immediate "Remove Device Owner now" row is session-gated via `runLoosening` (OUR `lib/ui/config_tab.dart:233-246`), matching the original's gate posture for removal. PARTIAL (confirmation friction reduced; core gating equivalent). **NEW** — not noted in the audit's F2 row.

---

## 17. Original tests — inventory and coverage mapping

Original suite: **12 unit-test files** under `app/src/test/` + **1 instrumented** file under `app/src/androidTest/`. Ours: 5 Dart test files, **no Kotlin/Android tests at all** (`project/android/` has no `src/test`), no instrumented tests.

| Original test (REF `app/src/test/...` unless noted) | Behaviors it pins | Counterpart in OUR `test/` | Verdict |
|---|---|---|---|
| `ExampleUnitTest.kt:13-16` | `2 + 2 == 4` (template) | — | Trivial; nothing to port |
| `data/ApkUpdateInstallerTest.kt:12-20` | Downgrade session flags `0x80` + `0x100000` set by `requestDowngrade` | None | **EXCLUDED-DOCUMENTED** (F29 not ported; test correctly absent) |
| `data/DeviceOwnerSetupBypassTest.kt:18-43` | `ShizukuRunner.ProcessResult` holds output/exitCode; `getUserId() == 0` for primary user; accounts-detected string formats the count; `restoreStuckUserSetupComplete()` does not crash without a binder | None (no Kotlin tests; `channel_client_test.dart` covers Dart-side parsing of shell errors but not `ProcessResult`, user-id, or the stuck-setup restore) | **NOT COVERED.** Note: despite its name this test concerns the *provisioning* `user_setup_complete` bypass (F30), **not** the F34 debug hatch; F34 has no original test |
| `data/FocusCycleTest.kt:12-56` | Focus→short break; last focus of cycle→long break; mid-session cycle-count lowering still yields long break; break→WAITING vs FOCUS by autoStart; long break closes cycle and resets completed to 0; full 8-step auto-start sequence | `challenges_test.dart:346-365` covers focus→break→focus→long-break with cycles = 2 | **PARTIAL** — WAITING/autoStart and the completed-count reset are untested because the behaviors are absent (§14) |
| `data/FocusModeTest.kt:25-61` | `getAllTargetApps` = individual apps ∪ group members, deduplicated, reacts to group selection changes | None (ours `FocusConfig.suspendGroups` exists in the model, OUR `lib/domain/focus.dart:17, 24`, but no union logic or test; the Focus UI exposes only individual apps) | **NOT COVERED** |
| `data/SystemRestrictionsTest.kt:19-88` | Restriction key catalog completeness (incl. Knox/OEM keys), resource-name resolution, diacritic-insensitive search normalization | None in Part 5 scope (restrictions engine is Part 3/4 scope) | Out of Part 5 scope; no equivalent test exists in our suite |
| `data/VisualBlockingLooseningTest.kt:10-108` | Loosening direction for enable/disable, target-set shrink, category uncheck, threshold direction, block-count/window/duration directions (mostly via `isLooserSet` + inline expressions) | `recovery_gate_test.dart:134-149` covers only the protection-toggle direction (`forProtectionToggle`) | **PARTIAL** (visual blocking itself is F16/F17, deferred; the `isLooserSet` primitive it uses is also untested in ours) |
| `models/ColorFilterScopeTest.kt:11-63` | Scope `appliesTo` for DEVICE/EXCEPT_APPS/ONLY_APPS + scope-transition loosening matrix | None | Out of Part 5 scope (F26 deferred-documented); no test |
| `models/FocusScheduleTest.kt:12-117` | `nextTriggerMillis` today/tomorrow/weekend-skip/disabled-null; schedule JSON round-trip; snooze allowed twice then blocked (`< 2`) | None | **NOT COVERED** — schedules are deferred (v1.1 tile, OUR `lib/ui/impulse_focus_screens.dart:596-600`) |
| `models/TimeWindowsTest.kt:21-188` | `TimeWindows` NONE/daily/per-day semantics, intersect, persistence read/write/clear, **`isLooserWindows` across days** (weekend-only widening = loosening; remove-all = loosening; from-unrestricted = tightening), summary formatting | `recovery_gate_test.dart:47-85` covers remove-all / widen / narrow / midnight-span on total minutes | **PARTIAL with a hole:** the original's per-day case is exactly the class ours' total-minutes implementation can fail (§6 counterexample is a same-total variant); no test in ours exercises a window *move* or per-day divergence |
| `screens/common/PendingChangeTest.kt:13-95` | `isLooserSet` add/same/remove; `isLooserRestrictions` Boolean, String, Array, and URLBlocklist cases | `recovery_gate_test.dart:87-132` covers key-drop, Boolean, and list shrink/grow | **PARTIAL** — String case and set-containment case untested because unimplemented (§6) |
| `screens/common/RecoveryGateTest.kt:32-62` | `change()`: with an active session both tightening and loosening execute immediately; without a session a tightening does **not** execute immediately (deferred by PendingChange) | `recovery_gate_test.dart:151-212` tests `PendingChange` and `RecoverySession` as isolated units | **NOT COVERED as gate semantics** — ours has no gate class to pin, and its apply-first model makes the original's second test unstatable (§6) |
| `androidTest/ExampleInstrumentedTest.kt:18-23` | Package name equals `io.github.warleysr.dechainer` | None | Template test; ours' package intentionally differs (`io.github.alnajashia.dominanter`); no instrumented suite exists in ours |

**Aggregate:** of the original's behavior-pinning tests that fall in Part 5 scope (PendingChange, RecoveryGate, TimeWindows-loosening, FocusCycle, FocusMode targets, FocusSchedule, DeviceOwnerSetupBypass), ours fully covers **none**, partially covers **3** (PendingChange, TimeWindows, FocusCycle), and leaves **4** uncovered (RecoveryGate semantics, FocusMode target union, FocusSchedule, DeviceOwnerSetupBypass). Ours does add tests the original lacks for its own model (session expiry/renew, forced-removal monotonicity, impulse clamping, challenge units, wizard widget flow — OUR `test/recovery_gate_test.dart`, `test/challenges_test.dart`, `test/widget_test.dart:65-129`), but two of the challenge tests pin *drifted* behavior as if original (words streak reset, §2; math no-reset untestable as written, §1).

---

## 18. Cross-check against COMPLIANCE_AUDIT.md

- Audit F22 calls Math/Words/Reading "Implemented & unit/build-tested" — the unit tests exist, but §§1–3 show operator, reset, pool, interaction, pacing, and configurability drifts the audit does not mention. **NEW.**
- Audit F22a (Tetris deferred) — **confirmed accurate** (§4).
- Audit F23 describes the gate/session/undo faithfully at the headline level but omits: the PendingChange apply-order inversion, the gate's challenge/code order inversion, the `isLooserWindows` total-minutes weakening, and the `isLooserRestrictions` String/containment gaps. **NEW** (§§6, 8).
- Audit F24 records the PBKDF2 deviation — **confirmed**; it omits the wizard's 4→2 step reduction and the shuffle-keyboard redesign forced by that deviation. **NEW** (§§8, 9).
- Audit F30 records the setup-guide difference — **confirmed**; it omits the missing Install action, missing 500 ms polling, and diagnostics replacing hard blockers. **NEW** (§11).
- Audit F2 records Dart-side forced-removal accounting — **confirmed**; it omits the removed confirmation dialogs/checkbox in the danger zone. **NEW** (§16).
- Audit F29 / F34 "not ported deliberately" — **confirmed by absence** (§§10, 12).
- Audit F33 (chrome-only translation) — **confirmed**, plus the reading-passage language coupling is also lost (§13).
