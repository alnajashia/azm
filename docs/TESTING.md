# Dominanter — Testing

> **Last updated:** 2026-11-09 (post-redesign rebuild + compliance audit — see `COMPLIANCE_AUDIT.md`)
> **Headline honesty statement:** All evidence in this file was produced in a
> Linux sandbox with **no Android device and no emulator attached**.
> **No device testing has occurred.** Nothing that touches a real Shizuku
> server, Device Owner provisioning, or the Accessibility Service has been
> run on hardware, and nothing in this file should be read as claiming
> otherwise. Statuses use three values only:
>
> - **Verified here** — executed in this environment, with the artefact/log
>   named.
> - **Requires real device** — cannot be meaningfully verified without
>   hardware (reason given); currently **untested**.
> - **Not yet** — not done and not blocked on hardware; future work.

Companion documents: [`ARCHITECTURE.md`](ARCHITECTURE.md) §9 (test plan),
[`IMPLEMENTATION_STATUS.md`](IMPLEMENTATION_STATUS.md) (per-feature status),
[`REVERSE_ENGINEERING.md`](REVERSE_ENGINEERING.md).

---

## 1. Evidence summary (what was actually run)

| Check | Result | Evidence |
|---|---|---|
| `flutter analyze` | ✅ **0 errors, 0 warnings**, 32 info-level lints (mostly `use_build_context_synchronously` behind `mounted` guards; deprecated `RadioListTile.groupValue`/`onChanged`; a dangling doc comment in the new redesign test) | Re-run 2026-11-09 after the UI redesign; log `build_logs/redesign_analyze.log`; see `IMPLEMENTATION_STATUS.md` §2a/§5 |
| `flutter test` | ✅ **41/41 passed** | Re-run 2026-11-09 after the UI redesign; log `build_logs/redesign_test.log`; per-file coverage in §2 below. (An earlier attempt failed on a full 512 MB `/tmp` tmpfs — environment, not code; runs use `TMPDIR` on the workspace disk.) |
| Kotlin compile (Gradle) | ✅ Compile-verified | `compileDebugKotlin` and `compileReleaseKotlin` pass as part of the successful `assembleDebug` / `assembleRelease` builds. The first real build found **5 Kotlin compile errors**, all fixed: a `*/` sequence terminating a KDoc comment early in `DeviceOwnerManager.kt`; the non-existent `PRIVATE_DNS_SET_SUCCESS` constant (correct: `PRIVATE_DNS_SET_NO_ERROR`); a duplicate companion object in the Accessibility Service; a missing `Context` threaded through `ShizukuProvisioning.refreshUserSetupComplete`; a vararg array type mismatch in `ShizukuRunner.exec` |
| `flutter build apk --debug` | ✅ Succeeded — first build 866 s (`build_logs/build12_debug.log`); **post-redesign rebuild also succeeded** | `build_logs/build14_redesign_debug.log`; recipe codified in `build_apk.sh`, root causes in `build_logs/README.md` |
| `flutter build apk --release` | ✅ Succeeded — first build 315 s (`build_logs/build13_release.log`); **post-redesign rebuild also succeeded** | `build_logs/build15_redesign_release.log` |
| APK badging (`aapt2 dump badging`) | ✅ Verified on the built APKs | `package: name='io.github.alnajashia.dominanter' versionCode='1' versionName='1.0.0' compileSdkVersion='36'`, `minSdkVersion:'30'`, `targetSdkVersion:'36'` |
| REA inspection of the rebuilt APK | ✅ Run on the **pre-redesign** release APK — see [`REA_REBUILT_APK.md`](REA_REBUILT_APK.md) | REA 6.8.0 CLI commands run against the first `app-release.apk` (50,406,827 B) 2026-11-09; **not re-run on the post-redesign APK** — that document's size/hash describe the earlier artefact, not the current one |
| Device / emulator testing | ❌ **None** | No device or emulator exists in this environment. Every device-dependent item in §3 is untested |

### Built APKs

| APK | Size (bytes) | SHA-256 | Signing |
|---|---|---|---|
| `app-debug.apk` | 163,293,074 | `4fdbab00ab3596740231a11a7546792cb64823d5d8022f5bd04033a1f3de49bc` | debug |
| `app-release.apk` | 50,472,363 | `14017379ad806dfb5b120708e94e35a02d192a1d459b7b63ac1f35a6b411c7a4` | **debug-signed** (scaffold `signingConfig = debug`; a real release keystore is a publishing decision, not yet made — this APK is **not publishable as-is**) |

Local deliverable copies (kept on this machine only, **not** in git — they
are binaries and are excluded from the snapshot pushes):

```
~/workspace/dominater-rebuild/project/release/dominanter-v1.0.0-debug.apk
~/workspace/dominater-rebuild/project/release/dominanter-v1.0.0-release.apk
```

