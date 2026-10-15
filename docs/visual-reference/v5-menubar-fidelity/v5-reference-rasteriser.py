#!/usr/bin/env python3
"""Offline V5 reference rasteriser.

The plan's browser route (opening `AIUnderlay-Glass-Material-Lab-v5.html`)
is blocked by the execution environment's navigation policy, so this script
re-implements the V5 lab's canvas `repaint()` in Python **verbatim** — same
ray count, crest positions, gradient stops and compositing — and can render
the same frame from the native Swift model so the two can be compared
without a browser.

Reference: docs/visual-reference/AIUnderlay-Glass-Material-Lab-v5.html,
`repaint(now)`.

Usage:
    python3 v5-reference-rasteriser.py --out build/v5-menubar-fidelity/reference
"""

from __future__ import annotations

import argparse
import math
import os

import numpy as np
from PIL import Image

# --- V5 constants (copied from the HTML, not eyeballed) ---------------------

V5_HALO_WIDTH = 4.2
V5_CORE_WIDTH = 1.16
V5_REFLECTION_ALPHA = 0.105
V5_TINT_CORE = (0xF5 / 255, 0xFA / 255, 0xFF / 255)
V5_RADIUS_CAP = 205.0

# Native constants, mirrored from SpectrumWaveModel / SpectrumFrameRasteriser
# so a change in the Swift has one obvious place to be reflected here.
SWIFT_BASE_HEIGHT = 0.22
SWIFT_CREST_HEIGHT = 0.52
SWIFT_FOCUS_HEIGHT = 0.28
SWIFT_BASE_ALPHA = 0.17
SWIFT_CREST_ALPHA = 0.28
SWIFT_FOCUS_ALPHA = 0.42
SWIFT_ALPHA_CEILING = 0.94
SWIFT_WAVE_A_TURNS = 1.0
SWIFT_WAVE_B_TURNS = 1.0
SWIFT_WAVE_A_CYCLES = 2.05
SWIFT_WAVE_B_CYCLES = 1.20
SWIFT_MIX_A = 0.61
SWIFT_MIX_B = 0.39
SWIFT_PHASE_A = 0.072
SWIFT_PHASE_B = 0.27
# Mirrors SpectrumWaveModel.travelLeadFraction: one exact lap per cycle.
SWIFT_LEAD = 0.0


def hex_to_rgb(value: str) -> tuple[float, float, float]:
    h = value.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def _gradient(values: list[float], locations: list[float], t: np.ndarray) -> np.ndarray:
    """Piecewise-linear gradient sampled at normalised positions `t` (0…1)."""
    return np.interp(t, locations, values)


def _ray_rect(canvas: np.ndarray, x0: float, x1: float, tops: np.ndarray, height: int,
              rgb: tuple[float, float, float], stops: list[float], alphas: list[float],
              scale: int) -> None:
    """Additively stamp one vertical gradient rect (screen-like accumulation)."""
    px0 = int(round(x0 * scale))
    px1 = int(round(x1 * scale))
    px0 = max(0, px0)
    px1 = min(canvas.shape[1], px1)
    if px1 <= px0:
        return
    ys = np.arange(height * scale)
    t = (ys / max(1.0, (height * scale - 1)))
    # CA/Canvas gradients run from the rect's bottom to its top; the lab's
    # rects are drawn from the tip (y) down to the base (h), so the profile is
    # sampled from the tip downward.
    profile = _gradient(stops, [i / (len(stops) - 1) for i in range(len(stops))], t)
    del alphas  # alpha profile is baked into `stops` by the caller
    col = np.zeros((height * scale, 4), dtype=np.float64)
    col[:, 0:3] = rgb
    col[:, 3] = profile
    span = canvas[:, px0:px1, :]
    for k in range(3):
        span[:, :, k] = 1 - (1 - span[:, :, k]) * (1 - col[:, k:k + 1] * col[:, 3:4])
    span[:, :, 3] = 1 - (1 - span[:, :, 3]) * (1 - col[:, 3:4])


