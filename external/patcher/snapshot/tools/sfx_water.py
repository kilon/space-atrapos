#!/usr/bin/env python3
"""The rivers' sounds - synthesised from scratch (numpy), with the building
blocks of tools/sfx_pirate.py.
  python3 tools/sfx_water.py  -> sounds/water/*.ogg (takes <name>_<n>.ogg)
  river_1     a seamless loop (9 s): a calm river - a soft broad wash, and the
              babble over stones: thousands of tiny bubble chirps (short rising
              sine blips, the sound a bubble makes as it forms), now and then a
              gurgle
  rapids_1    a seamless loop (9 s): white water - a deep roar (low rushing
              noise, surging), a bright hiss of spray over it, the bubbles thick
              and fast, heavier splashes
CosmosWaters plays them where the river nearest you runs (the rapids' louder).
"""
import os
import sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sfx_pirate as P
from sfx_pirate import SR, t_axis, noise, fft_filter

OUT = os.path.join(P.ROOT, "sounds", "water")


def _loop(x, fade):
    """Seamless: the tail crossfaded into the head."""
    n = int(fade * SR)
    head, tail = x[:n].copy(), x[-n:]
    w = np.linspace(0.0, 1.0, n)
    x = x[:-n].copy()
    x[:n] = head * w + tail * (1.0 - w)
    return x


def _bubbles(n_samples, rate, rng, f_lo, f_hi, amp):
    """Bubbles: each a short sine whose pitch rises as it decays (a forming bubble)."""
    x = np.zeros(n_samples)
    count = int(n_samples / SR * rate)
    for _ in range(count):
        dur = rng.uniform(0.006, 0.03)
        m = int(dur * SR)
        i = rng.integers(0, n_samples - m)
        tt = np.arange(m) / SR
        f0 = np.exp(rng.uniform(np.log(f_lo), np.log(f_hi)))
        sweep = f0 * (1.0 + tt / dur * rng.uniform(0.3, 1.4))
        ph = 2 * np.pi * np.cumsum(sweep) / SR
        x[i:i + m] += np.sin(ph) * np.exp(-tt / (dur * 0.35)) * amp * rng.uniform(0.3, 1.0)
    return x


def river(rng):
    dur = 9.6
    t = t_axis(dur)
    n = len(t)
    wash = fft_filter(noise(n, rng), lo=150, hi=2200) * 0.32
    wash *= 1.0 + 0.12 * np.sin(2 * np.pi * 0.21 * t) * np.sin(2 * np.pi * 0.053 * t + 1.0)
    hiss = fft_filter(noise(n, rng), lo=2500, hi=9000) * 0.05
    bub = _bubbles(n, 650, rng, 500, 2600, 0.11)
    gur = np.zeros(n)
    for _ in range(int(dur * 2.5)):   # (gurgles: a low bubble burst now and then)
        i = rng.integers(0, n - 9000)
        gur[i:i + 9000] += _bubbles(9000, 900, rng, 180, 600, 0.14) * np.hanning(9000)
    x = wash + hiss + fft_filter(bub, lo=300, hi=5000) + gur
    return _loop(x, 0.7), -12.0


def rapids(rng):
    dur = 9.6
    t = t_axis(dur)
    n = len(t)
    surge = 0.75 + 0.25 * np.sin(2 * np.pi * 0.17 * t + 0.4) * np.sin(2 * np.pi * 0.071 * t + 2.2)
    roar = fft_filter(noise(n, rng), lo=40, hi=900) * 0.9 * surge
    rush = fft_filter(noise(n, rng), lo=600, hi=4000) * 0.35 * surge
    spray = fft_filter(noise(n, rng), lo=3500, hi=12000) * 0.16
    bub = _bubbles(n, 2600, rng, 300, 3000, 0.09)
    spl = np.zeros(n)
    for _ in range(int(dur * 6)):   # (splashes: a burst of broadband noise falling off)
        i = rng.integers(0, n - 6000)
        spl[i:i + 6000] += fft_filter(noise(6000, rng), lo=400, hi=8000) * np.exp(-np.arange(6000) / rng.uniform(600, 1800)) * rng.uniform(0.2, 0.6)
    x = roar + rush + spray + fft_filter(bub, lo=250, hi=6000) + spl
    return _loop(x, 0.7), -7.0


SOUNDS = [("river", river, 1), ("rapids", rapids, 1)]


def main():
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith(".ogg"):
            os.remove(os.path.join(OUT, f))
    for name, fn, n in SOUNDS:
        for k in range(1, n + 1):
            rng = np.random.default_rng(sum(map(ord, name)) * 1000 + k + 29)
            x, gain_db = fn(rng)
            x = P.finish(np.asarray(x, float), gain_db)
            P.write_ogg(x, os.path.join(OUT, "%s_%d.ogg" % (name, k)))
    print("water sounds in", OUT, sorted(os.listdir(OUT)))


if __name__ == "__main__":
    main()
