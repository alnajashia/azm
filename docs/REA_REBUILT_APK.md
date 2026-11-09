# REA on the Rebuilt APK — Real Results

> **Date:** 2026-11-09 · **Tool:** REA (Reverse Engineer Anything) 6.8.0,
> CLI at `~/workspace/custom-connectors/custom.rea/app/node_modules/.bin/rea`
> **Target:** our own built `app-release.apk` (Dominanter v1.0.0) — the use
> case the original REA audit ([`REVERSE_ENGINEERING.md`](REVERSE_ENGINEERING.md)
> §5) identified as the legitimate one for this tool: a compiled Flutter
> APK, analysed by pure APK parsing.
>
> Every result below is real output from a command actually run on this
> machine. Raw JSON evidence is saved alongside this file in
> [`rea_rebuilt_apk/`](rea_rebuilt_apk/). Commands were checked with
> `rea --help` first; no command was invented. Blocked routes are reported
> as blocked — nothing is fabricated.

Target identity (confirmed independently by REA's own subject digest,
matching the build record):

| Property | Value |
|---|---|
| File | `build/app/outputs/flutter-apk/app-release.apk` |
| Bytes | 50,406,827 |
| SHA-256 | `c1bd2fa2ebc767ce296e830f5e1a2d864de7ec5cf82572fb527fc4f81a67103e` |

---

## 1. `identify-flutter-build` — ✅ succeeded (exit 0)

```bash
rea identify-flutter-build app-release.apk --json
# evidence_id ev_f899484e3acbcefd79b1209c21bc06742cc9a3dc0e07e5e990006451369743d8
# raw: rea_rebuilt_apk/identify_flutter_build.json
```

- `flutter_detected: true`, coverage `complete`.
- Dart snapshot hash (identical across all three ABIs, from 2 sources
  each): **`97ff04a728735e6b6b098bdf983faaba`**.
- Per-ABI `libapp.so` (present, valid ELF header) and `libflutter.so`
  (present, with build ID):

| ABI | `libapp.so` bytes | `libflutter.so` bytes | `libflutter.so` build ID |
|---|---|---|---|
| arm64-v8a | 5,702,576 | 11,036,664 | `e72fab63e41e9b8ee943d8a8e9cbab8b71aa013f` |
| armeabi-v7a | 6,292,060 | 7,926,664 | `c5a23af67225da6c688cd14a4ee184e8419e5f75` |
| x86_64 | 5,833,648 | 12,143,232 | `31065fb4a7e4ade6ccf1eef6ffaa187b86e107ad` |

- Engine toolchain line recovered from `libflutter.so`:
  `Android (12027248, +pgo, +bolt, +lto, +mlgo, based on r522817) clang version 18.0.1 (…)`.
- `dart_version: null` — REA did not recover a Dart version string from the
  binary; the project's Dart/Flutter version (Flutter 3.35.1 stable) comes
  from the build record, not from REA.

## 2. `inspect-dart-aot` — ✅ succeeded (exit 0)

```bash
rea inspect-dart-aot app-release.apk --json
# evidence_id ev_de00f99e215bfe3488d1ffbdef26d7a48e04c0c4234e7721d0a854cadcf1b5cf
# raw: rea_rebuilt_apk/inspect_dart_aot.json
```

Inspected the default ABI (`arm64-v8a`) `libapp.so` (5,702,576 bytes,
SHA-256 `b914ff849a4b36272929984000c53a95ff93e674a76a431659d10c45a037fec4`,
snapshot hash as above). Snapshot sections found:

| Section | Offset | Size | Magic valid |
|---|---|---|---|
| `_kDartVmSnapshotInstructions` | 2,097,152 | 92,464 | false (instructions sections carry no data magic) |
| `_kDartIsolateSnapshotInstructions` | 2,189,632 | 3,510,448 | false |
| `_kDartVmSnapshotData` | 832 | 18,240 | **true**, kind 3 |
| `_kDartIsolateSnapshotData` | 19,072 | 2,052,672 | **true**, kind 3 |

