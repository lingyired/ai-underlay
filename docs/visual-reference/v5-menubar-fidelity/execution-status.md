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

### Phase C commit

The scrim / tier-alpha / `mix-blend-mode` work landed as `c662038`
("drop the grey scrim and blend the glass tint like V5"); the re-measured
lab comparison landed as `0e4eb59`. Both are local commits on
`codex/v5-menubar-fidelity` and neither has been pushed, merged or released.

### The rendered lab is NOT a pixel oracle for the fill

The headless lab render is a valid reference for *motion and light* (canvas
rays, light field, travel) but it cannot be used as a pixel oracle for the
quota fill. Its scene composites through `backdrop-filter` over a synthetic
wallpaper and its Aurora `.quota` rules are a *flat* horizontal hue ramp
(`#285c95 → #367ab2 → #254666`) — measured on the rendered PNG, the inner tier
is `[47,103,154]` at row 6 and `[47,103,154]` at row 60: a vertical delta of
**zero**. Our fill is a deliberate V5-fill vertical ramp (0.30/0.46/0.20 alpha
outer, 0.88/0.68/0.30 inner) because that is what the earlier rounds and
`551e647` established as the product's reading rule. Comparing region *means*
between the two therefore measures the chroma of two different renderers'
compositing stacks, not fidelity of the fill; per-column correlations between
the web band and the native lane are R 0.01 / G 0.38 / B 0.55 on the live
fixture.

What the numbers below *are* good for: (a) the native before/after delta, which
is measured on one renderer with one fixture and one phase, and (b) the
"no white top line" guard. The residual "native brighter than the web" figure
is expected and explained by the two facts above.

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

The lab column of this first table came from the **default-parameter** HTML
render and the crop the earlier session used. The re-measure below re-renders
the lab with the user's selected parameters at a frozen phase, which is the
number to quote for fidelity; this table stays as the attribution record
(which cause moved which channel).

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


### Re-measure, same fixture and phase this time

The table above compares the native lane against the lab render at *its own*
default parameters. Re-running it with the lab set to the user's selected
parameters and a frozen phase (`speed 48` → `hz = 0.4849`, `t = 0.35 / hz =
0.7217`), left zone `x 314…1440`, rows `869…938`, mirrored so the fill anchor
matches the native lane, rows 30…95 %:

| strip | inner 6…34 % | outer 62…74 % |
| --- | --- | --- |
| web Aurora (selected params, frozen phase 0.35) | 98, 139, 190 | 129, 148, 185 |
| native before `3e51f0f` | 88, 137, 167 | 33, 61, 75 |
| native after `c662038` | **99, 157, 191** | 60, 107, 131 |
| native after, curtain hidden | 85, 146, 181 | 48, 96, 120 |

So the inner tier's *blue* is now within 1/255 of the web render and its green
runs 18/255 lighter (the agent tint at full strength screens a cyan
`#007DAF`); the outer tier is still markedly darker, which is the deliberate
palette rule. White-top guard on the committed lane: the maximum
`min(R, G, B)` over the top two device rows is **206** — a neutral white line
would be ≥250.

## Phase C: remaining items, measured

| Item | Result |
| --- | --- |
| Softness 0 / 17 / 32 | the rendered inner tier moves with the token: codex 89,141,168 → 95,150,174 → 98,153,177 (`GLASS_PREVIEW_DUMP` matrix in `build/phaseC-after/`) |
| Ambient 0 | `tintAmbient` is hidden (`isHidden = ambientGlow <= 0.001`) and holds no animation; `test_ambientGlowZero_doesNotHideTheThemeTint` pins that the glass tint itself stays |
| Grain 0 | no renderer consumes `material.grain`; the stored value is 0, so it contributes nothing. A non-zero grain still has no native implementation — that gap is unchanged by this round |
| White theme (`#ffffff`, Claude) | the legibility ceiling resolves to 0.55 before the tint layers are multiplied, so a white theme cannot wash the menu text: measured inner 133,108,95 at softness 17 with the copper palette underneath |
| Stacked-layer order | bed → fills → tint clip → caps; the tint is clipped to the real outer fill length, so a 0 % lane keeps black and an unknown lane keeps its neutral groove |


## Phase D: live menu-bar capture (finally taken)

The display unlocked at 15:08 on 2026-10-16, so the missing capture exists
after all. The running app was PID 28292, launched at 14:50 from
`build/DerivedData/Build/Products/Debug/AIUnderlay.app` — the `c662038` build.
Capture method is `screencapture -x -D1 -v` (real WindowServer compositing, no
`CALayer.render(in:)` involved).

