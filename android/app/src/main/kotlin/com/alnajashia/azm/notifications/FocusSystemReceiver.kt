package com.alnajashia.azm.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import com.alnajashia.azm.data.SettingsStore
import com.alnajashia.azm.focus.FocusSessionStore

/**
 * The focus broadcast receivers — a port of the original
 * `notifications/FocusReceiver.kt` from DeChainer (Apache-2.0,
 * warleysr/dechainer), which declares both classes in one file, as here.
 * Action strings carry our applicationId, like the rest of our contract.
 */

/** Phase-end alarm target and the status notification's action buttons. */
class FocusReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // Removal teardown disarm (v1.0.5 audit A-H2): while a Device
        // Owner removal is in progress, NO focus sync may run — the
        // teardown stops the session itself, and a mid-teardown sync
        // could re-apply focus claims the teardown is busy releasing.
        // (The Application and accessibility paths already checked the
        // flag; these receivers did not.)
        if (SettingsStore.isRemovalInProgress()) return
        when (intent.action) {
            ACTION_PHASE_END -> {
                // Keeps the process alive long enough for the alert sound to finish playing.
                val pending = goAsync()
                FocusSessionStore.sync(context)
                Handler(Looper.getMainLooper()).postDelayed(
                    { pending.finish() },
                    FocusSessionStore.SOUND_KEEP_ALIVE_MS,
                )
            }
            ACTION_START_FOCUS -> if (
                FocusSessionStore.getStatus(context)?.phase == FocusSessionStore.Phase.WAITING
            ) {
                FocusSessionStore.startFocus(context)
            }
            ACTION_SKIP_BREAK -> FocusSessionStore.skipBreak(context)
            ACTION_RESUME -> FocusSessionStore.resume(context)
            // Anywhere but WAITING, ending needs the recovery code.
            ACTION_STOP -> if (
                FocusSessionStore.getStatus(context)?.phase == FocusSessionStore.Phase.WAITING
            ) {
                FocusSessionStore.stop(context)
            }
            ACTION_REPOST -> FocusSessionStore.sync(context)
        }
    }

    companion object {
        const val ACTION_PHASE_END = "com.alnajashia.azm.focus.PHASE_END"
        const val ACTION_START_FOCUS = "com.alnajashia.azm.focus.START_FOCUS"
        const val ACTION_SKIP_BREAK = "com.alnajashia.azm.focus.SKIP_BREAK"
        const val ACTION_STOP = "com.alnajashia.azm.focus.STOP"
        const val ACTION_RESUME = "com.alnajashia.azm.focus.RESUME"
        const val ACTION_REPOST = "com.alnajashia.azm.focus.REPOST"
    }
}

/**
 * Re-arms the focus session after a reboot, an app update or a clock
 * change — the original's `FocusSystemReceiver`.
 *
 * The resync is exactly [FocusSessionStore.sync], whose semantics cover
 * every case:
 *  - **same boot, phase still running** — the elapsed-realtime deadline is
 *    untouched (clock changes cannot shorten a phase); sync merely
 *    re-arms the exact alarm, the notification and the service;
 *  - **after a reboot** — the boot count no longer matches, so the
 *    remaining time is recomputed from the wall-clock deadline and
 *    re-anchored onto the new boot's elapsed realtime;
 *  - **phase already expired while the process was dead** — sync advances
 *    it (with the phase-end alert) and applies the new phase's state;
 *  - **no phase but orphaned claims** (session data lost) — sync releases
 *    the recorded suspension/restriction claims.
 *
 * The original also reschedules `FocusScheduleManager` here; ours has no
 * native schedule engine (focus schedules are not ported), so there is
 * nothing to reschedule.
 */
class FocusSystemReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // Same removal-teardown disarm as FocusReceiver above (audit A-H2).
        if (SettingsStore.isRemovalInProgress()) return
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            "android.intent.action.TIME_SET" -> {
                FocusSessionStore.sync(context)
            }
        }
    }
}
