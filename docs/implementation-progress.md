# Implementation Progress

Updated at the end of every task. Status values: `DONE`, `PARTIAL`, `BLOCKED`, `TODO`.

## P0 — Feasibility Spike

| Task | Status | Notes |
|---|---|---|
| P0-1 工程骨架 | DONE | xcodegen project, Kit framework + app shell, smoke tests pass |
| P0-2 穿透覆盖窗口 | DONE | Band renders behind menu bar, icons on top; evidence `docs/preview/p0-band-menubar.png` |
| P0-3 菜单栏几何 | DONE | Window-server height + Quartz flip + notch, 7 unit tests. See ledger below. |
| P0-4 CLI 探测 + Fixture | DONE | Discovery + client + real desensitized fixtures (CodexBar 0.58.0) |
| P0-5 Agent 能力报告 | DONE | `docs/agent-capability-report.md`; event whitelist types added |

**P0 gate result:** static band visible behind the menu bar without occluding
icons or intercepting clicks; real menu bar height read (30pt); real CodexBar
CLI detected and JSON captured; agent capability matrix written. **P0 complete.**

## P1 — Domain / Renderer / Mock

| Task | Status | Notes |
|---|---|---|
| P1-1 Domain models | DONE | QuotaWindow/Snapshot/AgentSession/DisplayConfiguration/AppSettings + purity guard |
| P1-2 NestedGauge | DONE | chain-break on unknown, 8 tests |
| P1-3 GaugeLayout | DONE | abstract axis, notch/outerEdge, midline fallback, 9 tests |
| P1-4 Renderer | DONE | single GaugeLayerRenderer, baseline projection, end-cap, 8 tests |
| P1-5 Fixtures | DONE | 10 fixtures drive the real renderer |
| P1-6 Watchdog | DONE | needsReassert pure fn + 5s timer + lifecycle observers |
| P1-7 Settings UI | DONE | 4 tabs, live Appearance controls, NSStatusItem entry |

Evidence: `docs/preview/p1-*.png` (dual weekLow, dual full, single full).
Total tests: 74 passing.

## P2 — 真实额度接入

| Task | Status | Notes |
|---|---|---|
| P2-1/2 QuotaEngine + Manager | DONE | discovery/selection, incompatible-only state, injectable paths |
| P2-3 Usage Decoder | DONE | windowMinutes mapping, out-of-range→unavailable (no clamp), positional fields |
| P2-4 Cache + Scheduler | DONE | stale threshold, minute-level refresh, in-flight de-dup |
| P2-5 Managed installer | DONE | SHA-256 verify, rollback, App Store profile disables it |
| P2-6 Providers/Engine tabs | DONE | live provider table, engine detection, uninstall |
| P2-7 Live end-to-end | DONE | real codex quota rendered from CLI; claude unauthenticated → empty track |

**Fix during P2:** live mode previously fell back to a fixture before the first
snapshot arrived (~7s CLI fetch), which could be mistaken for real data. Now
live mode shows empty tracks until a real snapshot arrives. Evidence:
`docs/preview/p2-live-codex.png`.

Tests: 97 passing.

## P3 — Agent 桥接

| Task | Status | Notes |
|---|---|---|
| P3-1 Socket receiver | DONE | Unix socket 0600, line framing, defensive parsing, verified bound at runtime |
| P3-2 Adapters | DONE | Claude full mapping; Codex maps unknown → unknown (no invented waiting) |
| P3-3 Session reducer | DONE | stale-event rejection, aggregation priority, unknown counted |
| P3-4 Hook installer | DONE | preview → confirm → backup → marker-scoped uninstall |
| P3-5 Agent effects | DONE | endpoint dot, pulse, reduce-motion suppression |
| P3-6 E2E | DONE | real socket event → dot; visual evidence `docs/preview/p3-agent-waiting.png` |

Note: real Claude Code hook wiring requires the user to install hooks via the
Agent tab (not done automatically). The socket path is verified working with a
synthetic event.

Tests: 122 passing.

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
