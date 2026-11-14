package com.alnajashia.azm.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.alnajashia.azm.data.SettingsStore
import com.alnajashia.azm.lockdown.LockdownManager
import com.alnajashia.azm.lockdown.LockdownStore

/**
 * The lockdown's alarm receiver (Batch I-B, item 14): a recurring
 * window's start, and the active lockdown's end.
 *
 * The end alarm only calls [LockdownStore.sync] — sync decides
 * whether the lockdown really expired (and ends it) or was
 * re-anchored after a reboot (and re-arms). A window start is
 * skipped when a lockdown is already running: one active lockdown
 * at a time, no stacking.
 *
 * Never re-applies policy while a removal teardown is in progress
 * — the teardown is dismantling exactly this state.
 */
class LockdownReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (SettingsStore.isRemovalInProgress()) return
        when (intent.action) {
            LockdownManager.ACTION_WINDOW_START -> {
                val id = intent.getStringExtra(LockdownManager.EXTRA_LOCKDOWN_ID)
                val lockdown = LockdownStore.getLockdowns(context)
                    .firstOrNull { it.id == id && it.enabled }
                if (lockdown == null) {
                    LockdownManager.rescheduleWindows(context)
                    return
                }
                if (LockdownStore.activeLockdown(context) != null) {
                    // A lockdown is already running — skip this window.
                    LockdownManager.rescheduleWindows(context)
                    return
                }
                try {
                    LockdownStore.start(context, lockdown)
                } catch (e: Exception) {
                    Log.w(TAG, "Lockdown: window start failed", e)
                }
                LockdownManager.rescheduleWindows(context)
            }
            LockdownManager.ACTION_END -> {
                LockdownStore.sync(context)
            }
        }
    }

    companion object {
        private const val TAG = "LockdownReceiver"
    }
}
