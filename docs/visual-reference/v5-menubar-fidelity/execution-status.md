# V5 menubar fidelity execution status

- Branch: `codex/v5-menubar-fidelity`.
- Baseline: `551e647d0a6fe6a6e9790bad87a96249cafe0689` ("remove the quota
  fill's white top bevel"), the tip of the previous
  `codex/glass-spectrum-motion-visibility` work. `main` is older and was not
  used as a starting point.
- Worktree: `/Users/lingsmbp/.codex/worktrees/v5-menubar-fidelity/ai-underlay`.
- Plan: `docs/superpowers/plans/2026-10-16-v5-menubar-fidelity.md`.

## Reference route

The browser refuses `file://` navigation, so the V5 lab was **not** opened
this round. Everything below is a V5 source/parameter comparison:
`docs/visual-reference/AIUnderlay-Glass-Material-Lab-v5.html` (canvas
`repaint()`) against `docs/visual-reference/glass-experiment-v5-selected.json`
(blur 17, ambient 0, grain 0, density 100, quota 100, theme strength 100,
speed 48). `v5-reference-rasteriser.py` is a verbatim port of the lab's
canvas; it reproduces the real native frames to within 0.003 mean alpha, so it
is trustworthy for full-sequence analysis. **No new browser screenshots
exist.**

## Phase status

| Phase | State | Evidence |
| --- | --- | --- |
| A baseline | done | `build/v5-menubar-fidelity/before/curtain/` (32 PNGs) plus the gap table below |
| B rays and light field | done | `build/v5-menubar-fidelity/after/curtain/` (32 PNGs), 2 new tests |
| C glass/quota/attention | not started | renderer read and `551e647`'s de-white-edge work confirmed intact; V5 `.zone .quota` CSS not yet reconciled against the native quota renderer |
| D validation | partial | full suite 427 passed / 2 skipped, domain purity OK, `git diff --check` clean; Debug build and preview dump still to re-run |
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
./Scripts/test.sh -derivedDataPath build/DerivedData        # 427 passed, 2 skipped
./Scripts/check-domain-purity.sh                            # OK
TEST_RUNNER_V5_FIDELITY_DUMP=1 \
TEST_RUNNER_V5_FIDELITY_OUTPUT="$PWD/build/v5-menubar-fidelity/verify2/curtain" \
  ./Scripts/test.sh -derivedDataPath build/DerivedData \
    -only-testing:AIUnderlayKitTests/V5FidelityDumpTests  # 32 PNGs, byte-identical to after/
git diff --check                                            # clean
```

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
