#!/usr/bin/env python3
"""The pirate's sound effects, synthesised from scratch (numpy only) - the
game had no audio. Each sound is built from simple pieces - oscillators with
pitch sweeps, filtered noise, inharmonic metal partials, a formant "voice"
(a buzz through vowel resonances, ring-modulated and bit-crushed: a robot) -
then faded in/out (no clicks), normalised and written as OGG Vorbis.

  python3 tools/sfx_pirate.py            -> sounds/pirate/*.ogg (several takes of each)
                                            external/sfx/pirate_analysis.md (a table)
                                            external/sfx/pirate_spectrograms.png

Takes: <name>_<n>.ogg; Sfx (scripts/core/sfx.gd) plays a random one, with a little
random pitch, so repeats don't sound the same. Every take is seeded: the same
files every run.

The sounds (an evil android pirate with a laser rifle, a tattered coat):
  shot      the red laser rifle: a falling zap, a crack, a thump      (4 takes)
  raise     the rifle coming up: a servo whir up and a click           (2)
  lower     the rifle going down: a servo whir down and a clunk        (2)
  step      a metal foot: a dull thud and a short clank                (6)
  hurt      hit: a sizzle and a robotic grunt                          (4)
  death     power failing: a falling whine, sparks, a crash            (2)
  taunt     a robot pirate's growled babble, ending in a rolled "arr"  (4)
  flee      an alarm chirp and a quick, higher babble                  (2)
  bolt_hit  a red bolt striking: a sizzle and a snap                   (3)
  loot_drop the loot chest landing: a wooden thud, coins               (1)
  loot_take picking the loot up: coins and a rising chime              (1)
"""
import json
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "sounds", "pirate")
REPORT = os.path.join(ROOT, "external", "sfx")


# --- building blocks ----------------------------------------------------------------------------

def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def env_exp(t, attack, decay):
    """A fast attack (s) and an exponential decay (time constant, s)."""
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-np.maximum(t - attack, 0) / decay)


def phase_of(freq):
    """Phase (radians) of an oscillator whose frequency follows the array freq."""
    return 2 * np.pi * np.cumsum(freq) / SR


def saw(ph):
    return 2 * ((ph / (2 * np.pi)) % 1.0) - 1


def square(ph, duty=0.5):
    return np.where(((ph / (2 * np.pi)) % 1.0) < duty, 1.0, -1.0)


def noise(n, rng):
    return rng.standard_normal(n)


