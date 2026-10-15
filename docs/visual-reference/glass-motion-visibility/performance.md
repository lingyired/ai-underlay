# Motion-visibility performance notes — 2026-10-15

## Sequence build cost (main actor, one-off per size/colour/theme change)

Measured with a temporary probe running the real `SpectrumFrameCache.sequence`
path (macOS 27.0.1, Apple silicon, 30 pt lane, 2x):

| Lane width | Frames/cycle | Full sequence rebuild | Bitmap bytes (cached) |
|---:|---:|---:|---:|
| 512 pt (half of a dual lane) | 24 | 58 ms | 5.6 MiB |
| 1024 pt | 24 | 88 ms | 11.2 MiB |
| 2048 pt (single-bar) | 17 | 127 ms | 15.9 MiB |

Because the byte budget is fixed, a wider lane trades frame count (17) against
bytes (15.9 MiB); the rendered cadence stays at 0.70 Hz → 12 fps for a full
width bar and ~17 fps for a half-width lane.

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
