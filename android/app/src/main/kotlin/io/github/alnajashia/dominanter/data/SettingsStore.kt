package io.github.alnajashia.dominanter.data

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
 *  - `blocked_words_prefs` (`blocked_words`, `target_packages`, `passive_words_<pkg>`)
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

    private const val KEY_GROUPS = "groups"
    private const val KEY_HIDDEN_PACKAGES = "hidden_packages"
    private const val KEY_LOGS = "logs"
    private const val KEY_USAGE_DATE = "date"
    private const val KEY_INTENTIONAL_A11Y_DISABLE = "intentional_a11y_disable_at"
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
        val minutes = value.split(",").map { it.trim().toIntOrNull() ?: return null }
        return minutes.takeIf { it.size == DayOfWeek.entries.size }
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

    fun blockedWords(): Set<String> =
        prefs(PREFS_BLOCKED_WORDS).getStringSet("blocked_words", emptySet()) ?: emptySet()

    fun wordTargetPackages(): Set<String> =
        prefs(PREFS_BLOCKED_WORDS).getStringSet("target_packages", emptySet()) ?: emptySet()

    fun passiveWordsFor(packageName: String): Set<String> =
        prefs(PREFS_BLOCKED_WORDS).getStringSet("passive_words_$packageName", emptySet()) ?: emptySet()

    fun passiveWordPackages(): Set<String> =
        prefs(PREFS_BLOCKED_WORDS).all.keys
            .filter { it.startsWith("passive_words_") }
            .map { it.removePrefix("passive_words_") }
            .toSet()

    fun blockedActivities(): Set<String> =
        prefs(PREFS_ACTIVITY_BLOCKER).getStringSet("blocked_activities", emptySet()) ?: emptySet()

    fun setBlockedWords(words: Set<String>, targetPackages: Set<String>) {
        prefs(PREFS_BLOCKED_WORDS).edit()
            .putStringSet("blocked_words", words)
            .putStringSet("target_packages", targetPackages)
            .apply()
    }

    fun setPassiveWords(packageName: String, words: Set<String>) {
        val edit = prefs(PREFS_BLOCKED_WORDS).edit()
        val key = "passive_words_$packageName"
        if (words.isEmpty()) edit.remove(key) else edit.putStringSet(key, words)
        edit.apply()
    }

    // ------------------------------------------------------------------ hidden set (DPM-written)

    fun hiddenPackages(): Set<String> =
        prefs(PREFS_HIDDEN).getStringSet(KEY_HIDDEN_PACKAGES, emptySet()) ?: emptySet()

    fun setHiddenPackage(packageName: String, hidden: Boolean) {
        val current = hiddenPackages()
        val updated = if (hidden) current + packageName else current - packageName
        prefs(PREFS_HIDDEN).edit().putStringSet(KEY_HIDDEN_PACKAGES, updated).apply()
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
        prefs(PREFS_SECURITY).edit()
            .putLong(KEY_INTENTIONAL_A11Y_DISABLE, System.currentTimeMillis()).apply()
        DominanterState.intentionalDisableArmed = true
    }

    /** Consumed by the service's onUnbind: true (once) if the disable was intentional and recent. */
    fun consumeIntentionalAccessibilityDisable(): Boolean {
        if (DominanterState.intentionalDisableArmed) {
            DominanterState.intentionalDisableArmed = false
            prefs(PREFS_SECURITY).edit().remove(KEY_INTENTIONAL_A11Y_DISABLE).apply()
            return true
        }
        val armedAt = prefs(PREFS_SECURITY).getLong(KEY_INTENTIONAL_A11Y_DISABLE, 0L)
        if (armedAt == 0L) return false
        prefs(PREFS_SECURITY).edit().remove(KEY_INTENTIONAL_A11Y_DISABLE).apply()
        return System.currentTimeMillis() - armedAt <= INTENTIONAL_DISABLE_WINDOW_MS
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
object DominanterState {
    @Volatile var intentionalDisableArmed: Boolean = false

    @Volatile var accessibilityServiceRunning: Boolean = false

    /**
     * Event bridge to the Flutter EventChannel, installed by the channel
     * handler while an engine is attached. Null when no UI is alive — events
     * are advisory (ARCH §5.5); authoritative state is always re-readable.
     */
    @Volatile var eventSink: ((String, Map<String, Any?>) -> Unit)? = null
}
