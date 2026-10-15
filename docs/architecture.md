# Architecture

## Environment (recorded at P0)

| Item | Value |
|---|---|
| macOS | 27.0.0 (Darwin 27.0.0) |
| Xcode | 27.0 (27A266a) |
| Swift | 6.4 (swiftlang-6.4.0.34.1) |
| Architecture | Apple Silicon (arm64) |
| Project generator | xcodegen 2.x (`project.yml`) |
| Deployment target | macOS 14.0 |

## Target layout

```text
AIUnderlayKit.framework   # all logic: Domain / Data / Agent / Overlay / Application
AIUnderlay.app            # thin SwiftUI shell (LSUIElement), owns Info.plist
AIUnderlayKitTests        # unit tests against the kit (headless)
```

Rationale for the framework split: tests run without launching a GUI, and the
dependency direction (`Domain ← everything`) is enforced by module boundary —
`AIUnderlayKit` cannot accidentally pull in the app shell.

## Dependency rules (hard)

1. `Domain/` must not import `AppKit`, `SwiftUI`, or any data-source type.
2. `Overlay/` must not reference `Data/CodexBar/*`. The overlay consumes only
   `LaneRenderSpec`: geometry + quota windows + resolved colours, nothing else.
3. All layers depend inward on `Domain`; `Domain` depends on nothing but `Foundation`.

`Scripts/check-domain-purity.sh` enforces rule 1 in CI/pre-commit.

## Glass Spectrum (the single visual engine)

The overlay has exactly one effect engine. Everything a lane shows is built
from three renderers over one stable layer tree:

```text
laneHost
├── quotaGlass        bed (used-up black / neutral groove) + nested fills + tint + caps
├── spectrum          static scrim + one frame-sequence ray curtain
├── attention         wash + glow + bottom ribbon (+ glint sweep) + 2pt top line
└── baseline          pace marker, always on top
```

- `LaneContent` (coordinator payload) → `LaneRenderSpec` (geometry + content) →
  `GlassLayerHost.update(_:)`. Named slots are found and mutated in place, so a
  quota refresh, a theme hot-reload, or a repeated identical render never
  rebuilds the tree and never restarts an animation. A 100× repeat keeps layer
  identity and `animationStarts` at 1 (test: `GlassLayerHostTests`).
- Per-lane continuous animation budget: the curtain is **one** layer, plus the
  attention band's own layers and optional ambient drift (`≤4`, test
  `test_animatedLayerBudget_isSmall`). Ray density changes pixels inside the
  cached bitmap, never the number of layers. Diagnostics recurse through masks.
- Motion is Core Animation only. `SpectrumWaveModel` samples every ray at a
  phase, `SpectrumFrameRasteriser` turns one phase into one bitmap, and the
  renderer plays `SpectrumFrameCache`'s phase sequence with a discrete
  `contents` keyframe animation, so the wave swaps frames inside the render
  server with no per-frame CPU work and no timer. A 0.70 Hz cycle over 16–24
  frames is 11–17 fps — deliberately the V5 lab's cadence ("the amplitude
  change, not a high framerate, makes Running recognizable"), not 60 fps.
  Reduce Motion keeps the static layout and drops every animation.
- The frame cache is an LRU bounded in **bitmap bytes** (16 MiB), not entries:
  a wide single-bar lane costs ~983 KiB per frame, so the budget is what keeps
  the sequence from becoming a permanent allocation. Ray sprites are cached
  per (kind, colour, scale) and stamped; a frame is a few hundred blits.
- Tempo is part of the spec, not a global: `LaneRenderSpec.spectrumFloorHz`
  carries the user's baseline (settings → coordinator → spec) into
  `SpectrumRhythm.cycleDuration(outputTPS:floorHz:)`. The default floor is
  0.70 Hz (≈1.4 s/cycle); the floor is clamped to 0.15–1.10 Hz, and a change
  re-times the running curtain on the next render instead of waiting for the
  old cycle to finish.
- Wave shape and tempo are separate inputs. `LaneRenderSpec.waveIntensity`
  (0.30–1.00, default 0.75) scales only the wave's modulation terms; measured
  output speed changes the rhythm and nothing else, so a fast model cannot
  brighten or flatten the curtain.
- `showTravelingLight` is a spec flag, not a global switch: with it off the
  crest parks at the lane centre and the ray wave keeps propagating, so a
  running lane is still visibly in motion. The attention sweep is a separate
  flag (`showsAttentionSweep`) with its own per-kind tempo.
- Priority is a code constant, `Error > Waiting > Unread > none`; Running is an
  independent boolean. A running lane wears the highest attention colour.

### Glass = rendered, not sampled (decision D1)

The default path deliberately does **not** use `NSVisualEffectView` or any
desktop-backdrop sampling. The V5 look is reproduced with layered gradients,
pre-rendered ray textures, and the black quota bed — which keeps the overlay
cheap, screenshot-stable and free of extra permissions. `blurRadiusTarget`
controls cached halo softening in device pixels; the UI calls it material
softness, not desktop blur. Its stored name and 0–32 range remain compatible.
The limited native-material probe and remaining 30-minute/hardware validation
are recorded in `visual-reference/glass-fidelity/blur-spike.md`.

Evidence for the rendered look: `docs/preview/glass-spectrum/*.png`, produced by
`GlassPreviewTests` at the real 30/32/34 pt menu-bar heights.

## Overlay window facts (from reference notes, to be re-verified on this machine)

- Window level = `CGWindowLevelForKey(.desktopIconWindow) + 1` (never hardcode 24).
- Menu bar height must be read from `CGWindowListCopyWindowInfo` at the
  `CGWindowLevelForKey(.mainMenuWindow)` level; `visibleFrame` returns 0 on
  non-primary displays.
- All overlay APIs are public — no SkyLight, no screen-recording permission.

## Upstream

- CodexBar CLI: detected at `/opt/homebrew/bin/codexbar` on this machine.
- CodeStatus: reference for hook/reducer design (MIT).
