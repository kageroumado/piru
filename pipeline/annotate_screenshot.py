#!/usr/bin/env python3
"""Circle a tap target on a simulator screenshot for naive-user testing.

The circle marks WHERE without saying WHAT — the tester agent must read the
UI itself. Coordinates are logical points (the `axe describe-ui` space);
the scale factor maps them to screenshot pixels (@3x by default).

Usage:
    python3 pipeline/annotate_screenshot.py in.png out.png X Y [--radius 44] [--scale 3]
"""

import argparse

from PIL import Image, ImageDraw


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input")
    parser.add_argument("output")
    parser.add_argument("x", type=float, help="center X in logical points")
    parser.add_argument("y", type=float, help="center Y in logical points")
    parser.add_argument("--radius", type=float, default=44, help="circle radius in points")
    parser.add_argument("--scale", type=float, default=3, help="pixels per point (default @3x)")
    args = parser.parse_args()

    image = Image.open(args.input).convert("RGB")
    draw = ImageDraw.Draw(image)
    cx, cy, r = args.x * args.scale, args.y * args.scale, args.radius * args.scale
    for inset in range(int(2 * args.scale)):  # thick ring, readable at any zoom
        draw.ellipse(
            (cx - r + inset, cy - r + inset, cx + r - inset, cy + r - inset),
            outline=(255, 45, 85),
        )
    image.save(args.output)
    print(args.output)


if __name__ == "__main__":
    main()
