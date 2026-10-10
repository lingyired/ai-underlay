# Release Checklist

## Automated (must pass)

- [ ] `Scripts/test.sh` — full unit suite green.
- [ ] `Scripts/check-domain-purity.sh` — Domain has no UI/data-source imports.
- [ ] `xcodebuild -scheme AIUnderlay -configuration Release build` succeeds.

## Manual — verified on this session's machine

- [x] Band window renders behind the menu bar; icons/text stay on top.
- [x] Menu bar click-through works (system menus still open).
- [x] Menu bar height read from window server (30pt, single display).
- [x] No-notch degradation (midline split).
- [x] Dual layout: left blue (codex), right warm (claude), both directions.
- [x] Single layout: leading-to-trailing.
- [x] Live real quota rendered (codex via CodexBar 0.58.0).
- [x] Not-logged-in provider shows an empty track, not a fake value.
- [x] Agent endpoint dot renders for waitingApproval; socket binds.
- [x] Fixtures render through the real renderer.

## Manual — NOT verified (must be checked before public release)

- [ ] External (non-primary) display menu bar height. **No external display
      attached this session**; unit-tested only.
- [ ] Notch hardware (this machine has no notch). Midline path verified.
- [ ] macOS 14 / 15 behaviour (only macOS 27 available here).
- [ ] Auto-hidden menu bar following.
- [ ] Stage Manager / Mission Control.
- [ ] Sleep/wake, session lock/unlock on real hardware.
- [ ] Real Claude Code hook round-trip (requires installing hooks in a live
      Claude Code session).
- [ ] Codex CLI hook events on the installed version.
- [ ] Mixed 1x/2x displays.
- [ ] Performance sampling (CPU / memory / energy) across idle, active,
      sleep-wake, dual display.

## Release artifact

- [ ] `AIUnderlay.app` built for Release, ad-hoc signed for local use.
- [ ] Developer ID signing + notarization when a signing identity is available.
- [ ] `NOTICE` includes CodexBar and CodeStatus licenses.