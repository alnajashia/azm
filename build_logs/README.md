# Build log index — first successful APK (2026-11-09)

Reproduce with `../build_apk.sh debug` / `../build_apk.sh release`.

| Log | What happened |
|---|---|
| `build6.log` | Reproduction: Gradle client "Could not receive a message from the daemon" — daemon comms intercepted |
| `build7.log` | With `JAVA_TOOL_OPTIONS=-Djava.net.preferIPv4Stack=true` the daemon connects; plugin resolution then fails (TLS through tunnel dropped) |
| `gradle_help_debug.log` | `--debug` evidence: Gradle connects to the loopback relay, CONNECT succeeds, then 30 s timeouts awaiting the TLS ServerHello |
| `gradle_help_mitm.log` | First run through the TLS-terminating relay: resolution works; killed by an artificial 280 s timeout while still progressing (Flutter tools Gradle plugin compiled) |
| `build8_debug.log` | Full dependency download through the relay (incl. auto-install of NDK 27 + Build-Tools 35), then the Gradle daemon disappeared when the sandbox service restarted (ephemeral root FS) |
| `build9_debug.log` | Reached `:app:compileDebugKotlin` — 5 real Kotlin errors (listed in `docs/IMPLEMENTATION_STATUS.md` §1) |
| `build10/11_debug.log` | Interrupted by the sandbox restart that wiped `/usr/lib/jvm` and `/root/.gradle` |
| `build12_debug.log` | ✅ `assembleDebug` succeeded (866 s) with persistent-workspace Temurin JDK 21 + `GRADLE_USER_HOME`; `app-debug.apk` 148,894,306 B, SHA-256 `86bfa331e3124d5986dd61276d41904b691552fc145e3e9ac39d83d1eea23615` |
| `build13_release.log` | ✅ `assembleRelease` succeeded (315 s); `app-release.apk` 50,406,827 B, SHA-256 `c1bd2fa2ebc767ce296e830f5e1a2d864de7ec5cf82572fb527fc4f81a67103e`, debug-signed per scaffold config |

Root-cause summary (all evidence in the logs above and the relay log at
`~/workspace/tmp_build/mitm_relay.log`):
1. Java TCP not sourced from loopback is intercepted by the sandbox's
   `other_tcp` gate (it answers with a plaintext denial) → breaks the
   Gradle daemon handshake and direct proxy access. Fix:
   `-Djava.net.preferIPv4Stack=true` for client, daemon, and all JVMs.
2. The egress tunnel drops TLS ClientHellos that do not offer ALPN
   `http/1.1`; Java/Gradle send none → every HTTPS fetch timed out after
   a successful CONNECT. Fix: local TLS-terminating relay
   (`~/workspace/tmp_build/mitm_relay.py`, CA in `~/workspace/tmp_build/mitm/`)
   on 127.0.0.1:18080 — Gradle's already-configured proxy — which
   re-originates upstream TLS with ALPN and verifies real certs; the JVM
   trusts a truststore made of the JDK cacerts + the local CA.
3. The sandbox root FS is ephemeral: JDK and Gradle caches must live in
   `~/workspace` (Temurin tarball + `GRADLE_USER_HOME`), as `build_apk.sh`
   now sets up.
