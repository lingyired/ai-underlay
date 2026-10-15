# Glass Spectrum fidelity validation — 2026-10-15

## Result and review scope

Implementation commit: `83eb312`, branch `codex/glass-spectrum-fidelity-fix`, based on local main `a2725dcea4c5ec838ad5c03f26a550124342239b`. Two DeepSeek V4.1 Flash workers implemented the spectrum and material slices; the parent integrated, corrected compiler/geometry/timing issues, and ran the actual macOS project. Nothing pushed, merged or released.

The code and automated checks are complete. One-display live observation is recorded below; human visual sign-off, the hardware/OS matrix and a matched fixture GPU/CPU benchmark remain open.

## Root causes addressed

| Root cause | Result | Evidence |
|---|---|---|
| Bright static fence | Three weak beds at0.16 plus cached bright copies at0.78, masked to a local energy peak; no fixed bright focus. Wide fields and primary masks share travel geometry/time. | Spectrum tests, actual-ray pixel profile at0.2/0.6, phase PNGs |
| Softness token inert | Precomputed three-pass box-blurred material halo, device-pixel radius=softnessPt×scale×0.5; axis-specific downsampling compensation and bounded4MiB cache. | 0/17/32 pixel/edge-width tests; softness PNGs |
| Flat quota brightness | Weaker outer gradient and broad tint; brighter inner tier/end cap; true nested lengths and black exhausted region retained. | Quota tests, full-composition black-region pixel checks, live screenshots |
| Mask/animation lifecycle | Masks included in diagnostics/teardown; whole-Lane continuous animation budget≤10 with Attention and optional ambient. | Host lifecycle/budget tests |
| Settings regression risk | Floor slider, immediate updates and both sweep switches preserved. Traveling off keeps a fixed local bright region and vertical motion. | Existing settings/rhythm tests, toggle tests, live user settings unchanged |

## Automated validation

Environment: macOS27.0.1 / Xcode27.0 / XcodeGen2.45.4, Swift6 strict concurrency, macOS14 deployment target.

```bash
xcodegen generate
Scripts/check-domain-purity.sh
Scripts/test.sh -derivedDataPath build/DerivedData
xcodebuild -project AIUnderlay.xcodeproj -scheme AIUnderlay -destination 'platform=macOS' -derivedDataPath build/DerivedData build
```

- Domain purity: OK.
- Full suite:411 tests,1 skipped,0 failures. Skip is the opt-in PNG dump.
- Targeted renderer/material/host/preview/UI suite:85 tests,1 skipped,0 failures.
- Debug build: BUILD SUCCEEDED.
- PNG dump explicitly enabled afterward:1 test,0 skipped,0 failures;98 offline fixtures, including30/32/34pt at1x/2x, two horizontal phases and six softness samples.
- Logs: `/tmp/ai-underlay-glass-full-test.log`, `/tmp/ai-underlay-glass-build.log`, `/tmp/ai-underlay-glass-preview.log`; xcresult bundles under this worktree's build/DerivedData/Logs/Test/.

Deterministic PNGs sample the same horizontal trajectory and gradient stops as production; vertical breath is held at0.97 to isolate the moving brightness window. They are not presentation-tree screenshots.

## Visual evidence

- [Running phase0.2](../../preview/glass-spectrum/codex-running-phase20-32pt-2x.png) and [phase0.6](../../preview/glass-spectrum/codex-running-phase60-32pt-2x.png). Tests hide broad fields and quota end caps, so only moving ray pixels can pass the position check.
- [Codex softness0](../../preview/glass-spectrum/codex-softness0-32pt-2x.png), [17](../../preview/glass-spectrum/codex-softness17-32pt-2x.png), [32](../../preview/glass-spectrum/codex-softness32-32pt-2x.png). Equivalent Claude samples are alongside them. Ambient and grain stay0.
- [Original live menu bar](live/before-live-menubar.png), [after frame1](live/live-menubar-1.png), [after frame2](live/live-menubar-2.png): actual system text/icons over the overlay,30pt/2x,2048pt wide, one display/no notch.
- Local10.02-second recording: `build/glass-fidelity/after/live-menubar-running.mp4`. Ray-region crop below text yielded25 distinct frames from40 samples at4fps, confirming the running render is not a static texture.
- Actual executable path was verified as this worktree's build. Fixture remained off; floor≈0.82Hz, traveling off, attention sweep on. These live frames therefore show fixed local undulation, not horizontal travel.
- Browser V5 inspected with matching selected material/colors and both providers Running; its scene is1124CSSpx×34px. It is a qualitative reference, not a dimension/pixel-identical native comparison; full parity is not claimed.

The native snapshots show readable system text/icons and darker off-peak rays. Final subjective fidelity remains for the user to accept.

## Resource observations

See `performance.md` for approximately five-minute before/after samples. These are live-agent observations with uncontrolled other desktop workload, not a matched fixture benchmark. GPU counters are unmeasured; WindowServer is system-wide.

## Remaining checks

1. User visual sign-off at actual menu-bar scale, including a temporary traveling-on live check if desired.
2. Click-through, Spaces, external display/notch hardware, and macOS14/15 device matrix.
3. Matched fixture before/after CPU/RSS and attributed GPU testing, plus long-run cache/window lifecycle.
4. Controlled background-sampling experiment and30-minute native material stability pass; current short probe does not justify a system backdrop blur claim.
5. Live Unread ledger and TPS input remain separate features; this patch preserves their truthful contracts and uses fixtures only for unavailable states.
