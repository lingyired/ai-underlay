# Motion-visibility performance notes — 2026-10-15

## Sequence build cost (main actor, one-off per size/colour/theme change)

Measured with a temporary probe running the real `SpectrumFrameCache.sequence`
path (macOS 27.0.1, Apple silicon, 30 pt lane, 2x):

| Lane width | Frames/cycle | Full sequence rebuild | Bitmap bytes (cached) |
|---:|---:|---:|---:|
| 512 pt (half of a dual lane) | 24 | 58 ms | 5.6 MiB |
| 1024 pt | 24 | 88 ms | 11.2 MiB |
| 2048 pt (single-bar) | 16 | 120 ms | 15.0 MiB |

Because the byte budget is fixed, a wider lane trades frame count (16) against
bytes (15.0 MiB); at 0.70 Hz that is ~11 fps for a full-width bar and ~17 fps
for a half-width lane. The frame count is also rounded to a step of four and
capped at a nominal 18 fps, so dragging the tempo slider rarely rebuilds the
sequence (test: `test_frameCount_roundsToTheStep_soSliderDragsRarelyRebuild`).

The sequence is rebuilt only when size, scale, light colour, density, intensity
or travel mode changes — not on quota or session polls (test:
`test_sequenceIsCached_andRegeneratedOnlyWhenThePictureChanges`), and the LRU
caps total bitmap bytes at 16 MiB (test: `test_cacheBudget_isBoundedInBytes`).

## Continuous cost

Steady-state rendering is one `contents` keyframe animation on one layer per
lane; Core Animation swaps frames in the render server, so the app performs no
per-frame CPU work and runs no timer. The previous design kept 8–10 animated
transform/mask layers per lane.

## Matched-fixture CPU/RSS against the fidelity-fix baseline

Same machine, same display, same fixture (`bench-running` = `agentRunning`,
travelling light on, 0.70 Hz for the new build / 0.34 Hz floor for the old one),
45 one-second samples of the app process via `ps`, run through
`bench.sh`:

```bash
docs/visual-reference/glass-motion-visibility/bench.sh build/glass-motion/bench-new 45 bench-running
AIUNDERLAY_APP=/Users/lingsmbp/.codex/worktrees/glass-motion-baseline/ai-underlay/build/DerivedData/Build/Products/Debug/AIUnderlay.app \
  docs/visual-reference/glass-motion-visibility/bench.sh build/glass-motion/bench-baseline 45 bench-running
```

| Build | CPU mean | CPU p95 | CPU max | RSS mean | RSS max |
|---|---:|---:|---:|---:|---:|
| fidelity-fix baseline (`5040f53`) | 0.09 % | 0.70 % | 1.10 % | 129.8 MiB | 130.0 MiB |
| this branch (`2828899`) | 0.13 % | 0.60 % | 2.60 % | 158.1 MiB | 158.2 MiB |

Reading: steady-state CPU is unchanged in practice (both designs let the render
server play the animation; the app does no per-frame work). RSS is **+28 MiB**,
which is the price of the phase-sequence bitmaps — the new design caches 24
frames per lane instead of three static textures. The cache is capped at 16 MiB
of bitmap bytes by test (`test_cacheBudget_isBoundedInBytes`), so the delta is
bounded, not open-ended.

Not measured: attributed GPU/WindowServer cost, long-run cache behaviour on a
real multi-display setup, and wakeups.

## Timeline correctness (a cadence fact, not a performance number)

`timeline-probe.swift` measures how long each phase of the discrete `contents`
animation is actually presented. Before the fix the last of 24 phases was never
shown and the phase before the seam held for two steps; after it the full
sequence plays. Reproduce with:

```bash
swiftc -O docs/visual-reference/glass-motion-visibility/timeline-probe.swift -o /tmp/timeline-probe
/tmp/timeline-probe legacy 24 1.42857   # missing: [4, 12, 23]
/tmp/timeline-probe closed 24 1.42857   # full sequence
```
