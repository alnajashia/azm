# Dominanter

A Flutter reimplementation of [DeChainer](https://github.com/warleysr/dechainer)
(v1.12.0) — a self-control / app-blocking app — with
[Shizuku](https://github.com/RikkaApps/Shizuku) used only for setup-time
privileged provisioning. Dart provides the UI and pure logic; all privileged
effects live in Kotlin behind a single MethodChannel.

> **Status (2026-11-09):** Dart UI implemented, `flutter analyze` clean
> (0 errors, 0 warnings), `flutter test` 39/39 passing. **No APK yet and no
> on-device testing yet** — the debug build is blocked in this sandbox by a
> Gradle plugin download failure (network gate intercepting Java TCP
> connections), not by project code. See
> [`docs/IMPLEMENTATION_STATUS.md`](docs/IMPLEMENTATION_STATUS.md) for the
> honest per-feature status (F1–F34).

## What it does

- **Device Owner provisioning** via Shizuku (binder DPM path, with a `dpm
  set-device-owner` shell fallback), including the `user_setup_complete`
  bypass/restore and a cold-start repair for a stuck flag.
- **App control:** hide / suspend / uninstall-block per app, per-app and
  per-group time limits, allowed time windows, reopen handling.
- **Restrictions:** system restrictions (draft/apply), per-app managed
  restrictions, browser URL blocklist + forced SafeSearch, forced family
  private DNS.
- **Blocking enforcement:** Accessibility Service with active/passive word
  blocking, suspension audit log, and accessibility-loss lockdown.
- **Self-control gates:** 16-character paper recovery code (stored as a
  salted PBKDF2 hash, never plaintext), a 10-minute recovery session,
  math / words / reading challenges before loosening a restriction,
  impulse lock, focus (Pomodoro) mode, and 48-hour delayed forced removal.
- **UI:** Material 3, light/dark themes, English/Portuguese (app chrome;
  per-screen Portuguese is partial — see the status doc).

Deliberately **not** ported: Play Store rating scraping, the unauthenticated
lock-screen APK installer, and the debug self-disable hatch. Deferred to
v1.1: the NSFW TFLite pipeline, Tetris challenge, colour modes, and
browser/torrent install-watchers. Features deferred to v1.1 appear in the UI
as explicitly labelled tiles, never as dead buttons.

## Architecture

```
Flutter / Dart (UI + pure logic)
        │  MethodChannel dominanter/privileged (+ events channel)
Kotlin (Accessibility Service, Device Owner manager,
        Shizuku provisioning, settings/recovery stores)
        │  Shizuku API 13.1.5 — setup time only
Shizuku → Binder → Android system services (DPM, PackageManager, Settings)
```

Full design, channel contract (25 methods), data model and security
deviations: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) (1,022 lines).
Per-feature status: [`docs/IMPLEMENTATION_STATUS.md`](docs/IMPLEMENTATION_STATUS.md).

Key point from the reverse engineering: Shizuku is **not** the runtime
engine. Once Device Owner is granted, day-to-day blocking runs on ordinary
in-process `DevicePolicyManager` calls and the Accessibility Service;
Shizuku is needed again only for setup, diagnostics/re-grants, and the
cold-start `user_setup_complete` repair.

## Requirements

| Requirement | Version / note |
|---|---|
| Flutter | 3.35.1 stable |
| JDK | 21 |
| Android SDK | platform 36; `minSdk 30` (Android 11), `targetSdk 36` |
| Application ID | `io.github.alnajashia.dominanter` |
| Shizuku | Manager app `moe.shizuku.privileged.api`, API/provider `13.1.5` |
| Device | A real Android device for any privileged test — **use a sacrificial device first**: Device Owner provisioning and accessibility-loss lockdown are hard to undo casually |

## Setup — install and run

1. Install the Shizuku manager app and start its service (via ADB or
   wireless debugging, as Shizuku documents).
2. Clone this repo and fetch dependencies:
   ```sh
   git clone https://github.com/alnajashia/dominanter.git
   cd dominanter
   flutter pub get
   ```
3. Build and install the debug APK:
   ```sh
   flutter run
   # or: flutter build apk --debug
   ```
   **Note:** a first build downloads the Gradle distribution and plugins;
   if your network blocks Java TCP connections to the Gradle plugin portal
   (as this sandbox does), the build fails in Flutter's own Gradle files
   before reaching project code. That is an environment issue, not an app
   bug — see `build_logs/` for the recorded failures.
4. In the app, follow the setup wizard: create and write down the
   16-character recovery code on paper, grant Shizuku permission, provision
   Device Owner, enable the Accessibility Service, and grant
   `WRITE_SECURE_SETTINGS` when asked. The wizard shows five distinct
   Shizuku states and diagnostics if anything fails.

## Permissions

- **Device Owner** (`dpm set-device-owner`) — app suspension, restrictions,
  managed restrictions, private DNS. Granted once, via Shizuku.
- **Accessibility Service** — word blocking, time-limit enforcement,
  accessibility-loss lockdown.
- **Shizuku permission** — setup-time shell/binder access only.
- **`WRITE_SECURE_SETTINGS`** (via Shizuku) — Accessibility enablement and
  colour-mode grant.
- **Biometric / device credential** (optional, via `local_auth`) — entry gate.

No root is used or required. No accounts, telemetry, or UsageStatsManager.

## Tests

```sh
flutter analyze   # 0 errors, 0 warnings (2026-11-09)
flutter test      # 39 tests, all passing (2026-11-09):
                  # recovery gate, 5-second undo window, session model,
                  # challenges, focus timer, channel error mapping, widgets
```

Kotlin instrumentation tests and real-device verification are **not yet
done** — nothing is marked "verified" until it has run on a device. The
new Kotlin channel methods added during the Dart UI stage (SettingsStore
save methods for limits/windows/groups/words) have not yet been
compile-verified by Gradle; that is the first thing the APK build checks.

## Known limitations (v1)

- No APK / no device testing yet (see Status above).
- Graduated usage-warning notifications are configured and stored but not
  yet fired from the native service.
- Focus timer has no native foreground service — the countdown runs while
  the app is alive.
- Weekly window editing from the UI is daily-only.
- Portuguese translation is partial (app UI only).

## Attribution and license

Dominanter is a clean-room Flutter reimplementation of DeChainer's verified
behaviour, not a copy of its source. Original projects:

- **DeChainer** by warleysr — https://github.com/warleysr/dechainer —
  Apache License 2.0.
- **Shizuku** by RikkaApps — https://github.com/RikkaApps/Shizuku —
  Apache License 2.0. Shizuku's own restrictions apply: do not reuse its
  launcher icons, the name "Shizuku", the applicationId
  `moe.shizuku.privileged.api`, or `moe.shizuku.manager.permission.*` for
  another app. Dominanter uses its own applicationId
  `io.github.alnajashia.dominanter` and its own Shizuku provider authority.

Licensed under the **Apache License, Version 2.0** — see
[`LICENSE`](LICENSE). Copyright 2026 Ahmed Mohammed Alnajashi.
