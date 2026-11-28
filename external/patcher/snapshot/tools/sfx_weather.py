#!/usr/bin/env python3
"""The weather's sounds - synthesised from scratch (numpy), with the building
blocks of tools/sfx_pirate.py.
  python3 tools/sfx_weather.py  -> sounds/weather/*.ogg (takes <name>_<n>.ogg)
  rain_1      a seamless loop (8 s): the hiss of rain - a broad band of noise,
              thousands of tiny drop ticks in it, a few heavier spatters
  wind_1      a seamless loop (10 s): wind - low rushing noise swelling and
              ebbing in gusts, a faint whistle in the gusts
  thunder x4  distant thunder: a crack (for the near ones), then the long
              rolling rumble, uneven, fading
CosmosWeatherFx plays them (the loops up and down with the weather; the thunder
as late as the bolt struck far).
"""
import os
import sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sfx_pirate as P
from sfx_pirate import SR, t_axis, noise, fft_filter

OUT = os.path.join(P.ROOT, "sounds", "weather")


def _loop(x, fade):
    """Seamless: the tail crossfaded into the head."""
    n = int(fade * SR)
    head, tail = x[:n].copy(), x[-n:]
    w = np.linspace(0.0, 1.0, n)
    x = x[:-n].copy()
    x[:n] = head * w + tail * (1.0 - w)
    return x


def rain(rng):
    dur = 8.6
    t = t_axis(dur)
    x = fft_filter(noise(len(t), rng), lo=900, hi=9000) * 0.55
    x += fft_filter(noise(len(t), rng), lo=200, hi=1500) * 0.2
    ticks = np.zeros(len(t))
    for _ in range(int(dur * 900)):   # (drops: short clicks, a tiny decay each)
        i = rng.integers(0, len(t) - 200)
        a = rng.uniform(0.05, 0.35)
        ticks[i:i + 60] += a * np.exp(-np.arange(60) / rng.uniform(6, 18)) * rng.choice([-1, 1])
    for _ in range(int(dur * 14)):    # (heavier spatters)
        i = rng.integers(0, len(t) - 2000)
        ticks[i:i + 1800] += rng.uniform(0.2, 0.5) * fft_filter(noise(1800, rng), lo=1500, hi=7000) * np.exp(-np.arange(1800) / 400.0)
    x += fft_filter(ticks, lo=1200, hi=12000) * 0.8
    x *= 1.0 + 0.08 * np.sin(2 * np.pi * 0.23 * t)
    return _loop(x, 0.6), -10.0


def wind(rng):
    dur = 10.6
    t = t_axis(dur)
    base = fft_filter(noise(len(t), rng), lo=60, hi=700)
    gust = 0.55 + 0.45 * np.sin(2 * np.pi * 0.11 * t + 0.7) * np.sin(2 * np.pi * 0.037 * t + 2.0)
    gust = np.clip(gust, 0.15, 1.0)
    x = base * gust
    whistle = fft_filter(noise(len(t), rng), lo=900, hi=1300) * 0.25 * gust ** 3
    x = x + whistle
    return _loop(x, 0.8), -12.0


def thunder(rng):
    dur = rng.uniform(4.5, 7.0)
    t = t_axis(dur)
    x = np.zeros(len(t))
    near = rng.random() < 0.5
    if near:   # (the crack: a sharp broadband tear)
        n = int(0.35 * SR)
        x[:n] += fft_filter(noise(n, rng), lo=300, hi=6000) * np.exp(-np.arange(n) / (0.07 * SR)) * 1.4
    roll = fft_filter(noise(len(t), rng), lo=25, hi=260)
    env = np.zeros(len(t))
    k = 0.15
    while k < dur - 0.5:   # (the rumble: uneven peals, each swelling and dying)
        c = int(k * SR)
        w = int(rng.uniform(0.6, 1.6) * SR)
        seg = np.sin(np.pi * np.linspace(0, 1, min(w, len(t) - c))) ** 1.5 * rng.uniform(0.4, 1.0)
        env[c:c + len(seg)] = np.maximum(env[c:c + len(seg)], seg)
        k += rng.uniform(0.35, 1.1)
    env *= np.exp(-t / (dur * 0.55))
    x += roll * env * 1.6
    return x, -6.0


SOUNDS = [("rain", rain, 1), ("wind", wind, 1), ("thunder", thunder, 4)]


def main():
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith(".ogg"):
            os.remove(os.path.join(OUT, f))
    for name, fn, n in SOUNDS:
        for k in range(1, n + 1):
            rng = np.random.default_rng(sum(map(ord, name)) * 1000 + k + 17)
            x, gain_db = fn(rng)
            x = P.finish(np.asarray(x, float), gain_db)
            P.write_ogg(x, os.path.join(OUT, "%s_%d.ogg" % (name, k)))
    print("weather sounds in", OUT, sorted(os.listdir(OUT)))


if __name__ == "__main__":
    main()
