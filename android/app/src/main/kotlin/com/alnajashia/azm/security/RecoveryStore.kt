package com.alnajashia.azm.security

import android.content.Context
import android.util.Base64
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Locale
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

/**
 * Recovery-code storage — the documented security deviation of
 * `docs/ARCHITECTURE.md` §7.1.
 *
 * The original stored the 16-character code as **plaintext** in
 * `recovery_prefs`. This rebuild stores only a PBKDF2WithHmacSHA256 hash with a
 * per-install random salt, in a dedicated `recovery_secure` store:
 *
 *     recovery_code_salt       (Base64, 16 random bytes)
 *     recovery_code_hash       (Base64, 32-byte derived key)
 *     recovery_code_kdf_iterations
 *
 * The plaintext code exists only transiently: [generateCode] returns a fresh
 * code ONCE (to the Dart wizard, which shows it for the paper copy), and
 * [setCode] receives the confirmed code once for hashing. There is
 * deliberately **no** getter for the code or the hash — verification
 * ([verifyCode]) recomputes and compares in constant time.
 */
object RecoveryStore {
    private const val PREFS_NAME = "recovery_secure"
    private const val KEY_SALT = "recovery_code_salt"
    private const val KEY_HASH = "recovery_code_hash"
    private const val KEY_ITERATIONS = "recovery_code_kdf_iterations"
    private const val ITERATIONS = 210_000

    /**
     * The native recovery session (Batch C, C4). The Dart gate keeps
     * its own in-memory 10-minute session; this is the native mirror
     * of it, so a native decision — whether a sealed removal may
     * proceed — can be made without trusting a client-asserted flag.
     * Both clocks are recorded, exactly like Dart's `RecoverySession`:
     * the wall clock alone can be moved by changing the device time,
     * `elapsedRealtime` cannot.
     */
    const val RECOVERY_SESSION_MS = 600_000L
    private const val KEY_SESSION_VERIFIED_AT_WALL = "session_verified_at_wall"
    private const val KEY_SESSION_VERIFIED_AT_ELAPSED = "session_verified_at_elapsed"

    /** Sanity bound for a STORED iteration count at verify time (audit A-L7b). */
    private const val MAX_VERIFY_ITERATIONS = 1_000_000
    private const val SALT_BYTES = 16
    private const val KEY_BITS = 256
    private const val CODE_LENGTH = 16

    /**
     * The delayed forced-removal delay (F2) — THE single named source
     * of truth for the whole product (v1.0.6 user directive: 24 hours,
     * a deliberate deviation from the original's 48). The Dart side
     * reads this value through the channel's owner state
     * (`forcedRemovalDelayHours`) and never hard-codes its own for
     * live accounting.
     */
    const val FORCED_REMOVAL_DELAY_HOURS = 24

    // Same alphabet as the original generator (A–Z), so the user-facing format
    // (16 upper-case letters, written on paper) is unchanged.
    private const val CHAR_POOL = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** Generates a fresh 16-character code. Returns it once; stores nothing. */
    fun generateCode(): String {
        val random = SecureRandom()
        return (1..CODE_LENGTH)
            .map { CHAR_POOL[random.nextInt(CHAR_POOL.length)] }
            .joinToString("")
    }

    fun isSet(context: Context): Boolean =
        prefs(context).contains(KEY_HASH) && prefs(context).contains(KEY_SALT)

    /** Hashes and stores [code], replacing any previous code. Never stores plaintext. */
    fun setCode(context: Context, code: String) {
        val normalized = normalize(code)
        require(normalized.length == CODE_LENGTH && normalized.all { it in CHAR_POOL }) {
            "Recovery code must be $CODE_LENGTH letters A-Z"
        }
        val salt = ByteArray(SALT_BYTES).also { SecureRandom().nextBytes(it) }
        val hash = derive(normalized, salt, ITERATIONS)
        prefs(context).edit()
            .putString(KEY_SALT, Base64.encodeToString(salt, Base64.NO_WRAP))
            .putString(KEY_HASH, Base64.encodeToString(hash, Base64.NO_WRAP))
            .putInt(KEY_ITERATIONS, ITERATIONS)
            // A new code invalidates any session recorded under the old one.
            .remove(KEY_SESSION_VERIFIED_AT_WALL)
            .remove(KEY_SESSION_VERIFIED_AT_ELAPSED)
            .apply()
    }

