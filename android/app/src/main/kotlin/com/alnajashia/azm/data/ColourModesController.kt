package com.alnajashia.azm.data

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Resources
import android.net.Uri
import android.provider.Settings
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * Colour-modes enforcement (Batch C / GRAYSCALE_RESEARCH.md §6.2),
 * ported in structure from DeChainer's `ColorFilterController`
 * (Apache-2.0, warleysr/dechainer) with Azm naming and one addition:
 * a read-after-write verification set ([lastVerifyFailed]) so the
 * status can report whether the device actually applied the keys.
 *
 * The seven secure keys:
 *  - `accessibility_display_daltonizer_enabled` + `accessibility_display_daltonizer` ("0" = monochrome)
 *  - `accessibility_display_inversion_enabled`
 *  - `night_display_activated` + `night_display_color_temperature`
 *  - `reduce_bright_colors_activated` + `reduce_bright_colors_level`
 *
 * Writing them needs `WRITE_SECURE_SETTINGS`, which a Device Owner
 * cannot grant — Azm's Shizuku provisioning path is the only route
 * (see `ShizukuProvisioning.grantWriteSecureSettings`).
 *
 * Save/restore discipline: the first time a key is touched, its
 * current value is saved once under `previous_<key>` in
 * `colour_modes_state` and the key is added to `saved_keys`. Releasing
 * restores every saved key (a null saved value clears the key) and
 * clears the set. A key the filter never touched is never restored —
 * a real colour-correction user is never clobbered.
 */
object ColourModesController {
    private const val TAG = "ColourModesController"

    const val DALTONIZER_ENABLED = "accessibility_display_daltonizer_enabled"
    const val DALTONIZER = "accessibility_display_daltonizer"
    const val INVERSION_ENABLED = "accessibility_display_inversion_enabled"
    const val NIGHT_DISPLAY_ACTIVATED = "night_display_activated"
    const val NIGHT_DISPLAY_TEMPERATURE = "night_display_color_temperature"
    const val REDUCE_BRIGHT_COLORS_ACTIVATED = "reduce_bright_colors_activated"
    const val REDUCE_BRIGHT_COLORS_LEVEL = "reduce_bright_colors_level"

    const val MODE_MONOCHROMACY = "0"
    const val FALLBACK_NIGHT_LIGHT_MIN_TEMPERATURE = 2596
    const val FALLBACK_NIGHT_LIGHT_MAX_TEMPERATURE = 4082

    val allKeys: List<String> = listOf(
        DALTONIZER_ENABLED,
        DALTONIZER,
        INVERSION_ENABLED,
        NIGHT_DISPLAY_ACTIVATED,
        NIGHT_DISPLAY_TEMPERATURE,
        REDUCE_BRIGHT_COLORS_ACTIVATED,
        REDUCE_BRIGHT_COLORS_LEVEL,
    )

    val observedUris: List<Uri> = allKeys.map { Settings.Secure.getUriFor(it) }

    private const val KEY_SAVED_KEYS = "saved_keys"
    private fun previousKey(key: String) = "previous_$key"

    /**
     * The pre-filter values of the keys currently enforced (a null
     * value means the key was unset before the filter touched it).
     * The teardown step uses this to verify the release restored the
     * device exactly.
     */
    fun savedPreviousValues(context: Context): Map<String, String?> {
        val state = SettingsStore.prefs(SettingsStore.PREFS_COLOUR_MODES_STATE)
        val saved = savedKeys(context)
        return allKeys.filter { it in saved }
            .associateWith { state.getString(previousKey(it), null) }
    }

    /** Keys the last enforce could not read back as written. Volatile: for status reporting only. */
    @Volatile
    var lastVerifyFailed: Set<String> = emptySet()
        private set

    /**
     * Whether the device ships a platform night light. Some vendors
     * (notably Samsung) disable the AOSP night light; forcing its keys
     * there can black the screen, so on those devices the in-app
     * overlay ([accessibility.NightLightOverlay]) is used instead.
     */
    val platformNightLight: Boolean by lazy {
        systemBoolean("config_nightDisplayAvailable")
    }