| Evidence | Path |
| --- | --- |
| Full 2048pt bar, 2x, 60 device rows | `live/live-c662038-full-bar.png` |
| Four frames 0.45 s apart, left 600 pt | `live/live-c662038-motion-contact.png` |
| 6.81 s recording, 57.3 fps, 390 frames | `live/live-menubar-c662038.mp4` |
| Live bar over the web Aurora zone | `contact-live-vs-web.png` |

Measurements from the recording (left provider region, device x 1149…2074,
rows 6…30, a text-free strip):

| Metric | Value |
| --- | --- |
| dominant temporal frequency | **0.734 Hz** |
| configured floor | 0.729 Hz |
| temporal std of the fill | mean 1.7 / p90 4.1 / max 13.1 (8-bit) |
| spatial std across the fill (curtain contrast) | 14.4 |

The 0.5 % agreement between the measured 0.734 Hz and the configured 0.729 Hz
floor is the useful number here: the curtain really is playing at the user's
saved tempo in the composited menu bar, not merely in the offline renderer.

### Before / after, same region, real bar

The user's 11:14 screenshot (`3e51f0f` build) and this 15:08 capture
(`c662038`) share one text-free interval, device x 1149…1994. Row means there:

| row (device px) | before `3e51f0f` | after `c662038` |
| --- | --- | --- |
| 0 | 59.6, 106.4, 134.6 | 69.9, 124.8, 172.6 |
| 16 | 65.2, 120.8, 154.9 | 67.4, 124.4, 171.9 |
| 28 | 66.3, 127.8, 164.2 | 67.6, 122.3, 167.6 |
| 48 | 77.8, 114.6, 139.1 | 72.5, 100.0, 124.5 |
| 56 | 73.4, 96.4, 112.2 | 64.9, 81.1, 95.6 |

The upper body gained 33–38 counts of blue — the grey film is gone in the
composited bar, not just offline. The 1 pt bottom edge is darker than before,
which is the V5 `.sheen` doing its job. White-top guard over that same
interval: **82** (`min(R, G, B)` max over the top two rows), so the menu bar
still carries no neutral white line.

## Open items

- Phase C: softness, ambient 0, grain 0, stacked order and the white-theme
  case are now measured (table above). What remains open there is grain as a
  feature: the parameter is stored and validated but no renderer draws it.
- Phase D: re-run the Debug build and the `GLASS_PREVIEW_DUMP` matrix, and
  re-measure `SpectrumFrameCache.cachedByteCount` with the wider spans.
- Phase D: live menu-bar capture is **done** (see the Phase D section). It was
  taken with the user's own settings, not a fixture, so the attention states
  (Error / Waiting / Unread) and the traveller-on case are still unverified on
  hardware.
- Nothing has been pushed, merged, or released. The commit is local only.

## Round 3 (2026-10-16): what the material does to a colour

The user's report: „我们的等待似乎都比较灰，少了一些亮度，然后我们的主要他颜色一号线也比较灰" —
the Waiting alert reads grey and dim, and the 2 pt top line with it.

### The controlled probe

`probe-material-transfer.sh <out-dir> [colour …]` repaints the waiting top line
in flat known colours through the production fixture path, captures the real
bar and leaves a PNG per colour. Measured with `measure-strip.py` (screenshots
carry the display ICC, so every value is converted to sRGB first), device rows
0–3, columns 1200…2800:

| asked (`signalColors.waiting`) | measured on the bar |
| --- | --- |
| `#FFFFFF` | `185,185,185` |
| `#FF0000` | `255,37,0` |
| `#00FF00` | `0,196,0` |
| `#0000FF` | `4,51,255` |
| `#FFE1A0` (V5 alert) | `192,164,104` |
| `#FFC25B` (V5 tint) | `201,146,34` |
| `#FFD98A` | `202,147,0` |

Two facts follow, and they are not a per-channel scale:

1. **Pale colours are dimmed** — white lands at `0.70` and `#FFE1A0` at
   `192,164,104`, a tan that reads grey next to the kiosk display of the lab.
2. **Saturated colours survive and are pushed further** — pure red keeps its
   255, and every warm yellow loses its blue channel entirely. Saturation, not
   lightness, is the currency that buys visibility under this material.

The same probe's *body* rows also explain the older „一直在变" impression: the
desktop wallpaper is the dynamic **Sequoia Sunrise**, so the colour the
material mixes in changes with the time of day.

### The change

