package com.alnajashia.azm.lockdown

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.os.UserManager
import android.provider.Settings
import android.telecom.TelecomManager
import android.util.Log
import com.alnajashia.azm.channel.PrivException
import com.alnajashia.azm.data.SettingsStore
import com.alnajashia.azm.data.SuspensionClaims
import com.alnajashia.azm.data.SuspensionReason
import com.alnajashia.azm.deviceowner.AzmDeviceAdminReceiver
import com.alnajashia.azm.deviceowner.DeviceOwnerManager
import com.alnajashia.azm.notifications.LockdownNotifier
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters
import java.util.UUID

/**
 * Full-phone lockdown (Batch I-B, item 14): two tiers, user-chosen
 * in-app with a per-tier explanation.
 *
 *  - **Tier 1** (strict = false): suspends the lockdown's targets
 *    (every user app, chosen apps, or groups) with the claimed-set
 *    pattern, adds `DISALLOW_INSTALL_APPS` + `DISALLOW_SAFE_BOOT`,
 *    and locks the phone now. The home screen stays, with greyed-out
 *    icons.
 *  - **Tier 2** (strict = true): everything in Tier 1, plus
 *    `setLockTaskPackages([Azm])` and a dedicated countdown activity
 *    in lock-task mode — no Home/Recents, blank status bar, only
 *    Azm's countdown visible.
 *
 * Deadlines copy FocusSessionStore's dual-clock rule: one-shot
 * durations anchor on elapsed realtime while the boot lasts (moving
 * the clock cannot shorten a lockdown) and fall back to the wall
 * clock after a reboot; recurring windows are calendar concepts and
 * use the wall clock only. A lockdown is data, not a process:
 * [sync] is the idempotent entry point every caller funnels into
 * (end alarm, window start, boot/time receiver, app cold start), so
 * a lockdown that outlives its end, a reboot, or a force-stop ends
 * the moment Azm runs again.
 *
 * Hard limits (stated in the UI, not in a footnote): powering the
 * phone off cannot be prevented (the lockdown re-applies after
 * reboot — a pause, not an escape); the emergency dialer stays
 * reachable in lock task; the default dialer, the launcher, Settings
 * and Azm itself are never suspended (see [resolveTargets]).
 * Uninstall-blocking of suspended apps follows the existing
 * Settings switch (default ON) via
 * [DeviceOwnerManager.setPackagesSuspended]'s coupling.
 */
object LockdownStore {
    private const val TAG = "LockdownStore"
    const val PREFS_NAME = "lockdown_prefs"
    private const val KEY_LOCKDOWNS = "lockdowns"

    // Runtime state keys (same prefs, separate from the config list).
    // The active lockdown's full config rides here as JSON, so a
    // one-shot lockdown (never saved in the config list) survives a
    // reboot too.
    private const val KEY_ACTIVE_JSON = "active_lockdown_json"
    private const val KEY_ACTIVE_END_ELAPSED = "active_end_elapsed"
    private const val KEY_ACTIVE_END_WALL = "active_end_wall"
    private const val KEY_ACTIVE_BOOT_COUNT = "active_boot_count"

    /** One-shot durations the UI offers (minutes). */
    val ONE_SHOT_MINUTES = listOf(15, 30, 60, 180)
    const val ONE_SHOT_MIN_MINUTES = 5
    const val ONE_SHOT_MAX_MINUTES = 12 * 60

    /** The lockdown's own restrictions, on top of the suspension. */
    private val LOCKDOWN_RESTRICTIONS = setOf(
        UserManager.DISALLOW_INSTALL_APPS,
        UserManager.DISALLOW_SAFE_BOOT,
    )

    enum class LockdownKind { ONE_SHOT, RECURRING }
    enum class LockdownScope { ALL_APPS, APPS, GROUPS }