    /**
     * Whether a recovery session is currently active: the paper code
     * was verified less than [RECOVERY_SESSION_MS] ago, on BOTH
     * clocks. A session recorded under one clock only (or older than
     * 10 minutes on either) does not count.
     */
    fun isRecoverySessionActive(context: Context): Boolean {
        val p = prefs(context)
        if (!p.contains(KEY_SESSION_VERIFIED_AT_WALL) ||
            !p.contains(KEY_SESSION_VERIFIED_AT_ELAPSED)
        ) return false
        val wallAge = System.currentTimeMillis() - p.getLong(KEY_SESSION_VERIFIED_AT_WALL, 0L)
        val elapsedAge = android.os.SystemClock.elapsedRealtime() -
            p.getLong(KEY_SESSION_VERIFIED_AT_ELAPSED, 0L)
        return wallAge in 0 until RECOVERY_SESSION_MS &&
            elapsedAge in 0 until RECOVERY_SESSION_MS
    }

    /** Constant-time verification against the stored salted hash. */
    fun verifyCode(context: Context, code: String): Boolean {
        val p = prefs(context)
        val saltB64 = p.getString(KEY_SALT, null) ?: return false
        val hashB64 = p.getString(KEY_HASH, null) ?: return false
        val iterations = p.getInt(KEY_ITERATIONS, ITERATIONS)
        // A tampered iteration count must fail verification, not crash
        // or weaken it (v1.0.5 audit A-L7b): derive() with 0/negative
        // iterations throws out of PBEKeySpec.
        if (iterations !in 1..MAX_VERIFY_ITERATIONS) return false
        val salt = try { Base64.decode(saltB64, Base64.NO_WRAP) } catch (_: Exception) { return false }
        val expected = try { Base64.decode(hashB64, Base64.NO_WRAP) } catch (_: Exception) { return false }
        if (salt.size != SALT_BYTES || expected.size != KEY_BITS / 8) return false
        val actual = derive(normalize(code), salt, iterations)
        val ok = MessageDigest.isEqual(expected, actual)
        if (ok) {
            // A correct code opens a 10-minute recovery session, on
            // both clocks (see [isRecoverySessionActive]). The Dart
            // gate starts its own session in parallel; this native one
            // is what the seal checks consult.
            p.edit()
                .putLong(KEY_SESSION_VERIFIED_AT_WALL, System.currentTimeMillis())
                .putLong(
                    KEY_SESSION_VERIFIED_AT_ELAPSED,
                    android.os.SystemClock.elapsedRealtime(),
                )
                .apply()
        }
        return ok
    }

    /**
     * Codes are compared without spaces and case-insensitively, as typed
     * from paper. [Locale.ROOT] is load-bearing (v1.0.5 audit A-L7): in
     * Turkish/Azeri locales a locale-sensitive uppercase maps 'i' to
     * 'İ', which would reject valid codes containing I on such devices.
     */
    fun normalize(code: String): String = code.replace(" ", "").uppercase(Locale.ROOT)

    fun isValidFormat(code: String): Boolean {
        val n = normalize(code)
        return n.length == CODE_LENGTH && n.all { it in CHAR_POOL }
    }

    private fun derive(code: String, salt: ByteArray, iterations: Int): ByteArray {
        val spec = PBEKeySpec(code.toCharArray(), salt, iterations, KEY_BITS)
        return try {
            SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
        } finally {
            spec.clearPassword()
        }
    }
}