def v5_lane(width: int, height: int, phase: float, tint_hex: str, *, vivid: bool = True,
            density: float = 1.0, cursor_offset: float = 0.0, scale: int = 2) -> np.ndarray:
    """The V5 lab's canvas for one zone at one phase (phase = t*2π*hz, radians)."""
    tint = hex_to_rgb(tint_hex)
    canvas = np.zeros((height * scale, width * scale, 4), dtype=np.float64)

    boost = 0.55 + density * 1.25
    n = max(24, round(width / (8.5 if vivid else 10.5) * boost))
    cursor = (0.10 + (phase / (2 * math.pi) * 0.78 + cursor_offset) % 1) * width
    second = (0.75 - (phase / (2 * math.pi) * 0.31) % 1) * width
    radius = min(width * 0.28, V5_RADIUS_CAP)

    # Travelling light field: two radial gradients, `screen` composited.
    for cx, weight, r in ((cursor, 0.72, radius), (second, 0.29, radius * 0.66)):
        if r <= 0:
            continue
        xs = (np.arange(width * scale) + 0.5) / scale
        ys = (np.arange(height * scale) + 0.5) / scale
        dx = xs - cx
        dy = ys - height * 0.77
        dist = np.sqrt(dx[None, :] ** 2 + dy[:, None] ** 2) / r
        near = (0.28 if vivid else 0.22) * weight
        mid = (0.14 if vivid else 0.10) * weight
        # V5: createRadialGradient stops at 0, .34, 1 with those alphas.
        prof = np.interp(dist, [0.0, 0.34, 1.0], [near, mid, 0.0])
        prof = np.clip(prof, 0, 1)
        for k in range(3):
            canvas[:, :, k] = 1 - (1 - canvas[:, :, k]) * (1 - prof * tint[k])
        canvas[:, :, 3] = 1 - (1 - canvas[:, :, 3]) * (1 - prof)

    # Rays: a chromatic halo plus a bright core, every ray with its own height.
    for i in range(n):
        u = (i + 0.5) / n
        x = u * width
        dist = abs(x - cursor)
        wrap = min(dist, width - dist)
        focused = math.exp(-((wrap / (radius * 0.56)) ** 2))
        w1 = 0.5 + 0.5 * math.sin(phase * 1.25 - u * math.pi * 4.1 + i * 0.072)
        w2 = 0.5 + 0.5 * math.sin(phase * 0.82 + u * math.pi * 2.4 + i * 0.27)
        crest = 0.61 * w1 + 0.39 * w2
        ray_h = height * (0.22 + 0.52 * crest + 0.28 * focused)
        alpha = min(0.96, (0.22 if vivid else 0.17) + 0.28 * crest + 0.42 * focused)
        profile = np.array([0.0, alpha * 0.28, alpha * 0.78, alpha * 0.92])
        ys = np.arange(height * scale)
        # The rect spans from the tip (top) to the base (bottom).
        frac = (ys / max(1.0, height * scale - 1))
        frac = np.clip((ys - (height - ray_h) * scale) / max(1.0, ray_h * scale), 0, 1)
        halo = _gradient(profile.tolist(), [0.0, 0.18, 0.64, 1.0], frac)
        px0 = int(round((x - V5_HALO_WIDTH / 2) * scale))
        px1 = int(round((x + V5_HALO_WIDTH / 2) * scale))
        for px in range(max(0, px0), min(canvas.shape[1], px1)):
            col = canvas[:, px, :]
            for k in range(3):
                col[:, k] = 1 - (1 - col[:, k]) * (1 - halo * tint[k])
            col[:, 3] = 1 - (1 - col[:, 3]) * (1 - halo)

        core = np.array([0.0, alpha * 0.42, min(0.90, alpha * 0.76)])
        core_prof = _gradient(core.tolist(), [0.0, 0.5, 1.0], frac)
        core_rgb = np.zeros((height * scale, 3))
        core_rgb[:, :] = tint
        tip = np.clip((frac - 0.5) / 0.5, 0, 1)
        for k in range(3):
            core_rgb[:, k] = tint[k] * (1 - tip) + V5_TINT_CORE[k] * tip
        cpx0 = int(round((x - V5_CORE_WIDTH / 2) * scale))
        cpx1 = int(round((x + V5_CORE_WIDTH / 2) * scale))
        for px in range(max(0, cpx0), min(canvas.shape[1], cpx1)):
            col = canvas[:, px, :]
            for k in range(3):
                col[:, k] = 1 - (1 - col[:, k]) * (1 - core_prof * core_rgb[:, k])
            col[:, 3] = 1 - (1 - col[:, 3]) * (1 - core_prof)

    # Soft specular crest along the bottom edge, only under the moving light.
    half = radius * 0.5
    left = max(0.0, cursor - half)
    right = min(float(width), cursor + half)
    if right > left:
        xs = (np.arange(width * scale) + 0.5) / scale
        prof = np.zeros(width * scale)
        inside = (xs >= left) & (xs <= right)
        prof[inside] = 0.5 - np.abs((xs[inside] - cursor) / half)
        prof = np.clip(prof * 2, 0, 1) * 0.105
        y0 = int((height * 0.72) * scale)
        y1 = int(height * scale)
        for k in range(3):
            canvas[y0:y1, :, k] = 1 - (1 - canvas[y0:y1, :, k]) * (1 - prof * (1.0 if k == 2 else 1.0))
        canvas[y0:y1, :, 3] = 1 - (1 - canvas[y0:y1, :, 3]) * (1 - prof)

    return np.clip(canvas, 0, 1)


