#!/usr/bin/env python3
"""Sound effects on the planets' surfaces - synthesised from scratch (numpy),
with the building blocks of tools/sfx_pirate.py.
  python3 tools/sfx_surface.py  -> sounds/surface/*.ogg (takes <name>_<n>.ogg)
                                   external/sfx/surface_analysis.md, surface_spectrograms.png
  door_open x3    a sliding door opening: a pneumatic release hiss, the panels
                  whirring apart on their motor, a soft stop as they reach the wall
  door_close x3   closing: the motor whirring them shut, a firm clunk as they
                  meet, the seal hissing tight
Each lasts about as long as the door takes to move (SlidingDoor.SPEED).
  chest_open x2   a wooden chest: the latch clicks, the lid creaks up on its hinges
  locker_open x2  a metal locker: a latch snaps, the thin door squeaks and rattles
  vault_open x2   a vault: the wheel ratchets round, the bolts clunk back, the seal hisses
"""
import os
import sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sfx_pirate as P
from sfx_pirate import SR, t_axis, env_exp, phase_of, saw, noise, fft_filter, metal, thud, place

ROOT = P.ROOT
OUT = os.path.join(ROOT, "sounds", "surface")
REPORT = os.path.join(ROOT, "external", "sfx")


def motor(dur, f0, f1, rng):
    """The door's motor: a whirring saw with gear flutter, swelling and fading."""
    t = t_axis(dur)
    f = f0 + (f1 - f0) * (t / dur) ** 0.8
    ph = phase_of(f)
    x = saw(ph) * (0.65 + 0.35 * np.sin(2 * np.pi * rng.uniform(38, 46) * t))
    x = fft_filter(x, lo=160, hi=2600)
    return x * np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 0.7


def hiss(dur, lo, hi, attack, decay, rng):
    t = t_axis(dur)
    return fft_filter(noise(len(t), rng), lo=lo, hi=hi) * env_exp(t, attack, decay)


def door_open(rng):
    x = np.zeros(int(0.5 * SR))
    place(x, hiss(0.25, 1500, 6000, 0.002, 0.05, rng) * 0.28, 0.0)            # the seal lets go
    place(x, motor(0.32, rng.uniform(170, 200), rng.uniform(400, 460), rng) * 0.8, 0.03)
    t = t_axis(0.12)
    place(x, thud(t, f=rng.uniform(95, 115), decay=0.03, rng=rng) * 0.35, 0.33)   # a soft stop in the wall
    place(x, metal(t, rng, partials=3, lo=900, hi=2600, decay=(0.02, 0.05), amp=0.12), 0.33)
    return x, -9.0


def door_close(rng):
    x = np.zeros(int(0.55 * SR))
    place(x, motor(0.3, rng.uniform(420, 460), rng.uniform(160, 190), rng) * 0.8, 0.0)
    t = t_axis(0.16)
    place(x, thud(t, f=rng.uniform(75, 90), decay=0.05, rng=rng) * 0.9, 0.29)     # the panels meet
    place(x, metal(t, rng, partials=4, lo=500, hi=2200, decay=(0.03, 0.08), amp=0.3), 0.29)
    place(x, hiss(0.18, 2000, 6500, 0.01, 0.04, rng) * 0.2, 0.31)                  # sealing tight
    return x, -9.0


def creak(dur, f0, f1, rng, rough=0.5):
    """A hinge creak: a scraping, stuttering tone."""
    t = t_axis(dur)
    f = f0 + (f1 - f0) * (t / dur) + rng.uniform(5, 20) * np.sin(2 * np.pi * rng.uniform(6, 11) * t)
    ph = phase_of(f)
    x = saw(ph) * (1 - rough + rough * (np.sin(2 * np.pi * rng.uniform(28, 45) * t) > 0.2))   # stick-slip
    x = fft_filter(x, lo=400, hi=3800)
    return x * np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 0.8