`GlassSignalLights.tint(for:)` now reproduces V5's own saturated partner
(`--tint`: error `#FF587E`, waiting `#FFC25B`, unread `#2FE7AD`) for the shipped
palette and lifts the saturation for a user override, and every *painted* layer
of an alerting lane uses it:

| layer | before | after |
| --- | --- | --- |
| wash | `alert @ .24` | `tint @ .30` |
| glow | `alert @ .38` | `tint @ .46` |
| ribbon | `alert`, capped `.85` | `tint`, capped `.92` (V5's group is `.95`) |
| top line | `alert`, shadow `.75 / r3` | `tint`, shadow `.95 / r4.5` (V5: `0 0 9px` at `.95`) |
| curtain | `alert` | `tint` (`paintedLight(for:)`; a quiet lane keeps its running light) |

### Live before / after, same fixture, same wallpaper phase

Waiting fixture, device rows, columns 1200…2800:

| row | before | after |
| --- | --- | --- |
| 1 (top line) | `180,154,94` | `186,134,36` |
| 20 (body) | `62,111,133` | `70,113,127` |
| 56 (ribbon) | `112,102,74` | `128,100,44` |

The line keeps its hue and raises its chroma from 86 to 150 counts (max − min
per pixel), and the ribbon's bottom edge is warm light again instead of grey
film.

### Still open

- The **body** (quota fill + bed) has not been compensated: live row 24 is
  `61.9,138.2,181.1` against `126.4,198.4,233.5` in the offline renderer, so
  the everyday „不够通透" gap is the same material loss. Pre-compensating the
  fill means changing the product's everyday palette, so it needs the user's
  go-ahead.
- All of the above is measured on one wallpaper (Sequoia Sunrise, dark mode,
  Reduce Transparency off). A light wallpaper moves every number.

### Round 4 — the black band under the running bar

The user's „底部黑色的阴影" screenshot was matched onto this display (best
match mad 6.49 at dx=1055, dy=17). A full-screen A/B — overlay enabled vs
disabled, same session — shows device rows **60+ byte-identical** in both
captures (`45,45,45` / `68,68,68` / `34.4`): the `~1,1,1` line and the grey
rows below the strip are macOS's own menu-bar fence and desktop shadow, not
the app. Rows 0…58 differ between the two captures; those are ours.

Inside the bar two real causes were found and fixed:

1. `GlassQuotaRenderer.applyFillGradient` darkened its bottom stop by an extra
   `scaled(by: 0.55)`. V5's own bottom stop is the plain tier colour at
   `.20/.30` over the near-black base; the extra factor stacked a second
   attenuation. Removed.
2. `GlassSpectrumRenderer` composited the ray canvas source-over. V5 blits the
   whole light canvas with `mix-blend-mode: screen`, so the light *lifts* the
   fill; source-over replaced it with a grey veil, which is what made the
   lower quarter read dark. The spectrum group now carries
   `compositingFilter = "screenBlendMode"`.

V5's `.zone .sheen` is a *normal-blend* layer at z-index 7, above the
screen-blended rays. The native `scrim` is therefore a sibling of the spectrum
group (`laneOrder` now `quotaGlass, spectrum, scrim, attention, baseline`)
instead of a child: inside the group the screen filter would composite the
dark edge as light and neutralize it. On the lab render the sheen is exactly
the last-quarter decline (blue `205 → 193`) before the border rim.

### Live, same session and wallpaper phase, columns 1540…2114

| row | before | after |
| --- | --- | --- |
| 44 | `95,121,144` | `89.5,141.5,174` |
| 48 | `93,113,130` | `98,142.5,171` |
| 52 | `90,106,119` | `102.5,142.5,168` |
| 56 | `86,97,107` | `108.5,142.5,164` |
| 58 | `78,87,95` | `111,141,163.5` |
| 60 (macOS fence, both) | `45,45,45` | `45,45,45` |

The bottom quarter gained `+20…+33` green and `+56…+68` blue against the
pre-fix build, so the in-bar band no longer falls away before the system
fence. `scaled(by: 0.55)` had no test guarding it; the z-order test now pins
`scrim` above `spectrum`, and the sheen test asserts it stays a bottom edge
in the fill's blue family.

Also reset in the same session: the stored `appearance.signalColors.running`
was `#FFFFFF`, a leftover from the 18:03 material probe (round-3 backups at
16:04–17:29 all carry `{}`). It was backed up to
`build/round4/settings-before-restore.json` and cleared, so the running light
is the shipped `#D9EEFF` again.
