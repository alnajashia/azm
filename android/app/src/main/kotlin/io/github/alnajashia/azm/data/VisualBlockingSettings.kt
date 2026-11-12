package io.github.alnajashia.azm.data

import org.json.JSONArray
import org.json.JSONObject

/**
 * "Visual blocking" (F16/F17, added v1.0.6 at the user's order): the
 * shared source of truth for the on-device NSFW image-inspection
 * preferences — read by the settings channel (writer side) and by
 * `AzmAccessibilityService` (reader side), so the keys and
 * defaults cannot drift between the two.
 *
 * Behavioural reference: the original's `VisualBlockingSettings` +
 * `VisualBlockingSuspensionTracker` (Apache-2.0). Same keys, same
 * defaults; the escalation tracker (block history + active suspension
 * deadlines) is persisted in the same prefs file here instead of a
 * second store.
 *
 * Model: MobileNetV2 NSFW classifier by Gant Laborde (nsfw_model,
 * MIT License) — see `assets/models/NSFW_MODEL_NOTICE.txt`. Inference
 * is fully on-device; no screen content ever leaves the device.
 */
object VisualBlockingSettings {
    const val KEY_ENABLED = "enabled"
    const val KEY_TARGET_PACKAGES = "target_packages"
    const val KEY_CATEGORIES = "categories"
    const val KEY_THRESHOLD = "threshold"

    // Escalation: instead of only kicking the user out of the app on
    // every detection, suspend the app entirely once it has been
    // blocked KEY_SUSPEND_BLOCK_COUNT times within
    // KEY_SUSPEND_WINDOW_MINUTES, for KEY_SUSPEND_DURATION_MINUTES.
    // Off by default, so the behaviour without it is the plain
    // close-on-detection of the original's default path.
    const val KEY_SUSPEND_ENABLED = "suspend_enabled"
    const val KEY_SUSPEND_BLOCK_COUNT = "suspend_block_count"
    const val KEY_SUSPEND_WINDOW_MINUTES = "suspend_window_minutes"
    const val KEY_SUSPEND_DURATION_MINUTES = "suspend_duration_minutes"

    private const val KEY_BLOCK_HISTORY = "block_history"
    private const val KEY_ACTIVE_SUSPENSIONS = "active_suspensions"

    val DEFAULT_TARGET_PACKAGES: Set<String> = setOf("com.reddit.frontpage")
    val DEFAULT_CATEGORIES: Set<String> = setOf("hentai", "porn", "sexy")
    const val DEFAULT_THRESHOLD = 0.5f
    const val DEFAULT_SUSPEND_BLOCK_COUNT = 5
    const val DEFAULT_SUSPEND_WINDOW_MINUTES = 15
    const val DEFAULT_SUSPEND_DURATION_MINUTES = 30

    /** "neutral" means "nothing flagged" — never a selectable block category. */
    val SELECTABLE_CATEGORIES: List<String> =
        listOf("drawings", "hentai", "porn", "sexy")