def fft_filter(x, lo=None, hi=None, slope=1.0):
    """Band-limit x to lo..hi Hz (smooth edges) in the frequency domain."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    g = np.ones_like(f)
    if lo:
        g *= 1 / (1 + (lo / np.maximum(f, 1)) ** (2 * slope))
    if hi:
        g *= 1 / (1 + (f / hi) ** (2 * slope))
    return np.fft.irfft(X * g, len(x))


def biquad_bp(x, f0, q, gain=1.0):
    """A resonant band-pass (RBJ cookbook), f0 may be an array (a moving resonance)."""
    f0 = np.broadcast_to(np.asarray(f0, float), x.shape)
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i in range(len(x)):
        w = 2 * np.pi * f0[i] / SR
        alpha = np.sin(w) / (2 * q)
        cw = np.cos(w)
        a0 = 1 + alpha
        b0, b2 = alpha / a0, -alpha / a0
        a1, a2 = -2 * cw / a0, (1 - alpha) / a0
        yi = b0 * x[i] + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, x[i]
        y2, y1 = y1, yi
        y[i] = yi
    return y * gain


def metal(t, rng, partials=5, lo=600, hi=4000, decay=(0.04, 0.14), amp=1.0):
    """A clank: inharmonic partials, each decaying at its own rate."""
    out = np.zeros_like(t)
    for _ in range(partials):
        f = rng.uniform(lo, hi)
        out += np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / rng.uniform(*decay)) * rng.uniform(0.4, 1.0)
    return out * amp / partials


def thud(t, f=80, decay=0.05, rng=None):
    """A dull low hit: a falling sine and a little low noise."""
    ph = phase_of(f * (1 + 1.5 * np.exp(-t / 0.01)))
    x = np.sin(ph) * np.exp(-t / decay)
    if rng is not None:
        x += fft_filter(noise(len(t), rng), hi=400) * np.exp(-t / (decay * 0.6)) * 0.6
    return x


def crackle(t, rng, rate=120, dur_each=0.002, amp=1.0):
    """Electric crackle: random little clicks of filtered noise."""
    out = np.zeros_like(t)
    n = int(rate * t[-1]) if len(t) else 0
    for _ in range(n):
        i = rng.integers(0, len(t))
        L = int(dur_each * SR * rng.uniform(0.5, 2))
        seg = rng.standard_normal(min(L, len(t) - i)) * rng.uniform(0.3, 1.0)
        out[i:i + len(seg)] += seg * np.exp(-np.arange(len(seg)) / max(L / 3, 1))
    return fft_filter(out, lo=1500) * amp


def place(dst, src, at):
    i = int(at * SR)
    n = min(len(src), len(dst) - i)
    if n > 0:
        dst[i:i + n] += src[:n]
    return dst


def echo(x, delay=0.07, fb=0.3, taps=3):
    out = x.copy()
    d = int(delay * SR)
    for k in range(1, taps + 1):
        if d * k < len(x):
            out[d * k:] += x[:len(x) - d * k] * (fb ** k)
    return out


def robot(x, rng, ring=55.0, crush=0.0):
    """The android: ring modulation (a metallic voice) and optional bit-crushing."""
    t = np.arange(len(x)) / SR
    y = x * (0.55 + 0.45 * np.sin(2 * np.pi * ring * t))
    if crush:
        steps = 2 ** (16 - crush * 12)
        y = np.round(y * steps) / steps
        hold = int(1 + crush * 3)          # (sample-rate reduction too)
        y = np.repeat(y[::hold], hold)[:len(x)]
    return y


VOWELS = {   # F1, F2, F3 (Hz) - a deep, gruff voice
    "a": (700, 1150, 2500), "o": (500, 850, 2400), "u": (380, 800, 2300), "e": (500, 1700, 2500),
    "r": (480, 1150, 1500),   # (a low F3: the growled "r")
}


def voice(dur, pitch, vowels, rng, growl=0.0, breath=0.08):
    """A buzz (a glottal-ish pulse train at `pitch`, an array or a number) through
    three formant resonances moving through `vowels` (a list of letters)."""
    t = t_axis(dur)
    p = np.broadcast_to(np.asarray(pitch, float), t.shape).copy()
    if growl:   # a rough, rolled throat: fast irregular pitch flutter
        p *= 1 + growl * (0.5 * np.sin(2 * np.pi * 28 * t) + 0.5 * fft_filter(noise(len(t), rng), lo=15, hi=60) * 3)
    ph = phase_of(p)
    src = saw(ph) * 0.7 + square(ph, 0.18) * 0.3
    src += noise(len(t), rng) * breath
    # formants moving from vowel to vowel
    k = np.linspace(0, len(vowels) - 1, len(t))
    i0 = np.floor(k).astype(int)
    i1 = np.minimum(i0 + 1, len(vowels) - 1)
    fr = k - i0
    out = np.zeros_like(t)
    for j, (q, g) in enumerate(((5, 1.0), (7, 0.6), (9, 0.35))):
        fa = np.array([VOWELS[v][j] for v in vowels])
        f = fa[i0] * (1 - fr) + fa[i1] * fr
        out += biquad_bp(src, f, q, g)
    return out / (np.max(np.abs(out)) + 1e-9)     # (resonators leave it quiet: back to full scale)


def fade(x, a=0.003, b=0.02):
    """Fade in / out so no take starts or ends with a click."""
    n = len(x)
    na, nb = int(a * SR), int(b * SR)
    if na:
        x[:na] *= np.linspace(0, 1, na)
    if nb:
        x[n - nb:] *= np.linspace(1, 0, nb)
    return x


def finish(x, peak_db=-1.0):
    x = x - np.mean(x)
    x = np.tanh(x / (np.max(np.abs(x)) + 1e-9) * 1.2)      # (a gentle saturation: denser, no hard clips)
    x = fade(x)
    return x / (np.max(np.abs(x)) + 1e-9) * 10 ** (peak_db / 20)


# --- the sounds ---------------------------------------------------------------------------------

def shot(rng):
    dur = 0.42
    t = t_axis(dur)
    top = rng.uniform(2000, 2800)
    f = top * np.exp(-t / rng.uniform(0.03, 0.045)) + rng.uniform(150, 220)
    f *= 1 + 0.03 * np.sin(2 * np.pi * rng.uniform(40, 70) * t)      # (a wobble in the beam)
    ph = phase_of(f)
    beam = (saw(ph) * 0.6 + square(ph, 0.3) * 0.4) * env_exp(t, 0.002, 0.09)
    beam = fft_filter(beam, lo=120, hi=9000)
    crack = fft_filter(noise(len(t), rng), lo=2000, hi=9000) * env_exp(t, 0.0005, 0.012) * 1.2
    sub = thud(t, 65, 0.06) * 0.8
    x = beam + crack + sub
    return echo(x, 0.06, 0.22, 3), -1.5


def servo(dur, f0, f1, rng):
    t = t_axis(dur)
    f = f0 + (f1 - f0) * (t / dur) ** 0.7
    ph = phase_of(f)
    x = saw(ph) * (0.6 + 0.4 * np.sin(2 * np.pi * 32 * t))     # (gear teeth: a fast flutter)
    x = fft_filter(x, lo=250, hi=3000)
    return x * np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 0.6


def raise_(rng):
    dur = 0.55
    t = t_axis(dur)
    x = servo(0.38, rng.uniform(130, 150), rng.uniform(250, 290), rng) * 1.6
    x = np.pad(x, (0, len(t) - len(x)))
    click = fft_filter(noise(int(0.008 * SR), rng), lo=2500) * np.exp(-np.arange(int(0.008 * SR)) / 60)
    place(x, click * 0.9, 0.38)
    tc = t_axis(0.16)
    place(x, metal(tc, rng, 4, 1500, 4500, (0.02, 0.06), 0.6), 0.38)
    return x, -4.0


def lower(rng):
    dur = 0.7
    t = t_axis(dur)
    x = servo(0.48, rng.uniform(250, 280), rng.uniform(110, 130), rng) * 0.5
    x = np.pad(x, (0, len(t) - len(x)))
    tc = t_axis(0.22)
    place(x, thud(tc, 95, 0.05, rng) * 0.7 + metal(tc, rng, 4, 700, 2500, (0.03, 0.09), 0.6), 0.48)
    return x, -5.0


def step(rng):
    dur = 0.22
    t = t_axis(dur)
    x = thud(t, rng.uniform(60, 90), rng.uniform(0.03, 0.05), rng) * 0.9
    x += metal(t, rng, 5, 500, 3200, (0.015, 0.05), 0.45)
    grit = fft_filter(noise(len(t), rng), lo=800, hi=5000) * env_exp(t, 0.001, 0.015) * 0.25   # (gravel)
    return x + grit, -9.0


def hurt(rng):
    dur = 0.55
    t = t_axis(dur)
    sizzle = fft_filter(noise(len(t), rng), lo=1200, hi=9000) * env_exp(t, 0.001, 0.07) * 0.6
    sizzle += crackle(t, rng, 160, amp=0.5) * np.exp(-t / 0.12)
    p = rng.uniform(95, 120) * (1 - 0.35 * (t / dur))        # (the grunt falls)
    v = voice(dur, p, ["a", "u", "u"], rng, growl=0.06)
    v = robot(v, rng, ring=rng.uniform(45, 70), crush=0.25)
    v *= env_exp(t, 0.02, 0.18)
    x = place(sizzle * 0.45, v * 1.0, 0.03)
    return x, -2.0


def death(rng):
    dur = 1.9
    t = t_axis(dur)
    f = 520 * np.exp(-t / 0.45) + 35
    ph = phase_of(f)
    whine = (saw(ph) * 0.5 + np.sin(ph * 2) * 0.3) * np.clip(1.3 - t / 1.4, 0, 1)
    whine = np.tanh(whine * (1 + 3 * t))                     # (more and more broken)
    whine = fft_filter(whine, lo=40, hi=6000)
    sparks = crackle(t, rng, 90, amp=0.7) * np.clip(1.2 - t / 1.6, 0, 1)
    v = voice(0.7, 110 * np.exp(-t_axis(0.7) / 0.5), ["a", "o", "u"], rng, growl=0.12)
    v = robot(v, rng, ring=40, crush=0.4) * env_exp(t_axis(0.7), 0.02, 0.3)
    x = whine * 0.6 + sparks
    place(x, v * 0.7, 0.02)
    tc = t_axis(0.6)
    place(x, thud(tc, 70, 0.09, rng) * 1.0 + metal(tc, rng, 7, 300, 2800, (0.06, 0.25), 0.9), 1.15)   # (the crash)
    place(x, metal(t_axis(0.3), rng, 4, 900, 3500, (0.03, 0.1), 0.4), 1.33)                         # (a bounce)
    return echo(x, 0.09, 0.2, 2), -1.0


SYLL = [["a", "r"], ["o", "a"], ["u", "a"], ["e", "o"], ["a", "u"], ["o", "r"], ["a", "e"]]


def babble(rng, syllables, base, spread, growl_end=True, crush=0.3, ring=None):
    parts = []
    for k in range(syllables):
        d = rng.uniform(0.11, 0.2)
        tt = t_axis(d)
        p = base * rng.uniform(1 - spread, 1 + spread) * (1 + 0.15 * np.sin(np.pi * tt / d))   # (each syllable rises and falls)
        v = voice(d, p, SYLL[rng.integers(len(SYLL))], rng, growl=0.03)
        v *= np.sin(np.pi * np.clip(tt / d, 0, 1)) ** 0.5
        cons = fft_filter(noise(int(0.025 * SR), rng), lo=2500, hi=8000) * 0.25 * np.hanning(int(0.025 * SR))
        parts += [cons * (rng.random() < 0.6), v, np.zeros(int(rng.uniform(0.015, 0.05) * SR))]
    if growl_end:   # "arrr": a long, rolled growl
        d = rng.uniform(0.45, 0.6)
        tt = t_axis(d)
        v = voice(d, base * 0.85 * (1 - 0.15 * tt / d), ["a", "a", "r", "r", "r"], rng, growl=0.22)
        parts.append(v * np.minimum(1, (d - tt) / 0.12) * np.minimum(1, tt / 0.02))
    x = np.concatenate(parts)
    return robot(x, rng, ring=ring or rng.uniform(35, 60), crush=crush)


def taunt(rng):
    x = babble(rng, int(rng.integers(3, 6)), rng.uniform(85, 105), 0.18)
    return echo(x, 0.05, 0.15, 2), -2.5


def flee(rng):
    beeps = []
    for k in range(2):
        tt = t_axis(0.09)
        f = 1400 + 900 * tt / 0.09 if k == 0 else 1900 + 900 * tt / 0.09
        beeps.append(square(phase_of(np.full(len(tt), 1.0) * f), 0.4) * np.hanning(len(tt)) * 0.35)
        beeps.append(np.zeros(int(0.03 * SR)))
    x = np.concatenate(beeps + [babble(rng, 3, rng.uniform(140, 160), 0.2, growl_end=False, crush=0.2, ring=70)])
    return x, -5.0


def bolt_hit(rng):
    dur = 0.32
    t = t_axis(dur)
    snap = fft_filter(noise(len(t), rng), lo=1500, hi=10000) * env_exp(t, 0.0005, 0.02)
    f = 1800 * np.exp(-t / 0.02) + 300
    zap = square(phase_of(f), 0.35) * env_exp(t, 0.001, 0.04) * 0.4
    fizz = crackle(t, rng, 220, amp=0.6) * np.exp(-t / 0.08)
    return snap + zap + fizz, -3.0


def coins(t_len, rng, n=7, start=0.0):
    x = np.zeros(int(t_len * SR))
    at = start
    for k in range(n):
        tt = t_axis(0.25)
        ting = sum(np.sin(2 * np.pi * f * tt) * np.exp(-tt / rng.uniform(0.04, 0.1))
                   for f in rng.uniform(3200, 7800, 3)) / 3
        place(x, ting * rng.uniform(0.3, 0.8), at)
        at += rng.uniform(0.02, 0.07)
    return x


def loot_drop(rng):
    dur = 0.8
    t = t_axis(dur)
    tc = t_axis(0.4)
    wood = biquad_bp(noise(len(tc), rng), 190, 4) * env_exp(tc, 0.001, 0.05) * 1.2 + thud(tc, 85, 0.05) * 0.8
    x = np.zeros_like(t)
    place(x, wood, 0.0)
    x += coins(dur, rng, 8, 0.03)
    return x, -3.0


def loot_take(rng):
    dur = 0.9
    t = t_axis(dur)
    x = coins(dur, rng, 6, 0.0) * 0.8
    for k, f in enumerate((880, 1109, 1319, 1760)):            # (a rising arpeggio)
        tt = t_axis(0.35)
        ch = (np.sin(2 * np.pi * f * tt) + 0.3 * np.sin(2 * np.pi * 2 * f * tt)) * env_exp(tt, 0.003, 0.12) * 0.45
        place(x, ch, 0.06 + k * 0.07)
    return x, -4.0


SOUNDS = [("shot", shot, 4), ("raise", raise_, 2), ("lower", lower, 2), ("step", step, 6), ("hurt", hurt, 4),
          ("death", death, 2), ("taunt", taunt, 4), ("flee", flee, 2), ("bolt_hit", bolt_hit, 3),
          ("loot_drop", loot_drop, 1), ("loot_take", loot_take, 1)]


# --- writing and analysing ----------------------------------------------------------------------

def write_ogg(x, path):
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as fh:
        tmp = fh.name
    with wave.open(tmp, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "5", path], check=True)
    os.remove(tmp)


def analyse(x):
    db = lambda v: 20 * np.log10(max(v, 1e-9))
    peak = np.max(np.abs(x))
    rms = np.sqrt(np.mean(x ** 2))
    # loudness over the loudest 100 ms (what the ear judges a short effect by)
    w = int(0.1 * SR)
    win = np.sqrt(np.convolve(x ** 2, np.ones(w) / w, mode="valid")) if len(x) > w else np.array([rms])
    X = np.abs(np.fft.rfft(x))
    f = np.fft.rfftfreq(len(x), 1 / SR)
    centroid = float(np.sum(f * X) / (np.sum(X) + 1e-9))
    lowshare = float(np.sum(X[f < 250] ** 2) / (np.sum(X ** 2) + 1e-9))
    return {"dur": len(x) / SR, "peak_db": db(peak), "rms_db": db(rms), "loud100_db": db(np.max(win)),
            "crest_db": db(peak) - db(rms), "centroid_hz": centroid, "low_share": lowshare,
            "dc": float(np.mean(x)), "edge": float(max(abs(x[0]), abs(x[-1])))}


def spectrogram(x, w=360, h=120):
    n = 1024
    hop = max(1, (len(x) - n) // w)
    cols = []
    win = np.hanning(n)
    for i in range(w):
        seg = x[i * hop:i * hop + n]
        if len(seg) < n:
            seg = np.pad(seg, (0, n - len(seg)))
        cols.append(np.abs(np.fft.rfft(seg * win)))
    S = np.array(cols).T                                         # (freq x time)
    f = np.fft.rfftfreq(n, 1 / SR)
    rows = np.geomspace(40, 16000, h)                            # (log frequency, low at the bottom)
    idx = np.clip(np.searchsorted(f, rows), 0, len(f) - 1)
    S = 20 * np.log10(S[idx] + 1e-6)
    S = np.clip((S - (S.max() - 70)) / 70, 0, 1)[::-1]
    return S


def sheet(takes, path):
    from PIL import Image, ImageDraw
    W, H, cols = 360, 120, 4
    rows = (len(takes) + cols - 1) // cols
    img = Image.new("RGB", (cols * (W + 10) + 10, rows * (H + 34) + 10), (14, 12, 20))
    d = ImageDraw.Draw(img)
    for i, (name, x) in enumerate(takes):
        S = spectrogram(x, W, H)
        rgb = np.stack([np.clip(S * 2.2 - 0.6, 0, 1), np.clip(S * 1.6 - 0.15, 0, 1) ** 1.3, np.clip(S * 1.3, 0, 1) ** 0.6], -1)
        tile = Image.fromarray((rgb * 255).astype(np.uint8))
        cx, cy = 10 + (i % cols) * (W + 10), 10 + (i // cols) * (H + 34)
        img.paste(tile, (cx, cy + 20))
        d.text((cx, cy + 4), "%s  (%.2f s)" % (name, len(x) / SR), fill=(235, 220, 190))
    img.save(path)


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(REPORT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith(".ogg"):
            os.remove(os.path.join(OUT, f))
    rows, takes, index = [], [], {}
    for name, fn, n in SOUNDS:
        index[name] = n
        for k in range(1, n + 1):
            rng = np.random.default_rng(sum(map(ord, name)) * 1000 + k)   # (seeded: the same takes every run)
            x, gain_db = fn(rng)
            x = finish(np.asarray(x, float), gain_db)
            write_ogg(x, os.path.join(OUT, "%s_%d.ogg" % (name, k)))
            a = analyse(x)
            rows.append(("%s_%d" % (name, k), a))
            if k == 1:
                takes.append(("%s_%d" % (name, k), x))
    with open(os.path.join(OUT, "takes.json"), "w") as fh:
        json.dump(index, fh, indent=1, sort_keys=True)
    lines = ["# The pirate's sound effects - analysis", "",
             "Generated by tools/sfx_pirate.py (mono, 44.1 kHz, OGG Vorbis q5). loud100 = the loudest 100 ms (RMS);",
             "crest = peak over RMS (punchy > 15 dB); centroid = spectral centre of mass (brightness); low = share of energy",
             "under 250 Hz; edge = the first / last sample (0 = no click).", "",
             "| take | s | peak dBFS | loud100 dBFS | crest dB | centroid Hz | low | edge |",
             "|---|---|---|---|---|---|---|---|"]
    for n, a in rows:
        lines.append("| %s | %.2f | %.1f | %.1f | %.1f | %d | %.2f | %.4f |" % (n, a["dur"], a["peak_db"], a["loud100_db"], a["crest_db"],
                                                                         a["centroid_hz"], a["low_share"], a["edge"]))
    with open(os.path.join(REPORT, "pirate_analysis.md"), "w") as fh:
        fh.write("\n".join(lines) + "\n")
    sheet(takes, os.path.join(REPORT, "pirate_spectrograms.png"))
    total = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT) if f.endswith(".ogg"))
    print("%d takes, %.0f KB in %s" % (len(rows), total / 1024, OUT))
    print("\n".join(lines[7:]))


if __name__ == "__main__":
    main()
