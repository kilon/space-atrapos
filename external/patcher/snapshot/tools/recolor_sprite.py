#!/usr/bin/env python3
"""Recolour a sprite into another livery: every coloured part (saturation above
a threshold) takes the new hue, the bare metal (greys, whites, blacks) stays.

Used for the Independents' placeholder art (steel and emerald) until they have
a reference sheet of their own:

    python3 tools/recolor_sprite.py <src.png> <dst.png> [--hue 0.40] [--sat 0.8] [--min-sat 0.18]

--hue      the new hue, 0..1 (0.40: emerald)
--sat      multiplier for the coloured parts' saturation
--min-sat  pixels less saturated than this count as bare metal (kept)
--steel    also cool the bare metal a little toward steel blue-grey (0..1)
--glow     the brightest, most saturated parts (lights, engines) keep this
           saturation multiplier instead of --sat (so a muted hull still has
           vivid lights)
"""
import sys

import numpy as np
from PIL import Image


def recolor(src: str, dst: str, hue: float, sat: float, min_sat: float, steel: float, glow: float) -> None:
    im = Image.open(src).convert("RGBA")
    a = np.asarray(im).astype(np.float32) / 255.0
    rgb, alpha = a[..., :3], a[..., 3:]
    hsv = np.asarray(Image.fromarray((rgb * 255).astype(np.uint8), "RGB").convert("HSV")).astype(np.float32) / 255.0
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    coloured = s > min_sat
    # Smooth edge between metal and paint: weight by how far past the threshold.
    w = np.clip((s - min_sat) / 0.12, 0.0, 1.0)
    h2 = np.where(coloured, hue, h)
    lit = np.clip((v - 0.75) / 0.2, 0.0, 1.0) * np.clip((s - 0.5) / 0.3, 0.0, 1.0)   # lights, engines
    s2 = np.where(coloured, np.clip(s * (sat * (1.0 - lit) + glow * lit), 0.0, 1.0), s)
    new = np.stack([h2, s2, v], axis=-1)
    new_rgb = np.asarray(Image.fromarray((new * 255).astype(np.uint8), "HSV").convert("RGB")).astype(np.float32) / 255.0
    out = rgb * (1.0 - w[..., None]) + new_rgb * w[..., None]
    if steel > 0.0:
        grey = (1.0 - w)[..., None]
        tint = np.array([0.92, 0.97, 1.05], dtype=np.float32)
        out = out * (1.0 - steel * grey) + np.clip(out * tint, 0.0, 1.0) * (steel * grey)
    res = np.concatenate([np.clip(out, 0.0, 1.0), alpha], axis=-1)
    Image.fromarray((res * 255).astype(np.uint8), "RGBA").save(dst)


def main() -> None:
    args = []
    skip = False
    for a in sys.argv[1:]:
        if skip:
            skip = False
        elif a.startswith("--"):
            skip = True   # (its value follows)
        else:
            args.append(a)
    if len(args) != 2:
        print(__doc__)
        sys.exit(1)

    def opt(name: str, default: float) -> float:
        for i, a in enumerate(sys.argv):
            if a == "--" + name and i + 1 < len(sys.argv):
                return float(sys.argv[i + 1])
        return default

    sat = opt("sat", 0.8)
    recolor(args[0], args[1], opt("hue", 0.40), sat, opt("min-sat", 0.18), opt("steel", 0.6), opt("glow", sat))


if __name__ == "__main__":
    main()
