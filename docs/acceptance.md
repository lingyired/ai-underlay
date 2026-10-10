# Morning Acceptance Guide

Everything below is implemented and the automated suite is green (122 tests).
This is the checklist for your review pass.

## 0. Build & test (2 minutes)

```bash
cd /Users/lingsmbp/Documents/aiwork/ai-underlay
xcodegen generate
Scripts/test.sh                    # expect: 122 tests, 0 failures
Scripts/check-domain-purity.sh     # expect: OK
```

## 1. ⚠️ Two decisions that are genuinely yours

I implemented past both stop-gates (you were asleep). Please look at these
first — they are the only two things I could not decide for you.

### 1a. P0 gate — does the overlay sit correctly?

Open the app and confirm the bar sits **behind** the menu bar without covering
icons or stealing clicks.

```bash
open "$(find ~/Library/Developer/Xcode/DerivedData/AIUnderlay-*/Build/Products/Debug -name AIUnderlay.app -maxdepth 1 | head -1)"
```

Reference: `docs/preview/p0-band-menubar.png` (the P0 proof).

### 1b. P1 gate — is the information density right?

The bar can show: nested fills (up to 3 layers), a baseline marker, and an
agent endpoint dot. **You asked to "render it first, then tune."** Cycle the
fixtures and tell me what to change.

- Menu bar icon → **Settings… → Appearance → Fixture**.
- Try: `full`, `weekLow`, `sessionLow`, `allZero`, `missing`, `stale`, `reset`,
  `agentRunning`, `agentWaiting`, `notchless`.
- Toggle **Show baseline marker** / **Show agent effects** to see the density
  with and without each channel.

Tell me: too busy? baseline too subtle? endpoint dot too small? colors?

## 2. Real data

1. **Providers tab** → *Test Connection*. Expect `codex` = "signed in" with
   Weekly/5h windows (real data), `claude` = "not signed in" (no Claude cookies
   on this machine) with an empty track.
2. Set **Appearance → Fixture → Live data** and watch the left (codex) side
   fill from your real quota. First fetch takes ~7s (the CLI hits the OpenAI
   web dashboard).

## 3. Agent detection (optional, modifies your config)

The **Agent tab** previews the exact hook entries it would add to
`~/.claude/settings.json`, backs the file up first, and only removes its own
entries on uninstall. Nothing is installed until you click Install.

Verified: the socket binds and a synthetic event draws the endpoint dot. Not
verified: a real Claude Code session round-trip (needs you to install hooks and
run a session).

## 4. What is NOT verified (needs hardware/you)

See `docs/release-checklist.md` for the full list. The important ones:

- **External display** menu-bar height (only one display was attached; the
  multi-display path is unit-tested but not hardware-tested).
- **Notch** hardware (this machine has no notch; midline fallback verified).
- **macOS 14/15** (only macOS 27 available here).
- **Real Claude Code hooks**, **Codex hook events** on your installed versions.
- **Managed CLI install** — wired and tested, but `CodexBarInstaller.Release`
  still needs a pinned URL + SHA-256 before the button does anything.

## 5. Evidence captured

| File | Shows |
|---|---|
| `docs/preview/p0-band-menubar.png` | band behind menu bar, icons on top |
| `docs/preview/p1-full.png` | dual, both halves full |
| `docs/preview/p1-weekLow.png` | dual, partial fills |
| `docs/preview/p1-single-full.png` | single full-width bar |
| `docs/preview/p2-live-codex.png` | real codex quota, claude empty track |
| `docs/preview/p3-agent-waiting.png` | agent endpoint dot |
| `docs/preview/p4-settings.png` | settings window, 5 tabs |

## 6. How to run it like a user

The app is `LSUIElement` (no Dock icon). After launch, look for the **gauge
icon in the menu bar** → click → *Settings…*. To quit: same menu → *Quit*, or
`pkill -x AIUnderlay`.
