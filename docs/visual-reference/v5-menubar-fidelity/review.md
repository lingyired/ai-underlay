# V5 menubar fidelity — review (2026-10-16)

Branch `codex/v5-menubar-fidelity`, based on `551e647` (the tip of the
previous `codex/glass-spectrum-motion-visibility` work, not `main`).
Worktree: `/Users/lingsmbp/.codex/worktrees/v5-menubar-fidelity/ai-underlay`.

## What was wrong

The ray curtain did not look like the V5 lab's picture, for four reasons that
were all in the model, not in the colours:

1. **Wave B ran 2.4x too fast.** `waveBTurnsPerLoop` was `2`, i.e. 1.67
   lane-widths per cycle against the lab's 0.68. The curtain read as flicker
   rather than as a travelling wave.
2. **The crest had no radius cap.** V5 uses `radius = min(w * 0.28, 205)`; the
   native kernel grew with the lane, so on a wide bar the light spread out and
   the crest stopped being local.
3. **The glow used the Acrylic stops** (0.22 / 0.10) although the selected
   material is Aurora (0.28 / 0.14), which is why the travelling field looked
   weak next to the lab.
4. **The crest left the lane.** `travelLeadFraction = 0.25` moved it 1.5 laps
   per cycle, so at the loop seam the step changed the picture 2.27x more than
   a normal step — a visible hitch once per cycle.

The "glowing white column" was *not* a wrong core colour: the base ramp was
already V5-exact (white → tint·0.42 → `#f5faff`·0.76). What was missing was
the light around it, so the curtain body was raised instead.

## What changed

`AIUnderlayKit/Overlay/SpectrumWaveModel.swift`

- `maximumFocusRadius = 205`, `focusRadius(forWidth:)`,
  `focusSigmaFraction(forWidth:)`; `focus(...)` and `sample(...)` take the lane
  width (default `0` keeps the pure-math tests unchanged).
- `waveBTurnsPerLoop` 2 → 1. Drifts become 0.49 and 0.83 lane-widths per
  cycle — total 1.32 against the lab's 1.29, at the closest loop-closing
  integer pair.
- Height budget `0.22 + 0.52·crest + 0.28·focused` and alpha budget
  `0.17 + 0.28·crest + 0.42·focused`, ceiling 0.94 (lab: `0.22`, ceiling
  `0.96`). The deliberate −0.05 on the base alpha is documented in the file:
  the lab paints over its own dark wallpaper, the lane sits over the system
  menu bar's bright material.
- `travelLeadFraction` 0.25 → 0: exactly one lap per cycle. The focus kernel
  measures distance *around* the lane, so the wrap is continuous.

`AIUnderlayKit/Overlay/GlassSpectrumRenderer.swift`

- Aurora glow stops 0.28 / 0.14; the core sprite's base is now the literal
  `#f5faff` at 0.76 with a comment explaining why the base is not the bug.
- The renderer passes the lane width into `sample(...)` for the radius cap.

`AIUnderlayKitTests/OverlayTests/GlassSpectrumRendererTests.swift`

- Two new tests: `test_crestRadius_isCappedAtV5sMaximum_onWideLanes` and
  `test_waveDrift_matchesTheV5Lab_withoutBreakingTheLoop`.
- Two tests that pinned the old off-lane travel now pin the one-lap behaviour.

`AIUnderlayKitTests/OverlayTests/V5FidelityDumpTests.swift` (new, opt-in)

- Writes the curtain alone (no quota bed, no tint, no attention band) at
  30/34 pt, 1x/2x, phases 0/0.25/0.5/0.75, travelling and parked.

## Comparison (30 pt lane, 2x, normalised phase)

Reference is `v5-reference-rasteriser.py`, a verbatim Python port of the lab's
canvas `repaint()`. It reproduces the real native frames to within 0.003 mean
alpha, so the full-sequence numbers below are trustworthy.

| phase | V5 mean ink | native before | native after | corr before | corr after |
| --- | --- | --- | --- | --- | --- |
| 0.00 | 0.232 | 0.143 | 0.177 | 0.14 | 0.72 |
| 0.25 | 0.252 | 0.162 | 0.192 | 0.45 | 0.88 |
| 0.50 | 0.257 | 0.174 | 0.198 | 0.89 | 0.93 |
| 0.75 | 0.254 | 0.167 | 0.207 | 0.56 | 0.89 |

Ink is the mean alpha over the frame; correlation is the column-profile
correlation (where the light sits across the lane, not how bright it is).

Across one 24-step cycle the largest step is now 1.42x the median (was 2.27x;
the lab's own is 3.46x), so the seam hitch is gone.

Contact sheet and full matrices live in
`build/v5-menubar-fidelity/` (`before/curtain`, `after/curtain`, `reference`)
and are not committed.

## Status, honestly

- **Implementation**: phases A, B and the first half of C are done and
  committed. Phase C's remaining items (softness 0/17/32, ambient 0 / grain 0
  off verification, stacked order, the white-theme case) and Phase D's live
  menu-bar capture are **not** done.
- **Automation**: 431 tests passed, 3 skipped; domain purity OK; the curtain
  dump's 32 PNGs are byte-identical to `after/curtain`; the new
  `AuroraAlignDumpTests` writes 15 whole-lane PNGs including a measured
  before/after pair.
- **Real machine**: the screen locked mid-round, so there is **no valid live
  capture** of the fixed build. Every statement about the real bar here is
  offline renderer output.
- **Visual gap**: the inner fill now matches the lab (blue 196 vs 196); the
  outer tier is still 35/11/37 darker, because V5 separates its tiers by alpha
  over one hue while our outer tier is a darker *colour*.
- **Browser**: the lab **was** rendered this round, headless
  (`--headless --screenshot`), and the rendered PNG is the reference for the
  Phase C table. It is a headless browser render, not a native screenshot.
