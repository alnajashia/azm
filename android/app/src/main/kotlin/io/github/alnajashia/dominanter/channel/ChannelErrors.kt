package io.github.alnajashia.dominanter.channel

import io.flutter.plugin.common.MethodChannel

/**
 * The error taxonomy of `docs/ARCHITECTURE.md` §5.4.
 *
 * Every failure crossing the `dominanter/privileged` channel is a [PrivException]
 * carrying one of these stable codes plus a details map. Shell failures ALWAYS
 * include the process exit code when a process ran — the original
 * `ShizukuRunner.command()` never checked exit codes and reported failures with
 * empty stderr as success; that flaw is deliberately not ported.
 */
object ErrorCodes {
    const val INVALID_ARGUMENT = "INVALID_ARGUMENT"
    const val SHIZUKU_NOT_INSTALLED = "SHIZUKU_NOT_INSTALLED"
    const val SHIZUKU_NOT_RUNNING = "SHIZUKU_NOT_RUNNING"
    const val SHIZUKU_NO_PERMISSION = "SHIZUKU_NO_PERMISSION"
    const val SHIZUKU_PRE_V11 = "SHIZUKU_PRE_V11"
    const val SHIZUKU_BINDER_DEAD = "SHIZUKU_BINDER_DEAD"
    const val SHELL_FAILED = "SHELL_FAILED"
    const val PROVISIONING_FAILED = "PROVISIONING_FAILED"
    const val DPM_NOT_OWNER = "DPM_NOT_OWNER"
    const val DPM_FAILED = "DPM_FAILED"
    const val PACKAGE_NOT_FOUND = "PACKAGE_NOT_FOUND"
    const val PERMISSION_DENIED = "PERMISSION_DENIED"
    const val UNSUPPORTED_ANDROID = "UNSUPPORTED_ANDROID"
    const val TIMEOUT = "TIMEOUT"
    const val INTERNAL = "INTERNAL"
    const val NOT_IMPLEMENTED = "NOT_IMPLEMENTED"
}

/** A failure in the exact shape the channel contract requires. */
class PrivException(
    val code: String,
    message: String,
    val details: Map<String, Any?> = emptyMap(),
) : Exception(message) {

    fun sendTo(result: MethodChannel.Result) {
        result.error(code, message, details)
    }

    companion object {
        fun invalidArgument(message: String): PrivException =
            PrivException(ErrorCodes.INVALID_ARGUMENT, message)

        fun internal(cause: Throwable): PrivException =
            PrivException(
                ErrorCodes.INTERNAL,
                cause.message ?: "Internal error",
                mapOf("cause" to "${cause.javaClass.name}: ${cause.message}"),
            )

        fun dpmFailed(message: String, cause: Throwable? = null, verifiedState: Any? = null): PrivException {
            val details = mutableMapOf<String, Any?>()
            if (cause != null) details["cause"] = "${cause.javaClass.name}: ${cause.message}"
            if (verifiedState != null) details["verifiedState"] = verifiedState
            return PrivException(ErrorCodes.DPM_FAILED, message, details)
        }

        /** A shell process ran and exited non-zero (or produced an unusable result). */
        fun shellFailed(command: String, exitCode: Int, stdout: String, stderr: String): PrivException =
            PrivException(
                ErrorCodes.SHELL_FAILED,
                "Command failed with exit code $exitCode: $command",
                mapOf(
                    "exitCode" to exitCode,
                    "command" to command,
                    "stdout" to stdout.take(MAX_OUTPUT),
                    "stderr" to stderr.take(MAX_OUTPUT),
                ),
            )

        fun notImplemented(what: String, reason: String): PrivException =
            PrivException(
                ErrorCodes.NOT_IMPLEMENTED,
                "$what is not implemented in this version: $reason",
                mapOf("feature" to what),
            )

        private const val MAX_OUTPUT = 2048
    }
}

/** Caps free-text (shell output / exception text) before it crosses the channel. */
fun String.capped(max: Int = 2048): String = if (length <= max) this else take(max)
