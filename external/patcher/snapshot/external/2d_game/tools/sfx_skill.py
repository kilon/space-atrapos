#!/usr/bin/env python3
"""The sounds of the automaton's skills (Skills), synthesised from scratch with
the building blocks of tools/sfx_pirate.py (numpy: oscillators, filtered noise,
thuds, crackle) and written as OGG Vorbis.

  python3 tools/sfx_skill.py     -> sounds/skill/*.ogg (takes <name>_<n>.ogg) + takes.json

  whoosh   a limb through the air (a blow thrown)          (3 takes)
  punch    a fist landing: a smack and a thump             (4)
  kick     a foot landing: heavier, lower                  (3)
  leap     servos kicking off: a rising rush               (2)
  land     both feet down: a thud and grit                 (2)
  guard    arms braced: a metal clack                      (2)
  cast     a spell gathering: a rising shimmer             (2)
  beam     the Helios Lance: a bright sustained ray        (2)
  fire     Phlox thrown: a roaring whoosh                  (2)
  burst    Phlox bursting: a boom and crackle              (2)
  thunder  Keraunos: a crack and a rolling rumble          (2)
  dome     the Aegis Dome going up: a swelling hum         (1)
  summon   the eidola rising: a low chord and a shimmer    (1)
  levelup  a level gained: a rising three-note chime       (1)
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sfx_pirate as S   # noqa: E402

OUT = os.path.join(S.ROOT, "sounds", "skill")


def whoosh(rng):
    t = S.t_axis(0.22)
    f = rng.uniform(500, 800) + 1600 * np.sin(np.pi * t / t[-1]) ** 2
    x = S.biquad_bp(S.noise(len(t), rng), f, 2.2) * np.sin(np.pi * t / t[-1]) ** 1.5
    return x, -9.0


def punch(rng):
    t = S.t_axis(0.2)
    smack = S.fft_filter(S.noise(len(t), rng), lo=700, hi=5000) * S.env_exp(t, 0.0005, rng.uniform(0.012, 0.02))
    body = S.thud(t, rng.uniform(95, 130), 0.045, rng)
    clank = S.metal(t, rng, 4, 900, 3000, (0.01, 0.04), 0.5)
    return smack * 0.9 + body * 1.2 + clank, -2.0


def kick(rng):
    t = S.t_axis(0.28)
    smack = S.fft_filter(S.noise(len(t), rng), lo=400, hi=3500) * S.env_exp(t, 0.0005, 0.02)
    body = S.thud(t, rng.uniform(60, 80), 0.08, rng)
    clank = S.metal(t, rng, 5, 500, 2200, (0.02, 0.07), 0.6)
    return smack * 0.8 + body * 1.5 + clank, -1.5


def leap(rng):
    t = S.t_axis(0.42)
    f = 300 + 2200 * (t / t[-1]) ** 1.6
    rush = S.biquad_bp(S.noise(len(t), rng), f, 1.8) * np.sin(np.pi * t / t[-1]) ** 0.8
    ph = S.phase_of(160 + 500 * (t / t[-1]) ** 2)
    servo = S.fft_filter(S.saw(ph), lo=200, hi=3500) * S.env_exp(t, 0.02, 0.15) * 0.35
    return rush + servo, -6.0


def land(rng):
    t = S.t_axis(0.3)
    x = S.thud(t, rng.uniform(55, 70), 0.09, rng) * 1.5
    grit = S.fft_filter(S.noise(len(t), rng), lo=1500, hi=6000) * S.env_exp(t, 0.002, 0.05) * 0.35
    return x + grit + S.metal(t, rng, 3, 400, 1500, (0.02, 0.06), 0.4), -3.0


def guard(rng):
    t = S.t_axis(0.25)
    return S.metal(t, rng, 6, 700, 3600, (0.03, 0.1), 1.2) + S.thud(t, 140, 0.03) * 0.6, -6.0


def cast(rng):
    t = S.t_axis(0.5)
    u = t / t[-1]
    x = np.zeros_like(t)
    for k, base in enumerate((330, 495, 660, 990)):
        ph = S.phase_of(base * (1 + 0.6 * u ** 2) * (1 + 0.004 * np.sin(2 * np.pi * (5 + k) * t)))
        x += np.sin(ph) / (k + 1)
    shimmer = S.fft_filter(S.noise(len(t), rng), lo=4000) * u ** 2 * 0.25
    return (x * 0.5 + shimmer) * np.sin(np.pi * u) ** 0.6, -10.0


def beam(rng):
    t = S.t_axis(0.6)
    u = t / t[-1]
    ph = S.phase_of(rng.uniform(420, 480) * (1 + 0.02 * np.sin(2 * np.pi * 31 * t)))
    ray = S.fft_filter(S.saw(ph) * 0.5 + S.square(ph * 2.01, 0.4) * 0.3, lo=200, hi=7000)
    hiss = S.fft_filter(S.noise(len(t), rng), lo=3000) * 0.3
    env = np.minimum(1.0, u * 12) * (1 - u) ** 0.6
    return (ray + hiss) * env + S.thud(t, 70, 0.08) * 0.8, -3.0


def fire(rng):
    t = S.t_axis(0.5)
    u = t / t[-1]
    f = 900 - 500 * u
    roar = S.biquad_bp(S.noise(len(t), rng), f, 1.2) * np.minimum(1.0, u * 15) * (1 - u) ** 0.8
    low = S.fft_filter(S.noise(len(t), rng), hi=220) * (1 - u) * 0.8
    return roar + low, -5.0


def burst(rng):
    t = S.t_axis(0.8)
    boom = S.thud(t, rng.uniform(45, 58), 0.18, rng) * 1.6
    blast = S.fft_filter(S.noise(len(t), rng), lo=200, hi=4000) * S.env_exp(t, 0.001, 0.09)
    crack = S.crackle(t, rng, 90, 0.003, 0.5) * np.exp(-t / 0.3)
    return boom + blast + crack, -1.0


def thunder(rng):
    t = S.t_axis(1.1)
    crack = S.fft_filter(S.noise(len(t), rng), lo=1500, hi=9000) * S.env_exp(t, 0.0005, 0.03) * 1.5
    zap = S.crackle(t, rng, 220, 0.003, 0.9) * np.exp(-t / 0.12)
    rumble = S.fft_filter(S.noise(len(t), rng), hi=260) * S.env_exp(t, 0.03, 0.4) * 1.6
    rumble *= 1 + 0.5 * np.sin(2 * np.pi * rng.uniform(5, 9) * t)
    return crack + zap + rumble, -1.0


def dome(rng):
    t = S.t_axis(0.9)
    u = t / t[-1]
    x = np.zeros_like(t)
    for k, f in enumerate((110, 165, 220, 330)):
        x += np.sin(S.phase_of(f * (1 + 0.08 * u))) / (k + 1)
    ring = np.sin(S.phase_of(880 + 440 * u)) * u ** 2 * 0.2
    return (x * 0.6 + ring) * np.sin(np.pi * u) ** 0.5, -6.0


def summon(rng):
    t = S.t_axis(1.1)
    u = t / t[-1]
    x = np.zeros_like(t)
    for k, f in enumerate((82.4, 123.5, 164.8, 246.9, 329.6)):
        x += np.sin(S.phase_of(f * (1 + 0.003 * np.sin(2 * np.pi * (3 + k) * t)))) / (k + 1) ** 0.7
    shimmer = S.fft_filter(S.noise(len(t), rng), lo=5000) * np.sin(np.pi * u) ** 2 * 0.2
    return (x * 0.5 + shimmer) * np.sin(np.pi * u) ** 0.5, -6.0


def levelup(rng):
    t = S.t_axis(0.9)
    x = np.zeros_like(t)
    for i, f in enumerate((523.25, 659.25, 783.99, 1046.5)):
        tt = S.t_axis(0.5)
        note = (np.sin(2 * np.pi * f * tt) + 0.4 * np.sin(2 * np.pi * f * 2 * tt)) * S.env_exp(tt, 0.004, 0.16)
        S.place(x, note, i * 0.1)
    return x, -8.0


SOUNDS = [("whoosh", whoosh, 3), ("punch", punch, 4), ("kick", kick, 3), ("leap", leap, 2), ("land", land, 2), ("guard", guard, 2),
          ("cast", cast, 2), ("beam", beam, 2), ("fire", fire, 2), ("burst", burst, 2), ("thunder", thunder, 2), ("dome", dome, 1),
          ("summon", summon, 1), ("levelup", levelup, 1)]


def main():
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith(".ogg"):
            os.remove(os.path.join(OUT, f))
    index = {}
    for name, fn, n in SOUNDS:
        index[name] = n
        for k in range(1, n + 1):
            rng = np.random.default_rng(sum(map(ord, name)) * 1000 + k)
            x, gain_db = fn(rng)
            S.write_ogg(S.finish(np.asarray(x, float), gain_db), os.path.join(OUT, "%s_%d.ogg" % (name, k)))
    with open(os.path.join(OUT, "takes.json"), "w") as fh:
        json.dump(index, fh, indent=1, sort_keys=True)
    total = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT) if f.endswith(".ogg"))
    print("%d sounds, %d takes, %.0f KB in %s" % (len(SOUNDS), sum(index.values()), total / 1024, OUT))


if __name__ == "__main__":
    main()
