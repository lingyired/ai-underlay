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

Not yet measured: matched-fixture CPU/RSS/GPU/WindowServer deltas against the
fidelity-fix build, and long-run cache behaviour on a real multi-display setup.
The capture machine was locked, so no live menu-bar recording accompanies this
pass yet.

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
