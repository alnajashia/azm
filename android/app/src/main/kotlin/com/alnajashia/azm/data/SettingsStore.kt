package com.alnajashia.azm.data

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.time.DayOfWeek

/**
 * The single Kotlin reader/writer of the SharedPreferences schema
 * (`docs/ARCHITECTURE.md` §8). File and key names mirror the original DeChainer
 * schema so the Accessibility Service, the channel handler and any future
 * tooling all see the same layout:
 *
 *  - `app_limits` (Int minutes/pkg) / `app_weekly_limits` (CSV of 7 Ints/pkg)
 *  - `app_time_windows` (JSON `[{s,e}]`/pkg) / `app_weekly_time_windows` (JSON 7 day-arrays)
 *  - `app_groups` (`groups` JSON array)
 *  - `internal_usage_stats` / `group_usage_stats` (Long ms per key, written by the service)
 *  - `reopen_times` (Int seconds/pkg)
 *  - `blocked_words_prefs` (`word_assignments_json`: one assignment
 *    table `[{w, p, m}]`, mode `active`|`passive`; legacy keys
 *    `blocked_words` / `target_packages` / `passive_words_<pkg>`
 *    migrated once on first read, then cleared)
 *  - `activity_blocker_prefs` (`blocked_activities`)
 *  - `hidden_apps_prefs` (`hidden_packages`)
 *  - `suspension_logs_prefs` (`logs` JSON array, capped)
 *  - `security_prefs` (misc flags, incl. the intentional-accessibility-disable flag)
 *
 * Decoders fail safe for UI reads, but log corruption — a decode failure must
 * never be silently interpreted as "no restrictions configured" (ARCH §7.4.5);
 * enforcement readers in the service use the same decoders and therefore the
 * same logged, empty-on-corruption behaviour the original had, minus the silence.
 */
object SettingsStore {
    private const val TAG = "SettingsStore"

    const val PREFS_APP_LIMITS = "app_limits"
    const val PREFS_APP_WEEKLY_LIMITS = "app_weekly_limits"
    const val PREFS_APP_WINDOWS = "app_time_windows"
    const val PREFS_APP_WEEKLY_WINDOWS = "app_weekly_time_windows"
    const val PREFS_GROUPS = "app_groups"
    const val PREFS_USAGE = "internal_usage_stats"
    const val PREFS_GROUP_USAGE = "group_usage_stats"
    const val PREFS_USAGE_META = "usage_meta"
    const val PREFS_REOPEN = "reopen_times"
    const val PREFS_BLOCKED_WORDS = "blocked_words_prefs"
    const val PREFS_ACTIVITY_BLOCKER = "activity_blocker_prefs"
    const val PREFS_HIDDEN = "hidden_apps_prefs"
    const val PREFS_SUSPENSION_LOGS = "suspension_logs_prefs"
    const val PREFS_SECURITY = "security_prefs"
    const val PREFS_BROWSER = "browser_prefs"
    const val PREFS_FOCUS = "focus_prefs"
    const val PREFS_FOCUS_SCHEDULES = "focus_schedules_prefs"
    const val PREFS_USAGE_WARNING = "usage_warning_prefs"
    const val PREFS_RECOVERY_STATE = "recovery_prefs"
    const val PREFS_VISUAL_BLOCKING = "visual_blocking_prefs"
    const val PREFS_SEAL_RULES = "seal_rules_prefs"
    const val PREFS_COLOUR_MODES = "colour_modes_prefs"
    const val PREFS_COLOUR_MODES_STATE = "colour_modes_state"

    private const val KEY_GROUPS = "groups"
    private const val KEY_HIDDEN_PACKAGES = "hidden_packages"
    private const val KEY_BLOCK_TORRENTS = "block_torrents"
    private const val KEY_AUTO_UNINSTALL_BLOCKED = "auto_uninstall_blocked_packages"
    private const val KEY_AUTO_BLOCK_UNINSTALL_SUSPENDED = "auto_block_uninstall_suspended"
    private const val KEY_LOGS = "logs"
    private const val KEY_USAGE_DATE = "date"
    private const val KEY_INTENTIONAL_A11Y_DISABLE = "intentional_a11y_disable_at"
    private const val KEY_REMOVAL_IN_PROGRESS = "removal_in_progress_at"
    const val KEY_PROTECTION_TORN_DOWN = "protection_torn_down"

    /** How long a persisted removal flag stays authoritative (see setRemovalInProgress). */
    private const val REMOVAL_FLAG_WINDOW_MS = 30 * 60 * 1000L
    private const val MAX_LOGS = 100
    private const val INTENTIONAL_DISABLE_WINDOW_MS = 120_000L

    @Volatile
    private var appContext: Context? = null

    fun init(context: Context) {
        appContext = context.applicationContext
    }

    private fun ctx(): Context =
        appContext ?: throw IllegalStateException("SettingsStore not initialised (Application.onCreate)")

    fun prefs(name: String): SharedPreferences =
        ctx().getSharedPreferences(name, Context.MODE_PRIVATE)

    // ------------------------------------------------------------------ limits

    fun timeLimitFor(packageName: String): TimeLimit {
        decodeWeeklyLimit(prefs(PREFS_APP_WEEKLY_LIMITS).getString(packageName, null))
            ?.let { return TimeLimit.perDay(it) }
        return TimeLimit.daily(prefs(PREFS_APP_LIMITS).getInt(packageName, 0))
    }

