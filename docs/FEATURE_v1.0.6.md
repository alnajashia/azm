# Azm v1.0.6 — Feature Report

Everything new in v1.0.6 beyond the audit fixes (which are covered in
`docs/CODE_AUDIT_v1.0.5.md`): content inspection (Phase B), app-lock
timing (Phase C), seal rules (Phase D), the 24-hour forced-removal
directive, plain-language errors (Phase E), and UI items 8–12.

## Phase B — Content inspection (from the original's spec)

### Spec extracted from the original implementation

Read end-to-end from the original's accessibility service, its visual
blocking settings model, its detector, and its settings screen:

- **Settings:** master enable (default off); target packages (default:
  Reddit only); categories (default: hentai, porn, sexy — selectable:
  every model label except neutral); confidence threshold (default
  0.5); optional escalation (default off): 5 detections within
  15 minutes suspend the app for 30 minutes.
- **Capture:** the model warms up when a target package comes to the
  foreground. Scans trigger on window-content changes, throttled to
  one per 2 seconds, never overlapping. **Media regions are located
  first** in the accessibility node tree — by view-class keywords
  (image/photo/video/media/player/gif/texture/surface/web view), by
  content-description/text keywords in both English and Portuguese,
  by Reddit post-card patterns, and by a geometric fallback (leaf
  node, no text, ≥ 96 dp, aspect ratio 0.4–3.0, at most 5 candidates).
  A screenshot is taken **only when at least one region exists**; each
  region is cropped and classified separately.
- **Model:** 224×224 RGB float32 in [0,1]; labels
  `[drawings, hentai, neutral, porn, sexy]`; the unsafe score is the
  sum of the *selected* categories' scores; a region blocks when its
  score exceeds the threshold.
- **Reaction:** the app is suspended and immediately un-suspended (a
  pulse that throws the user out), the blocked screen is shown, and
  the incident is logged. Under escalation, the suspension is *held*
  for the configured duration instead; held suspensions survive
  service restarts (persisted deadlines, restored on reconnect) and
  releasing one app never releases an app held by a different feature.
- **Text checking** in the original is its per-app banned-word
  blocking over accessibility node text — which this codebase already
  implements (word blocking); the settings screen therefore exposes
  image inspection as its own feature and does not fake a second text
  toggle.

### Model provenance and license

The original ships `nsfw_model.tflite` (17,355,548 bytes). That file
is **byte-identical** to `saved_model.tflite` from the official
**GantMan/nsfw_model v1.2.0** release. The nsfw_model project is
**MIT-licensed**, and its README expressly invites product use with
attribution. The copy bundled here was taken from the official
release — not extracted from the original app — and the app ships the
attribution and license text alongside the model
(`NSFW_MODEL_NOTICE.txt` in the app assets). Before bundling, the
model was exercised offline with the LiteRT runtime: input
`[1, 224, 224, 3]` float32, output `[1, 5]` probabilities summing to
1.0, sensible scores on synthetic inputs.

### Implementation and deviations

- Inference and capture live in the **Kotlin accessibility service**;
  Dart only carries settings across the channel. The runtime is
  LiteRT (`com.google.ai.edge.litert:litert`), the same runtime the
  original uses. The model file is stored uncompressed so it can be
  memory-mapped. Screen content **never leaves the device** — there
  are no network calls with screen content anywhere in this feature.
- Settings live in the app's own native preferences (same keys and
  defaults as the original), so the accessibility service reads them
  without depending on the Flutter engine being alive.
- Deviation (documented): the original's held-suspension release
  consults every blocking feature's claims including impulse holds;
  here the release guard consults the focus session store's claims.
  The impulse-lock path holds apps through a different mechanism and
  never releases another feature's suspension, so the observable
  behaviour matches; the difference is internal bookkeeping only.
- Deviation (scope): the original's service also performed unrelated
  duties (usage warnings, word blocking, lockdown) that this codebase
  already implements separately; only the visual-blocking behaviour
  was ported in this phase.

### Verification limits (honest)

Verified here: the settings/logic units in Dart (defaults, clamps,
gate classification), the model file's identity and offline inference
sanity, the Kotlin compile, and the model's presence in the built
APK. **Not verified here: actual detection on real content, on a real
device** — screenshot capture, region finding against real apps, and
the suspend reaction require a physical device and remain
device-unverified.

