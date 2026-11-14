package com.alnajashia.azm.data

import android.content.SharedPreferences
import java.time.LocalTime
import java.util.concurrent.TimeUnit

/**
 * Colour-modes settings (Batch C / GRAYSCALE_RESEARCH.md §6.1), ported
 * in structure from DeChainer's `ColorFilterSettings` (Apache-2.0,
 * warleysr/dechainer) with Azm naming and one addition:
 * `apply_during_focus` (§8.3).
 *
 * Storage: one SharedPreferences file, `colour_modes_prefs`, with
 * per-mode windows (`windows_<MODE>`, JSON `[{s,e}]` via
 * [SettingsStore.encodeWindows]/[SettingsStore.decodeWindows]),
 * scope (`scope_<MODE>`) and app lists (`excluded_apps_<MODE>` /
 * `only_apps_<MODE>`). The applied-state file
 * (`colour_modes_state`, `previous_<key>` + `saved_keys`) lives in
 * [ColourModesController].
 *
 * Empty windows mean "always, while enabled" (research §8.2.6): an
 * enabled mode with no windows is a standing commitment, not a dead
 * setting. This is a deliberate deviation from DeChainer's literal
 * `scheduledModes`, which requires a window to contain the current
 * minute — under that reading an enabled mode with no windows could
 * never apply, and its lock could never engage.
 *
 * All lock arithmetic lives here, next to the enforcement loop: Dart
 * only displays the result. A change is a loosening exactly when it
 * leaves a mode off somewhere it used to apply; loosening a locked
 * mode (active window now, or a focus session with
 * `apply_during_focus`) is refused unless a recovery session is
 * active. Tightening is always free.
 */
object ColourModesSettings {
    const val KEY_ENABLED = "enabled"
    const val KEY_MODES = "modes"
    const val KEY_NIGHT_LIGHT_INTENSITY = "night_light_overlay_intensity"
    const val KEY_NIGHT_LIGHT_TEMPERATURE = "night_light_temperature"
    const val KEY_EXTRA_DIM_LEVEL = "extra_dim_level"
    const val KEY_EXTRA_DIM_USE_OVERLAY = "extra_dim_use_overlay"
    const val KEY_APPLY_DURING_FOCUS = "apply_during_focus"

    val DEFAULT_MODES = setOf(ColourMode.GRAYSCALE)
    const val DEFAULT_NIGHT_LIGHT_INTENSITY = 5
    const val MAX_NIGHT_LIGHT_INTENSITY = 60
    const val DEFAULT_NIGHT_LIGHT_TEMPERATURE = 3200
    val NIGHT_LIGHT_TEMPERATURES = listOf(1800, 2000, 2500, 2700, 3200, 4000)
    const val DEFAULT_EXTRA_DIM_LEVEL = 50

    fun windowsKey(mode: ColourMode) = "windows_${mode.name}"
    fun scopeKey(mode: ColourMode) = "scope_${mode.name}"
    fun excludedAppsKey(mode: ColourMode) = "excluded_apps_${mode.name}"
    fun onlyAppsKey(mode: ColourMode) = "only_apps_${mode.name}"

    /** The whole configuration, as the channel reads and writes it. */
    data class Config(
        val enabled: Boolean = false,
        val modes: Set<ColourMode> = DEFAULT_MODES,
        val windows: Map<ColourMode, List<TimeWindow>> = emptyMap(),
        val scopes: Map<ColourMode, ColourScope> = emptyMap(),
        val excludedApps: Map<ColourMode, Set<String>> = emptyMap(),
        val onlyApps: Map<ColourMode, Set<String>> = emptyMap(),
        val nightLightTemperature: Int = DEFAULT_NIGHT_LIGHT_TEMPERATURE,
        val nightLightIntensity: Int = DEFAULT_NIGHT_LIGHT_INTENSITY,
        val extraDimLevel: Int = DEFAULT_EXTRA_DIM_LEVEL,
        // Batch G, item 4: when true, Azm dims with its own overlay
        // instead of the platform reduce_bright_colors keys — for
        // devices whose framework ignores those keys (the user's
        // Android 12 Transsion phone). Default false.
        val extraDimUseOverlay: Boolean = false,
        val applyDuringFocus: Boolean = false,
    ) {
        fun windowsFor(mode: ColourMode): List<TimeWindow> = windows[mode] ?: emptyList()
        fun scopeFor(mode: ColourMode): ColourScope = scopes[mode] ?: ColourScope.DEVICE
        fun coverageFor(mode: ColourMode): ColourScope.Coverage = ColourScope.Coverage(
            scopeFor(mode),
            excludedApps[mode] ?: emptySet(),
            onlyApps[mode] ?: emptySet(),
        )
    }

