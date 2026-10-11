# AI Underlay

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: macOS 14+](https://img.shields.io/badge/Platform-macOS%2014%2B-blue.svg)](#requirements)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange.svg)](https://swift.org)
[![Tests: 163 passing](https://img.shields.io/badge/Tests-163%20passing-brightgreen.svg)](Scripts/test.sh)
[![No telemetry](https://img.shields.io/badge/Telemetry-none-lightgrey.svg)](docs/privacy-and-permissions.md)

Draws an AI quota and agent-activity bar **into the macOS menu bar background**.
It does not add menu bar items for each provider — instead it paints a single
nested progress bar behind the system menu bar, using a click-through window
that sits above the desktop icons and below the menu bar.

- Left side: Codex · Right side: Claude Code (configurable, per display).
- Nested quota: each shorter window occupies the *remaining* length of the
  longer one (week → 5h), with a pace baseline marker.
- Agent state (running / waiting for approval / waiting for input) shown as a
  small endpoint indicator — never by altering the quota numbers.
- Data comes from the community **CodexBar** CLI; agent state comes from the
  agents' own lifecycle hooks.

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

1. Launch the app. It appears as a small gauge icon in the menu bar (no Dock
   icon). Click it → **Settings…**.
2. **Appearance** — choose dual/single, anchor (notch or screen edge),
   direction, and a preview fixture. Changes render live.
3. **Providers / Engine** — see the detected CodexBar CLI and each provider's
   login state. *Test Connection* refreshes immediately.
4. **Agent** — preview and install Claude Code hooks (this is the only way the
   app modifies `~/.claude/settings.json`, and it backs the file up first).
5. **Diagnostics** — measured geometry and overlay state, with a desensitized
   copy button.

### Offline preview

Set **Appearance → Fixture** to any of `full`, `weekLow`, `sessionLow`,
`allZero`, `missing`, `stale`, `reset`, `agentRunning`, `agentWaiting`,
`notchless`. These drive the *real* renderer, so what you see is exactly what
the menu bar will draw — no provider login required.

## Where the data comes from

- **Quota**: the external `CodexBar` CLI, invoked as a subprocess with an
  absolute path and array arguments (never a shell). We parse its JSON, map
  windows by `windowMinutes` (300 = 5h, 10080 = weekly), and never invent a
  "monthly" layer that the source did not report.
- **Agent**: the agents' official hooks write one JSON line to a local Unix
  socket. Events carry only provider, session id, event kind, and time.

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
external process and references CodeStatus only for design.

## Known limitations

- Only the primary display was verified on the development machine; multi-display
  and notch hardware are unit-tested but not yet verified on real hardware.
- Fullscreen auto-hide is **not** implemented: reliably detecting fullscreen
  Spaces needs private SkyLight APIs, which we deliberately avoid to keep the
  App Store option open.
- The managed-CLI installer requires a pinned release URL + SHA-256 to be filled
  in before use; the GitHub build path is wired but not yet pointed at a release.