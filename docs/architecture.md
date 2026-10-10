# Architecture

## Environment (recorded at P0)

| Item | Value |
|---|---|
| macOS | 27.0.0 (Darwin 27.0.0) |
| Xcode | 27.0 (27A266a) |
| Swift | 6.4 (swiftlang-6.4.0.34.1) |
| Architecture | Apple Silicon (arm64) |
| Project generator | xcodegen 2.x (`project.yml`) |
| Deployment target | macOS 14.0 |

## Target layout

```text
AIUnderlayKit.framework   # all logic: Domain / Data / Agent / Overlay / Application
AIUnderlay.app            # thin SwiftUI shell (LSUIElement), owns Info.plist
AIUnderlayKitTests        # unit tests against the kit (headless)
```

Rationale for the framework split: tests run without launching a GUI, and the
dependency direction (`Domain ← everything`) is enforced by module boundary —
`AIUnderlayKit` cannot accidentally pull in the app shell.

## Dependency rules (hard)

1. `Domain/` must not import `AppKit`, `SwiftUI`, or any data-source type.
2. `Overlay/GaugeLayerRenderer.swift` must not reference `Data/CodexBar/*`.
3. All layers depend inward on `Domain`; `Domain` depends on nothing but `Foundation`.

`Scripts/check-domain-purity.sh` enforces rule 1 in CI/pre-commit.

## Overlay window facts (from reference notes, to be re-verified on this machine)

- Window level = `CGWindowLevelForKey(.desktopIconWindow) + 1` (never hardcode 24).
- Menu bar height must be read from `CGWindowListCopyWindowInfo` at the
  `CGWindowLevelForKey(.mainMenuWindow)` level; `visibleFrame` returns 0 on
  non-primary displays.
- All overlay APIs are public — no SkyLight, no screen-recording permission.

## Upstream

- CodexBar CLI: detected at `/opt/homebrew/bin/codexbar` on this machine.
- CodeStatus: reference for hook/reducer design (MIT).