    private fun prefs(): SharedPreferences =
        SettingsStore.prefs(SettingsStore.PREFS_COLOUR_MODES)

    fun load(): Config = loadFrom(prefs())

    fun loadFrom(p: SharedPreferences): Config {
        // Absent key = never configured: the default (grayscale only).
        // A present-but-empty set is a real choice (all modes off) and
        // must stay empty — it must not silently re-enable grayscale.
        val storedNames = p.getStringSet(KEY_MODES, null)
        val modes = if (storedNames == null) {
            DEFAULT_MODES
        } else {
            storedNames.mapNotNull { ColourMode.fromName(it) }
                .filter { it.isAvailable }
                .toSet()
        }
        val windows = ColourMode.entries.associateWith { mode ->
            SettingsStore.decodeWindows(p.getString(windowsKey(mode), null))
        }
        val scopes = ColourMode.entries.associateWith { mode ->
            ColourScope.fromName(p.getString(scopeKey(mode), null))
        }
        val excluded = ColourMode.entries.associateWith { mode ->
            p.getStringSet(excludedAppsKey(mode), emptySet()) ?: emptySet()
        }
        val only = ColourMode.entries.associateWith { mode ->
            p.getStringSet(onlyAppsKey(mode), emptySet()) ?: emptySet()
        }
        return Config(
            enabled = p.getBoolean(KEY_ENABLED, false),
            modes = modes,
            windows = windows,
            scopes = scopes,
            excludedApps = excluded,
            onlyApps = only,
            nightLightTemperature = p.getInt(KEY_NIGHT_LIGHT_TEMPERATURE, DEFAULT_NIGHT_LIGHT_TEMPERATURE),
            nightLightIntensity = p.getInt(KEY_NIGHT_LIGHT_INTENSITY, DEFAULT_NIGHT_LIGHT_INTENSITY),
            extraDimLevel = p.getInt(KEY_EXTRA_DIM_LEVEL, DEFAULT_EXTRA_DIM_LEVEL),
            extraDimUseOverlay = p.getBoolean(KEY_EXTRA_DIM_USE_OVERLAY, false),
            applyDuringFocus = p.getBoolean(KEY_APPLY_DURING_FOCUS, false),
        )
    }

    fun save(config: Config) {
        val edit = prefs().edit()
        edit.putBoolean(KEY_ENABLED, config.enabled)
        edit.putStringSet(KEY_MODES, config.modes.map { it.name }.toSet())
        for (mode in ColourMode.entries) {
            val w = config.windowsFor(mode)
            if (w.isEmpty()) edit.remove(windowsKey(mode))
            else edit.putString(windowsKey(mode), SettingsStore.encodeWindows(w))
            edit.putString(scopeKey(mode), config.scopeFor(mode).name)
            val ex = config.excludedApps[mode] ?: emptySet()
            if (ex.isEmpty()) edit.remove(excludedAppsKey(mode))
            else edit.putStringSet(excludedAppsKey(mode), ex)
            val only = config.onlyApps[mode] ?: emptySet()
            if (only.isEmpty()) edit.remove(onlyAppsKey(mode))
            else edit.putStringSet(onlyAppsKey(mode), only)
        }
        edit.putInt(KEY_NIGHT_LIGHT_TEMPERATURE, config.nightLightTemperature)
        edit.putInt(KEY_NIGHT_LIGHT_INTENSITY, config.nightLightIntensity)
        edit.putInt(KEY_EXTRA_DIM_LEVEL, config.extraDimLevel)
        edit.putBoolean(KEY_EXTRA_DIM_USE_OVERLAY, config.extraDimUseOverlay)
        edit.putBoolean(KEY_APPLY_DURING_FOCUS, config.applyDuringFocus)
        edit.apply()
    }

