package com.alnajashia.azm.focus

import android.content.Context
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The user's own focus sounds (2026-11-22), bundled as assets:
 * [SOUND_BREAK] plays when a break starts (short or long), and one of
 * the two pre-focus sounds plays to completion BEFORE every focus
 * phase — the phase begins only after the sound ends.
 *
 * Playback always happens on the main looper so completion callbacks
 * are guaranteed. Every failure path still invokes the completion
 * callback: a broken sound must never block a phase.
 */
object FocusSounds {
    private const val TAG = "FocusSounds"

    const val SOUND_BREAK = "sounds/focus/start_relax.mp3"
    const val SOUND_LONG_BREAK = "sounds/focus/long_relax.mp3"
    const val SOUND_PRE_FOCUS_1 = "sounds/focus/before_focus_start.mp3"
    const val SOUND_PRE_FOCUS_2 = "sounds/focus/before_focus_start2.mp3"

    /** Hard cap: a stuck player must never delay a phase beyond this. */
    private const val WATCHDOG_MS = 12_000L

    /** Plays the break sound (short or long); [onDone] runs when it
     *  ends — the break timer starts only after that. */
    fun playBreakStart(context: Context, long: Boolean, onDone: () -> Unit) {
        play(context, if (long) SOUND_LONG_BREAK else SOUND_BREAK, onDone)
    }

    /** Plays the chosen pre-focus sound; [onDone] runs when it ends
     *  (or fails, or the watchdog fires). */
    fun playPreFocus(context: Context, choice: Int, onDone: () -> Unit) {
        play(
            context,
            if (choice == 1) SOUND_PRE_FOCUS_2 else SOUND_PRE_FOCUS_1,
            onDone,
        )
    }

    /** Settings preview: hear the choice without starting anything. */
    fun preview(context: Context, choice: Int) {
        playPreFocus(context, choice) {}
    }

    private fun play(context: Context, asset: String, onDone: (() -> Unit)?) {
        val appContext = context.applicationContext
        val finished = AtomicBoolean(false)
        fun finish() {
            if (finished.compareAndSet(false, true)) onDone?.invoke()
        }
        Handler(Looper.getMainLooper()).post {
            try {
                val player = MediaPlayer()
                val afd = appContext.assets.openFd(asset)
                player.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                afd.close()
                player.setOnCompletionListener {
                    it.release()
                    finish()
                }
                player.setOnErrorListener { p, _, _ ->
                    p.release()
                    finish()
                    true
                }
                player.prepare()
                player.start()
                Handler(Looper.getMainLooper()).postDelayed({ finish() }, WATCHDOG_MS)
            } catch (e: Exception) {
                Log.w(TAG, "Focus sound failed: $asset", e)
                finish()
            }
        }
    }
}