    fun setTimeLimit(packageName: String, limit: TimeLimit) {
        val daily = prefs(PREFS_APP_LIMITS)
        val weekly = prefs(PREFS_APP_WEEKLY_LIMITS)
        val perDay = limit.weeklyMinutes?.takeIf { limit.isSet }
        if (perDay != null) {
            daily.edit().remove(packageName).apply()
            weekly.edit().putString(packageName, perDay.joinToString(",")).apply()
        } else {
            weekly.edit().remove(packageName).apply()
            daily.edit().apply {
                if (limit.dailyMinutes > 0) putInt(packageName, limit.dailyMinutes) else remove(packageName)
            }.apply()
        }
    }

    fun limitedPackages(): Set<String> =
        prefs(PREFS_APP_LIMITS).all.keys + prefs(PREFS_APP_WEEKLY_LIMITS).all.keys

    private fun decodeWeeklyLimit(value: String?): List<Int>? {
        if (value.isNullOrEmpty()) return null
        val minutes = value.split(",").map { it.trim().toIntOrNull() }
        // Corruption is logged, never silent (v1.0.5 audit A-M3 — the
        // sibling decoders already logged; this one dropped the value
        // without a trace, against this file's header contract).
        if (minutes.size != DayOfWeek.entries.size || minutes.any { it == null }) {
            Log.w(TAG, "Corrupt weekly limit value, treating as unset: $value")
            return null
        }
        return minutes.filterNotNull()
    }

    // ------------------------------------------------------------------ windows

    fun timeWindowsFor(packageName: String): TimeWindows {
        decodeWeeklyWindows(prefs(PREFS_APP_WEEKLY_WINDOWS).getString(packageName, null))
            ?.let { return TimeWindows.perDay(it) }
        return TimeWindows.daily(decodeWindows(prefs(PREFS_APP_WINDOWS).getString(packageName, null)))
    }

    fun setTimeWindows(packageName: String, windows: TimeWindows) {
        val daily = prefs(PREFS_APP_WINDOWS)
        val weekly = prefs(PREFS_APP_WEEKLY_WINDOWS)
        val perDay = windows.weeklyWindows?.takeIf { windows.isSet }
        if (perDay != null) {
            daily.edit().remove(packageName).apply()
            weekly.edit().putString(packageName, encodeWeeklyWindows(perDay).toString()).apply()
        } else {
            weekly.edit().remove(packageName).apply()
            daily.edit().apply {
                if (windows.dailyWindows.isNotEmpty()) {
                    putString(packageName, encodeWindows(windows.dailyWindows))
                } else remove(packageName)
            }.apply()
        }
    }

    fun windowedPackages(): Set<String> =
        prefs(PREFS_APP_WINDOWS).all.keys + prefs(PREFS_APP_WEEKLY_WINDOWS).all.keys

    fun decodeWindows(json: String?): List<TimeWindow> {
        if (json.isNullOrEmpty()) return emptyList()
        return try {
            val array = JSONArray(json)
            (0 until array.length()).map { i ->
                val obj = array.getJSONObject(i)
                TimeWindow(obj.getInt("s"), obj.getInt("e"))
            }
        } catch (e: Exception) {
            Log.w(TAG, "Corrupt time-windows value, treating as unset: $json", e)
            emptyList()
        }
    }

    fun encodeWindows(windows: List<TimeWindow>): String = encodeWindowArray(windows).toString()

    fun encodeWindowArray(windows: List<TimeWindow>): JSONArray {
        val array = JSONArray()
        windows.forEach { w ->
            array.put(JSONObject().apply { put("s", w.startMinute); put("e", w.endMinute) })
        }
        return array
    }