    /**
     * Parses a channel config map (wire keys per research §6.1).
     * Throws [IllegalArgumentException] on malformed values; the
     * handler maps it to INVALID_ARGUMENT. Modes unavailable on this
     * device are dropped, exactly as [loadFrom] drops them on read.
     */
    @Suppress("UNCHECKED_CAST")
    fun configFromMap(raw: Map<*, *>): Config {
        fun windowsList(value: Any?): List<TimeWindow> {
            val list = value as? List<*> ?: return emptyList()
            return list.map { item ->
                val m = item as? Map<*, *>
                    ?: throw IllegalArgumentException("Window must be a {s, e} map")
                val s = (m["s"] as? Number)?.toInt()
                    ?: throw IllegalArgumentException("Window needs int s")
                val e = (m["e"] as? Number)?.toInt()
                    ?: throw IllegalArgumentException("Window needs int e")
                if (s !in 0..1439 || e !in 1..1440 || s == e) {
                    throw IllegalArgumentException("Window minutes out of range: s=$s e=$e")
                }
                TimeWindow(s, e)
            }
        }
        fun stringSet(value: Any?): Set<String> =
            (value as? List<*>)?.filterIsInstance<String>()?.toSet() ?: emptySet()

        // Absent list = never configured: the default (grayscale only).
        // A present-but-empty list is a real choice (all modes off).
        val rawModes = raw["modes"] as? List<*>
        val modes = if (rawModes == null) {
            DEFAULT_MODES
        } else {
            rawModes.filterIsInstance<String>()
                .mapNotNull { ColourMode.fromName(it) }
                .filter { it.isAvailable }
                .toSet()
        }
        val temperature = (raw["nightLightTemperature"] as? Number)?.toInt()
            ?: DEFAULT_NIGHT_LIGHT_TEMPERATURE
        if (temperature !in NIGHT_LIGHT_TEMPERATURES) {
            throw IllegalArgumentException("Unknown night light temperature: $temperature")
        }
        val intensity = (raw["nightLightIntensity"] as? Number)?.toInt()
            ?: DEFAULT_NIGHT_LIGHT_INTENSITY
        if (intensity !in 0..MAX_NIGHT_LIGHT_INTENSITY) {
            throw IllegalArgumentException("Night light intensity out of range: $intensity")
        }
        val dimLevel = (raw["extraDimLevel"] as? Number)?.toInt() ?: DEFAULT_EXTRA_DIM_LEVEL
        if (dimLevel !in 0..100) {
            throw IllegalArgumentException("Extra dim level out of range: $dimLevel")
        }
        return Config(
            enabled = raw["enabled"] as? Boolean ?: false,
            modes = modes,
            windows = ColourMode.entries.associateWith { mode ->
                windowsList((raw["windows"] as? Map<*, *>)?.get(mode.name))
            },
            scopes = ColourMode.entries.associateWith { mode ->
                ColourScope.fromName(((raw["scopes"] as? Map<*, *>)?.get(mode.name) as? String))
            },
            excludedApps = ColourMode.entries.associateWith { mode ->
                stringSet((raw["excludedApps"] as? Map<*, *>)?.get(mode.name))
            },
            onlyApps = ColourMode.entries.associateWith { mode ->
                stringSet((raw["onlyApps"] as? Map<*, *>)?.get(mode.name))
            },
            nightLightTemperature = temperature,
            nightLightIntensity = intensity,
            extraDimLevel = dimLevel,
            extraDimUseOverlay = raw["extraDimUseOverlay"] as? Boolean ?: false,
            applyDuringFocus = raw["applyDuringFocus"] as? Boolean ?: false,
        )
    }