## Phase C — App-lock timing

WhatsApp-style entry grace (Immediately / 1 minute / 15 minutes /
1 hour; default Immediately). Persisted wall-clock unlock timestamp;
future timestamps clamp to expired; failed attempts never start a
grace; a 3-second transient debounce prevents biometric-prompt and
system-dialog relock loops. The grace governs the app-entry gate
only — the recovery session and sensitive-action gates are unchanged.
Lengthening is gated by the recovery session; shortening is free.
Decision logic is unit-tested (per-option elapsed comparison, clamp,
no-grace-on-failure).

## Phase D — Seal rules

User-defined rules that make Azm refuse its own removal:

- **Condition seals** (hold while true, probed live and natively at
  attempt time): a chosen app is uninstall-blocked or hidden; a
  chosen app is suspended; a focus session is running.
- **Event seals** (hold for a chosen duration — 30 min, 1 h, 6 h,
  24 h, 7 days): content inspection detects an inappropriate image in
  a chosen app; a banned word is detected in a chosen app. Timing is
  anchored to `elapsedRealtime` (clock changes cannot shorten a
  seal), with the wall-clock deadline kept as a post-reboot fallback.
- **Enforcement is native:** the removal handler refuses while any
  seal is active and returns a typed refusal carrying the responsible
  rule and remaining time, which the UI renders in plain language.
  Filing the delayed forced removal is likewise refused while sealed;
  a countdown filed *before* a seal still executes at its 24-hour
  mark (this is stated in the seal UI copy).
- **Gates:** adding a rule or lengthening a duration is free;
  disabling/deleting a rule or shortening a duration requires the
  recovery session. An active seal can never be cancelled from the
  UI, and the paper code does not break it — both stated in the copy.
- **Honest limit (in the UI and here):** seals have teeth only while
  Azm is Device Owner; without it, Android allows uninstalling any
  app and no in-app rule can prevent that. Rules created while not
  owner are marked unenforceable.
- Tests pin the Dart-side rule logic (gate classification, native-name
  mapping, remaining-time formatting). Native refusal is verified at
  compile/inspection level and is device-unverified.

## 24-hour forced removal (directive)

The delayed forced removal delay is 24 hours everywhere in this
product (the original used 48 — this is a deliberate user-directed
deviation). One native constant is the source of truth; Dart binds
the value reported in the native state at startup. Elapsed-realtime
anchoring and the boot/process re-checks are unchanged.

## Phase E — Plain-language errors, centered Card

All user-visible errors are typed codes mapped by a single Dart-side
mapper to localized plain-language messages (Arabic and English),
with technical detail confined to a local debug log. Presentation: a
centered modal Card over a dimmed scrim, high-contrast in both themes
(white card / near-black text in light; near-black card / white text
in dark), red accent, explicit OK button, never auto-dismissed, never
dismissible by tapping outside. Short confirmations remain lightweight
but meet the same contrast bar. The mapper contract, the Card
presentation, and a ban on raw-error interpolation into UI text are
all pinned by tests.

## Items 8–13 — UI polish

- **Item 8:** in-app logo halved (lock screen 80 dp → 40 dp) with more
  surrounding whitespace; launcher icons untouched.
- **Item 9:** all UI icons unified to the outlined style; active
  states use the red accent, not filled glyphs; a source-scan test
  guards the rule. **0** filled references remain outside item 10's
  exception.
- **Item 10:** one documented corner-radius scale (16 / 20 / 28 /
  pill) across cards, dialogs, buttons, fields, sheets, chips, menus;
  the Apps search field is a pill with the “include system apps”
  toggle inside it as a trailing button — outlined when off, filled
  when on, the user's single explicit exception to item 9.
- **Item 11:** the header is a minimal brand row (small logo + name,
  no actions); session controls moved to a titled “Recovery session”
  card below the header, same handlers and gates, visible only while
  a session is active.
- **Item 12:** plain-language explanations for all **74** catalog
  restrictions in Arabic and English, from one shared source keyed by
  restriction id, shown via an info button in the Phase E centered
  Card; viewing is ungated; a test pins total bilingual coverage.
- **Item 13:** the Restrictions screen's not-provisioned card now
  switches to the Config tab instead of opening setup as a pop-up
  page; the pop-up path is removed, the card text is unchanged, and
  the navigation is ungated.