def swift_lane(width: int, height: int, phase_turns: float, tint_hex: str, *,
               density: float = 1.0, travels: bool = True, scale: int = 2) -> np.ndarray:
    """Faithful port of the native model at the starting commit, for a gap table."""
    tint = hex_to_rgb(tint_hex)
    canvas = np.zeros((height * scale, width * scale, 4), dtype=np.float64)
    count = max(24, round(width / 8.5 * (0.55 + density * 1.25)))
    lead = SWIFT_LEAD
    span = 1 + 2 * lead
    primary = (-lead + span * phase_turns) if travels else 0.5
    secondary = (1 + lead - span * phase_turns) if travels else 0.5
    radius = 0.28 * width

    for cx, weight, r in ((primary, 0.72, radius), (secondary, 0.29, radius * 0.66)):
        if r <= 0:
            continue
        xs = (np.arange(width * scale) + 0.5) / scale
        ys = (np.arange(height * scale) + 0.5) / scale
        dx = xs - cx * width
        dy = ys - height * 0.77
        dist = np.sqrt(dx[None, :] ** 2 + dy[:, None] ** 2) / r
        # Native `drawGlow` now uses the Aurora stops, same as V5.
        prof = np.clip(np.interp(dist, [0.0, 0.34, 1.0], [0.28 * weight, 0.14 * weight, 0.0]), 0, 1)
        for k in range(3):
            canvas[:, :, k] = 1 - (1 - canvas[:, :, k]) * (1 - prof * tint[k])
        canvas[:, :, 3] = 1 - (1 - canvas[:, :, 3]) * (1 - prof)

    for i in range(count):
        u = (i + 0.5) / count
        x = u * width
        dist = abs(u - primary)
        wrap = min(dist, 1 - dist)
        focused = math.exp(-((wrap / (radius / width * 0.56)) ** 2))
        a = 0.5 + 0.5 * math.sin(2 * math.pi * (SWIFT_WAVE_A_TURNS * phase_turns - SWIFT_WAVE_A_CYCLES * u)
                                  + i * SWIFT_PHASE_A)
        b = 0.5 + 0.5 * math.sin(2 * math.pi * (SWIFT_WAVE_B_TURNS * phase_turns + SWIFT_WAVE_B_CYCLES * u)
                                  + i * SWIFT_PHASE_B)
        wave = SWIFT_MIX_A * a + SWIFT_MIX_B * b
        ray_h = height * min(max(SWIFT_BASE_HEIGHT + SWIFT_CREST_HEIGHT * wave + SWIFT_FOCUS_HEIGHT * focused, 0.10), 0.96)
        alpha = min(max(SWIFT_BASE_ALPHA + SWIFT_CREST_ALPHA * wave + SWIFT_FOCUS_ALPHA * focused,
                        SWIFT_BASE_ALPHA), SWIFT_ALPHA_CEILING)
        ys = np.arange(height * scale)
        frac = np.clip((ys - (height - ray_h) * scale) / max(1.0, ray_h * scale), 0, 1)
        halo = _gradient([0.0, alpha * 0.28, alpha * 0.78, alpha * 0.92], [0.0, 0.18, 0.64, 1.0], frac)
        for px in range(max(0, int(round((x - V5_HALO_WIDTH / 2) * scale))),
                        min(canvas.shape[1], int(round((x + V5_HALO_WIDTH / 2) * scale)))):
            col = canvas[:, px, :]
            for k in range(3):
                col[:, k] = 1 - (1 - col[:, k]) * (1 - halo * tint[k])
            col[:, 3] = 1 - (1 - col[:, 3]) * (1 - halo)

        # Native core sprite: white 0 → tint*0.42 → near-white 0.76 (fixed!).
        core = _gradient([0.0, alpha * 0.42, 0.76], [0.0, 0.5, 1.0], frac)
        tip = np.clip((frac - 0.5) / 0.5, 0, 1)
        core_rgb = np.zeros((height * scale, 3))
        for k in range(3):
            core_rgb[:, k] = tint[k] * (1 - tip) + (1.0, 1.0, 1.0)[k] * tip
        for px in range(max(0, int(round((x - V5_CORE_WIDTH / 2) * scale))),
                        min(canvas.shape[1], int(round((x + V5_CORE_WIDTH / 2) * scale)))):
            col = canvas[:, px, :]
            for k in range(3):
                col[:, k] = 1 - (1 - col[:, k]) * (1 - core * core_rgb[:, k])
            col[:, 3] = 1 - (1 - col[:, 3]) * (1 - core)

    return np.clip(canvas, 0, 1)


