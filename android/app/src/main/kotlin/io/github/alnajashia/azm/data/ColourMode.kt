package io.github.alnajashia.azm.data

import android.annotation.SuppressLint
import android.content.res.Resources
import android.os.Build

/**
 * Colour-filter modes (Batch C / GRAYSCALE_RESEARCH.md §6.2), ported in
 * structure from DeChainer's `ColorFilterMode` (Apache-2.0,
 * warleysr/dechainer) with Azm naming. The four modes share one
 * controller, one enforcement loop and one screen; grayscale is the
 * default and first mode.
 *
 * Availability is a device fact, not a preference: grayscale, night
 * light and inversion exist on every Android device (the daltonizer /
 * inversion secure keys are AOSP since Android 5); extra dim exists
 * only from Android 12 (API 31) on devices whose system resources
 * declare `config_reduceBrightColorsAvailable`.
 */
enum class ColourMode {
    GRAYSCALE,
    NIGHT_LIGHT,
    EXTRA_DIM,
    INVERSION;

    val isAvailable: Boolean
        get() = when (this) {
            EXTRA_DIM -> extraDimAvailable
            GRAYSCALE, NIGHT_LIGHT, INVERSION -> true
        }

    companion object {
        val available: List<ColourMode> get() = entries.filter { it.isAvailable }

        fun fromName(name: String?): ColourMode? =
            entries.firstOrNull { it.name == name }

        private val extraDimAvailable by lazy {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                systemBoolean("config_reduceBrightColorsAvailable")
        }

        @SuppressLint("DiscouragedApi")
        private fun systemBoolean(name: String): Boolean {
            val resources = Resources.getSystem()
            val id = resources.getIdentifier(name, "bool", "android")
            return id != 0 && resources.getBoolean(id)
        }
    }
}