String pool (coverage `partial`) independently confirms the shipped Dart
code is this project's: it contains the `package:dominanter/…` URIs for
every Dart source file (`main.dart`, `app_controller.dart`,
`data/config_store.dart`, `data/privileged_channel.dart`,
`domain/challenges.dart`, `domain/focus.dart`, `domain/recovery.dart`, and
all `ui/*.dart` screens), alongside the expected `package:flutter/…` and
dependency (`characters`, `collection`, …) URIs. This is useful
supply-chain evidence: the release APK's AOT snapshot verifiably contains
the audited Dart sources, not a stale or substituted build.

## 3. `inspect-apk-signature` — ✅ succeeded (exit 0)

```bash
rea inspect-apk-signature app-release.apk --json
# evidence_id ev_fea8f2b7e888ddd03b99d7d090be35369f3517ba7b79535c520e4fc0009f6488
# raw: rea_rebuilt_apk/inspect_apk_signature.json
```

- Schemes: **v2 present**; v1, v3, v3.1 absent; no source stamp.
  Strongest scheme `v2`; posture `self_consistent: true`,
  `schemes_agree_on_signer: true`.
- Signer (exactly one): certificate subject/issuer
  `CN=Android Debug, O=Android, C=US`, serial `01`,
  SHA-256 fingerprint
  `8f1fddfcfe6633cc2b2838c64bbef43eae0c2a6c90f8591989b3bf14ba0b3200`,
  RSA key, validity 2026-11-09 → 2056-11-01.
- Declared content digest matches the APK (`matches_apk: true`).

This independently confirms, from the artefact itself, the fact stated in
[`TESTING.md`](TESTING.md) and
[`IMPLEMENTATION_STATUS.md`](IMPLEMENTATION_STATUS.md): **the release APK
is signed with the Android Debug certificate. It is not publishable** until
a real release keystore is created and the build is re-signed.

## 4. Routes that remain blocked — stated plainly

Both commands exist in REA 6.8.0 (verified in `rea --help`) and both were
run; both failed with `capability_unavailable` (exit 1) because their
backing tools are not installed on this machine. No output was invented
for them.

| Command | Exit | Real error (verbatim, abridged) | What's missing |
|---|---|---|---|
| `inspect-android-package` | 1 | `Set REA_JADX_MCP_JAR to the absolute path of a caller-supplied jadx-headless-mcp 0.7.1 JAR. REA does not download or install it.` (`provider_id: jadx`, `failure_code: not_configured`) | A caller-supplied JADX headless MCP JAR — and a Java runtime to run it. Neither is installed on this install (see the original audit). Raw: `rea_rebuilt_apk/inspect_android_package.json` |
| `decode-android-resources` | 1 | `The selected apktool launcher was not found: apktool. Set REA_APKTOOL_COMMAND to an absolute apktool launcher (the upstream wrapper or a java -jar script).` (`provider_id: apktool`) | apktool (not installed). Raw: `rea_rebuilt_apk/decode_android_resources.json` |

Consequences, honestly scoped:

- Class/method-level REA analysis of the APK (the JADX route:
  `inspect-android-class`, `search-android-classes`,
  `trace-android-references`, …) remains unavailable until Java + the
  JADX MCP JAR are supplied and the connector's `ALLOWED_TOOLS` gate is
  reviewed for them.
- Manifest/resource facts about this APK were instead verified with the
  Android SDK's own `aapt2 dump badging` (see
  [`TESTING.md`](TESTING.md) §1) — a first-party tool, not a substitute
  REA result.

## 5. Summary

REA's pure-parsing routes work on the rebuilt APK and produced three real,
independent verifications of the build: it **is** a Flutter build (with a
consistent Dart snapshot hash across ABIs), its AOT string pool contains
exactly this project's Dart sources, and it is **debug-signed under APK
Signature Scheme v2 only**. The engine-dependent routes (JADX, apktool)
remain blocked by missing tooling on this install, exactly as the original
audit predicted.
