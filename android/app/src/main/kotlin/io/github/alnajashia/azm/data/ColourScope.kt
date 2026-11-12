package io.github.alnajashia.azm.data

/**
 * Per-mode coverage scope (Batch C / GRAYSCALE_RESEARCH.md §6.2),
 * ported in structure from DeChainer's `ColorFilterScope` (Apache-2.0,
 * warleysr/dechainer) with Azm naming.
 *
 *  - DEVICE: the mode applies across the whole phone.
 *  - EXCEPT_APPS: the mode applies everywhere except the listed apps.
 *  - ONLY_APPS: the mode applies only while a listed app is in front.
 *
 * [isLoosening] is the lock's scope rule: a scope change is a
 * loosening exactly when it leaves the mode off somewhere it used to
 * apply. The lock refuses loosening during an active window (or a
 * focus session with `apply_during_focus`) unless a recovery session
 * is active; tightening is always free.
 */
enum class ColourScope {
    DEVICE,
    EXCEPT_APPS,
    ONLY_APPS;

    fun appliesTo(
        foregroundPackage: String?,
        excludedApps: Set<String>,
        onlyApps: Set<String>,
    ): Boolean = when (this) {
        DEVICE -> true
        EXCEPT_APPS -> foregroundPackage !in excludedApps
        ONLY_APPS -> foregroundPackage in onlyApps
    }

    companion object {
        fun fromName(name: String?): ColourScope =
            entries.firstOrNull { it.name == name } ?: DEVICE

        /** Whether going from [from] to [to] leaves the mode off somewhere it used to apply. */
        fun isLoosening(from: Coverage, to: Coverage): Boolean = when (to.scope) {
            DEVICE -> false
            EXCEPT_APPS -> when (from.scope) {
                DEVICE -> to.excludedApps.isNotEmpty()
                EXCEPT_APPS -> !from.excludedApps.containsAll(to.excludedApps)
                ONLY_APPS -> from.onlyApps.any { it in to.excludedApps }
            }
            ONLY_APPS -> when (from.scope) {
                DEVICE, EXCEPT_APPS -> true
                ONLY_APPS -> !to.onlyApps.containsAll(from.onlyApps)
            }
        }
    }

    data class Coverage(
        val scope: ColourScope,
        val excludedApps: Set<String>,
        val onlyApps: Set<String>,
    )
}