def metrics(frame: np.ndarray, scale: int) -> dict:
    """Ink metrics that describe 'fence vs soft curtain' without an eye."""
    alpha = frame[:, :, 3]
    h = frame.shape[0] // scale
    columns = alpha.reshape(h, scale, frame.shape[1])
    top_frac = []
    white = 0
    ink = 0.0
    for x in range(frame.shape[1]):
        col = alpha[:, x]
        rows = np.nonzero(col > 0.05)[0]
        if rows.size:
            top_frac.append(1 - rows.min() / frame.shape[0])
            ink += col.sum() / scale
        rgb = frame[:, x, :3]
        strong = col > 0.5
        if strong.any():
            white += int((rgb[strong].min(axis=1) > 0.86).sum())
    top_frac = np.array(top_frac)
    return {
        "columns_with_ink": int(top_frac.size),
        "top_spread_pt": float((top_frac.max() - top_frac.min()) * h) if top_frac.size else 0.0,
        "mean_ink": ink / max(1, frame.shape[1]),
        "white_core_px": white,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="build/v5-menubar-fidelity/reference")
    parser.add_argument("--width", type=int, default=480)
    parser.add_argument("--height", type=int, default=30)
    parser.add_argument("--scale", type=int, default=2)
    parser.add_argument("--tint", default="#d9eeff")
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)

    rows = []
    for phase_turns in (0.0, 0.25, 0.5, 0.75):
        v5 = v5_lane(args.width, args.height, phase_turns * 2 * math.pi, args.tint, scale=args.scale)
        swift = swift_lane(args.width, args.height, phase_turns, args.tint, scale=args.scale)
        for name, frame in (("v5", v5), ("swift", swift)):
            img = Image.fromarray((frame * 255).astype(np.uint8), mode="RGBA")
            img.save(os.path.join(args.out, f"{name}-phase{int(phase_turns * 100):02d}.png"))
        rows.append((phase_turns, metrics(v5, args.scale), metrics(swift, args.scale)))

    print(f"{'phase':>6} | {'v5 top spread':>13} {'v5 white':>9} {'swift top spread':>16} {'swift white':>11}")
    for phase, a, b in rows:
        print(f"{phase:>6.2f} | {a['top_spread_pt']:>13.1f} {a['white_core_px']:>9d} "
              f"{b['top_spread_pt']:>16.1f} {b['white_core_px']:>11d}")


if __name__ == "__main__":
    main()
