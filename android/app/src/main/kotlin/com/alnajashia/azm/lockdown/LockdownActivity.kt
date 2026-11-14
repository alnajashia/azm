package com.alnajashia.azm.lockdown

import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import com.alnajashia.azm.R
import com.alnajashia.azm.security.RecoveryStore

/**
 * The Tier 2 (strict) lockdown screen (Batch I-B, item 14): the
 * only thing visible while a strict lockdown runs. Built with
 * programmatic Views like [com.alnajashia.azm.focus.FocusReminderActivity]
 * (Azm has no Compose): show-when-locked + turn-screen-on +
 * keep-screen-on, a live countdown, and an early-exit that asks for
 * the 16-character paper recovery code — verified natively via
 * [RecoveryStore.verifyCode], the same PBKDF2 check the Dart gate
 * uses. Back is disabled (kiosk); the emergency dialer stays
 * reachable from the lock screen by the system.
 *
 * The activity watches the active state on a 1-second tick: when
 * the lockdown ends elsewhere (end alarm, the Dart UI) it leaves
 * lock task and finishes. Conversely, [LockdownStore.sync]
 * re-launches it when it is not running — the same watchdog in
 * both directions.
 */
class LockdownActivity : Activity() {

    companion object {
        @Volatile
        var isRunning: Boolean = false
            private set

        private const val TAG = "LockdownActivity"
    }

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var countdownView: TextView
    private lateinit var codeEntry: EditText
    private lateinit var confirmButton: Button
    private lateinit var errorView: TextView

    private val tick = object : Runnable {
        override fun run() {
            val active = LockdownStore.activeLockdown(this@LockdownActivity)
            if (active == null ||
                LockdownStore.remainingMs(this@LockdownActivity, active) <= 0
            ) {
                // Ended elsewhere (alarm, Dart UI) — leave lock task and finish.
                exitLockTask()
                finish()
                return
            }
            countdownView.text = formatRemaining(
                LockdownStore.remainingMs(this@LockdownActivity, active),
            )
            handler.postDelayed(this, 1000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

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

        val titleView = TextView(this).apply {
            text = getString(R.string.lockdown_activity_title)
            textSize = 24f
            gravity = Gravity.CENTER
        }
        countdownView = TextView(this).apply {
            text = "--:--:--"
            textSize = 48f
            gravity = Gravity.CENTER
        }
        val noteView = TextView(this).apply {
            text = getString(R.string.lockdown_activity_note)
            textSize = 15f
            gravity = Gravity.CENTER
        }
        val endButton = Button(this).apply {
            text = getString(R.string.lockdown_end_early)
            setOnClickListener {
                codeEntry.visibility = View.VISIBLE
                confirmButton.visibility = View.VISIBLE
                codeEntry.requestFocus()
            }
        }
        codeEntry = EditText(this).apply {
            hint = getString(R.string.lockdown_code_hint)
            inputType = InputType.TYPE_CLASS_TEXT
            visibility = View.GONE
        }
        confirmButton = Button(this).apply {
            text = getString(R.string.lockdown_confirm_end)
            visibility = View.GONE
            setOnClickListener { tryEndEarly() }
        }
        errorView = TextView(this).apply {
            visibility = View.GONE
            gravity = Gravity.CENTER
        }

        layout.addView(titleView)
        layout.addView(countdownView)
        layout.addView(noteView)
        layout.addView(endButton)
        layout.addView(codeEntry)
        layout.addView(confirmButton)
        layout.addView(errorView)
        setContentView(layout)

        handler.post(tick)
    }

    override fun onStart() {
        super.onStart()
        isRunning = true
    }

    override fun onResume() {
        super.onResume()
        val active = LockdownStore.activeLockdown(this)
        if (active == null) {
            finish()
            return
        }
        try {
            startLockTask()
        } catch (e: Exception) {
            Log.w(TAG, "Lockdown: startLockTask failed", e)
        }
    }

    override fun onStop() {
        super.onStop()
        isRunning = false
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        isRunning = false
        super.onDestroy()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        // Kiosk: no back. The only exit is the end of the lockdown
        // or the recovery code.
    }

    private fun tryEndEarly() {
        val code = codeEntry.text.toString().trim()
        if (code.isEmpty()) {
            errorView.text = getString(R.string.lockdown_code_hint)
            errorView.visibility = View.VISIBLE
            return
        }
        if (!RecoveryStore.verifyCode(this, code)) {
            errorView.text = getString(R.string.lockdown_wrong_code)
            errorView.visibility = View.VISIBLE
            codeEntry.text.clear()
            return
        }
        LockdownStore.end(this)
        exitLockTask()
        finish()
    }

    private fun exitLockTask() {
        try {
            stopLockTask()
        } catch (_: Exception) {
            // Not in lock task — nothing to leave.
        }
    }

    private fun formatRemaining(ms: Long): String {
        val totalSeconds = ms / 1000
        val hours = totalSeconds / 3600
        val minutes = (totalSeconds % 3600) / 60
        val seconds = totalSeconds % 60
        return "%02d:%02d:%02d".format(hours, minutes, seconds)
    }
}
