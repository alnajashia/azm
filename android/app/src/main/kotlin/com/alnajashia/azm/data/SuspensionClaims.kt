package com.alnajashia.azm.data

import android.content.Context

/**
 * The shared suspension-claims registry (Batch I-B, item 14).
 *
 * Each long-lived feature that suspends packages owns one claim set
 * (one SharedPreferences StringSet per reason). The claim rule is the
 * one FocusSessionStore already used: a feature claims a package only
 * when it already claims it or the package is not currently
 * suspended — so a package suspended by an untracked party (impulse
 * lock, applied from Dart; visual blocking, timed and self-releasing)
 * is never claimed and never released by another feature.
 *
 * On release, a feature releases only the packages in its own set
 * that no OTHER tracked feature claims ([releasableBy]) — so ending a
 * lockdown never releases a focus session's apps and vice versa. The
 * sets are disjoint by construction (the claim rule), but the
 * registry check is the defence in depth that makes the invariant
 * explicit and testable.
 *
 * User restrictions use the same shape: one claim set per reason, so
 * a lockdown ending never clears a restriction the focus session
 * still claims.
 */
object SuspensionClaims {
    const val REASON_FOCUS = "FOCUS"
    const val REASON_LOCKDOWN = "LOCKDOWN"

    private const val PREFS_NAME = "suspension_claims_prefs"
    private const val KEY_PREFIX = "claims_"
    private const val KEY_RESTRICTIONS_PREFIX = "restrictions_"

    private val ALL_REASONS = setOf(REASON_FOCUS, REASON_LOCKDOWN)

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun claimedPackages(context: Context, reason: String): Set<String> =
        prefs(context).getStringSet(KEY_PREFIX + reason, emptySet()) ?: emptySet()

    fun claimPackages(context: Context, reason: String, packages: Set<String>) {
        prefs(context).edit().putStringSet(KEY_PREFIX + reason, packages).apply()
    }

    fun clearPackages(context: Context, reason: String) {
        prefs(context).edit().remove(KEY_PREFIX + reason).apply()
    }

    /** The subset of [packages] claimed by any tracked reason other than [reason]. */
    fun claimedByOthers(context: Context, reason: String, packages: Set<String>): Set<String> {
        val others = ALL_REASONS - reason
        return packages.filter { pkg ->
            others.any { pkg in claimedPackages(context, it) }
        }.toSet()
    }

    /** The subset of [packages] this reason may release: its own, claimed by nobody else. */
    fun releasableBy(context: Context, reason: String, packages: Set<String>): Set<String> =
        packages - claimedByOthers(context, reason, packages)

    fun claimedRestrictions(context: Context, reason: String): Set<String> =
        prefs(context).getStringSet(KEY_RESTRICTIONS_PREFIX + reason, emptySet()) ?: emptySet()

    fun claimRestrictions(context: Context, reason: String, keys: Set<String>) {
        prefs(context).edit().putStringSet(KEY_RESTRICTIONS_PREFIX + reason, keys).apply()
    }

    fun clearRestrictions(context: Context, reason: String) {
        prefs(context).edit().remove(KEY_RESTRICTIONS_PREFIX + reason).apply()
    }

    /** The subset of [keys] this reason may clear: its own, claimed by nobody else. */
    fun releasableRestrictions(context: Context, reason: String, keys: Set<String>): Set<String> {
        val others = ALL_REASONS - reason
        return keys.filter { key ->
            others.none { key in claimedRestrictions(context, it) }
        }.toSet()
    }
}
