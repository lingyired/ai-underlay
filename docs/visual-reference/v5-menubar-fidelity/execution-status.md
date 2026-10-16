# V5 menubar fidelity execution status

- Branch: `codex/v5-menubar-fidelity`.
- Baseline: `551e647d0a6fe6a6e9790bad87a96249cafe0689` ("remove the quota
  fill's white top bevel"), the tip of the previous
  `codex/glass-spectrum-motion-visibility` work. `main` is older and was not
  used as a starting point.
- Worktree: `/Users/lingsmbp/.codex/worktrees/v5-menubar-fidelity/ai-underlay`.
- Plan: `docs/superpowers/plans/2026-10-16-v5-menubar-fidelity.md`.

## Reference route

Two references are used, and the report says which one any number comes from:

1. **Rendered lab.** Headless Chrome renders the V5 lab to PNG, which is what
   the Phase C numbers below compare against:

   ```bash
   "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless \
     --hide-scrollbars --force-device-scale-factor=2 --window-size=1440,1100 \
     --virtual-time-budget=6000 --screenshot=/tmp/lab-full.png \
     "file://$PWD/docs/visual-reference/AIUnderlay-Glass-Material-Lab-v5.html"
   ```

   The Aurora scene's menu bar lands on rows 872…938 at 2x; the left zone is
   `x 320…1440`. That is a **headless browser render**, not a screenshot of
   the native bar.
2. **Source/parameter port.** `AIUnderlay-Glass-Material-Lab-v5.html` (canvas
   `repaint()`) against `glass-experiment-v5-selected.json` (blur 17, ambient
   0, grain 0, density 100, quota 100, theme strength 100, speed 48), with
   `v5-reference-rasteriser.py` as a verbatim port of the lab canvas; it
   reproduces the real native frames to within 0.003 mean alpha.

The earlier note that "the browser refuses `file://`" applied to an in-app
browser panel; the Chrome binary renders the same file without trouble.

## Phase status

| Phase | State | Evidence |
| --- | --- | --- |
| A baseline | done | `build/v5-menubar-fidelity/before/curtain/` (32 PNGs) plus the gap table below |
| B rays and light field | done | `build/v5-menubar-fidelity/after/curtain/` (32 PNGs), 2 new tests |
| C glass/quota/attention | partial | the scrim / tier-alpha / `mix-blend-mode` reconciliation is done and measured (see Phase C below); softness 0/17/32, ambient 0 / grain 0, stacked order and the white-theme case are still open |
| D validation | partial | full suite 431 passed / 3 skipped, domain purity OK, `git diff --check` clean, Debug build re-run; `GLASS_PREVIEW_DUMP` matrix and live capture still to re-run |
| E deliverable | in progress | this file + `review.md` |

## Phase A → B gap table (30 pt lane, 2x, normalised phase)

| phase | V5 mean ink | native before | native after | before corr | after corr |
| --- | --- | --- | --- | --- | --- |
| 0.00 | 0.232 | 0.143 | 0.177 | 0.14 | 0.72 |
| 0.25 | 0.252 | 0.162 | 0.192 | 0.45 | 0.88 |
| 0.50 | 0.257 | 0.174 | 0.198 | 0.89 | 0.93 |
| 0.75 | 0.254 | 0.167 | 0.207 | 0.56 | 0.89 |

Correlation is the column-profile correlation against the V5 port. The
remaining ~0.055 ink gap is the deliberate `baseAlpha` 0.17 versus the lab's
0.22 (the lab paints over its own dark wallpaper, the lane sits over the
system menu bar's bright material).

## Phase B changes

| Root cause | Fix |
| --- | --- |
| Wave B ran 2 turns per loop = 1.67 lane-widths/cycle vs V5's 0.68 | `waveBTurnsPerLoop` 2 → 1 (drift 0.49 / 0.83, lab 0.61 / 0.68) |
| No crest radius cap, so a wide lane spread its light | `maximumFocusRadius = 205` + `focusRadius(forWidth:)` |
| Glow used the Acrylic stops | Aurora stops 0.28 / 0.14 |
| Crest swept 1.5 laps/cycle and left the lane | `travelLeadFraction` 0.25 → 0 (one exact lap, 1.42x seam step vs 2.27x before, lab's own 3.46x) |

Height/alpha budget moved to the lab's `0.22 + 0.52·crest + 0.28·focused`,
`0.17 + 0.28·crest + 0.42·focused`, ceiling 0.94. The core sprite base stays
at 0.76: the "white column" look was a dim halo around a correct core, so the
curtain body was raised instead of the core re-tinted.

## Commands run this round

```bash
xcodegen generate
./Scripts/test.sh -derivedDataPath build/DerivedData        # 431 passed, 3 skipped
./Scripts/check-domain-purity.sh                            # OK
TEST_RUNNER_AURORA_ALIGN_DUMP=1 \
TEST_RUNNER_AURORA_ALIGN_OUTPUT="$PWD/build/aurora-align-after" \
  ./Scripts/test.sh -derivedDataPath build/DerivedData \
    -only-testing:AIUnderlayKitTests/AuroraAlignDumpTests  # 15 lane PNGs incl. before/after pair
TEST_RUNNER_V5_FIDELITY_DUMP=1 \
TEST_RUNNER_V5_FIDELITY_OUTPUT="$PWD/build/v5-menubar-fidelity/verify2/curtain" \
  ./Scripts/test.sh -derivedDataPath build/DerivedData \
    -only-testing:AIUnderlayKitTests/V5FidelityDumpTests  # 32 PNGs, byte-identical to after/
git diff --check                                            # clean
```

## Phase C: the grey film (measured)

The complaint was "灰蒙蒙的 / 没那么通透". It was not the rays — it was a
half-black scrim the curtain put over the whole fill, plus two smaller
attenuations. Measured on a 1712 pt / 98.7 % / 60.8 % lane at 2x against the
headless Aurora render (region means, 8-bit; inner = 6…34 % of the lane,
outer = 62…74 %):

| variant | inner fill | Δ vs lab | outer fill | Δ vs lab |
| --- | --- | --- | --- | --- |
| V5 lab (mirrored) | 110, 149, 196 | — | 92, 113, 163 | — |
| before (`3e51f0f`) | 81, 128, 156 | −29, −21, −40 | 31, 58, 70 | −61, −55, −93 |
| scrim fixed, old tier alphas | 99, 159, 195 | −11, +10, −2 | 37, 71, 88 | −55, −42, −75 |
| tier alphas fixed, old scrim | 81, 129, 157 | −29, −20, −39 | 47, 83, 102 | −44, −30, −61 |
| screen blend removed only | 93, 155, 192 | −17, +6, −4 | 49, 95, 120 | −43, −18, −42 |
| **after (all three)** | **100, 160, 196** | **−11, +11, −0** | **57, 102, 126** | **−35, −11, −37** |

So the inner fill now matches the lab in blue (196 vs 196) and is slightly
brighter in green. What moved the number:

| Cause | Fix |
| --- | --- |
| 0.45-alpha **black scrim** over the bottom 82 % of every fill | replaced by V5's own `.zone .sheen`: `#08162a1f`, transparent below 76 %, no white top line (`551e647` de-white-edge stays honoured) |
| Tier ladder applied **twice** — the palette darkens the colour *and* the gradient lowers its alpha | `applyFillGradient(tierFactor:)` divides V5's alphas by the tier's own brightness, so the rendered ladder matches V5 while the palette keeps its promise |
| Tint painted **over** the fill instead of `screen` | `compositingFilter = "screenBlendMode"` on `tintBloom` / `tintLinear` / `tintHalo`, matching V5's `mix-blend-mode: screen` |

The remaining outer-tier gap (−35, −11, −37) is V5 painting one hue at two
alphas while our outer tier is a *darker colour*: at the same rendered ink the
neighbouring inner tier glows through in the lab, and our nested fill is
opaque. Left open deliberately — closing it means giving up the
outer-darker-than-inner ladder that `551e647` and the earlier motion work
established as the product's reading rule.

### Honesty note on the live capture

The macOS screen locked (screensaver active, `screenSaverRunning == true`)
partway through this round, so **no valid live menu-bar capture of the fixed
build exists**. The five paired captures taken before the lock show it, and
every capture after it is the screensaver, not the bar. The numbers above are
the offline renderer's own output and the headless lab render; neither is a
claim about the real composited bar.

## Open items

- Phase C: reconcile the remaining glass/quota/attention numbers with the V5
  `.zone .quota` and `.glass-tint` CSS, then verify softness 0/17/32 and the
  selected ambient 0 / grain 0 actually disable their contributions.
- Phase D: re-run the Debug build and the `GLASS_PREVIEW_DUMP` matrix, and
  re-measure `SpectrumFrameCache.cachedByteCount` with the wider spans.
- Phase D: live menu-bar capture (fixture-driven) using the reviewed
  `live-capture.sh` backup/restore wrapper; the machine was unlocked earlier
  this round but no live capture has been taken yet.
- Nothing has been pushed, merged, or released. The commit is local only.