    /** The wire map [configFromMap] parses back, for get/config round-trips. */
    fun configToMap(config: Config): Map<String, Any?> = mapOf(
        "enabled" to config.enabled,
        "modes" to config.modes.map { it.name },
        "windows" to ColourMode.entries.associate { mode ->
            mode.name to config.windowsFor(mode).map { mapOf("s" to it.startMinute, "e" to it.endMinute) }
        },
        "scopes" to ColourMode.entries.associate { mode ->
            mode.name to config.scopeFor(mode).name
        },
        "excludedApps" to ColourMode.entries.associate { mode ->
            mode.name to (config.excludedApps[mode] ?: emptySet()).toList()
        },
        "onlyApps" to ColourMode.entries.associate { mode ->
            mode.name to (config.onlyApps[mode] ?: emptySet()).toList()
        },
        "nightLightTemperature" to config.nightLightTemperature,
        "nightLightIntensity" to config.nightLightIntensity,
        "extraDimLevel" to config.extraDimLevel,
        "extraDimUseOverlay" to config.extraDimUseOverlay,
        "applyDuringFocus" to config.applyDuringFocus,
    )

    fun currentMinuteOfDay(now: LocalTime = LocalTime.now()): Int = now.hour * 60 + now.minute

    /** Windows of [windows] containing [minuteOfDay]. Empty windows contain every minute. */
    fun activeWindows(windows: List<TimeWindow>, minuteOfDay: Int): List<TimeWindow> =
        if (windows.isEmpty()) listOf(TimeWindow(0, 1440))
        else windows.filter { it.contains(minuteOfDay) }

    /** Whether [mode] is switched on right now: enabled, selected, and inside a window (or windowless). */
    fun isModeActiveNow(config: Config, mode: ColourMode, minuteOfDay: Int = currentMinuteOfDay()): Boolean {
        if (!config.enabled || mode !in config.modes) return false
        val w = config.windowsFor(mode)
        return w.isEmpty() || w.any { it.contains(minuteOfDay) }
    }

    /** Modes whose schedule says "on" at [minuteOfDay] (before scope filtering). */
    fun scheduledModes(config: Config, minuteOfDay: Int = currentMinuteOfDay()): Set<ColourMode> {
        if (!config.enabled) return emptySet()
        return config.modes.filter { isModeActiveNow(config, it, minuteOfDay) }.toSet()
    }

    /**
     * Modes to actually enforce for [foregroundPackage] at
     * [minuteOfDay]: the scheduled modes whose scope admits the
     * foreground app, plus grayscale when a focus session is running
     * and [Config.applyDuringFocus] is on (focus phases only — never
     * breaks; the caller passes [focusPhase] = true only for a focus
     * phase).
     */
    fun modesToApply(
        config: Config,
        foregroundPackage: String?,
        minuteOfDay: Int = currentMinuteOfDay(),
        focusPhase: Boolean = false,
    ): Set<ColourMode> {
        val scheduled = scheduledModes(config, minuteOfDay).filter { mode ->
            config.coverageFor(mode).scope.appliesTo(
                foregroundPackage,
                config.coverageFor(mode).excludedApps,
                config.coverageFor(mode).onlyApps,
            )
        }.toMutableSet()
        if (focusPhase && config.applyDuringFocus && config.enabled &&
            ColourMode.GRAYSCALE in config.modes
        ) {
            scheduled += ColourMode.GRAYSCALE
        }
        return scheduled
    }

    /** Whether any enabled mode's scope depends on the foreground app. */
    fun dependsOnForegroundApp(config: Config): Boolean =
        config.enabled && config.modes.any { config.scopeFor(it) != ColourScope.DEVICE }

    fun scheduledWindows(config: Config): List<TimeWindow> =
        config.modes.flatMap { config.windowsFor(it) }

