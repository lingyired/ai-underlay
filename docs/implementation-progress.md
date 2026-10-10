# Implementation Progress

Updated at the end of every task. Status values: `DONE`, `PARTIAL`, `BLOCKED`, `TODO`.

## P0 — Feasibility Spike

| Task | Status | Notes |
|---|---|---|
| P0-1 工程骨架 | DONE | xcodegen project, Kit framework + app shell, smoke tests pass |
| P0-2 穿透覆盖窗口 | DONE | Band renders behind menu bar, icons on top; evidence `docs/preview/p0-band-menubar.png` |
| P0-3 菜单栏几何 | DONE | Window-server height + Quartz flip + notch, 7 unit tests. See ledger below. |
| P0-4 CLI 探测 + Fixture | TODO | |
| P0-5 Agent 能力报告 | TODO | |

## P1 — Domain / Renderer / Mock

TODO

## P2 — 真实额度接入

TODO

## P3 — Agent 桥接

TODO

## P4 — 发布收尾

TODO

## Hardware verification ledger

Items that can only be confirmed on a real Mac session (to be filled during
manual verification):

| Item | Verified | Value observed |
|---|---|---|
| Band window level correct, no menu bar occlusion | ☑ | icons/text stay on top; screenshot `docs/preview/p0-band-menubar.png` |
| Menu bar height (internal display) | ☑ | 30 pt (window server layer 24), `Scripts/probe-menubar.swift` |
| Menu bar height (external display) | ☐ | no external display attached during this session |
| Notch edges detected | ☑ (no-notch path) | single display has no notch; `auxTopLeft/Right = nil` → midline fallback required |

Session machine: single built-in display 2048×1152 pt @2x, menu bar level = 24.
No external display was attached, so the multi-display / non-primary-height
case is verified by unit test only (`test_height_picksMatchingDisplayNotGlobalMax`),
not on hardware. To be re-checked with an external display attached.