    data class Lockdown(
        val id: String = UUID.randomUUID().toString(),
        val kind: LockdownKind = LockdownKind.ONE_SHOT,
        val durationMinutes: Int = 180,
        val startHour: Int = 6,
        val startMinute: Int = 0,
        val endHour: Int = 10,
        val endMinute: Int = 0,
        val daysOfWeek: Set<Int> = emptySet(), // 1 = Monday .. 7 = Sunday
        val scope: LockdownScope = LockdownScope.ALL_APPS,
        val targetApps: Set<String> = emptySet(),
        val targetGroups: Set<String> = emptySet(),
        val strict: Boolean = false,
        val enabled: Boolean = true,
        val label: String = "",
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "id" to id,
            "kind" to kind.name,
            "durationMinutes" to durationMinutes,
            "startHour" to startHour,
            "startMinute" to startMinute,
            "endHour" to endHour,
            "endMinute" to endMinute,
            "days" to daysOfWeek.sorted(),
            "scope" to scope.name,
            "targetApps" to targetApps.sorted(),
            "targetGroups" to targetGroups.sorted(),
            "strict" to strict,
            "enabled" to enabled,
            "label" to label,
        )

        fun toJson(): JSONObject = JSONObject()
            .put("id", id)
            .put("kind", kind.name)
            .put("durationMinutes", durationMinutes)
            .put("startHour", startHour)
            .put("startMinute", startMinute)
            .put("endHour", endHour)
            .put("endMinute", endMinute)
            .put("days", JSONArray(daysOfWeek.sorted()))
            .put("scope", scope.name)
            .put("targetApps", JSONArray(targetApps.sorted()))
            .put("targetGroups", JSONArray(targetGroups.sorted()))
            .put("strict", strict)
            .put("enabled", enabled)
            .put("label", label)

        /**
         * The next wall-clock start for a recurring window — the same
         * math as FocusSchedule.nextTriggerMillis (start time + days).
         */
        fun nextWindowStartMillis(now: LocalDateTime = LocalDateTime.now()): Long? {
            if (kind != LockdownKind.RECURRING || !enabled || daysOfWeek.isEmpty()) return null
            val currentDay = now.dayOfWeek.value
            val currentTimeInMinutes = now.hour * 60 + now.minute
            val targetTimeInMinutes = startHour * 60 + startMinute
            if (currentDay in daysOfWeek && targetTimeInMinutes > currentTimeInMinutes) {
                val target = now.withHour(startHour).withMinute(startMinute).withSecond(0).withNano(0)
                return target.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
            }
            var minDateTime: LocalDateTime? = null
            for (dayVal in daysOfWeek) {
                val candidate = now.with(TemporalAdjusters.next(java.time.DayOfWeek.of(dayVal)))
                    .withHour(startHour).withMinute(startMinute).withSecond(0).withNano(0)
                if (minDateTime == null || candidate.isBefore(minDateTime)) {
                    minDateTime = candidate
                }
            }
            return minDateTime?.atZone(ZoneId.systemDefault())?.toInstant()?.toEpochMilli()
        }

        /**
         * The wall-clock end for a window starting at [startMillis].
         * End <= start means overnight: the end is the next day.
         * A window with start == end is invalid (the UI forbids it);
         * defensively it ends 24 h after the start.
         */
        fun windowEndWallMillis(startMillis: Long): Long {
            val start = LocalDateTime.ofInstant(
                java.time.Instant.ofEpochMilli(startMillis),
                ZoneId.systemDefault(),
            )
            var end = start.withHour(endHour).withMinute(endMinute).withSecond(0).withNano(0)
            if (!end.isAfter(start)) end = end.plusDays(1)
            return end.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
        }