Checksums of the copies were verified identical to the build outputs above
at copy time. These are the **post-redesign rebuilds of 2026-11-09**
(`build14_redesign_debug.log` / `build15_redesign_release.log`), which
supersede the first builds (debug 148,894,306 B / `86bfa331…`; release
50,406,827 B / `c1bd2fa2…`). Badging was re-verified with `aapt2` on both
new APKs: `io.github.alnajashia.dominanter`, versionCode 1 / versionName
1.0.0, minSdk 30, targetSdk 36 — unchanged.

Neither APK has been installed or run on any device.

---

## 2. Dart test suite — 41 tests, by file

| File | Tests | Covers |
|---|---|---|
| `test/recovery_gate_test.dart` | 20 | The recovery-gate domain model (F23): loosening vs tightening detection for daily/per-weekday time limits (raise/remove = loosens, lower/add = tightens, any single loosening weekday wins), time windows (widen/remove = loosens, narrow = tightens, midnight-spanning windows measured correctly), restriction sets (dropping a key loosens, `true → false` loosens), blocklists (shrinking loosens, growing does not); the 5-second undo window (`PendingChange`: undo inside 5 s reverts exactly once, after 5 s the change stands); the 10-minute in-memory recovery session (start, clock expiry, renew, end); 48-hour forced-removal accounting (negative deltas never rewind it); impulse lock (duration clamped to 15 min–6 h, ticks to completion, negative ticks ignored) |
| `test/challenges_test.dart` | 8 | Access challenges (F22) and focus model (F25): math challenge requires 5 correct answers and wrong answers do not advance; all four operations produce self-consistent problems; words challenge streak restarts on a mistake; reading challenge reveals one tick at a time, advances passages, completes; Tetris is the **only** challenge unavailable in v1; focus phase cycle (focus → break → focus → long break at cycle 2); pause stores remaining time and resume re-enters focus with it; focus config JSON round-trip preserves v1 defaults and values |
| `test/channel_client_test.dart` | 8 | The typed Dart client for the `dominanter/privileged` MethodChannel (§3 of `IMPLEMENTATION_STATUS.md`): `getShizukuState` parses the exact Kotlin payload; all five Shizuku states parse distinctly; `SHELL_FAILED` keeps error code, `exitCode`, command and stderr from `details` (regression test for the original `ShizukuRunner.command()` flaw — shell failures must never be reported as success); `DPM_NOT_OWNER` is mapped and recognisable; a missing native side becomes `UNAVAILABLE`, never a fake result; `listInstalledApps` parses Kotlin `AppInfo` maps including a null rating; `setAppSuspended` returns verified per-package results; time-limit / windows / groups payloads round-trip through the client |
| `test/widget_test.dart` | 3 | Critical gates as widgets: the lock-screen panic button is visible **before** any authentication (F21/F32); the first-run wizard shows the generated recovery code grouped for writing on paper (F24); the wizard stores the re-typed code via the channel (F24) |
| `test/redesign_test.dart` | 2 | UI redesign (2026-11-09): the floating pill navigation renders 4 destinations and tapping the 3rd switches the tab; the circular focus timer ring shows the `FocusSession` model's remaining time (idle 25:00 → 24:5x after Start) |

**Total: 41 tests, all passing.**

What these tests do **not** prove: that any Kotlin method does what the
Dart client expects on a real device. The channel tests run against a mock
MethodChannel with payloads transcribed from the Kotlin source; the
contract is compile-verified on both sides and unit-tested on the Dart
side, but the first end-to-end proof requires hardware (§3).

---

## 3. The 17 master test areas — status

From the master prompt's testing phase, mapped to `ARCHITECTURE.md` §9.

