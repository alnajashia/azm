package com.alnajashia.azm.focus

import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import com.alnajashia.azm.R
import com.alnajashia.azm.notifications.FocusReminderNotifier
import com.alnajashia.azm.notifications.FocusScheduleReceiver

/**
 * Full-screen focus reminder (Batch I-A, item 13): a port of
 * Dechainer's `activities/FocusReminderActivity.kt` (Apache-2.0),
 * rebuilt with programmatic Views like [BlockActivity] (Azm has no
 * Compose): show-when-locked + turn-screen-on + keep-screen-on, with
 * Start / Snooze-5-min / Dismiss. After the second snooze the snooze
 * button becomes "I can't start now" (dismiss), exactly as in the
 * original.
 *
 * Flutter UI cannot be reliably presented from a background alarm
 * (the engine may not even be running), so this is a native Activity.
 */
class FocusReminderActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        FocusReminderNotifier.cancel(this)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        val snoozeCount = intent.getIntExtra(EXTRA_SNOOZE_COUNT, 0)
        val scheduleId = intent.getStringExtra(FocusScheduleManager.EXTRA_SCHEDULE_ID)
        val label = intent.getStringExtra(FocusScheduleManager.EXTRA_SCHEDULE_LABEL) ?: ""

        val padding = (32 * resources.displayMetrics.density).toInt()
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(padding, padding, padding, padding)
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }
        layout.addView(TextView(this).apply {
            text = if (label.isBlank()) {
                getString(R.string.focus_reminder_title)
            } else {
                getString(R.string.focus_reminder_title_label, label)
            }
            textSize = 28f
            gravity = Gravity.CENTER
        })
        layout.addView(TextView(this).apply {
            text = getString(R.string.focus_reminder_desc)
            textSize = 16f
            gravity = Gravity.CENTER
            setPadding(0, padding / 2, 0, padding)
        })
        layout.addView(Button(this).apply {
            text = getString(R.string.focus_reminder_start)
            setOnClickListener {
                FocusScheduleManager.cancelSnooze(this@FocusReminderActivity)
                FocusSessionStore.startFocus(this@FocusReminderActivity)
                finish()
            }
        })
        if (snoozeCount < FocusScheduleManager.MAX_SNOOZES) {
            layout.addView(Button(this).apply {
                text = getString(R.string.focus_reminder_snooze)
                setOnClickListener {
                    FocusScheduleManager.scheduleSnooze(
                        this@FocusReminderActivity,
                        snoozeCount + 1,
                        scheduleId,
                        label,
                    )
                    finish()
                }
            })
            layout.addView(Button(this).apply {
                text = getString(R.string.focus_reminder_dismiss)
                setOnClickListener {
                    FocusScheduleManager.cancelSnooze(this@FocusReminderActivity)
                    finish()
                }
            })
        } else {
            layout.addView(Button(this).apply {
                text = getString(R.string.focus_reminder_cannot_start)
                setOnClickListener {
                    FocusScheduleManager.cancelSnooze(this@FocusReminderActivity)
                    finish()
                }
            })
        }
        setContentView(layout)
    }

    companion object {
        const val EXTRA_SNOOZE_COUNT = FocusScheduleReceiver.EXTRA_SNOOZE_COUNT
    }
}
