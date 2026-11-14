package com.alnajashia.azm.data

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.SystemClock
import com.alnajashia.azm.deviceowner.AzmDeviceAdminReceiver
import com.alnajashia.azm.focus.FocusSessionStore
import com.alnajashia.azm.lockdown.LockdownStore
import org.json.JSONArray
import org.json.JSONObject

/**
 * SEAL rules (v1.0.6, Phase D — user order): user-defined conditions
 * under which Azm refuses to remove itself. While any seal is active,
 * the privileged channel's removal operations (immediate removal and
 * scheduling the delayed forced removal) refuse with a typed SEALED
 * error naming the responsible rule.
 *
 * Two rule families:
 *  - CONDITION seals hold while a live-probed state is true (a chosen
 *    app is uninstall-blocked/hidden by Azm, a chosen app is suspended
 *    by Azm, a focus session is running). They are evaluated from
 *    authoritative probes at attempt time — never from cached UI
 *    state.
 *  - EVENT seals hold for a user-chosen duration from a detection
 *    event (Phase B visual detection or a banned-word block in a
 *    chosen app). The accessibility service records them natively at
 *    detection time. Deadlines are anchored to
 *    [SystemClock.elapsedRealtime] so wall-clock changes cannot
 *    shorten them; a wall-clock deadline is stored alongside purely
 *    as the post-reboot fallback (elapsedRealtime resets at boot).
 *
 * Honest limit (also stated in the UI): a seal has teeth only while
 * Azm is Device Owner. Without owner rights Android lets the user
 * uninstall any app and no in-app rule can prevent it — the probes
 * below then simply read false and no seal engages.
 */
object SealRules {

    enum class Trigger {
        APP_BLOCKED, APP_SUSPENDED, FOCUS_RUNNING, LOCKDOWN_RUNNING, VISUAL_DETECTION, BANNED_WORD,
    }

    data class Rule(
        val id: String,
        val trigger: Trigger,
        // Batch H, item 12: a rule watches MANY apps (was one
        // `packageName`) AND a group's members. A rule with neither
        // an app nor a group never engages (the editor forbids it).
        val packageNames: List<String> = emptyList(),
        val groupId: String? = null,
        val durationMinutes: Int?,
        val enabled: Boolean,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "id" to id,
            "trigger" to trigger.name,
            "packageNames" to packageNames,
            "groupId" to groupId,
            "durationMinutes" to durationMinutes,
            "enabled" to enabled,
        )

        fun toJson(): JSONObject = JSONObject()
            .put("id", id)
            .put("trigger", trigger.name)
            .put("packageNames", JSONArray(packageNames))
            .put("groupId", groupId ?: JSONObject.NULL)
            .put("durationMinutes", durationMinutes ?: JSONObject.NULL)
            .put("enabled", enabled)

        companion object {
            fun fromJson(json: JSONObject): Rule? {
                val trigger = try {
                    Trigger.valueOf(json.optString("trigger", ""))
                } catch (_: Exception) {
                    return null
                }
                val id = json.optString("id", "")
                if (id.isEmpty()) return null
                // Batch H migration: a legacy `packageName` becomes a
                // one-element `packageNames`.
                val names = json.optJSONArray("packageNames")?.let { arr ->
                    (0 until arr.length())
                        .mapNotNull { arr.optString(it).takeIf { s -> s.isNotEmpty() } }
                }
                val legacy = json.optString("packageName", "").ifEmpty { null }
                return Rule(
                    id = id,
                    trigger = trigger,
                    packageNames = names ?: (legacy?.let { listOf(it) } ?: emptyList()),
                    groupId = json.optString("groupId", "").ifEmpty { null },
                    durationMinutes = if (json.isNull("durationMinutes")) {
                        null
                    } else {
                        json.optInt("durationMinutes", 0).takeIf { it > 0 }
                    },
                    enabled = json.optBoolean("enabled", true),
                )
            }

            fun fromMap(m: Map<*, *>): Rule? {
                val trigger = try {
                    Trigger.valueOf(m["trigger"] as? String ?: "")
                } catch (_: Exception) {
                    return null
                }
                val id = m["id"] as? String ?: return null
                if (id.isEmpty()) return null
                val names = (m["packageNames"] as? List<*>)
                    ?.filterIsInstance<String>()
                    ?.filter { it.isNotEmpty() }
                val legacy = (m["packageName"] as? String)?.ifEmpty { null }
                return Rule(
                    id = id,
                    trigger = trigger,
                    packageNames = names ?: (legacy?.let { listOf(it) } ?: emptyList()),
                    groupId = (m["groupId"] as? String)?.ifEmpty { null },
                    durationMinutes = (m["durationMinutes"] as? Number)?.toInt()
                        ?.takeIf { it > 0 },
                    enabled = m["enabled"] as? Boolean ?: true,
                )
            }
        }

