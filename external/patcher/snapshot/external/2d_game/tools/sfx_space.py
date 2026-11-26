#!/usr/bin/env python3
"""Sound effects for space: the ships (yours and the others), their weapons,
hits and explosions, the stations and jump gates - synthesised from scratch
(numpy), with the building blocks of tools/sfx_pirate.py.

  python3 tools/sfx_space.py   -> sounds/space/*.ogg (takes <name>_<n>.ogg)
                                  external/sfx/space_analysis.md, space_spectrograms.png
  python3 tools/sfx_space.py <name>...   -> only those sounds (the rest left as they are)

One-shots (Sfx plays a random take, pitch varied a little):
  signal_found x1   signal sources located: an eerie rising chime, twice
  hazard_zap x2     inside a signal site's anomaly: a crackle and a low buzz
  monster_roar x1   the Void Leviathan: a vast warbling moan with a growl
  laser x4          your laser: a quick bright pew
  plasma x3         the plasma cannon: a fat, wobbling blast with a low thump
  missile x3        a missile launch: a clunk, a hiss and a rising whoosh
  enemy_laser x4    other ships' lasers: thinner, more nasal
  hit_shield x4     a hit on your shields: a ringing energy "tchong"
  hit_hull x4       a hit on your hull: a metal clang and crunch
  spark x4          a laser bolt striking another ship: a short crackle
  boom_small x3     a missile / plasma impact: a crisp, short explosion
  boom_big x3       a ship exploding: a deep rumbling blast and debris
  ship_boom_small x3   a fighter / interceptor blowing up: a sharp crack, a fireball whoomp,
                       debris pinging away, a short rumble
  ship_boom_medium x3  a gunship / freighter: a heavier blast, two secondary pops, more debris
  ship_boom_large x2   a frigate or bigger (bosses too): a deep detonation, a chain of secondary
                       blasts, the hull groaning apart, a long rumbling tail
  ship_boom_player x1  your own ship: the reactor whining up, a huge blast, a ringing in your ears
  scan_laser x2     the scanner sweeping an asteroid: a buzzing laser warble, data chirps
  scan_pulse x2     a system scan: a deep sonar-like energy pulse rippling outwards, three times
  scan_done x1      a scan complete: two bright rising blips
  shields_down x1   an alarm: two falling tones, twice
  afterburner x2    a roaring kick, sweeping up
  shield_boost x2   a rising charge and a shimmering hum
  repair x2         ratchets and a welding buzz, then a chime
  rock_break x3     an asteroid shattering: a stony crunch and pebbles
  pickup x3         an item picked up: a soft blip up
  credits x3        credits: bright coin chimes
  dock x1           docking: thrusters easing, clamps, a pressure hiss
  undock x1         undocking: a release hiss, clamps letting go, thrust up
  jump x2           a jump: charging up, then a swooping warp
  land x1           descending into the atmosphere: a rushing roar down
  take_off x1       climbing out: a roar up, fading into space
  select x2         a weapon selected: a short double tick
Loops (seamless; played continuously, faded by the game):
  engine_loop       your engine: a low hum and soft rumble (louder / higher with thrust)
  mining_loop       the mining beam: a buzzing, crackling laser
  station_hum       a station: a deep machinery hum with a slow throb and distant clanks
  gate_hum          a jump gate: an eerie chord shimmering in and out
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sfx_pirate as P   # (the building blocks and the writer)
from sfx_pirate import SR, t_axis, env_exp, phase_of, saw, square, noise, fft_filter, biquad_bp, metal, thud, crackle, place, echo, fade

ROOT = P.ROOT
OUT = os.path.join(ROOT, "sounds", "space")
REPORT = os.path.join(ROOT, "external", "sfx")


def laser(rng):
    t = t_axis(0.2)
    f = rng.uniform(1900, 2400) * np.exp(-t / rng.uniform(0.025, 0.035)) + rng.uniform(380, 480)
    ph = phase_of(f)
    x = (square(ph, 0.25) * 0.6 + np.sin(ph) * 0.4) * env_exp(t, 0.001, 0.05)
    x += fft_filter(noise(len(t), rng), lo=3000) * env_exp(t, 0.0005, 0.006) * 0.3
    return echo(fft_filter(x, lo=200, hi=9000), 0.045, 0.18, 2), -8.0


def plasma(rng):
    t = t_axis(0.55)
    f = rng.uniform(600, 750) * np.exp(-t / 0.09) + rng.uniform(70, 90)
    f *= 1 + 0.08 * np.sin(2 * np.pi * rng.uniform(25, 35) * t)        # (the wobble)
    ph = phase_of(f)
    x = (saw(ph) * 0.5 + square(ph, 0.5) * 0.5) * env_exp(t, 0.003, 0.14)
    x = fft_filter(x, lo=50, hi=4000)
    x += thud(t, 55, 0.08) * 0.9
    x += fft_filter(noise(len(t), rng), lo=500, hi=4000) * env_exp(t, 0.002, 0.05) * 0.35
    return echo(x, 0.07, 0.25, 3), -4.0


def missile(rng):
    t = t_axis(1.0)
    x = np.zeros_like(t)
    place(x, metal(t_axis(0.15), rng, 4, 400, 1800, (0.02, 0.06), 0.9) + thud(t_axis(0.15), 90, 0.03) * 0.7, 0.0)
    hiss = fft_filter(noise(len(t), rng), lo=1500, hi=8000) * env_exp(t - 0.05, 0.03, 0.25) * (t > 0.05) * 0.5
    whoosh_f = 300 + 1500 * np.clip((t - 0.08) / 0.8, 0, 1) ** 0.6
    whoosh = biquad_bp(noise(len(t), rng), whoosh_f, 3) * np.clip((t - 0.06) / 0.1, 0, 1) * np.exp(-np.maximum(t - 0.2, 0) / 0.35)
    return x + hiss + whoosh * 0.6, -5.0


def enemy_laser(rng):
    t = t_axis(0.22)
    f = rng.uniform(1300, 1600) * np.exp(-t / 0.04) + rng.uniform(250, 320)
    ph = phase_of(f)
    x = saw(ph) * env_exp(t, 0.001, 0.06)
    x = biquad_bp(x, 1400, 2.2) + fft_filter(x, lo=300, hi=5000) * 0.4    # (nasal)
    return echo(x, 0.05, 0.15, 2), -10.0


def hit_shield(rng):
    t = t_axis(0.6)
    out = np.zeros_like(t)
    for f in rng.uniform([600, 900, 1350], [700, 1050, 1600]):
        out += np.sin(2 * np.pi * f * t * (1 + 0.04 * np.exp(-t / 0.05))) * np.exp(-t / rng.uniform(0.12, 0.2))
    out = out / 3 * (1 + 0.5 * np.sin(2 * np.pi * 18 * t))                  # (a shimmer)
    zap = fft_filter(noise(len(t), rng), lo=2500, hi=9000) * env_exp(t, 0.0005, 0.02) * 0.6
    return out + zap, -6.0


def hit_hull(rng):
    t = t_axis(0.5)
    x = metal(t, rng, 7, 300, 3500, (0.04, 0.18), 1.2) + thud(t, rng.uniform(70, 100), 0.05, rng) * 0.8
    x += fft_filter(noise(len(t), rng), lo=800, hi=6000) * env_exp(t, 0.001, 0.03) * 0.5     # (crunch)
    return x, -4.0


def spark(rng):
    t = t_axis(0.18)
    x = crackle(t, rng, 300, amp=0.6) * np.exp(-t / 0.05)
    x += fft_filter(noise(len(t), rng), lo=2000, hi=9000) * env_exp(t, 0.0005, 0.025) * 1.0
    x += np.sin(2 * np.pi * rng.uniform(1800, 2600) * t) * env_exp(t, 0.001, 0.03) * 0.4      # (a little ping)
    return x, -7.0


def boom(rng, size):
    dur = 0.8 if size == "small" else 2.6
    t = t_axis(dur)
    dec = 0.12 if size == "small" else 0.6
    body = fft_filter(noise(len(t), rng), hi=1500 if size == "small" else 700) * env_exp(t, 0.002, dec)
    crack = fft_filter(noise(len(t), rng), lo=1500, hi=9000) * env_exp(t, 0.0005, 0.02 if size == "small" else 0.05)
    low = thud(t, 50 if size == "small" else 38, 0.12 if size == "small" else 0.45) * (0.8 if size == "small" else 1.3)
    x = body + crack * 0.6 + low
    if size == "big":
        # rumble with random swells, and debris clanks scattered after
        rumble = fft_filter(noise(len(t), rng), hi=200) * env_exp(t, 0.05, 1.0) * 1.2
        x += rumble
        for k in range(6):
            place(x, metal(t_axis(0.3), rng, 4, 600, 3000, (0.03, 0.1), 0.25), rng.uniform(0.2, 1.4))
        x += crackle(t, rng, 60, amp=0.35) * np.exp(-t / 0.8)
    return echo(x, 0.09, 0.25, 3), (-3.0 if size == "small" else -1.0)


def _blast(rng, dur, body_hi, body_dec, thump_f, thump_dec, crack_dec, amp=1.0):
    """One explosion: a crack, a fireball (bright then dark), a falling thump."""
    t = t_axis(dur)
    bright = fft_filter(noise(len(t), rng), lo=300, hi=body_hi) * env_exp(t, 0.002, body_dec * 0.35)
    dark = fft_filter(noise(len(t), rng), hi=body_hi * 0.35) * env_exp(t, 0.008, body_dec)
    crack = fft_filter(noise(len(t), rng), lo=2000, hi=10000) * env_exp(t, 0.0004, crack_dec)
    snap = metal(t, rng, 4, 2500, 6500, (0.004, 0.015), 1.0)
    low = thud(t, thump_f, thump_dec, rng)
    return (bright * 0.7 + dark * 0.9 + crack * 0.55 + snap * 0.5 + low * 1.3) * amp


def ship_boom(rng, size):
    cfg = {  # dur, body hi, body decay, thump f, thump decay, crack decay, secondaries, debris, tail
        "small": (1.8, 2600, 0.22, rng.uniform(52, 62), 0.16, 0.025, 0, 4, 0.5),
        "medium": (2.8, 2000, 0.35, rng.uniform(42, 50), 0.28, 0.035, 2, 7, 0.9),
        "large": (4.6, 1500, 0.6, rng.uniform(32, 38), 0.5, 0.05, 5, 11, 1.6),
        "player": (4.4, 1600, 0.55, 34, 0.5, 0.05, 3, 9, 1.4),
    }[size]
    dur, hi, dec, f, tdec, cdec, n_sec, n_debris, tail = cfg
    x = np.zeros(int(dur * SR))
    t = t_axis(dur)
    at = 0.0
    if size == "player":   # the reactor whining up to the breaking point
        w = t_axis(0.5)
        ph = phase_of(420 + 1500 * (w / 0.5) ** 2)
        whine = (np.sin(ph) * 0.6 + saw(ph) * 0.15) * (0.5 + 0.5 * np.sin(2 * np.pi * 22 * w)) * (w / 0.5) ** 1.5
        place(x, fft_filter(whine, lo=300, hi=6000) * 0.35, 0.0)
        at = 0.48
    place(x, _blast(rng, dur - at, hi, dec, f, tdec, cdec), at)
    # Secondary blasts: smaller, higher, scattered after the first.
    for k in range(n_sec):
        when = at + rng.uniform(0.18, 0.35 + dur * 0.45) * (1 + k * 0.15)
        if when < dur - 0.4:
            place(x, _blast(rng, 0.9, hi * 1.3, dec * 0.4, f * rng.uniform(1.3, 1.8), tdec * 0.45, cdec * 0.8,
                            amp=rng.uniform(0.35, 0.65)), when)
    # The hull groaning apart (big ships).
    if size in ("large", "player"):
        g = t_axis(1.6)
        ph = phase_of(rng.uniform(85, 100) * np.exp(-g / 1.4))
        groan = saw(ph) * (0.6 + 0.4 * np.sin(2 * np.pi * 7 * g)) * env_exp(g, 0.25, 0.8)
        place(x, fft_filter(groan, lo=60, hi=900) * 0.3, at + 0.5)
    # Debris pinging away, burning crackle, a rumbling tail.
    for k in range(n_debris):
        place(x, metal(t_axis(0.35), rng, 4, 700, 4200, (0.02, 0.09), rng.uniform(0.12, 0.3)), at + rng.uniform(0.15, dur * 0.7))
    x += crackle(t, rng, 50 + 15 * n_sec, amp=0.3) * np.exp(-t / (dur * 0.35)) * (t > at)
    x += fft_filter(noise(len(t), rng), hi=180) * env_exp(np.maximum(t - at, 0), 0.06, tail) * (t > at) * 1.1
    if size == "player":   # a ringing in your ears, fading
        x += np.sin(2 * np.pi * 3600 * t) * 0.04 * env_exp(np.maximum(t - at, 0), 0.3, 1.2) * (t > at)
    return echo(x, 0.11, 0.22, 3), -1.0


def scan_laser(rng):
    t = t_axis(1.3)
    f = 900 + 500 * np.sin(2 * np.pi * 1.15 * t) + 60 * np.sin(2 * np.pi * 31 * t)    # sweeping back and forth
    ph = phase_of(f)
    x = (np.sin(ph) * 0.6 + square(ph, 0.3) * 0.2) * (0.7 + 0.3 * np.sin(2 * np.pi * 47 * t))
    x = fft_filter(x, lo=300, hi=6000) * np.minimum(1.0, t / 0.05) * np.minimum(1.0, (1.3 - t) / 0.15)
    for k in range(9):   # data chirps
        c = t_axis(0.03)
        place(x, np.sin(phase_of(rng.uniform(2500, 4200) + 3000 * c / 0.03)) * np.exp(-c / 0.012) * 0.25, rng.uniform(0.05, 1.2))
    return x, -9.0


def scan_pulse(rng):
    x = np.zeros(int(2.6 * SR))
    for k in range(3):   # three pulses, like the rings
        t = t_axis(1.8)
        ph = phase_of(rng.uniform(150, 170) * np.exp(-t / 1.2) + 60)
        ping = np.sin(ph) * env_exp(t, 0.004, 0.5) + np.sin(ph * 2.01) * env_exp(t, 0.004, 0.25) * 0.4
        whoosh = fft_filter(noise(len(t), rng), lo=200, hi=2200) * env_exp(t, 0.05, 0.4) * 0.25
        place(x, (ping + whoosh) * (1.0 - k * 0.25), k * 0.28)
    return echo(x, 0.16, 0.35, 4), -4.0


def scan_done(rng):
    x = np.zeros(int(0.4 * SR))
    for k, f in enumerate([1320, 1980]):
        t = t_axis(0.15)
        place(x, np.sin(phase_of(f * (1 + 0.15 * t / 0.15))) * env_exp(t, 0.003, 0.06), k * 0.09)
    return x, -10.0


def signal_found(rng):
    """Signal sources located: an eerie rising chime with a faint warble, twice."""
    x = np.zeros(int(1.6 * SR))
    for k, f0 in enumerate([520, 780]):
        t = t_axis(0.9)
        f = f0 * (1 + 0.5 * (t / 0.9) ** 0.6) * (1 + 0.012 * np.sin(2 * np.pi * 7 * t))
        ph = phase_of(f)
        tone = (np.sin(ph) + 0.35 * np.sin(ph * 2.002) + 0.15 * np.sin(ph * 3.01)) * env_exp(t, 0.02, 0.35)
        place(x, tone * (1.0 - 0.2 * k), 0.22 * k)
    return echo(x, 0.18, 0.4, 4), -8.0


def hazard_zap(rng):
    """Inside an anomaly: an electric crackle with a low buzz."""
    t = t_axis(0.45)
    buzz = saw(phase_of(55 + 8 * np.sin(2 * np.pi * 9 * t))) * env_exp(t, 0.01, 0.2) * 0.5
    x = fft_filter(buzz, lo=40, hi=1200)
    for k in range(int(rng.uniform(5, 9))):
        c = t_axis(rng.uniform(0.01, 0.03))
        place(x, fft_filter(noise(len(c), rng), lo=1500, hi=9000) * np.exp(-c / 0.006) * rng.uniform(0.4, 0.9), rng.uniform(0.0, 0.35))
    return x, -10.0


def monster_roar(rng):
    """The Void Leviathan: a vast, slow, warbling moan with a growl under it."""
    t = t_axis(3.2)
    f = 62 * (1 + 0.25 * np.sin(np.pi * t / 3.2)) * (1 + 0.03 * np.sin(2 * np.pi * 4.5 * t))
    ph = phase_of(f)
    body = saw(ph) * 0.6 + np.sin(ph * 1.5) * 0.4
    growl = body * (0.6 + 0.4 * np.sin(2 * np.pi * 23 * t))
    x = fft_filter(growl, lo=30, hi=900) * env_exp(t, 0.6, 1.6)
    x += fft_filter(noise(len(t), rng), lo=200, hi=1400) * env_exp(t, 0.4, 1.2) * 0.12   # breath
    return echo(x, 0.31, 0.45, 5), -4.0


def shields_down(rng):
    parts = []
    for k in range(2):
        for f in (880, 660):
            tt = t_axis(0.16)
            parts += [square(phase_of(np.full(len(tt), float(f))), 0.5) * np.hanning(len(tt)) ** 0.3 * 0.5, np.zeros(int(0.03 * SR))]
        parts.append(np.zeros(int(0.12 * SR)))
    return fft_filter(np.concatenate(parts), hi=5000), -15.0


def afterburner(rng):
    t = t_axis(1.6)
    roar = fft_filter(noise(len(t), rng), lo=60, hi=900) * env_exp(t, 0.05, 0.7)
    sweep = biquad_bp(noise(len(t), rng), 200 + 1800 * np.clip(t / 0.9, 0, 1), 2.5) * env_exp(t, 0.1, 0.5)
    kick = thud(t, 45, 0.15) * 1.2
    return roar + sweep * 0.7 + kick, -3.0


def shield_boost(rng):
    t = t_axis(1.4)
    f = 220 + 660 * np.clip(t / 0.8, 0, 1) ** 1.5
    ph = phase_of(f)
    rise = (np.sin(ph) + 0.4 * np.sin(2 * ph) + 0.2 * np.sin(3.01 * ph)) * np.clip(t / 0.8, 0, 1) * np.exp(-np.maximum(t - 0.8, 0) / 0.25)
    shimmer = sum(np.sin(2 * np.pi * f2 * t) for f2 in (880, 1320, 1760.5)) / 3 * np.clip((t - 0.7) / 0.1, 0, 1) * np.exp(-np.maximum(t - 0.8, 0) / 0.3)
    shimmer *= 1 + 0.6 * np.sin(2 * np.pi * 14 * t)
    return rise * 0.6 + shimmer * 0.5, -5.0


def repair(rng):
    t = t_axis(1.3)
    x = np.zeros_like(t)
    for k in range(6):   # ratchet clicks
        place(x, metal(t_axis(0.06), rng, 3, 2000, 5000, (0.005, 0.015), 0.8), 0.04 + k * 0.07)
    weld = (fft_filter(noise(len(t), rng), lo=2000, hi=7000) * (0.6 + 0.4 * square(phase_of(np.full(len(t), 60.0)))) * 0.3
            * np.clip((t - 0.45) / 0.03, 0, 1) * np.clip((0.95 - t) / 0.05, 0, 1))
    x += weld + crackle(t, rng, 80, amp=0.3) * (t > 0.45) * (t < 0.95)
    for k, f in enumerate((784, 1175)):
        tt = t_axis(0.4)
        place(x, np.sin(2 * np.pi * f * tt) * env_exp(tt, 0.003, 0.15) * 0.5, 1.0 + k * 0.08)
    return x, -5.0


def rock_break(rng):
    t = t_axis(1.0)
    x = fft_filter(noise(len(t), rng), lo=100, hi=2500) * env_exp(t, 0.002, 0.12) + thud(t, 60, 0.12, rng) * 0.8
    for k in range(14):   # pebbles
        tt = t_axis(0.08)
        peb = biquad_bp(noise(len(tt), rng), rng.uniform(1200, 4000), 6) * np.exp(-tt / 0.01)
        place(x, peb * rng.uniform(0.2, 0.6), rng.uniform(0.05, 0.7))
    return x, -4.0


def pickup(rng):
    t = t_axis(0.25)
    f = rng.uniform(520, 700) * 2 ** (np.clip(t / 0.08, 0, 1) * rng.uniform(0.9, 1.4))
    ph = phase_of(f)
    return (np.sin(ph) + 0.3 * np.sin(2 * ph)) * env_exp(t, 0.003, 0.08), -9.0


def credits(rng):
    return P.coins(0.6, rng, 4, 0.0), -8.0


def dock(rng):
    t = t_axis(2.2)
    thr = fft_filter(noise(len(t), rng), lo=100, hi=1200) * np.clip(1 - t / 1.0, 0, 1) * 0.4    # (easing off)
    x = thr
    tc = t_axis(0.5)
    place(x, thud(tc, 70, 0.08, rng) + metal(tc, rng, 6, 300, 2500, (0.05, 0.2), 1.0), 1.0)          # clamps
    place(x, metal(tc, rng, 4, 500, 3000, (0.03, 0.12), 0.6), 1.15)
    hiss = fft_filter(noise(len(t), rng), lo=2500, hi=9000) * np.clip((t - 1.3) / 0.05, 0, 1) * np.exp(-np.maximum(t - 1.35, 0) / 0.3) * 0.5
    return echo(x + hiss, 0.08, 0.25, 3), -3.0


def undock(rng):
    x, g = dock(rng)
    x = x[::-1].copy()                 # (the docking, backwards: hiss, clamps, thrust building)
    return x, g


def jump(rng):
    t = t_axis(2.4)
    f = 80 + 900 * np.clip(t / 1.4, 0, 1) ** 2
    ph = phase_of(f)
    charge = (saw(ph) * 0.4 + np.sin(ph * 1.5) * 0.4) * np.clip(t / 1.4, 0, 1) ** 1.5 * (t < 1.45)
    charge = fft_filter(charge, hi=6000)
    tw = t - 1.45
    warp_f = 1800 * np.exp(-np.maximum(tw, 0) / 0.18) + 60
    warp = (np.sin(phase_of(warp_f)) * 0.8 + biquad_bp(noise(len(t), rng), np.maximum(warp_f, 100), 2) * 0.6) * (tw > 0) * np.exp(-np.maximum(tw, 0) / 0.35)
    return echo(charge + warp * 1.3, 0.1, 0.3, 3), -2.0


def atmosphere(rng, up):
    t = t_axis(3.0)
    e = np.sin(np.pi * np.clip(t / 3.0, 0, 1)) ** 0.8
    fc = 300 + 1500 * (t / 3.0 if up else 1 - t / 3.0)
    roar = biquad_bp(noise(len(t), rng), fc, 1.2) * 0.6 + fft_filter(noise(len(t), rng), hi=250) * 0.8
    return roar * e, -3.0


def select(rng):
    x = np.zeros(int(0.12 * SR))
    for k in range(2):
        tt = t_axis(0.03)
        place(x, np.sin(2 * np.pi * (1500 + 500 * k) * tt) * np.exp(-tt / 0.008), 0.0 + k * 0.05)
    return x, -12.0


# --- loops -----------------------------------------------------------------------------------------

def make_loop(fn, dur, rng):
    """fn(t, rng) over dur + 1 s, the last second crossfaded into the first: seamless."""
    t = t_axis(dur + 1.0)
    x = fn(t, rng)
    n, k = int(dur * SR), SR
    w = np.linspace(0, 1, k)
    head = x[:k] * w + x[n:n + k] * (1 - w)
    return np.concatenate([head, x[k:n]])


def engine_loop(rng):
    def fn(t, rng):
        hum = sum(np.sin(2 * np.pi * f * t) * a for f, a in ((55, 1.0), (110, 0.5), (165.5, 0.25), (220.3, 0.12)))
        hum *= 1 + 0.08 * np.sin(2 * np.pi * 7 * t)
        rumble = fft_filter(noise(len(t), rng), lo=40, hi=400) * 0.6
        air = fft_filter(noise(len(t), rng), lo=800, hi=3000) * 0.12
        return hum * 0.5 + rumble + air
    return make_loop(fn, 4.0, rng), -10.0


def mining_loop(rng):
    def fn(t, rng):
        buzz = saw(phase_of(np.full(len(t), 120.0) * (1 + 0.01 * np.sin(2 * np.pi * 3 * t))))
        buzz = biquad_bp(buzz, 900, 1.5) + fft_filter(buzz, lo=100, hi=3000) * 0.3
        return buzz * 0.6 + crackle(t, rng, 70, amp=0.5) + fft_filter(noise(len(t), rng), lo=3000, hi=8000) * 0.08
    return make_loop(fn, 3.0, rng), -3.0


def station_hum(rng):
    def fn(t, rng):
        hum = sum(np.sin(2 * np.pi * f * t) * a for f, a in ((48, 1.0), (96, 0.6), (144.2, 0.3), (240.5, 0.12)))
        hum *= 0.75 + 0.25 * np.sin(2 * np.pi * t / 2.0)              # (a slow throb, 2 s - divides the loop)
        air = fft_filter(noise(len(t), rng), lo=150, hi=1200) * 0.25
        x = hum * 0.6 + air
        for k in range(5):
            place(x, metal(t_axis(0.4), rng, 4, 300, 1500, (0.05, 0.2), 0.35), rng.uniform(0.5, 7.0))
        return x
    return make_loop(fn, 8.0, rng), -12.0


def gate_hum(rng):
    def fn(t, rng):
        x = np.zeros_like(t)
        for f, ph in ((110, 0), (164.8, 1.3), (220.5, 2.1), (329.6, 0.7), (440.9, 2.9)):
            x += np.sin(2 * np.pi * f * t + 0.6 * np.sin(2 * np.pi * 0.25 * t + ph)) * (0.6 + 0.4 * np.sin(2 * np.pi * t / 4.0 + ph))
        return x / 5 + fft_filter(noise(len(t), rng), lo=2000, hi=8000) * 0.05 * (1 + np.sin(2 * np.pi * t / 4.0))
    return make_loop(fn, 8.0, rng), -12.0


SOUNDS = [("laser", laser, 4), ("plasma", plasma, 3), ("missile", missile, 3), ("enemy_laser", enemy_laser, 4),
          ("hit_shield", hit_shield, 4), ("hit_hull", hit_hull, 4), ("spark", spark, 4),
          ("boom_small", lambda r: boom(r, "small"), 3), ("boom_big", lambda r: boom(r, "big"), 3),
          ("ship_boom_small", lambda r: ship_boom(r, "small"), 3), ("ship_boom_medium", lambda r: ship_boom(r, "medium"), 3),
          ("ship_boom_large", lambda r: ship_boom(r, "large"), 2), ("ship_boom_player", lambda r: ship_boom(r, "player"), 1),
          ("scan_laser", scan_laser, 2), ("scan_pulse", scan_pulse, 2), ("scan_done", scan_done, 1),
          ("signal_found", signal_found, 1), ("hazard_zap", hazard_zap, 2), ("monster_roar", monster_roar, 1),
          ("shields_down", shields_down, 1), ("afterburner", afterburner, 2), ("shield_boost", shield_boost, 2),
          ("repair", repair, 2), ("rock_break", rock_break, 3), ("pickup", pickup, 3), ("credits", credits, 3),
          ("dock", dock, 1), ("undock", undock, 1), ("jump", jump, 2), ("land", lambda r: atmosphere(r, False), 1),
          ("take_off", lambda r: atmosphere(r, True), 1), ("select", select, 2),
          ("engine_loop", engine_loop, 1), ("mining_loop", mining_loop, 1), ("station_hum", station_hum, 1),
          ("gate_hum", gate_hum, 1)]
LOOPS = {"engine_loop", "mining_loop", "station_hum", "gate_hum"}


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(REPORT, exist_ok=True)
    only = sys.argv[1:]   # (names: make just those - the other takes stay byte-for-byte as they are)
    if only:
        global SOUNDS
        SOUNDS = [s for s in SOUNDS if s[0] in only]
    for f in os.listdir(OUT):
        if f.endswith(".ogg") and (not only or f.rsplit("_", 1)[0] in only):
            os.remove(os.path.join(OUT, f))
    rows, takes = [], []
    for name, fn, n in SOUNDS:
        for k in range(1, n + 1):
            rng = np.random.default_rng(sum(map(ord, name)) * 1000 + k + 7)
            x, gain_db = fn(rng)
            x = np.asarray(x, float)
            if name in LOOPS:   # (no fades: they must join up; just level them)
                x = x - x.mean()
                x = x / (np.max(np.abs(x)) + 1e-9) * 10 ** (gain_db / 20)
            else:
                x = P.finish(x, gain_db)
            P.write_ogg(x, os.path.join(OUT, "%s_%d.ogg" % (name, k)))
            a = P.analyse(x)
            if name in LOOPS:
                a["edge"] = abs(x[0] - x[-1])   # (for a loop: the jump across the seam)
            rows.append(("%s_%d" % (name, k), a))
            if k == 1:
                takes.append(("%s_%d" % (name, k), x))
    lines = ["# Space sound effects - analysis", "",
             "Generated by tools/sfx_space.py (mono, 44.1 kHz, OGG Vorbis q5). Columns as in pirate_analysis.md;",
             "for the loops, edge = the jump across the loop seam.", "",
             "| take | s | peak dBFS | loud100 dBFS | crest dB | centroid Hz | low | edge |", "|---|---|---|---|---|---|---|---|"]
    for nme, a in rows:
        lines.append("| %s | %.2f | %.1f | %.1f | %.1f | %d | %.2f | %.4f |" % (nme, a["dur"], a["peak_db"], a["loud100_db"], a["crest_db"],
                                                                         a["centroid_hz"], a["low_share"], a["edge"]))
    if only:
        print("\n".join(lines[6:]))
        return
    with open(os.path.join(REPORT, "space_analysis.md"), "w") as fh:
        fh.write("\n".join(lines) + "\n")
    P.sheet(takes, os.path.join(REPORT, "space_spectrograms.png"))
    total = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT) if f.endswith(".ogg"))
    print("%d takes, %.0f KB in %s" % (len(rows), total / 1024, OUT))
    print("\n".join(lines[6:]))


if __name__ == "__main__":
    main()
