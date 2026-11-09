package io.github.alnajashia.dominanter.shizuku

import io.github.alnajashia.dominanter.channel.ErrorCodes
import io.github.alnajashia.dominanter.channel.PrivException
import moe.shizuku.server.IShizukuService
import rikka.shizuku.Shizuku
import java.io.BufferedReader
import java.io.FileInputStream
import java.io.InputStreamReader
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/**
 * Runs shell commands in the Shizuku server process (shell/root UID) via the
 * internal `IShizukuService.newProcess` — a port of the original DeChainer
 * `utils/ShizukuRunner.kt`, with its flaws fixed (`docs/ARCHITECTURE.md` §5.4):
 *
 *  1. **Exit codes are always returned and are the caller's success criterion.**
 *     The original `command()` flavour never called `waitFor()` before
 *     reporting: a command that failed with a non-zero exit and empty stderr
 *     was reported as success (`done = true`). There is no such path here —
 *     both flavours return a [ProcessResult] with the real exit code, and the
 *     provisioning callers throw `SHELL_FAILED` (with the exit code) on
 *     non-zero exits.
 *  2. **stdout and stderr are drained concurrently** (the original `command()`
 *     drained them sequentially — a pipe-buffer deadlock risk).
 *  3. **Timeouts are enforced**: a process that does not finish within
 *     [timeoutMs] is destroyed and reported as [ErrorCodes.TIMEOUT]. The
 *     original had no timeout at all.
 *
 * Returns `null` (as the original `exec` did) when no command could be run at
 * all: no binder, dead binder, or a pre-V11 server. Callers translate that
 * into the proper `SHIZUKU_*` channel error via [ShizukuGateway].
 */
object ShizukuRunner {

    data class ProcessResult(
        val exitCode: Int,
        val output: String,
        val error: String,
    )

    const val DEFAULT_TIMEOUT_MS = 30_000L

    private val streamExecutor = Executors.newCachedThreadPool { r ->
        Thread(r, "shizuku-stream").apply { isDaemon = true }
    }

    /**
     * Argv form (port of the original `exec`): if a single argument contains a
     * space it is run through `sh -c`, exactly as the original did.
     */
    fun exec(vararg command: String, timeoutMs: Long = DEFAULT_TIMEOUT_MS): ProcessResult? {
        val cmdArray = if (command.size == 1 && command[0].contains(" ")) {
            arrayOf("sh", "-c", command[0])
        } else {
            command
        }
        return run(cmdArray, timeoutMs)
    }

    /**
     * Shell-string form (the original `command()` call shape), kept for the
     * provisioning call sites that build command strings — but synchronous and
     * exit-code-checked: it returns the full [ProcessResult] instead of
     * streaming to a listener that could mistake empty stderr for success.
     */
    fun execShell(command: String, timeoutMs: Long = DEFAULT_TIMEOUT_MS): ProcessResult? =
        run(arrayOf("sh", "-c", command), timeoutMs)

    /** Like [exec], but throws the taxonomy's `SHELL_FAILED` on a non-zero exit. */
    fun execChecked(vararg command: String, timeoutMs: Long = DEFAULT_TIMEOUT_MS): ProcessResult {
        val display = command.joinToString(" ")
        val result = exec(*command, timeoutMs = timeoutMs)
            ?: throw ShizukuGateway.unavailableException()
        if (result.exitCode != 0) throw PrivException.shellFailed(display, result.exitCode, result.output, result.error)
        return result
    }

    /** Like [execShell], but throws `SHELL_FAILED` on a non-zero exit. */
    fun execShellChecked(command: String, timeoutMs: Long = DEFAULT_TIMEOUT_MS): ProcessResult {
        val result = execShell(command, timeoutMs)
            ?: throw ShizukuGateway.unavailableException()
        if (result.exitCode != 0) throw PrivException.shellFailed(command, result.exitCode, result.output, result.error)
        return result
    }

    private fun run(cmdArray: Array<String>, timeoutMs: Long): ProcessResult? {
        val binder = Shizuku.getBinder() ?: return null
        if (!binder.pingBinder()) return null
        if (Shizuku.isPreV11()) return null
        val service = IShizukuService.Stub.asInterface(binder) ?: return null
        val process = try {
            service.newProcess(cmdArray, null, null) ?: return null
        } catch (_: Exception) {
            return null
        }

        // Drain both streams concurrently (fix #2).
        val stdoutFuture = streamExecutor.submit(Callable {
            readFully(process.inputStream?.fileDescriptor)
        })
        val stderrFuture = streamExecutor.submit(Callable {
            readFully(process.errorStream?.fileDescriptor)
        })

        val finished = try {
            process.waitForTimeout(timeoutMs, TimeUnit.MILLISECONDS.toString())
        } catch (_: Exception) {
            false
        }
        if (!finished) {
            try { process.destroy() } catch (_: Exception) { /* already gone */ }
            throw PrivException(
                ErrorCodes.TIMEOUT,
                "Shizuku command timed out after ${timeoutMs}ms: ${cmdArray.joinToString(" ")}",
                mapOf("command" to cmdArray.joinToString(" "), "timeoutMs" to timeoutMs),
            )
        }
        val exitCode = try { process.exitValue() } catch (_: Exception) { -1 }
        val output = awaitStream(stdoutFuture)
        val error = awaitStream(stderrFuture)
        return ProcessResult(exitCode, output.trim(), error.trim())
    }

    private fun readFully(fd: java.io.FileDescriptor?): String {
        if (fd == null) return ""
        return try {
            BufferedReader(InputStreamReader(FileInputStream(fd))).use { it.readText() }
        } catch (_: Exception) {
            ""
        }
    }

    private fun awaitStream(future: java.util.concurrent.Future<String>): String =
        try {
            future.get(5, TimeUnit.SECONDS)
        } catch (_: TimeoutException) {
            ""
        } catch (_: Exception) {
            ""
        }
}