    fun hasPermission(context: Context): Boolean =
        ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.WRITE_SECURE_SETTINGS,
        ) == PackageManager.PERMISSION_GRANTED

    fun isApplied(context: Context): Boolean = savedKeys(context).isNotEmpty()

    /** Modes currently enforced, derived from the saved-keys set. */
    fun appliedModes(context: Context): Set<ColourMode> {
        val saved = savedKeys(context)
        val modes = mutableSetOf<ColourMode>()
        if (DALTONIZER_ENABLED in saved || DALTONIZER in saved) modes += ColourMode.GRAYSCALE
        if (NIGHT_DISPLAY_ACTIVATED in saved || NIGHT_DISPLAY_TEMPERATURE in saved) modes += ColourMode.NIGHT_LIGHT
        if (REDUCE_BRIGHT_COLORS_ACTIVATED in saved || REDUCE_BRIGHT_COLORS_LEVEL in saved) modes += ColourMode.EXTRA_DIM
        if (INVERSION_ENABLED in saved) modes += ColourMode.INVERSION
        return modes
    }

    /** The secure-key values [modes] require, from [settings]. */
    fun targetsFor(settings: ColourModesSettings.Config, modes: Set<ColourMode>): Map<String, String> {
        val targets = mutableMapOf<String, String>()
        if (ColourMode.GRAYSCALE in modes) {
            targets[DALTONIZER] = MODE_MONOCHROMACY
            targets[DALTONIZER_ENABLED] = "1"
        }
        if (ColourMode.NIGHT_LIGHT in modes) {
            if (platformNightLight) {
                val temperature = settings.nightLightTemperature.coerceIn(
                    nightLightMinTemperature,
                    nightLightMaxTemperature,
                )
                targets[NIGHT_DISPLAY_TEMPERATURE] = temperature.toString()
                targets[NIGHT_DISPLAY_ACTIVATED] = "1"
            }
            // No platform night light: the overlay handles the tint;
            // no secure key is written.
        }
        if (ColourMode.EXTRA_DIM in modes) {
            targets[REDUCE_BRIGHT_COLORS_LEVEL] = settings.extraDimLevel.toString()
            targets[REDUCE_BRIGHT_COLORS_ACTIVATED] = "1"
        }
        if (ColourMode.INVERSION in modes) {
            targets[INVERSION_ENABLED] = "1"
        }
        return targets
    }

    /**
     * Enforces [targets]: restores any saved key the targets no longer
     * need, saves the current value of each newly touched key once,
     * writes, and reads back to verify. A failed write is logged and
     * recorded in [lastVerifyFailed], never thrown — enforcement must
     * never crash the accessibility service.
     */
    fun enforce(context: Context, targets: Map<String, String>) {
        try {
            val resolver = context.contentResolver
            val state = SettingsStore.prefs(SettingsStore.PREFS_COLOUR_MODES_STATE)
            val saved = savedKeys(context).toMutableSet()
            // Restore keys the targets no longer need, and persist the
            // reduced set — a restored key must not stay "saved", or a
            // later release would try to restore it again and a later
            // enforce would skip saving its (now changed) current value.
            var restoredAny = false
            for (key in allKeys) {
                if (key !in targets && key in saved) {
                    restoreKey(context, state, key)
                    saved.remove(key)
                    restoredAny = true
                }
            }
            if (restoredAny) {
                state.edit().putStringSet(KEY_SAVED_KEYS, saved).apply()
            }
            // Save-once, then write each target key.
            val failed = mutableSetOf<String>()
            for ((key, value) in targets) {
                if (key !in saved) {
                    val current = Settings.Secure.getString(resolver, key)
                    val edit = state.edit()
                    if (current == null) edit.remove(previousKey(key))
                    else edit.putString(previousKey(key), current)
                    edit.putStringSet(KEY_SAVED_KEYS, saved + key)
                    edit.commit()
                    saved += key
                }
                if (Settings.Secure.getString(resolver, key) != value) {
                    Settings.Secure.putString(resolver, key, value)
                }
                if (Settings.Secure.getString(resolver, key) != value) {
                    Log.e(TAG, "Failed to apply $key=$value")
                    failed += key
                }
            }
            lastVerifyFailed = failed
        } catch (e: Exception) {
            Log.e(TAG, "enforce failed", e)
        }
    }

    /**
     * Restores every saved key to its pre-filter value, in reversed
     * key order, and clears the saved set. A no-op when nothing was
     * saved. Returns the keys that were restored.
     */
    fun release(context: Context): Set<String> {
        val state = SettingsStore.prefs(SettingsStore.PREFS_COLOUR_MODES_STATE)
        val saved = savedKeys(context)
        if (saved.isEmpty()) return emptySet()
        for (key in allKeys.reversed()) {
            if (key in saved) restoreKey(context, state, key)
        }
        state.edit().remove(KEY_SAVED_KEYS).apply()
        lastVerifyFailed = emptySet()
        return saved
    }

    private fun savedKeys(context: Context): Set<String> =
        SettingsStore.prefs(SettingsStore.PREFS_COLOUR_MODES_STATE)
            .getStringSet(KEY_SAVED_KEYS, emptySet()) ?: emptySet()

    private fun restoreKey(context: Context, state: android.content.SharedPreferences, key: String) {
        try {
            val previous = state.getString(previousKey(key), null)
            Settings.Secure.putString(context.contentResolver, key, previous)
            val edit = state.edit()
            edit.remove(previousKey(key))
            edit.apply()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to restore $key", e)
        }
    }

    private val nightLightMinTemperature by lazy {
        systemInteger("config_nightDisplayColorTemperatureMin", FALLBACK_NIGHT_LIGHT_MIN_TEMPERATURE)
    }

    private val nightLightMaxTemperature by lazy {
        systemInteger("config_nightDisplayColorTemperatureMax", FALLBACK_NIGHT_LIGHT_MAX_TEMPERATURE)
    }

    @SuppressLint("DiscouragedApi")
    private fun systemBoolean(name: String): Boolean {
        val resources = Resources.getSystem()
        val id = resources.getIdentifier(name, "bool", "android")
        return id != 0 && resources.getBoolean(id)
    }

    @SuppressLint("DiscouragedApi")
    private fun systemInteger(name: String, fallback: Int): Int {
        val resources = Resources.getSystem()
        val id = resources.getIdentifier(name, "integer", "android")
        return if (id != 0) resources.getInteger(id) else fallback
    }
}