    fun decodeWeeklyWindows(json: String?): List<List<TimeWindow>>? {
        if (json.isNullOrEmpty()) return null
        return try {
            val array = JSONArray(json)
            if (array.length() != DayOfWeek.entries.size) return null
            (0 until array.length()).map { i ->
                val dayArray = array.getJSONArray(i)
                (0 until dayArray.length()).map { j ->
                    val obj = dayArray.getJSONObject(j)
                    TimeWindow(obj.getInt("s"), obj.getInt("e"))
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Corrupt weekly time-windows value", e)
            null
        }
    }

    fun encodeWeeklyWindows(weekly: List<List<TimeWindow>>): JSONArray {
        val array = JSONArray()
        weekly.forEach { array.put(encodeWindowArray(it)) }
        return array
    }

    // ------------------------------------------------------------------ groups

    fun groups(): List<AppGroup> = decodeGroups(prefs(PREFS_GROUPS).getString(KEY_GROUPS, null))

    /**
     * Persists groups in exactly the JSON schema [decodeGroups] reads, mirroring
     * the original `AppGroupRepository.encode` (data/AppGroupRepository.kt:118-133):
     * `limit` (daily) and `windows` are ALWAYS written, with `weeklyLimit` /
     * `weeklyWindows` added when the group is per-weekday — never an either/or.
     * The group's per-group reopening cooldown is round-tripped as
     * `reopenSeconds`.
     *
     * The one-group-per-app invariant is enforced here for whole-list saves,
     * mirroring the original's `setGroupPackages` / `setPackageGroup`
     * (AppGroupRepository.kt:66-94): the group a package is assigned to wins
     * and every other group loses it. A whole-list save has no per-operation
     * target group, so the LAST group in the list containing a package is the
     * assignment that wins; earlier groups lose the package.
     *
     * Usage entries of groups that no longer exist after this save are
     * removed from `group_usage_stats`, mirroring the original's `deleteGroup`
     * cleanup (AppGroupRepository.kt:56-59).
     */
    fun saveGroups(groups: List<AppGroup>) {
        // One-group-per-app: the last group in the list wins each package.
        val winningGroupIndex = HashMap<String, Int>()
        groups.forEachIndexed { index, g ->
            g.packageNames.forEach { pkg -> winningGroupIndex[pkg] = index }
        }
        val deduped = groups.mapIndexed { index, g ->
            val kept = g.packageNames.filter { winningGroupIndex[it] == index }.toSet()
            if (kept == g.packageNames) g else g.copy(packageNames = kept)
        }
        // Group-usage cleanup for groups deleted by this save.
        val deletedIds = groups().map { it.id }.toSet() - deduped.map { it.id }.toSet()
        if (deletedIds.isNotEmpty()) {
            val usageEdit = prefs(PREFS_GROUP_USAGE).edit()
            deletedIds.forEach { usageEdit.remove(it) }
            usageEdit.apply()
        }
        val array = JSONArray()
        deduped.forEach { g ->
            val obj = JSONObject()
            obj.put("id", g.id)
            obj.put("name", g.name)
            val packages = JSONArray()
            g.packageNames.forEach { packages.put(it) }
            obj.put("packages", packages)
            obj.put("limit", g.timeLimit.dailyMinutes)
            g.timeLimit.weeklyMinutes?.let { weekly ->
                val arr = JSONArray()
                weekly.forEach { arr.put(it) }
                obj.put("weeklyLimit", arr)
            }
            obj.put("reopenSeconds", g.reopenSeconds)
            obj.put("windows", encodeWindowArray(g.timeWindows.dailyWindows))
            g.timeWindows.weeklyWindows?.let { weekly ->
                obj.put("weeklyWindows", encodeWeeklyWindows(weekly))
            }
            array.put(obj)
        }
        prefs(PREFS_GROUPS).edit().putString(KEY_GROUPS, array.toString()).apply()
    }

    fun groupForPackage(packageName: String): AppGroup? =
        groups().firstOrNull { packageName in it.packageNames }

    private fun decodeGroups(json: String?): List<AppGroup> {
        if (json.isNullOrEmpty()) return emptyList()
        return try {
            val array = JSONArray(json)
            (0 until array.length()).map { i ->
                val obj = array.getJSONObject(i)
                val packagesArray = obj.getJSONArray("packages")
                val packages = (0 until packagesArray.length()).map { packagesArray.getString(it) }.toSet()
                val windows = obj.optJSONArray("windows")?.let { arr ->
                    (0 until arr.length()).map { j ->
                        val w = arr.getJSONObject(j)
                        TimeWindow(w.getInt("s"), w.getInt("e"))
                    }
                } ?: emptyList()
                val weeklyWindows = obj.optJSONArray("weeklyWindows")?.let { arr ->
                    decodeWeeklyWindows(arr.toString())
                }
                val weekly = obj.optJSONArray("weeklyLimit")?.let { arr ->
                    (0 until arr.length()).map { arr.getInt(it) }
                }?.takeIf { it.size == DayOfWeek.entries.size }
                AppGroup(
                    id = obj.getString("id"),
                    name = obj.getString("name"),
                    packageNames = packages,
                    timeLimit = weekly?.let { TimeLimit.perDay(it) }
                        ?: TimeLimit.daily(obj.optInt("limit", 0)),
                    timeWindows = weeklyWindows?.let { TimeWindows.perDay(it) }
                        ?: TimeWindows.daily(windows),
                    reopenSeconds = obj.optInt("reopenSeconds", 0),
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "Corrupt app_groups value, treating as no groups", e)
            emptyList()
        }
    }

    // ------------------------------------------------------------------ usage

    /** Clears both usage stores when the calendar day has rolled over. Returns true if it reset. */
    fun resetUsageIfNewDay(today: String): Boolean {
        val meta = prefs(PREFS_USAGE_META)
        if (meta.getString(KEY_USAGE_DATE, null) == today) return false
        prefs(PREFS_USAGE).edit().clear().apply()
        prefs(PREFS_GROUP_USAGE).edit().clear().apply()
        meta.edit().putString(KEY_USAGE_DATE, today).apply()
        return true
    }

    fun usageDate(): String? = prefs(PREFS_USAGE_META).getString(KEY_USAGE_DATE, null)

    fun usageMs(packageName: String): Long = prefs(PREFS_USAGE).getLong(packageName, 0L)

    fun addUsage(packageName: String, deltaMs: Long) {
        val p = prefs(PREFS_USAGE)
        p.edit().putLong(packageName, p.getLong(packageName, 0L) + deltaMs).apply()
    }

    fun allUsage(): Map<String, Long> =
        prefs(PREFS_USAGE).all.mapNotNull { (k, v) -> (v as? Long)?.let { k to it } }.toMap()

    fun groupUsageMs(groupId: String): Long = prefs(PREFS_GROUP_USAGE).getLong(groupId, 0L)

    fun addGroupUsage(groupId: String, deltaMs: Long) {
        val p = prefs(PREFS_GROUP_USAGE)
        p.edit().putLong(groupId, p.getLong(groupId, 0L) + deltaMs).apply()
    }

    fun allGroupUsage(): Map<String, Long> =
        prefs(PREFS_GROUP_USAGE).all.mapNotNull { (k, v) -> (v as? Long)?.let { k to it } }.toMap()

    // ------------------------------------------------------------------ reopen (v1.1 enforcement, stored from v1)

    fun reopenSeconds(packageName: String): Int = prefs(PREFS_REOPEN).getInt(packageName, 0)

    fun setReopenSeconds(packageName: String, seconds: Int) {
        val edit = prefs(PREFS_REOPEN).edit()
        if (seconds > 0) edit.putInt(packageName, seconds) else edit.remove(packageName)
        edit.apply()
    }

    fun reopenPackages(): Set<String> = prefs(PREFS_REOPEN).all.keys

    // ------------------------------------------------------------------ words / activities

    // ------------------------------------------- blocked words (Batch H, item 10)
    //
    // ONE canonical store: assignments (word, targets, modes). One row
    // per word: the word, its targets — direct apps (packageNames)
    // and/or groups (groupIds) — and its modes, "active" (typed-word
    // blocking, F14) or "passive" (on-screen scan, F15). The modes
    // apply to ALL of the word's targets. A group target covers every
    // app in the group at enforcement time (expandedPackages). Before
    // Batch H there were two parallel stores — one global active word
    // list + targets, and per-app passive lists. Batch H merged them
    // as one row per (word, app, mode); Batch J merges further to one
    // row per word so one word can cover many apps and many groups
    // at once. The two ENFORCEMENT modes stay separate (they trigger
    // differently); both views (words-per-app and apps-per-word)
    // read the same truth.
    //
    // Enforcement is per assignment, not per global list: typing word
    // W in app A blocks only when some assignment covers A (directly
    // or through a group) with mode active. The old global-list
    // semantics would have over-blocked (W typed in ANY target app
    // blocks, even one where W was never assigned). Migration
    // (one-way, on first read): the legacy keys (blocked_words x
    // target_packages -> active; passive_words_<pkg> -> passive) and
    // old Batch H rows ({w, p: single pkg, m: single mode}) are
    // merged by word, and the legacy keys are cleared.

    data class WordAssignment(
        val word: String,
        val packageNames: List<String>,
        val groupIds: List<String>,
        val modes: Set<String>, // subset of {"active", "passive"}
    ) {
        fun toJson(): JSONObject = JSONObject()
            .put("w", word)
            .put("p", JSONArray(packageNames))
            .put("g", JSONArray(groupIds))
            .put("m", JSONArray(modes.sorted()))

        /** Packages this entry covers: direct apps plus every member of its groups. */
        fun expandedPackages(groups: List<AppGroup>): Set<String> {
            val out = packageNames.toMutableSet()
            val byId = groups.associateBy { it.id }
            for (id in groupIds) {
                byId[id]?.packageNames?.let { out += it }
            }
            return out
        }

        companion object {
            private fun stringList(value: Any?): List<String> = when (value) {
                is JSONArray -> (0 until value.length())
                    .mapNotNull { value.optString(it).trim().takeIf { s -> s.isNotEmpty() } }
                is String -> listOf(value.trim()).filter { it.isNotEmpty() }
                else -> emptyList()
            }

            private fun modeSet(value: Any?): Set<String> = when (value) {
                is JSONArray -> (0 until value.length())
                    .mapNotNull { value.optString(it).takeIf { s -> s == "active" || s == "passive" } }
                    .toSet()
                is String -> setOf(value).filter { it == "active" || it == "passive" }.toSet()
                else -> emptySet()
            }

            // Accepts the Batch J shape ({w, p: [...], g: [...],
            // m: [...]}) and the old Batch H shape ({w, p: single
            // pkg, m: single mode}); the caller merges rows by word.
            fun fromJson(json: JSONObject): WordAssignment? {
                val word = json.optString("w", "").trim()
                if (word.isEmpty()) return null
                val pkgs = stringList(json.opt("p")).distinct().sorted()
                val groups = stringList(json.opt("g")).distinct().sorted()
                val modes = modeSet(json.opt("m"))
                if (pkgs.isEmpty() && groups.isEmpty()) return null
                if (modes.isEmpty()) return null
                return WordAssignment(word, pkgs, groups, modes)
            }

            /** Merge rows that share a word into one row (union of targets and modes). */
            fun merged(rows: List<WordAssignment>): List<WordAssignment> =
                rows.groupBy { it.word }.map { (word, same) ->
                    WordAssignment(
                        word,
                        same.flatMap { it.packageNames }.distinct().sorted(),
                        same.flatMap { it.groupIds }.distinct().sorted(),
                        same.flatMap { it.modes }.toSet(),
                    )
                }.sortedBy { it.word }
        }
    }

    private const val KEY_WORD_ASSIGNMENTS = "word_assignments_json"

    fun wordAssignments(): List<WordAssignment> {
        val prefs = prefs(PREFS_BLOCKED_WORDS)
        val raw = prefs.getString(KEY_WORD_ASSIGNMENTS, null)
        if (raw != null) {
            return try {
                val array = JSONArray(raw)
                val parsed = (0 until array.length()).mapNotNull {
                    array.optJSONObject(it)?.let { WordAssignment.fromJson(it) }
                }
                val merged = WordAssignment.merged(parsed)
                // One-time convergence: old Batch H rows (one per
                // app/mode) become one row per word. Writes back only
                // when the stored form actually differs.
                val stored =
                    JSONArray().apply { merged.forEach { put(it.toJson()) } }.toString()
                if (stored != raw) {
                    prefs.edit().putString(KEY_WORD_ASSIGNMENTS, stored).apply()
                }
                merged
            } catch (e: Exception) {
                Log.w("SettingsStore", "Corrupt word assignments discarded: ${e.message}")
                emptyList()
            }
        }
        // First read after the Batch H merge: migrate the legacy keys.
        // NOTE: read the raw keys here, NOT the derived readers below
        // (they call back into wordAssignments — that would recurse).
        val migrated = mutableListOf<WordAssignment>()
        val legacyWords =
            prefs.getStringSet("blocked_words", emptySet()) ?: emptySet()
        val legacyTargets =
            prefs.getStringSet("target_packages", emptySet()) ?: emptySet()
        val legacyPassivePkgs = prefs.all.keys
            .filter { it.startsWith("passive_words_") }
            .map { it.removePrefix("passive_words_") }
            .toSet()
        for (word in legacyWords) {
            for (pkg in legacyTargets) {
                migrated += WordAssignment(word, listOf(pkg), emptyList(), setOf("active"))
            }
        }
        for (pkg in legacyPassivePkgs) {
            val words = prefs.getStringSet("passive_words_$pkg", emptySet())
                ?: emptySet()
            for (word in words) {
                migrated += WordAssignment(word, listOf(pkg), emptyList(), setOf("passive"))
            }
        }
        val merged = WordAssignment.merged(migrated)
        val edit = prefs.edit().putString(
            KEY_WORD_ASSIGNMENTS,
            JSONArray().apply { merged.forEach { put(it.toJson()) } }.toString(),
        )
        edit.remove("blocked_words").remove("target_packages")
        for (pkg in legacyPassivePkgs) edit.remove("passive_words_$pkg")
        edit.apply()
        return merged
    }

    fun setWordAssignments(assignments: List<WordAssignment>) {
        val clean = WordAssignment.merged(
            assignments.map {
                WordAssignment(
                    it.word.trim(),
                    it.packageNames.map { p -> p.trim() }.filter { p -> p.isNotEmpty() },
                    it.groupIds.map { g -> g.trim() }.filter { g -> g.isNotEmpty() },
                    it.modes.filter { m -> m == "active" || m == "passive" }.toSet(),
                )
            }.filter {
                it.word.isNotEmpty() &&
                    (it.packageNames.isNotEmpty() || it.groupIds.isNotEmpty()) &&
                    it.modes.isNotEmpty()
            },
        )
        val array = JSONArray()
        clean.forEach { array.put(it.toJson()) }
        prefs(PREFS_BLOCKED_WORDS).edit()
            .putString(KEY_WORD_ASSIGNMENTS, array.toString())
            .apply()
    }

    // Legacy readers, now DERIVED from the assignment table so the
    // payload and any older reader keep seeing the same values.
    // Group targets are expanded to their member packages here, so a
    // word assigned to a group reads exactly like a word assigned to
    // each of the group's apps.
    fun blockedWords(): Set<String> =
        wordAssignments().filter { "active" in it.modes }.map { it.word }.toSet()

    fun wordTargetPackages(): Set<String> {
        val groups = groups()
        return wordAssignments().filter { "active" in it.modes }
            .flatMap { it.expandedPackages(groups) }.toSet()
    }

    fun passiveWordsFor(packageName: String): Set<String> {
        val groups = groups()
        return wordAssignments()
            .filter { "passive" in it.modes && packageName in it.expandedPackages(groups) }
            .map { it.word }.toSet()
    }

    fun passiveWordPackages(): Set<String> {
        val groups = groups()
        return wordAssignments().filter { "passive" in it.modes }
            .flatMap { it.expandedPackages(groups) }.toSet()
    }

    // Legacy writers, now ADAPTERS over the assignment table: the old
    // channel methods keep working, and the two stores can never
    // drift apart again.
    fun setBlockedWords(words: Set<String>, targetPackages: Set<String>) {
        // Keep the passive side untouched; replace the active side:
        // every listed word gains mode active over the targets, and
        // active is dropped from words no longer listed. A listed
        // word keeps its groups (they are not part of this old call).
        val current = wordAssignments()
        val next = current.mapNotNull { entry ->
            val modes = entry.modes - "active"
            if (entry.word in words) {
                entry.copy(
                    packageNames = targetPackages.sorted(),
                    modes = modes + "active",
                )
            } else if (modes.isEmpty()) {
                null
            } else {
                entry.copy(modes = modes)
            }
        }.toMutableList()
        val have = next.map { it.word }.toSet()
        for (word in words) {
            if (word !in have) {
                next += WordAssignment(word, targetPackages.sorted(), emptyList(), setOf("active"))
            }
        }
        setWordAssignments(next)
    }

    fun setPassiveWords(packageName: String, words: Set<String>) {
        val groups = groups()
        val current = wordAssignments()
        val next = current.mapNotNull { entry ->
            if ("passive" !in entry.modes) return@mapNotNull entry
            // Words no longer listed lose their DIRECT coverage of
            // this app. Group coverage is left alone: removing a group
            // here would change other apps too, and the old store
            // could not express it.
            if (entry.word !in words && packageName in entry.packageNames) {
                val pkgs = entry.packageNames - packageName
                val modes =
                    if (pkgs.isEmpty() && entry.groupIds.isEmpty()) entry.modes - "passive"
                    else entry.modes
                if (modes.isEmpty()) null else entry.copy(packageNames = pkgs, modes = modes)
            } else {
                entry
            }
        }.toMutableList()
        for (word in words) {
            val existing = next.firstOrNull { it.word == word }
            val covered = existing?.let { packageName in it.expandedPackages(groups) } == true
            if (existing == null) {
                next += WordAssignment(word, listOf(packageName), emptyList(), setOf("passive"))
            } else if (!covered) {
                val idx = next.indexOf(existing)
                next[idx] = existing.copy(
                    packageNames = (existing.packageNames + packageName).distinct().sorted(),
                    modes = existing.modes + "passive",
                )
            }
            // Else already covered (directly or via a group): nothing to add.
        }
        setWordAssignments(next)
    }

    fun blockedActivities(): Set<String> =
        prefs(PREFS_ACTIVITY_BLOCKER).getStringSet("blocked_activities", emptySet()) ?: emptySet()

    fun setBlockedActivities(activities: Set<String>) {
        prefs(PREFS_ACTIVITY_BLOCKER).edit()
            .putStringSet("blocked_activities", activities)
            .apply()
    }

    // ------------------------------------------------- protected activities (Batch C)

    /**
     * Packages whose activities must never be blocked, whatever the
     * user types: the system UI, Settings, the in-call UI, and Azm
     * itself. Blocking any of them can lock the user out of the phone
     * (no home, no settings, no way to answer a call, no way to open
     * Azm to undo it). The default launcher is resolved live and
     * cached for 5 minutes; the class-name checks below cover any
     * launcher whose activity is not named after its package.
     */
    private val PROTECTED_ACTIVITY_PACKAGES = setOf(
        "com.android.systemui",
        "com.android.settings",
        "com.android.server.telecom",
    )

    @Volatile
    private var cachedLauncherPackage: String? = null

    @Volatile
    private var cachedLauncherAtMs: Long = 0L

    fun defaultLauncherPackage(): String? {
        val now = System.currentTimeMillis()
        val cached = cachedLauncherPackage
        if (cached != null && now - cachedLauncherAtMs < 5 * 60 * 1000L) return cached
        val resolved = try {
            val home = android.content.Intent(android.content.Intent.ACTION_MAIN)
                .addCategory(android.content.Intent.CATEGORY_HOME)
            ctx().packageManager
                .resolveActivity(home, android.content.pm.PackageManager.MATCH_DEFAULT_ONLY)
                ?.activityInfo?.packageName
        } catch (_: Exception) {
            null
        }
        cachedLauncherPackage = resolved
        cachedLauncherAtMs = now
        return resolved
    }

    /**
     * Whether the activity ([packageName], [className]) is protected
     * from blocking. The channel handler refuses to store a blocked
     * entry matching this, and the accessibility service refuses to
     * act on one that somehow got stored.
     */
    fun isProtectedActivity(packageName: String?, className: String): Boolean {
        if (className.contains("Launcher", ignoreCase = true) ||
            className.contains("InCall", ignoreCase = true)
        ) return true
        if (packageName == null) return false
        if (packageName in PROTECTED_ACTIVITY_PACKAGES) return true
        if (packageName == ctx().packageName) return true
        if (packageName == defaultLauncherPackage()) return true
        return false
    }

    // ------------------------------------------------------------------ hidden set (DPM-written)

    fun hiddenPackages(): Set<String> =
        prefs(PREFS_HIDDEN).getStringSet(KEY_HIDDEN_PACKAGES, emptySet()) ?: emptySet()

    fun setHiddenPackage(packageName: String, hidden: Boolean) {
        val current = hiddenPackages()
        val updated = if (hidden) current + packageName else current - packageName
        prefs(PREFS_HIDDEN).edit().putStringSet(KEY_HIDDEN_PACKAGES, updated).apply()
    }

    // ------------------------------------------------------- block torrents (Batch F, item 4)

    /** Mirrors DeChainer's `SecurityManager` `block_torrents` flag. */
    fun isBlockTorrentsEnabled(): Boolean =
        prefs(PREFS_SECURITY).getBoolean(KEY_BLOCK_TORRENTS, false)

    fun setBlockTorrentsEnabled(enabled: Boolean) {
        prefs(PREFS_SECURITY).edit().putBoolean(KEY_BLOCK_TORRENTS, enabled).apply()
    }

    // ------------------------------------------- auto uninstall-block (Batch F, item 6)

    /**
     * Packages whose uninstall-block Azm applied AUTOMATICALLY when they
     * were suspended (item 6). A manual block set by the user in the app
     * sheet is never recorded here, so unsuspending never clears a block
     * the user set on purpose.
     */
    fun autoUninstallBlockedPackages(): Set<String> =
        prefs(PREFS_SECURITY).getStringSet(KEY_AUTO_UNINSTALL_BLOCKED, emptySet())
            ?: emptySet()

    fun setAutoUninstallBlocked(packageName: String, blocked: Boolean) {
        val current = autoUninstallBlockedPackages()
        val updated = if (blocked) current + packageName else current - packageName
        prefs(PREFS_SECURITY).edit().putStringSet(KEY_AUTO_UNINSTALL_BLOCKED, updated).apply()
    }

    // --------------------------------- auto-block-uninstall toggle (Batch F, item 6)

    /**
     * Whether suspending an app also blocks its uninstall (item 6's
     * Settings switch). Default TRUE: the Batch F auto-coupling stays
     * on unless the user turns it off in Settings.
     */
    fun isAutoBlockUninstallSuspended(): Boolean =
        prefs(PREFS_SECURITY).getBoolean(KEY_AUTO_BLOCK_UNINSTALL_SUSPENDED, true)

    fun setAutoBlockUninstallSuspended(enabled: Boolean) {
        prefs(PREFS_SECURITY).edit().putBoolean(KEY_AUTO_BLOCK_UNINSTALL_SUSPENDED, enabled).apply()
    }

    // ------------------------------------------------------------------ suspension log (F27)

    fun logSuspension(packageName: String, reason: SuspensionReason, details: String? = null) {
        val context = ctx()
        synchronized(this) {
            val current = readLogs().toMutableList()
            val now = System.currentTimeMillis()
            // As in the original: dedupe identical package+reason within 5 s.
            val recent = current.firstOrNull { it.optString("packageName") == packageName && it.optString("reason") == reason.name }
            if (recent != null && now - recent.optLong("timestamp", 0L) < 5_000L) return
            val appName = try {
                val pm = context.packageManager
                pm.getApplicationLabel(pm.getApplicationInfo(packageName, 0)).toString()
            } catch (_: Exception) {
                packageName
            }
            val entry = JSONObject().apply {
                put("id", java.util.UUID.randomUUID().toString())
                put("packageName", packageName)
                put("appName", appName)
                put("timestamp", now)
                put("reason", reason.name)
                details?.let { put("details", it) }
            }
            current.add(0, entry)
            while (current.size > MAX_LOGS) current.removeAt(current.size - 1)
            val array = JSONArray()
            current.forEach { array.put(it) }
            prefs(PREFS_SUSPENSION_LOGS).edit().putString(KEY_LOGS, array.toString()).apply()
        }
    }

    fun clearLogs() {
        prefs(PREFS_SUSPENSION_LOGS).edit().remove(KEY_LOGS).apply()
    }

    // ------------------------------------------------- generic config access

    /**
     * Stores that the channel's generic get/setSetting may touch. These hold
     * Dart-domain configuration (ARCH §8.2: browser blocklists, focus and
     * impulse config, challenge config, usage-warning stages, forced-removal
     * state) as JSON strings / scalars — never enforcement state, which uses
     * the typed accessors above, and never the recovery code (§7.1).
     */
    val GENERIC_SETTING_STORES: Set<String> = setOf(
        PREFS_SECURITY, PREFS_BROWSER, PREFS_FOCUS, PREFS_FOCUS_SCHEDULES,
        PREFS_USAGE_WARNING, PREFS_RECOVERY_STATE,
    )

    fun genericGet(store: String, key: String): Any? {
        val value = prefs(store).all[key] ?: return null
        return if (value is Set<*>) value.filterIsInstance<String>() else value
    }

    fun genericSet(store: String, key: String, value: Any?) {
        val edit = prefs(store).edit()
        when (value) {
            null -> edit.remove(key)
            is String -> edit.putString(key, value)
            is Boolean -> edit.putBoolean(key, value)
            is Int -> edit.putInt(key, value)
            is Long -> edit.putLong(key, value)
            is Float -> edit.putFloat(key, value)
            is Double -> edit.putFloat(key, value.toFloat())
            is List<*> -> edit.putStringSet(key, value.filterIsInstance<String>().toSet())
            else -> throw IllegalArgumentException("Unsupported setting value type: ${value.javaClass}")
        }
        edit.apply()
    }

    fun readLogs(): List<JSONObject> {
        val json = prefs(PREFS_SUSPENSION_LOGS).getString(KEY_LOGS, null) ?: return emptyList()
        return try {
            val array = JSONArray(json)
            (0 until array.length()).map { array.getJSONObject(it) }
        } catch (e: Exception) {
            Log.w(TAG, "Corrupt suspension log", e)
            emptyList()
        }
    }

    // ------------------------------------------------------------------ intentional a11y disable (F28 guard)

    /** Arms the guard that suppresses the accessibility-loss lockdown for an intentional disable. */
    fun armIntentionalAccessibilityDisable() {
        val now = System.currentTimeMillis()
        prefs(PREFS_SECURITY).edit()
            .putLong(KEY_INTENTIONAL_A11Y_DISABLE, now).apply()
        AzmState.intentionalDisableArmedAt = now
    }

    /** Consumed by the service's onUnbind: true (once) if the disable was intentional and recent. */
    fun consumeIntentionalAccessibilityDisable(): Boolean {
        // The volatile fast path enforces the SAME 120 s window as the
        // persisted path (v1.0.5 audit A-M5): previously a stale in-process
        // arm was honoured forever, so one intentional disable could have
        // suppressed a much later, genuine accessibility-loss lockdown in
        // the same process.
        val volatileArmedAt = AzmState.intentionalDisableArmedAt
        if (volatileArmedAt != 0L) {
            AzmState.intentionalDisableArmedAt = 0L
            prefs(PREFS_SECURITY).edit().remove(KEY_INTENTIONAL_A11Y_DISABLE).apply()
            return System.currentTimeMillis() - volatileArmedAt <= INTENTIONAL_DISABLE_WINDOW_MS
        }
        val armedAt = prefs(PREFS_SECURITY).getLong(KEY_INTENTIONAL_A11Y_DISABLE, 0L)
        if (armedAt == 0L) return false
        prefs(PREFS_SECURITY).edit().remove(KEY_INTENTIONAL_A11Y_DISABLE).apply()
        return System.currentTimeMillis() - armedAt <= INTENTIONAL_DISABLE_WINDOW_MS
    }

    // ------------------------------------------------------------------ removal in progress (v1.0.5 fix #6)

    /**
     * Sets the persisted "removal in progress" flag. While it is set, the
     * accessibility-loss lockdown and every policy re-application stay
     * disarmed: component teardown during an app-initiated removal (and
     * during the uninstall that follows) is expected, and the lockdown
     * firing there — synchronous package suspension plus an install block
     * from the service's main-thread `onUnbind`, inside the package
     * manager's own removal operation — is what froze devices on
     * uninstall (system UI stuck, watchdog reboot). The teardown in
     * [com.alnajashia.azm.deviceowner.DeviceOwnerManager]
     * sets this FIRST and clears it LAST, so a failed removal re-arms
     * protection instead of leaving it silently disarmed.
     */
    fun setRemovalInProgress(active: Boolean) {
        val edit = prefs(PREFS_SECURITY).edit()
        if (active) {
            edit.putLong(KEY_REMOVAL_IN_PROGRESS, System.currentTimeMillis())
        } else {
            edit.remove(KEY_REMOVAL_IN_PROGRESS)
        }
        // commit(), not apply() (v1.0.5 audit A-M4): this flag is the
        // teardown's first line of defence, and apply()'s async disk
        // write could be lost if the process dies mid-teardown — the
        // disarm must be durable before anything else happens. All call
        // sites are background threads (channel executor / teardown),
        // so the synchronous write costs nothing on the UI thread.
        edit.commit()
        AzmState.removalInProgress = active
    }

    /**
     * True while a removal teardown is running. The volatile mirror is
     * authoritative inside this process; the persisted timestamp is the
     * backstop for a fresh process (e.g. the service restarting during
     * the uninstall that follows a removal) and expires after
     * [REMOVAL_FLAG_WINDOW_MS], so a teardown interrupted by a process
     * death can never leave the lockdown disarmed forever.
     */
    fun isRemovalInProgress(): Boolean {
        if (isProtectionTornDown()) return true
        if (AzmState.removalInProgress) return true
        val startedAt = prefs(PREFS_SECURITY).getLong(KEY_REMOVAL_IN_PROGRESS, 0L)
        if (startedAt == 0L) return false
        return System.currentTimeMillis() - startedAt <= REMOVAL_FLAG_WINDOW_MS
    }

    /**
     * Permanent teardown flag (Batch D deadlock fix): set at the start of
     * Device Owner removal teardown and never cleared by teardown itself.
     * Guarantees accessibility service onUnbind lockdown and any other
     * enforcement can NEVER fire once torn down.
     */
    fun setProtectionTornDown(tornDown: Boolean) {
        val edit = prefs(PREFS_SECURITY).edit()
        if (tornDown) {
            edit.putBoolean(KEY_PROTECTION_TORN_DOWN, true)
        } else {
            edit.remove(KEY_PROTECTION_TORN_DOWN)
        }
        edit.commit()
        AzmState.protectionTornDown = tornDown
    }

    fun isProtectionTornDown(): Boolean {
        if (AzmState.protectionTornDown) return true
        return prefs(PREFS_SECURITY).getBoolean(KEY_PROTECTION_TORN_DOWN, false)
    }

    /** Packages the F28 lockdown controls: every package with any enforcement configured. */
    fun controlledPackages(): Set<String> {
        val groupPackages = groups()
            .filter { it.timeLimit.isSet || it.timeWindows.isSet }
            .flatMap { it.packageNames }
        return wordTargetPackages() +
            passiveWordPackages() +
            limitedPackages() +
            windowedPackages() +
            reopenPackages() +
            groupPackages
    }
}

/** Process-local shared state between the channel handler, the Application and the service. */
object AzmState {
    /** Permanent protection torn down flag (Batch D deadlock fix). */
    @Volatile var protectionTornDown: Boolean = false

    /** Wall-clock time the intentional-disable guard was armed in this process (0 = not armed). */
    @Volatile var intentionalDisableArmedAt: Long = 0L

    /** Volatile mirror of the persisted removal-in-progress flag (v1.0.5 fix #6). */
    @Volatile var removalInProgress: Boolean = false

    @Volatile var accessibilityServiceRunning: Boolean = false

    /**
     * Event bridge to the Flutter EventChannel, installed by the channel
     * handler while an engine is attached. Null when no UI is alive — events
     * are advisory (ARCH §5.5); authoritative state is always re-readable.
     */
    @Volatile var eventSink: ((String, Map<String, Any?>) -> Unit)? = null
}