def click(rng, f=2600, amp=1.0):
    t = t_axis(0.03)
    return metal(t, rng, partials=3, lo=f * 0.6, hi=f * 1.6, decay=(0.004, 0.012), amp=amp)


def chest_open(rng):
    x = np.zeros(int(0.7 * SR))
    place(x, click(rng, 1800, 0.8), 0.0)                                   # the latch
    place(x, click(rng, 1400, 0.5), 0.05)
    place(x, creak(0.45, rng.uniform(260, 320), rng.uniform(420, 520), rng) * 0.55, 0.1)
    t = t_axis(0.12)
    place(x, thud(t, f=rng.uniform(130, 160), decay=0.025, rng=rng) * 0.4, 0.55)   # the lid at rest
    return x, -9.0


def locker_open(rng):
    x = np.zeros(int(0.6 * SR))
    place(x, click(rng, 3200, 1.0), 0.0)
    place(x, creak(0.3, rng.uniform(700, 800), rng.uniform(950, 1100), rng, rough=0.7) * 0.4, 0.06)
    t = t_axis(0.25)
    place(x, metal(t, rng, partials=6, lo=700, hi=3500, decay=(0.04, 0.12), amp=0.45), 0.34)   # the door's thin rattle
    return x, -10.0


def vault_open(rng):
    x = np.zeros(int(1.2 * SR))
    for k in range(7):                                                     # the wheel's ratchet
        place(x, click(rng, rng.uniform(2000, 2400), 0.7), 0.04 + k * 0.075)
    t = t_axis(0.2)
    place(x, thud(t, f=rng.uniform(60, 75), decay=0.07, rng=rng) * 1.0, 0.6)       # the bolts drawn back
    place(x, metal(t, rng, partials=5, lo=300, hi=1500, decay=(0.05, 0.15), amp=0.35), 0.6)
    place(x, hiss(0.4, 1200, 6000, 0.01, 0.12, rng) * 0.3, 0.65)
    place(x, motor(0.35, 120, 90, rng) * 0.35, 0.78)                      # the heavy door swinging
    return x, -8.0


SOUNDS = [("door_open", door_open, 3), ("door_close", door_close, 3), ("chest_open", chest_open, 2),
          ("locker_open", locker_open, 2), ("vault_open", vault_open, 2)]


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(REPORT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith(".ogg"):
            os.remove(os.path.join(OUT, f))
    rows, takes = [], []
    for name, fn, n in SOUNDS:
        for k in range(1, n + 1):
            rng = np.random.default_rng(sum(map(ord, name)) * 1000 + k + 11)
            x, gain_db = fn(rng)
            x = P.finish(np.asarray(x, float), gain_db)
            P.write_ogg(x, os.path.join(OUT, "%s_%d.ogg" % (name, k)))
            rows.append(("%s_%d" % (name, k), P.analyse(x)))
            if k == 1:
                takes.append(("%s_%d" % (name, k), x))
    lines = ["# Surface sound effects - analysis", "",
             "Generated by tools/sfx_surface.py (mono, 44.1 kHz, OGG Vorbis q5). Columns as in pirate_analysis.md.", "",
             "| take | s | peak dBFS | loud100 dBFS | crest dB | centroid Hz | low |", "|---|---|---|---|---|---|---|"]
    for nme, a in rows:
        lines.append("| %s | %.2f | %.1f | %.1f | %.1f | %d | %.2f |" % (nme, a["dur"], a["peak_db"], a["loud100_db"], a["crest_db"],
                                                                   a["centroid_hz"], a["low_share"]))
    with open(os.path.join(REPORT, "surface_analysis.md"), "w") as fh:
        fh.write("\n".join(lines) + "\n")
    P.sheet(takes, os.path.join(REPORT, "surface_spectrograms.png"))
    total = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT) if f.endswith(".ogg"))
    print("%d takes, %.0f KB in %s" % (len(rows), total / 1024, OUT))
    print("\n".join(lines[5:]))


if __name__ == "__main__":
    main()
