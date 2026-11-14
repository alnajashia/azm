package com.alnajashia.azm.accessibility

import android.accessibilityservice.AccessibilityService
import android.graphics.Color
import android.graphics.PixelFormat
import android.view.View
import android.view.WindowManager
import android.view.WindowManager.LayoutParams

/**
 * Azm's own extra-dim overlay (Batch G, item 4).
 *
 * Same technique as [NightLightOverlay] (Batch C): a plain full-screen,
 * non-touchable, non-focusable black view on
 * `TYPE_ACCESSIBILITY_OVERLAY` — it never intercepts input and never
 * appears in the window list the service tracks.
 *
 * It is the fallback for devices whose framework ignores the platform
 * `reduce_bright_colors_*` keys even though the device declares them
 * available (the user's Android 12 Transsion phone: the keys verify
 * as written, or the write is rejected, yet the screen never dims).
 * The service shows it when EXTRA_DIM applies and either the user
 * chose it (`extraDimUseOverlay`) or the platform keys failed
 * verification ([data.ColourModesController.lastVerifyFailed]).
 *
 * Strength is approximate: the platform path dims the backlight below
 * its minimum, while an overlay darkens pixels. Level 0–100 maps to a
 * black alpha of 0–128 (half black at full level), which roughly
 * halves the light output at level 100 — verify the feel on device.
 */
class ExtraDimOverlay(private val service: AccessibilityService) {
    private val windowManager = service.getSystemService(WindowManager::class.java)
    private var view: View? = null

    fun show(level: Int) {
        val color = dim(level)
        view?.let {
            it.setBackgroundColor(color)
            return
        }

        val overlay = View(service).apply { setBackgroundColor(color) }
        val params = LayoutParams(
            LayoutParams.MATCH_PARENT,
            LayoutParams.MATCH_PARENT,
            LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            LayoutParams.FLAG_NOT_TOUCHABLE or LayoutParams.FLAG_NOT_FOCUSABLE or
                LayoutParams.FLAG_LAYOUT_IN_SCREEN or LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            layoutInDisplayCutoutMode = LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            fitInsetsTypes = 0
        }
        windowManager.addView(overlay, params)
        view = overlay
    }

    fun hide() {
        view?.let { windowManager.removeView(it) }
        view = null
    }

    private fun dim(level: Int): Int {
        val alpha = (level.coerceIn(0, 100) * MAX_ALPHA / 100f).toInt()
        return Color.argb(alpha, 0, 0, 0)
    }

    private companion object {
        const val MAX_ALPHA = 128
    }
}