| # | Area | Status | Notes |
|---|---|---|---|
| 1 | First launch | **Requires real device** | Startup routing (F31: wizard-only until a recovery code exists) is implemented and the wizard is widget-tested, but the installed app's first-launch flow has never run anywhere. Why device: first launch exercises the real `MainActivity`/application startup, the native stores, and the Shizuku provider — none exist off-device. |
| 2 | Application initialization | **Requires real device** | Native initialisation (application class, cold-start `user_setup_complete` repair, store setup) is Kotlin-side and only compile-verified. |
| 3 | Shizuku installation detection | **Requires real device** | Detection is a `PackageManager` check for `moe.shizuku.privileged.api` plus the Dart-side state parsing, which **is** unit-tested (all five states). The package check itself needs a device with/without the Shizuku manager installed. |
| 4 | Shizuku service status detection | **Requires real device** | Status comes from `Shizuku.pingBinder()` against a live Shizuku server. No server exists in this environment; **device-unverified**. |
| 5 | Permission request | **Requires real device** | `Shizuku.requestPermission(911)` and its result listener are implemented both sides; the system permission dialog and callback only exist on a device running Shizuku. |
| 6 | Permission authorization | **Requires real device** | Same as #5 — grant flow is user interaction with the real Shizuku manager. |
| 7 | Permission denial | **Requires real device** | Denial handling and UI states are implemented (five distinct Shizuku states in the setup wizard); the denial path itself is untriggerable without a device. |
| 8 | Shizuku connection | **Requires real device** | Binder acquisition via `ShizukuProvider` happens in the app process on a device. **Device-unverified.** |
| 9 | Binder communication | **Requires real device** | The highest-risk item in the project: the binder-wrapped `DevicePolicyManager` path (`ShizukuBinderWrapper` + reflection into `DevicePolicyManager.mService` + HiddenApiBypass hidden overloads) is Android-version-fragile by construction and has **never executed** outside compilation. It is spike #1 in `ARCHITECTURE.md` §10 and gates all provisioning claims. |
| 10 | Every implemented system operation | **Requires real device** | Each DPM operation (hide/suspend/uninstall-block, user restrictions, managed restrictions, private DNS), `WRITE_SECURE_SETTINGS` grant, and accessibility enablement is implemented and compile-verified, and the Dart client is unit-tested against transcribed payloads — but no operation has executed against a real `DevicePolicyManager`. Partially covered here only at the Dart/domain level (§2). |
| 11 | Service disconnection | **Requires real device** | Behaviour on Shizuku server death (binder death, `pingBinder()` going false, UI state transitions) needs a running server to kill. Implemented states exist; the transition is untested. |
| 12 | Authorization revocation | **Requires real device** | Revoking Dominanter's permission in the Shizuku manager and observing the app degrade honestly (never fake success) requires a device. |
| 13 | Unsupported Android versions | **Not yet** | Pre-V11 Shizuku and below-minSdk behaviour are handled in code (pre-V11 hard-fail state; `minSdk 30`), but no emulator or device matrix has been run. Emulator work does not strictly need hardware, but no emulator exists in this environment either; left as Not yet rather than Verified. |
| 14 | Application lifecycle changes | **Not yet** | Dart-side timer models are unit-tested (pause/resume, session expiry by clock), but process death / reboot behaviour is a known limitation: forced-removal and impulse accounting advance only while the app process is alive, and focus has no native foreground service in v1 (see `IMPLEMENTATION_STATUS.md` §6). On-device lifecycle testing has not been done. |
| 15 | Error handling | **Verified here** *(Dart level only)* | Channel error taxonomy is unit-tested: `SHELL_FAILED` preserves exit code/command/stderr, `DPM_NOT_OWNER` maps distinctly, a missing native side surfaces as `UNAVAILABLE` — never a fabricated success. Native-side error behaviour on a real system is part of #10 and remains device-unverified. |
| 16 | UI responsiveness | **Not yet** | Screens are widget-tested for the critical gates only. No performance profiling, frame-timing, or large-app-list stress test has been run; "responsive" is currently a design property (Material 3, loading/empty/error states on every screen), not a measured one. |
| 17 | Data persistence | **Verified here** *(partial)* | Round-trips are unit-tested at the Dart/domain level (focus config JSON, time-limit/windows/groups channel payloads, recovery/session models). Native `SettingsStore`/`RecoveryStore` persistence across process death and reboot is **not** verified — that part requires a device and is included in #14's gap. |

### Explicitly device-unverified (do not upgrade without a device report)

- Shizuku binder connection, permission grant/denial/revocation, and
  server-disconnection behaviour.
- Device Owner provisioning — **both** paths: the binder-wrapped DPM
  reflection path and the `dpm set-device-owner` shell fallback — and
  Device Owner removal.
- Accessibility Service enablement via Shizuku, runtime blocking
  (words, time limits/windows), and the **accessibility-loss lockdown
  (F28)**. F28 is fail-closed and hard to undo casually: it must be tested
  **first, on a sacrificial device**.
- Every DPM effect (hide/suspend/uninstall-block, restrictions, private
  DNS) and the `WRITE_SECURE_SETTINGS` grant.

### Not yet done at all (not hardware-blocked)

- Kotlin instrumentation tests for the channel contract.
- Emulator compatibility runs (unsupported versions, lifecycle).
- UI performance/responsiveness measurement.
- A real release keystore and a signed, publishable release build.

---

## 4. Build verification notes

The sandbox build failures recorded in `build_logs/` were environmental,
not project defects: the egress tunnel drops TLS ClientHellos without ALPN
`http/1.1` (which Java/Gradle never send) and intercepts Java TCP sourced
from non-loopback addresses. The working recipe — `preferIPv4Stack` for
all JVMs, a loopback TLS-terminating relay that re-originates TLS with
ALPN, a JVM truststore of JDK cacerts + the relay CA, and a persistent-
workspace JDK 21 + `GRADLE_USER_HOME` — is codified in `build_apk.sh` and
root-caused in `build_logs/README.md`. On a normal developer machine,
`flutter build apk --debug|--release` is expected to work directly; the
relay ceremony is specific to this sandbox.