        /** Every package this rule watches: its own apps plus the group's members. */
        fun effectivePackages(): Set<String> {
            val pkgs = packageNames.toMutableSet()
            groupId?.let { gid ->
                SettingsStore.groups().firstOrNull { it.id == gid }
                    ?.let { pkgs += it.packageNames }
            }
            return pkgs
        }
    }

    /** One currently-holding seal, for the refusal error and the Status tab. */
    data class ActiveSeal(
        val ruleId: String,
        val trigger: Trigger,
        val packageName: String?,
        /** Null = holds while the condition holds (no countdown). */
        val remainingMs: Long?,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "ruleId" to ruleId,
            "trigger" to trigger.name,
            "packageName" to packageName,
            "remainingMs" to remainingMs,
        )
    }

    /** Durations offered for event seals (minutes): 30m, 1h, 6h, 24h, 7d. */
    val EVENT_DURATIONS_MINUTES = listOf(30, 60, 360, 1440, 10080)

    private const val KEY_RULES = "rules"
    private const val KEY_EVENT_DEADLINES = "event_deadlines"

    private fun prefs() = SettingsStore.prefs(SettingsStore.PREFS_SEAL_RULES)

    fun loadRules(): List<Rule> {
        val raw = prefs().getString(KEY_RULES, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { Rule.fromJson(array.optJSONObject(it)) }
        } catch (e: Exception) {
            android.util.Log.w("SealRules", "Corrupt rules discarded: ${e.message}")
            emptyList()
        }
    }

    fun saveRules(rules: List<Rule>) {
        val array = JSONArray()
        rules.forEach { array.put(it.toJson()) }
        prefs().edit().putString(KEY_RULES, array.toString()).apply()
    }

    // ------------------------------------------------------------ event seals

    /**
     * Records a detection event natively (called by the accessibility
     * service at detection time): every enabled rule matching
     * [trigger] + [packageName] gets a deadline of now + its duration;
     * an existing later deadline is never shortened. The triggering
     * package is stored with the deadline so the active seal can name
     * the app that actually caused it (Batch H: rules watch many apps).
     */
    fun recordEvent(trigger: Trigger, packageName: String) {
        val matching = loadRules().filter {
            it.enabled && it.trigger == trigger &&
                it.durationMinutes != null &&
                packageName in it.effectivePackages()
        }
        if (matching.isEmpty()) return
        val deadlines = readDeadlines()
        val nowElapsed = SystemClock.elapsedRealtime()
        val nowWall = System.currentTimeMillis()
        for (rule in matching) {
            val durationMs = rule.durationMinutes!!.toLong() * 60_000L
            val candidateElapsed = nowElapsed + durationMs
            val existing = deadlines.optJSONObject(rule.id)
            if (existing != null && existing.optLong("deadlineElapsed", 0L) > candidateElapsed &&
                nowElapsed >= existing.optLong("setElapsed", 0L)
            ) {
                continue // a longer same-boot deadline already stands
            }
            deadlines.put(
                rule.id,
                JSONObject()
                    .put("setElapsed", nowElapsed)
                    .put("setWall", nowWall)
                    .put("deadlineElapsed", candidateElapsed)
                    .put("deadlineWall", nowWall + durationMs)
                    .put("packageName", packageName),
            )
        }
        writeDeadlines(deadlines)
    }

    private fun readDeadlines(): JSONObject {
        val raw = prefs().getString(KEY_EVENT_DEADLINES, null) ?: return JSONObject()
        return try {
            JSONObject(raw)
        } catch (e: Exception) {
            android.util.Log.w("SealRules", "Corrupt deadlines discarded: ${e.message}")
            JSONObject()
        }
    }

    private fun writeDeadlines(deadlines: JSONObject) {
        prefs().edit().putString(KEY_EVENT_DEADLINES, deadlines.toString()).apply()
    }

    /** Clears all recorded event deadlines (called during teardown). */
    fun clearEventDeadlines() {
        prefs().edit().remove(KEY_EVENT_DEADLINES).apply()
    }

    /**
     * The live event seal for one rule: (remaining ms, triggering
     * package), or null when it has expired (and is pruned).
     * Same-boot: pure elapsedRealtime math, immune to wall-clock
     * changes. After a reboot (elapsedRealtime moved backwards past
     * the set anchor): the stored wall deadline governs.
     */
    private fun eventSeal(ruleId: String): Pair<Long, String?>? {
        val deadlines = readDeadlines()
        val entry = deadlines.optJSONObject(ruleId) ?: return null
        val nowElapsed = SystemClock.elapsedRealtime()
        val setElapsed = entry.optLong("setElapsed", 0L)
        val remaining = if (nowElapsed >= setElapsed) {
            entry.optLong("deadlineElapsed", 0L) - nowElapsed
        } else {
            entry.optLong("deadlineWall", 0L) - System.currentTimeMillis()
        }
        if (remaining <= 0L) {
            deadlines.remove(ruleId)
            writeDeadlines(deadlines)
            return null
        }
        return remaining to entry.optString("packageName", "").ifEmpty { null }
    }

    // ------------------------------------------------------------ evaluation

    /**
     * Every seal holding RIGHT NOW. Condition seals are probed live;
     * event seals read their anchored deadlines. Disabled rules and
     * rules whose probe cannot run (not Device Owner) never engage.
     */
    fun activeSeals(context: Context): List<ActiveSeal> {
        val result = mutableListOf<ActiveSeal>()
        val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE)
            as? DevicePolicyManager
        val admin = ComponentName(context, AzmDeviceAdminReceiver::class.java)
        val adminActive = dpm?.isAdminActive(admin) == true
        for (rule in loadRules()) {
            if (!rule.enabled) continue
            when (rule.trigger) {
                Trigger.APP_BLOCKED -> {
                    if (!adminActive || dpm == null) continue
                    // Batch H: the seal engages when ANY watched app
                    // (its own apps or the group's members) is blocked
                    // or hidden, and names that app.
                    val match = rule.effectivePackages().firstOrNull { pkg ->
                        runCatching {
                            dpm.isUninstallBlocked(admin, pkg) ||
                                dpm.isApplicationHidden(admin, pkg)
                        }.getOrDefault(false)
                    } ?: continue
                    result += ActiveSeal(rule.id, rule.trigger, match, null)
                }
                Trigger.APP_SUSPENDED -> {
                    val match = rule.effectivePackages().firstOrNull { pkg ->
                        runCatching {
                            val info = context.packageManager.getApplicationInfo(pkg, 0)
                            info.flags and ApplicationInfo.FLAG_SUSPENDED != 0
                        }.getOrDefault(false)
                    } ?: continue
                    result += ActiveSeal(rule.id, rule.trigger, match, null)
                }
                Trigger.FOCUS_RUNNING -> {
                    if (FocusSessionStore.isActive()) {
                        result += ActiveSeal(rule.id, rule.trigger, null, null)
                    }
                }
                Trigger.LOCKDOWN_RUNNING -> {
                    // Batch I-B, item 14: a lockdown running counts as a
                    // seal condition, like a focus session.
                    if (LockdownStore.isActive(context)) {
                        result += ActiveSeal(rule.id, rule.trigger, null, null)
                    }
                }
                Trigger.VISUAL_DETECTION, Trigger.BANNED_WORD -> {
                    val (remaining, pkg) = eventSeal(rule.id) ?: continue
                    result += ActiveSeal(rule.id, rule.trigger, pkg, remaining)
                }
            }
        }
        return result
    }

    /** The first holding seal, if any — the removal refusal decision. */
    fun firstActiveSeal(context: Context): ActiveSeal? = activeSeals(context).firstOrNull()
}