        companion object {
            // Block body, not `= try { ... }`: the `return null`
            // below is prohibited in an expression-bodied function
            // (same lesson as FocusSchedule.fromJson in Batch I-A).
            fun fromJson(json: JSONObject): Lockdown? {
                return try {
                    val id = json.optString("id", "")
                        .takeIf { it.isNotEmpty() } ?: return null
                    val daysArray = json.optJSONArray("days")
                    val days = if (daysArray == null) {
                        emptySet()
                    } else {
                        (0 until daysArray.length())
                            .map { daysArray.optInt(it) }
                            .filter { it in 1..7 }
                            .toSet()
                    }
                    fun stringSet(key: String): Set<String> {
                        val arr = json.optJSONArray(key) ?: return emptySet()
                        return (0 until arr.length()).mapNotNull { arr.optString(it).takeIf { s -> s.isNotEmpty() } }.toSet()
                    }
                    Lockdown(
                        id = id,
                        kind = runCatching { LockdownKind.valueOf(json.optString("kind", "ONE_SHOT")) }.getOrDefault(LockdownKind.ONE_SHOT),
                        durationMinutes = json.optInt("durationMinutes", 180).coerceIn(ONE_SHOT_MIN_MINUTES, ONE_SHOT_MAX_MINUTES),
                        startHour = json.optInt("startHour", 6).coerceIn(0, 23),
                        startMinute = json.optInt("startMinute", 0).coerceIn(0, 59),
                        endHour = json.optInt("endHour", 10).coerceIn(0, 23),
                        endMinute = json.optInt("endMinute", 0).coerceIn(0, 59),
                        daysOfWeek = days,
                        scope = runCatching { LockdownScope.valueOf(json.optString("scope", "ALL_APPS")) }.getOrDefault(LockdownScope.ALL_APPS),
                        targetApps = stringSet("targetApps"),
                        targetGroups = stringSet("targetGroups"),
                        strict = json.optBoolean("strict", false),
                        enabled = json.optBoolean("enabled", true),
                        label = json.optString("label", ""),
                    )
                } catch (_: Exception) {
                    null
                }
            }

            fun fromMap(m: Map<*, *>): Lockdown? {
                val id = m["id"] as? String ?: return null
                if (id.isEmpty()) return null
                fun stringSet(key: String): Set<String> =
                    (m[key] as? List<*>)?.mapNotNull { (it as? String)?.takeIf { s -> s.isNotEmpty() } }?.toSet() ?: emptySet()
                val days = (m["days"] as? List<*>)
                    ?.mapNotNull { (it as? Number)?.toInt() }
                    ?.filter { it in 1..7 }
                    ?.toSet() ?: emptySet()
                return Lockdown(
                    id = id,
                    kind = runCatching { LockdownKind.valueOf(m["kind"] as? String ?: "ONE_SHOT") }.getOrDefault(LockdownKind.ONE_SHOT),
                    durationMinutes = ((m["durationMinutes"] as? Number)?.toInt() ?: 180).coerceIn(ONE_SHOT_MIN_MINUTES, ONE_SHOT_MAX_MINUTES),
                    startHour = ((m["startHour"] as? Number)?.toInt() ?: 6).coerceIn(0, 23),
                    startMinute = ((m["startMinute"] as? Number)?.toInt() ?: 0).coerceIn(0, 59),
                    endHour = ((m["endHour"] as? Number)?.toInt() ?: 10).coerceIn(0, 23),
                    endMinute = ((m["endMinute"] as? Number)?.toInt() ?: 0).coerceIn(0, 59),
                    daysOfWeek = days,
                    scope = runCatching { LockdownScope.valueOf(m["scope"] as? String ?: "ALL_APPS") }.getOrDefault(LockdownScope.ALL_APPS),
                    targetApps = stringSet("targetApps"),
                    targetGroups = stringSet("targetGroups"),
                    strict = m["strict"] as? Boolean ?: false,
                    enabled = m["enabled"] as? Boolean ?: true,
                    label = m["label"] as? String ?: "",
                )
            }
        }
    }

    data class ActiveLockdown(
        val lockdown: Lockdown,
        val endElapsedRealtime: Long,
        val endWallClock: Long,
        val bootCount: Int,
    )

    // ------------------------------------------------------------ config

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun getLockdowns(context: Context): List<Lockdown> {
        val json = prefs(context).getString(KEY_LOCKDOWNS, null) ?: return emptyList()
        return try {
            val array = JSONArray(json)
            (0 until array.length()).mapNotNull { array.optJSONObject(it)?.let { Lockdown.fromJson(it) } }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun saveLockdowns(context: Context, lockdowns: List<Lockdown>) {
        val array = JSONArray()
        lockdowns.forEach { array.put(it.toJson()) }
        prefs(context).edit().putString(KEY_LOCKDOWNS, array.toString()).apply()
        LockdownManager.rescheduleWindows(context)
    }

    // ------------------------------------------------------------ runtime state

    private fun readActive(context: Context): ActiveLockdown? {
        val p = prefs(context)
        val json = p.getString(KEY_ACTIVE_JSON, null) ?: return null
        val lockdown = try {
            Lockdown.fromJson(JSONObject(json))
        } catch (_: Exception) {
            null
        } ?: return null
        return ActiveLockdown(
            lockdown = lockdown,
            endElapsedRealtime = p.getLong(KEY_ACTIVE_END_ELAPSED, 0L),
            endWallClock = p.getLong(KEY_ACTIVE_END_WALL, 0L),
            bootCount = p.getInt(KEY_ACTIVE_BOOT_COUNT, -1),
        )
    }

    private fun persistActive(context: Context, active: ActiveLockdown) {
        prefs(context).edit()
            .putString(KEY_ACTIVE_JSON, active.lockdown.toJson().toString())
            .putLong(KEY_ACTIVE_END_ELAPSED, active.endElapsedRealtime)
            .putLong(KEY_ACTIVE_END_WALL, active.endWallClock)
            .putInt(KEY_ACTIVE_BOOT_COUNT, active.bootCount)
            .apply()
    }

    private fun clearActive(context: Context) {
        prefs(context).edit()
            .remove(KEY_ACTIVE_JSON)
            .remove(KEY_ACTIVE_END_ELAPSED)
            .remove(KEY_ACTIVE_END_WALL)
            .remove(KEY_ACTIVE_BOOT_COUNT)
            .apply()
    }

    fun activeLockdown(context: Context): ActiveLockdown? = readActive(context)

    fun remainingMs(context: Context, active: ActiveLockdown): Long =
        if (active.bootCount == bootCount(context)) {
            active.endElapsedRealtime - SystemClock.elapsedRealtime()
        } else {
            active.endWallClock - System.currentTimeMillis()
        }.coerceAtLeast(0L)

    fun isActive(context: Context): Boolean {
        val active = readActive(context) ?: return false
        return remainingMs(context, active) > 0
    }

    fun stateMap(context: Context): Map<String, Any?> {
        val active = readActive(context)
        return mapOf(
            "lockdowns" to getLockdowns(context).map { it.toMap() },
            "active" to active?.let {
                mapOf(
                    "id" to it.lockdown.id,
                    "label" to it.lockdown.label,
                    "strict" to it.lockdown.strict,
                    "scope" to it.lockdown.scope.name,
                    "endWallClockMs" to it.endWallClock,
                    "remainingMs" to remainingMs(context, it),
                    "claimedCount" to SuspensionClaims.claimedPackages(
                        context,
                        SuspensionClaims.REASON_LOCKDOWN,
                    ).size,
                )
            },
            "canScheduleExactAlarms" to LockdownManager.canScheduleExactAlarms(context),
        )
    }

    // ------------------------------------------------------------ start / end / sync

    /**
     * Starts [lockdown]. One active lockdown at a time: if one is
     * already running, it is returned unchanged (a window firing
     * during a one-shot is skipped, not stacked).
     */
    fun start(context: Context, lockdown: Lockdown): ActiveLockdown {
        DeviceOwnerManager.requireOwner(context)
        readActive(context)?.let { return it }

        val targets = resolveTargets(context, lockdown)
        // Claim rule (shared with focus): claim only packages not
        // currently suspended — a package held by the impulse lock,
        // visual blocking, or a focus session is never claimed and
        // never released by this lockdown.
        val toClaim = targets.filter { pkg -> !isSuspended(context, pkg) }.toSet()
        val claimed = suspendPackages(context, toClaim)
        val claimedRestrictions = applyRestrictions(context)

        val now = System.currentTimeMillis()
        val (endElapsed, endWall) = when (lockdown.kind) {
            LockdownKind.ONE_SHOT -> {
                val durMs = lockdown.durationMinutes * 60_000L
                SystemClock.elapsedRealtime() + durMs to now + durMs
            }
            LockdownKind.RECURRING -> {
                val endWall = lockdown.windowEndWallMillis(now)
                SystemClock.elapsedRealtime() + (endWall - now) to endWall
            }
        }
        // Persist BEFORE arming the alarm: crash safety — sync() can
        // finish from persisted state.
        val active = ActiveLockdown(
            lockdown = lockdown,
            endElapsedRealtime = endElapsed,
            endWallClock = endWall,
            bootCount = bootCount(context),
        )
        persistActive(context, active)
        SuspensionClaims.claimPackages(context, SuspensionClaims.REASON_LOCKDOWN, claimed)
        SuspensionClaims.claimRestrictions(
            context,
            SuspensionClaims.REASON_LOCKDOWN,
            claimedRestrictions,
        )
        LockdownManager.armEndAlarm(context, endElapsed)
        if (lockdown.strict) {
            setLockTaskPackages(context)
            LockdownManager.launchActivity(context)
        }
        LockdownNotifier.showActive(context, active)
        try {
            dpm(context).lockNow()
        } catch (e: Exception) {
            Log.w(TAG, "Lockdown: lockNow failed", e)
        }
        return active
    }

    /** Idempotent: ending twice, or ending with no active lockdown, is a no-op. */
    fun end(context: Context) {
        val active = readActive(context)
        if (active == null) {
            releaseOrphanedClaims(context)
            return
        }
        val claimed = SuspensionClaims.claimedPackages(context, SuspensionClaims.REASON_LOCKDOWN)
        val releasable = SuspensionClaims.releasableBy(
            context,
            SuspensionClaims.REASON_LOCKDOWN,
            claimed,
        )
        SuspensionClaims.clearPackages(context, SuspensionClaims.REASON_LOCKDOWN)
        releasePackages(context, releasable)
        val claimedRestrictions = SuspensionClaims.claimedRestrictions(
            context,
            SuspensionClaims.REASON_LOCKDOWN,
        )
        val releasableRestrictions = SuspensionClaims.releasableRestrictions(
            context,
            SuspensionClaims.REASON_LOCKDOWN,
            claimedRestrictions,
        )
        SuspensionClaims.clearRestrictions(context, SuspensionClaims.REASON_LOCKDOWN)
        releaseRestrictions(context, releasableRestrictions)
        LockdownManager.cancelEndAlarm(context)
        LockdownNotifier.cancel(context)
        clearActive(context)
        // Leave lock-task mode: the activity exits itself on its tick
        // (it watches the active state); clearing the allowlist here
        // is the belt to its braces.
        runCatching {
            dpm(context).setLockTaskPackages(admin(context), emptyArray())
        }.onFailure { Log.w(TAG, "Lockdown: could not clear lock-task packages", it) }
    }

    /**
     * The idempotent entry point: end alarm, window start, boot/time
     * receiver, app cold start. Advances an expired lockdown, re-arms
     * the end alarm and re-asserts the claims of a live one, and
     * releases orphaned claims when nothing is active.
     */
    fun sync(context: Context) {
        if (SettingsStore.isRemovalInProgress()) return
        val active = readActive(context)
        if (active == null) {
            releaseOrphanedClaims(context)
            LockdownManager.rescheduleWindows(context)
            return
        }
        val remaining = remainingMs(context, active)
        if (remaining <= 0) {
            end(context)
            LockdownManager.rescheduleWindows(context)
            return
        }
        // After a reboot the wall clock is the truth: re-anchor the
        // elapsed-realtime deadline onto the new boot — and arm the
        // end alarm with the ANCHORED value (the stale endElapsed
        // from the old boot is meaningless now).
        val effectiveEndElapsed = if (active.bootCount != bootCount(context)) {
            val anchored = SystemClock.elapsedRealtime() + remaining
            persistActive(
                context,
                active.copy(
                    endElapsedRealtime = anchored,
                    bootCount = bootCount(context),
                ),
            )
            anchored
        } else {
            active.endElapsedRealtime
        }
        // Re-assert: suspension persists across reboot, but re-apply
        // the claimed set (idempotent) and re-arm the end alarm.
        reapplySuspension(context, active)
        LockdownManager.armEndAlarm(context, effectiveEndElapsed)
        if (active.lockdown.strict) LockdownManager.launchActivityIfNeeded(context)
        LockdownNotifier.showActive(context, active)
    }

    // ------------------------------------------------------------ targets

    /**
     * The lockdown's targets, minus everything that must stay
     * reachable: Azm itself, the default launcher, the default
     * dialer, and [SettingsStore.isProtectedActivity] (system UI,
     * Settings, telecom). Non-suspendable packages (device admins,
     * installer/verifier, permission controller) are NOT filtered
     * here — the DPM call reports them as failed and they are left
     * out of the claim set, never faked as suspended.
     */
    fun resolveTargets(context: Context, lockdown: Lockdown): Set<String> {
        val installed = installedPackages(context)
        val resolved = when (lockdown.scope) {
            LockdownScope.ALL_APPS ->
                DeviceOwnerManager.listInstalledApps(context, false)
                    .map { it.packageName }.toSet()
            LockdownScope.APPS -> lockdown.targetApps
            LockdownScope.GROUPS -> SettingsStore.groups()
                .filter { it.id in lockdown.targetGroups }
                .flatMap { it.packageNames }.toSet()
        }
        val dialer = try {
            context.getSystemService(TelecomManager::class.java)?.defaultDialerPackage
        } catch (_: Exception) {
            null
        }
        return resolved
            .intersect(installed)
            .filter { pkg ->
                pkg != context.packageName &&
                    pkg != dialer &&
                    !SettingsStore.isProtectedActivity(pkg, "")
            }.toSet()
    }

    private fun installedPackages(context: Context): Set<String> = try {
        context.packageManager.getInstalledApplications(0)
            .map { it.packageName }.toSet()
    } catch (_: Exception) {
        emptySet()
    }

    // ------------------------------------------------------------ effects (DPM)

    private fun dpm(context: Context): DevicePolicyManager =
        context.getSystemService(DevicePolicyManager::class.java)

    private fun admin(context: Context): ComponentName =
        ComponentName(context, AzmDeviceAdminReceiver::class.java)

    private fun bootCount(context: Context): Int =
        Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1)

    private fun isSuspended(context: Context, pkg: String): Boolean =
        try {
            dpm(context).isPackageSuspended(admin(context), pkg)
        } catch (_: Exception) {
            false
        }

    /**
     * Suspends [packages] and returns the subset that actually
     * reached the suspended state. [DeviceOwnerManager.setPackagesSuspended]
     * throws on a partial failure (after suspending the rest), so the
     * catch re-reads the states and retries the coupling for the
     * succeeded subset — a second call with only those cannot throw
     * for the same reason.
     */
    private fun suspendPackages(context: Context, packages: Set<String>): Set<String> {
        if (packages.isEmpty()) return emptySet()
        return try {
            DeviceOwnerManager.setPackagesSuspended(
                context,
                packages.toList(),
                true,
                SuspensionReason.LOCKDOWN,
            )
            packages
        } catch (e: Exception) {
            Log.w(TAG, "Lockdown: partial suspension failure, re-reading states", e)
            val actually = packages.filter { isSuspended(context, it) }.toSet()
            if (actually.isNotEmpty()) {
                runCatching {
                    DeviceOwnerManager.setPackagesSuspended(
                        context,
                        actually.toList(),
                        true,
                        SuspensionReason.LOCKDOWN,
                    )
                }.onFailure { Log.w(TAG, "Lockdown: coupling retry failed", it) }
            }
            if (actually.size != packages.size) {
                Log.w(TAG, "Lockdown: could not suspend ${(packages - actually).joinToString()}")
            }
            actually
        }
    }

    private fun reapplySuspension(context: Context, active: ActiveLockdown) {
        val claimed = SuspensionClaims.claimedPackages(context, SuspensionClaims.REASON_LOCKDOWN)
        if (claimed.isEmpty()) return
        suspendPackages(context, claimed)
    }

    private fun releasePackages(context: Context, packages: Set<String>) {
        if (packages.isEmpty()) return
        runCatching {
            DeviceOwnerManager.setPackagesSuspended(context, packages.toList(), false, null)
        }.onFailure { Log.w(TAG, "Lockdown: could not release ${packages.joinToString()}", it) }
    }

    private fun applyRestrictions(context: Context): Set<String> {
        val dpm = dpm(context)
        val admin = admin(context)
        if (!dpm.isAdminActive(admin)) return emptySet()
        val current = try {
            dpm.getUserRestrictions(admin)
        } catch (_: Exception) {
            return emptySet()
        }
        val newly = mutableSetOf<String>()
        LOCKDOWN_RESTRICTIONS.forEach { key ->
            if (current.containsKey(key)) return@forEach // already set — not ours to claim
            try {
                dpm.addUserRestriction(admin, key)
                newly.add(key)
            } catch (e: Exception) {
                Log.w(TAG, "Lockdown: could not add restriction $key", e)
            }
        }
        return newly
    }

    private fun releaseRestrictions(context: Context, keys: Set<String>) {
        if (keys.isEmpty()) return
        val dpm = dpm(context)
        val admin = admin(context)
        if (!dpm.isAdminActive(admin)) return
        keys.forEach { key ->
            runCatching { dpm.clearUserRestriction(admin, key) }
                .onFailure { Log.w(TAG, "Lockdown: could not clear restriction $key", it) }
        }
    }

    private fun releaseOrphanedClaims(context: Context) {
        val orphaned = SuspensionClaims.claimedPackages(context, SuspensionClaims.REASON_LOCKDOWN)
        if (orphaned.isNotEmpty()) {
            val releasable = SuspensionClaims.releasableBy(
                context,
                SuspensionClaims.REASON_LOCKDOWN,
                orphaned,
            )
            SuspensionClaims.clearPackages(context, SuspensionClaims.REASON_LOCKDOWN)
            releasePackages(context, releasable)
        }
        val orphanedRestrictions = SuspensionClaims.claimedRestrictions(
            context,
            SuspensionClaims.REASON_LOCKDOWN,
        )
        if (orphanedRestrictions.isNotEmpty()) {
            val releasable = SuspensionClaims.releasableRestrictions(
                context,
                SuspensionClaims.REASON_LOCKDOWN,
                orphanedRestrictions,
            )
            SuspensionClaims.clearRestrictions(context, SuspensionClaims.REASON_LOCKDOWN)
            releaseRestrictions(context, releasable)
        }
    }

    private fun setLockTaskPackages(context: Context) {
        try {
            dpm(context).setLockTaskPackages(admin(context), arrayOf(context.packageName))
        } catch (e: Exception) {
            Log.w(TAG, "Lockdown: could not set lock-task packages", e)
        }
    }
}
