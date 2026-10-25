# AI Underlay

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: macOS 14+](https://img.shields.io/badge/Platform-macOS%2014%2B-blue.svg)](#requirements)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange.svg)](https://swift.org)
[![Tests: XCTest suite](https://img.shields.io/badge/Tests-XCTest%20suite-blue.svg)](Scripts/test.sh)
[![No telemetry](https://img.shields.io/badge/Telemetry-none-lightgrey.svg)](docs/privacy-and-permissions.md)

Draws an AI quota and agent-activity bar **into the macOS menu bar background**.
It does not add menu bar items for each provider — instead it paints a single
nested progress bar behind the system menu bar, using a click-through window
that sits above the desktop icons and below the menu bar.

- Left side: Codex · Right side: Claude Code (configurable, per display).
- Nested quota: each shorter window occupies the *remaining* length of the
  longer one (week → 5h), with a pace baseline marker.
- A one-provider dual split paints its two sides differently, so the 5-hour side
  and the weekly side never look alike: the 5-hour side turns the provider's own
  hue by 30°, the weekly side keeps the provider colour, and either side can be
  overridden by hand (设置 → 主题与颜色 → 自定义颜色 → 单服务商双侧拆分).
- Agent state (running / waiting for approval / waiting for input / unread) is
  shown with independent light-field and alert visuals — never by altering
  quota numbers.
- One visual engine: **Glass Spectrum** (aurora glass + frosted quota detail).
  A dense fine-ray light curtain travels while an agent works, and the same
  ribbon/lamp language shows Error > Waiting > Unread. Cached ray textures
  provide a faint bed and moving local peaks; no per-frame CPU painting.
  Turning **横穿扫光** (the whole-lane sweep) off does not stop the motion: each
  ray keeps its own travelling wave, so a running lane is never mistaken for
  an idle one. Tempo defaults to 1.4 s/cycle and is adjustable in
  设置 → 外观与布局 → Agent 动效, together with the wave strength.
- Three separate colour roles: **quota colours**, the per-provider **glass
  tint**, and global **signal lights** — a theme can change any of them without
  changing the others.
- Quota comes from the community **CodexBar** CLI. Codex activity uses a
  read-only Desktop connection with local logs as fallback; Claude Code uses
  local sessions with optional lifecycle hooks.

## Requirements

- macOS 14 or later
- Xcode 27 / Swift 6.4 to build
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Optional: [CodexBar](https://github.com/steipete/CodexBar) CLI for real quota
  (`brew install --cask codexbar`, or use your existing install)

## Build & run

```bash
xcodegen generate
open AIUnderlay.xcodeproj          # or:
xcodebuild -scheme AIUnderlay -destination 'platform=macOS' build
```

Run the tests headlessly:

```bash
Scripts/test.sh
Scripts/check-domain-purity.sh
```

## Using it

1. Launch the app. Click the small gauge icon in the menu bar, then **设置…**.
   Reopening the app or pressing **⌘,** also opens Settings, including when the
   menu bar icon has been hidden. The settings window has a resizable sidebar.
2. **外观与布局** — choose dual/single, anchor (notch or screen edge), direction,
   and optional offline previews. Unavailable controls explain their conditions.
   With exactly one provider switched on, dual mode can split its 5-hour and
   weekly windows across the two sides. Motion tuning is grouped under advanced
   controls and respects both the app and macOS Reduce Motion preferences.
3. **主题与颜色** — pick a theme, then optionally expand personal colors,
   material tuning, or theme-file tools. Controls show resolved values using
   **personal overrides → active theme → built-in defaults**. Switching themes
   preserves personal edits; scoped restore actions return them to the theme.
   Themes are appearance-only: `docs/theme/README.md`.
4. **服务商 / 运行引擎** — switch each provider on or off for this app (a
   provider switched off here is neither fetched nor drawn, even when CodexBar
   has it enabled), and see the detected CodexBar CLI plus each provider's
   upstream and data state. Connection checks follow the actual request state;
   stale cached data is identified. Proxy fields validate addresses before use.
5. **Agent 集成 / 诊断** — Codex connects automatically while Codex Desktop is
   open: no Hook installation or approval. If unavailable, local logs continue
   detection with limited question/approval coverage. Old AI Underlay Codex hooks
   have a manual cleanup action. Claude Code retains optional preview/apply
   hooks. Diagnostics shows the Codex connection and a desensitized report.

Changes apply immediately. A visible error and retry action appear if settings
cannot be saved. An unreadable settings file is backed up before replacement.

### Offline preview

Choose a named scenario under **外观与布局 → 离线预览**, such as 额度充足,
5 小时额度偏低, or Agent 正在运行. The Settings window and quota popup display
a persistent preview indicator with an exit action. These examples drive the
real renderer without provider login; their numbers and activity are simulated.
Choose **实时额度** or **退出预览** to restore live data. The internal scenario
keys remain stable in `FixtureSnapshots`; `docs/preview/glass-spectrum/` holds
offline rendered examples for development review.

## Where the data comes from

- **Quota**: the external `CodexBar` CLI, invoked as a subprocess with an
  absolute path and array arguments (never a shell). We parse its JSON, map
  windows by `windowMinutes` (300 = 5h, 10080 = weekly), and never invent a
  "monthly" layer that the source did not report.
- **Codex activity**: a read-only connection to the local Desktop Unix socket
  projects lifecycle and pending-request metadata into state. Local SQLite and
  rollout logs cover sessions absent from the stream. Raw wire payloads are
  transiently decoded, never logged or persisted. Codex hooks are ignored.
- **Claude activity**: local session logs, optionally supplemented by lifecycle
  hooks writing a JSON line to the app's local Unix socket.
- **Download counts (opt-in, 设置 → 下载监控)**: one `GET` every 5 minutes
  against the user's own stats endpoint (default
  `https://lingai.net/api/dl/statustrio`), which aggregates the landing page's
  netdisk button clicks with GitHub release download counts. Off by default;
  switching it on is the only network call the app makes on its own behalf, and
  it sends nothing about the user. The netdisk vendors expose no download
  numbers to third parties, so the click-side count is self-collected.

See `docs/architecture.md`, `docs/privacy-and-permissions.md`, and
`docs/agent-capability-report.md`.

## Project layout

```
AIUnderlayKit/     all logic: Domain / Data / Agent / Overlay / Application
AIUnderlay/        thin SwiftUI app shell (LSUIElement)
AIUnderlayKitTests/ unit tests (headless)
docs/              design spec, plan, architecture, privacy, progress
```

Dependency rule: `Domain` depends on nothing but Foundation; `Data`, `Agent`,
`Overlay`, and `UI` depend inward on `Domain`. The renderer never imports a
data-source type.

## License / third-party

This project is [MIT licensed](LICENSE). See `NOTICE` for third-party notices.
CodexBar and CodeStatus are separate projects; this app invokes CodexBar as an
external process and references CodeStatus only for design. The native Codex
Desktop adapter is adapted from MIT-licensed Codex Pacer; its license is bundled
in the app.

## Known limitations

- Only the primary display was verified on the development machine; multi-display
  and notch hardware are unit-tested but not yet verified on real hardware.
- The glass is **rendered**, not sampled from the desktop: no `NSVisualEffectView`
  backdrop blur (see `docs/architecture.md`). On-device 30-minute blur/CPU spike
  is still open.
- Live unread completion tracking is not integrated in this branch; unread
  visuals are currently available in offline fixtures.
- Codex Desktop IPC is an internal protocol and may change. Unsupported or
  unavailable connections fall back to logs; CLI/IDE questions and approvals
  are not guaranteed observable in that mode. Remote hosts are not connected.
- Real output TPS is not measured yet, so the light field runs at the selected
  baseline tempo rather than claiming to measure output speed.
- Fullscreen auto-hide is **not** implemented: reliably detecting fullscreen
  Spaces needs private SkyLight APIs, which we deliberately avoid to keep the
  App Store option open.
- The managed-CLI installer requires a pinned release URL + SHA-256 to be filled
  in before use; the GitHub build path is wired but not yet pointed at a release.
  The unfinished installer is kept out of the user-facing setup flow.

The 2026-10-17 product review, implementation notes, and validation are in
[`docs/productization/`](docs/productization/2026-10-17-product-review.md).

Codex Hook-free integration and current preview validation:
[`docs/productization/codex-hook-free-validation.md`](docs/productization/codex-hook-free-validation.md).
