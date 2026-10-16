#!/usr/bin/env python3
"""Report median menu-bar-strip colours from a screenshot.

Screenshots carry the display's ICC profile, so every value is converted to
sRGB before it is printed; otherwise a colour measured on the XV272U cannot be
compared with the sRGB values the renderer asks for.

usage: measure-strip.py <image.png> [--rows 0-3,10,30]
"""

import argparse
import statistics as stats
import sys

from PIL import Image, ImageCms


def to_srgb(image: Image.Image) -> Image.Image:
    profile = image.info.get("icc_profile")
    if not profile:
        return image.convert("RGB")
    source = ImageCms.ImageCmsProfile(__import__("io").BytesIO(profile))
    target = ImageCms.createProfile("sRGB")
    return ImageCms.profileToProfile(image.convert("RGB"), source, target)


def parse_rows(spec: str) -> list[int]:
    rows: list[int] = []
    for part in spec.split(","):
        if "-" in part:
            low, high = part.split("-")
            rows.extend(range(int(low), int(high) + 1))
        else:
            rows.append(int(part))
    return rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("image")
    parser.add_argument("--rows", default="0-3,10,20,30,40,50,56,58")
    parser.add_argument("--x", default="1200:2800", help="device-pixel column span")
    parser.add_argument("--step", type=int, default=7)
    args = parser.parse_args()

    low, high = (int(v) for v in args.x.split(":"))
    image = to_srgb(Image.open(args.image))
    pixels = image.load()
    for y in parse_rows(args.rows):
        sample = [pixels[x, y] for x in range(low, high, args.step)]
        med = [stats.median(channel) for channel in zip(*sample)]
        print(f"row {y:>3}  {med[0]:6.1f} {med[1]:6.1f} {med[2]:6.1f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