    fun millisUntilNextBoundary(windows: List<TimeWindow>, now: LocalTime = LocalTime.now()): Long? {
        if (windows.isEmpty()) return null
        val nowMinute = currentMinuteOfDay(now)
        val minutesAhead = windows
            .flatMap { listOf(it.startMinute, it.endMinute % 1440) }
            .minOf { boundary -> ((boundary - nowMinute + 1440) % 1440).takeIf { it > 0 } ?: 1440 }
        val intoCurrentMinute = TimeUnit.SECONDS.toMillis(now.second.toLong()) +
            TimeUnit.NANOSECONDS.toMillis(now.nano.toLong())
        return TimeUnit.MINUTES.toMillis(minutesAhead.toLong()) - intoCurrentMinute
    }

    /**
     * Modes currently locked against loosening: on right now (enabled,
     * selected, inside a window — or windowless), or grayscale during
     * a focus session with `apply_during_focus` on.
     */
    fun lockedModesNow(
        config: Config,
        minuteOfDay: Int = currentMinuteOfDay(),
        focusPhase: Boolean = false,
    ): Set<ColourMode> {
        val locked = mutableSetOf<ColourMode>()
        val focusLocked = config.applyDuringFocus && focusPhase && config.enabled &&
            ColourMode.GRAYSCALE in config.modes
        for (mode in ColourMode.entries) {
            if (isModeActiveNow(config, mode, minuteOfDay) ||
                (focusLocked && mode == ColourMode.GRAYSCALE)
            ) locked += mode
        }
        return locked
    }

    /**
     * The locked modes a change from [old] to [new] would loosen, at
     * [minuteOfDay] with [focusPhase] (true during a focus phase).
     * Empty means the write may proceed. A recovery session ([sessionActive])
     * opens every lock, so it short-circuits to empty.
     *
     * A mode is locked when it is on right now — enabled, selected, and
     * inside a window (or windowless) — or when a focus session is
     * running with `apply_during_focus` (grayscale only). Loosening a
     * locked mode is: switching the feature off, deselecting the mode,
     * shrinking its windows off the current minute, narrowing its scope
     * ([ColourScope.isLoosening]), lowering its night-light temperature
     * or intensity / extra-dim level, or switching `apply_during_focus`
     * off mid-focus.
     */
    fun lockedModesForChange(
        old: Config,
        new: Config,
        minuteOfDay: Int = currentMinuteOfDay(),
        focusPhase: Boolean = false,
        sessionActive: Boolean = false,
    ): Set<ColourMode> {
        if (sessionActive) return emptySet()
        val locked = mutableSetOf<ColourMode>()
        val focusLocked = old.applyDuringFocus && focusPhase && old.enabled &&
            ColourMode.GRAYSCALE in old.modes
        for (mode in lockedModesNow(old, minuteOfDay, focusPhase)) {
            val loosened = when {
                !new.enabled -> true
                mode !in new.modes -> true
                !newWindowsCoverNow(old, new, mode, minuteOfDay) -> true
                ColourScope.isLoosening(old.coverageFor(mode), new.coverageFor(mode)) -> true
                mode == ColourMode.NIGHT_LIGHT &&
                    (new.nightLightTemperature < old.nightLightTemperature ||
                        new.nightLightIntensity < old.nightLightIntensity) -> true
                mode == ColourMode.EXTRA_DIM && new.extraDimLevel < old.extraDimLevel -> true
                focusLocked && mode == ColourMode.GRAYSCALE && !new.applyDuringFocus -> true
                else -> false
            }
            if (loosened) locked += mode
        }
        return locked
    }

    /**
     * Whether [new]'s windows for [mode] still cover the current
     * minute, given [old]'s windows covered it (or were empty).
     * Shrinking off "now" is a loosening; widening, or leaving the
     * coverage of "now" untouched, is not.
     */
    private fun newWindowsCoverNow(
        old: Config,
        new: Config,
        mode: ColourMode,
        minuteOfDay: Int,
    ): Boolean {
        val newWindows = new.windowsFor(mode)
        if (newWindows.isEmpty()) return true
        return newWindows.any { it.contains(minuteOfDay) }
    }
}
