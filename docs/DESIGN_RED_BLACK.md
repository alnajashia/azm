# Azm — Red & Black Design (v2, 2026-11-09)

Supersedes the red/blue/black identity of the first redesign, at the
user's explicit request: **red and black only**.

## Sources of inspiration (user-supplied images)

1. **Glossy red planes image** — layered deep-red gradient screens
   floating over a light-grey backdrop; pill-shaped red list rows;
   circular icon badges; an area chart filled with a red gradient;
   and a chunky 3D red timer ring with large white numerals («05»)
   on a dark-red disc.
2. **Pinterest pill bars image** — three floating capsule bars
   (white / red / black). This design fuses the red and black
   variants: an **always-black capsule** whose active destination
   sits in a **filled red swept indicator** with a white dot beneath
   its label.

## The palette (only two hues: red and black)

| Role | Value |
|---|---|
| Red (primary) | `#D90429` |
| Red bright | `#E5383B` |
| Red glow | `#FF2E4D` |
| Red dark | `#9E031E` |
| Red deep | `#5C0212` |
| Red deepest | `#2A0208` |
| Black background (dark) | `#0A0A0C` |
| Black pill bar | `#101013` |
| Black surface | `#141417` |
| Black surface high | `#1E1E23` |
| Black surface highest | `#2A2A31` |
| Light background | `#F4F4F5` (black tint) |
| Light surface | `#FFFFFF` (black tint) |

Rules:

- The only chromatic colour is red, in the single scale above.
  Everything else is black and its tints/shades (charcoals, greys,
  white for text/background legibility). **No blue anywhere** —
  the scheme's `secondary` role is black in light mode and a
  monochrome light tint in dark mode; `tertiary` stays in the red
  scale. A widget test (`Red/black identity: no blue-dominant
  colour anywhere`) scans both schemes, the shared palette and
  both hero gradients and fails if any colour turns blue-dominant.
- Red is reserved for CTAs, indicators, the timer ring and hero
  surfaces — never long body text (white on `#D90429` ≈ 5.9:1).

## What changed, component by component

| Component | File | Change |
|---|---|---|
| Theme / palette | `lib/theme.dart` | Blue scale (`#1D3557/#2563EB/#5B8DEF`) deleted entirely. Secondary = black/monochrome, tertiary = red scale. Card radius 16→20, dialog radius 24, pill-leaning filled buttons (radius 16). |
| Hero gradient | `lib/theme.dart` (`heroGradient`) | Dark: glossy red plane `#9E031E → #5C0212 → #12030A` (was red→black→blue). Light: red wash `#FFD9DE → #FFFFFF → #ECECEF` (blue wash removed). |
| GradientCard | `lib/ui/common.dart` | Radius 20→24, red hairline border in dark mode, extra red glow shadow, taller gloss highlight (46→56dp). |
| Pill navigation | `lib/ui/pill_nav.dart` | Bar is **always black** (`#101013`) in both modes (was white in light mode); inactive items use a fixed light-grey on black (the theme's near-black muted colour would be unreadable on the black bar in light mode); red under-glow shadow added; active indicator gradient gains the glow stop `#FF2E4D → #D90429 → #9E031E`. Swept clipper, white dot, destinations and behaviour unchanged. |
| Focus timer ring | `lib/ui/common.dart` (`FocusTimerRing`) | Break phase was **blue** — now dark red `#9E031E`; focus stays bright red. New black disc inside the ring (dark: black gradient; light: white→grey) with a red hairline rim and a soft red glow, echoing the reference's timer disc. |
| App comment | `lib/main.dart` | Identity comment updated to v2. |

No functionality, channel calls, domain logic, navigation structure,
Kotlin code or dependencies changed — this is a theme/widget-layer
redesign only, exactly like v1.

## Verification

- `flutter analyze` — 0 errors, 0 warnings (31 pre-existing `info`
  lints in untouched files remain; none in the redesigned files).
- `flutter test` — **43/43 passed** (41 previous, unmodified in
  behaviour, plus 2 new v2 tests: the palette guard and
  “pill nav bar is black even in the light theme”).
- Release APK rebuilt and verified on disk: 50,472,363 B,
  SHA-256 `38bf66b1a310635dfaba8ca40965d39996903775ac8164070009f7c11d928420`,
  refreshed into `project/release/azm-v1.0.0-release.apk`
  (copy hash verified identical to the build output). Supersedes
  the v1 redesign release hash `14017379…` for the current build.
  Debug APK was not rebuilt in this round.
- Not tested on a real device, as with every previous build.