    data class Config(
        val enabled: Boolean,
        val targetPackages: Set<String>,
        val categories: Set<String>,
        val threshold: Float,
        val suspendEnabled: Boolean,
        val suspendBlockCount: Int,
        val suspendWindowMinutes: Int,
        val suspendDurationMinutes: Int,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "enabled" to enabled,
            "targetPackages" to targetPackages.sorted(),
            "categories" to categories.sorted(),
            "threshold" to threshold.toDouble(),
            "suspendEnabled" to suspendEnabled,
            "suspendBlockCount" to suspendBlockCount,
            "suspendWindowMinutes" to suspendWindowMinutes,
            "suspendDurationMinutes" to suspendDurationMinutes,
        )
    }

    private fun prefs() = SettingsStore.prefs(SettingsStore.PREFS_VISUAL_BLOCKING)

    fun load(): Config {
        val p = prefs()
        return Config(
            enabled = p.getBoolean(KEY_ENABLED, false),
            targetPackages = p.getStringSet(KEY_TARGET_PACKAGES, DEFAULT_TARGET_PACKAGES)
                ?: DEFAULT_TARGET_PACKAGES,
            categories = (p.getStringSet(KEY_CATEGORIES, DEFAULT_CATEGORIES)
                ?: DEFAULT_CATEGORIES).intersect(SELECTABLE_CATEGORIES.toSet())
                .ifEmpty { DEFAULT_CATEGORIES },
            threshold = p.getFloat(KEY_THRESHOLD, DEFAULT_THRESHOLD).coerceIn(0.05f, 0.99f),
            suspendEnabled = p.getBoolean(KEY_SUSPEND_ENABLED, false),
            suspendBlockCount = p.getInt(KEY_SUSPEND_BLOCK_COUNT, DEFAULT_SUSPEND_BLOCK_COUNT)
                .coerceIn(1, 100),
            suspendWindowMinutes = p.getInt(
                KEY_SUSPEND_WINDOW_MINUTES, DEFAULT_SUSPEND_WINDOW_MINUTES,
            ).coerceIn(1, 1440),
            suspendDurationMinutes = p.getInt(
                KEY_SUSPEND_DURATION_MINUTES, DEFAULT_SUSPEND_DURATION_MINUTES,
            ).coerceIn(1, 10080),
        )
    }

    fun save(config: Config) {
        prefs().edit()
            .putBoolean(KEY_ENABLED, config.enabled)
            .putStringSet(KEY_TARGET_PACKAGES, config.targetPackages)
            .putStringSet(
                KEY_CATEGORIES,
                config.categories.intersect(SELECTABLE_CATEGORIES.toSet()),
            )
            .putFloat(KEY_THRESHOLD, config.threshold.coerceIn(0.05f, 0.99f))
            .putBoolean(KEY_SUSPEND_ENABLED, config.suspendEnabled)
            .putInt(KEY_SUSPEND_BLOCK_COUNT, config.suspendBlockCount.coerceIn(1, 100))
            .putInt(
                KEY_SUSPEND_WINDOW_MINUTES,
                config.suspendWindowMinutes.coerceIn(1, 1440),
            )
            .putInt(
                KEY_SUSPEND_DURATION_MINUTES,
                config.suspendDurationMinutes.coerceIn(1, 10080),
            )
            .apply()
    }

    fun configFromMap(m: Map<*, *>): Config {
        fun strSet(key: String, fallback: Set<String>): Set<String> =
            (m[key] as? List<*>)?.filterIsInstance<String>()?.toSet() ?: fallback
        fun int(key: String, fallback: Int): Int =
            (m[key] as? Number)?.toInt() ?: fallback
        return Config(
            enabled = m["enabled"] as? Boolean ?: false,
            targetPackages = strSet("targetPackages", DEFAULT_TARGET_PACKAGES),
            categories = strSet("categories", DEFAULT_CATEGORIES),
            threshold = (m["threshold"] as? Number)?.toFloat() ?: DEFAULT_THRESHOLD,
            suspendEnabled = m["suspendEnabled"] as? Boolean ?: false,
            suspendBlockCount = int("suspendBlockCount", DEFAULT_SUSPEND_BLOCK_COUNT),
            suspendWindowMinutes = int("suspendWindowMinutes", DEFAULT_SUSPEND_WINDOW_MINUTES),
            suspendDurationMinutes = int(
                "suspendDurationMinutes", DEFAULT_SUSPEND_DURATION_MINUTES,
            ),
        )
    }

    // ---------------------------------------------------- escalation tracker

    private fun readJson(key: String): JSONObject {
        val raw = prefs().getString(key, null) ?: return JSONObject()
        return try {
            JSONObject(raw)
        } catch (e: Exception) {
            android.util.Log.w(
                "VisualBlockingSettings", "Corrupt $key discarded: ${e.message}",
            )
            JSONObject()
        }
    }

    private fun writeJson(key: String, json: JSONObject) {
        prefs().edit().putString(key, json.toString()).apply()
    }

    /**
     * Records a block of [packageName] at [nowMs]; returns true when
     * this block completes the escalation window — i.e. at least
     * [blockCount] blocks within the last [windowMinutes] minutes.
     * Stale timestamps are pruned on every call.
     */
    fun registerBlock(
        packageName: String,
        blockCount: Int,
        windowMinutes: Int,
        nowMs: Long = System.currentTimeMillis(),
    ): Boolean {
        val history = readJson(KEY_BLOCK_HISTORY)
        val cutoff = nowMs - windowMinutes.toLong() * 60_000L
        val kept = mutableListOf<Long>()
        val existing = history.optJSONArray(packageName)
        if (existing != null) {
            for (i in 0 until existing.length()) {
                val t = existing.optLong(i, 0L)
                if (t > cutoff) kept += t
            }
        }
        kept += nowMs
        history.put(packageName, JSONArray(kept))
        writeJson(KEY_BLOCK_HISTORY, history)
        return kept.size >= blockCount
    }

    /** Marks [packageName] visually suspended until [untilMs]; returns [untilMs]. */
    fun startSuspension(packageName: String, durationMinutes: Int, nowMs: Long = System.currentTimeMillis()): Long {
        val until = nowMs + durationMinutes.toLong() * 60_000L
        val active = readJson(KEY_ACTIVE_SUSPENSIONS)
        active.put(packageName, until)
        writeJson(KEY_ACTIVE_SUSPENSIONS, active)
        return until
    }

    fun endSuspension(packageName: String) {
        val active = readJson(KEY_ACTIVE_SUSPENSIONS)
        if (active.has(packageName)) {
            active.remove(packageName)
            writeJson(KEY_ACTIVE_SUSPENSIONS, active)
        }
    }

    fun isSuspended(packageName: String, nowMs: Long = System.currentTimeMillis()): Boolean {
        val until = readJson(KEY_ACTIVE_SUSPENSIONS).optLong(packageName, 0L)
        return until > nowMs
    }

    /** All recorded visual suspensions (package → deadline epoch ms), expired included. */
    fun activeSuspensions(): Map<String, Long> {
        val active = readJson(KEY_ACTIVE_SUSPENSIONS)
        val result = mutableMapOf<String, Long>()
        val keys = active.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            result[key] = active.optLong(key, 0L)
        }
        return result
    }
}
