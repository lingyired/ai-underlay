# Native material probe — limited evidence

- Platform: macOS 27.0.1, one 2048×1152 display, backing scale 2, actual menu bar 30pt, no notch.
- Standalone AppKit probe: borderless 320×30pt window at x=600, same desktop-icon+1 level as MenuBarBandWindow; ignores mouse events; NSVisualEffectView .behindWindow / .menu / .active.
- Existing app and its settings were left running unchanged. This probe therefore sampled a composite that included the existing overlay; it is not an isolated proof of wallpaper-only sampling.
- Six-second functional observation: transparent control, forced Aqua, forced Dark Aqua. Aqua visibly changed and flattened the underlying stripe pattern; Dark Aqua resembled the control. Images: blur-probe/{transparent,aqua,dark-aqua}.png. The reproducible source and log are in blur-probe/.
- This short probe does not establish a 17pt blur radius, long-run stability, Space transitions, multi-display behavior, GPU cost, or compatibility with macOS 14–15. No recording permissions or global appearance settings were changed.
- Decision for this patch: keep rendered glass and make its own softness observable. Do not ship system backdrop sampling on this evidence. A controlled wallpaper/window comparison and 30-minute hardware pass remain pending.
