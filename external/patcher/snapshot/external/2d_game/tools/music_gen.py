#!/usr/bin/env python3
"""The game's music: three ambient electronic tracks, composed and synthesised
from scratch (numpy only), each a seamless 2-minute loop.

  menu     "Atrapos"        72 BPM, D minor  - lush, hopeful: pads, a delayed arpeggio, bells
  space    "Deep Drift"     60 BPM, C minor  - vast and dark: drones, slow chords, twinkles,
                                               sonar pings, noise swells
  surface  "Minoan Shores"  96 BPM, A minor / E Phrygian dominant - warm, ancient: a lyre-like
                                               arpeggio, frame drum and shaker, a breathy flute,
                                               the sea

  python3 tools/music_gen.py [track ...]   -> music/<track>.ogg (stereo, 44.1 kHz, Vorbis q4)
                                              external/music/<track>.png (spectrogram + level)
                                              external/music/analysis.md

How a track is made: notes (bar, beat, MIDI note, length in beats) are
rendered by simple instruments - an additive saw pad (a few detuned voices),
an FM bell, an additive pluck (higher harmonics dying faster), a sub bass, a
breathy flute, a frame drum, a shaker, noise textures - onto dry and reverb
send buses; the pads go through a slowly sweeping low-pass; a stereo
convolution reverb (decaying noise) and a ping-pong delay; then a gentle
compressor, the level set to about -17 dBFS RMS and a soft limit at -1 dBFS.
Seamless: everything is rendered with 12 s of tail past the loop's end and the
tail is added back onto the start, so reverb and long notes ring across the
loop point; each track also starts and ends in the same musical state. Every
random choice is seeded - the same files every run.
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "music")
REPORT = os.path.join(ROOT, "external", "music")
LOOP = 120.0
TAIL = 12.0


def mtof(m):
    return 440.0 * 2 ** ((np.asarray(m, float) - 69) / 12)


NOTE = {n: i for i, n in enumerate(["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"])}
NOTE.update({"Db": 1, "Eb": 3, "Gb": 6, "Ab": 8, "Bb": 10})


def n(name):
    """'D3' -> MIDI 50."""
    return NOTE[name[:-1]] + 12 * (int(name[-1]) + 1)


# --- the mix ------------------------------------------------------------------------------------

class Mix:
    def __init__(self, bpm, seed):
        self.bpm = bpm
        self.beat = 60.0 / bpm
        self.N = int((LOOP + TAIL) * SR)
        self.dry = np.zeros((2, self.N))
        self.send = np.zeros((2, self.N))
        self.pad = np.zeros((2, self.N))       # (the pads' own bus: a sweeping low-pass)
        self.delay = np.zeros((2, self.N))     # (into the ping-pong delay)
        self.rng = np.random.default_rng(seed)

    def at(self, bar, beat=0.0):
        return (bar * 4 + beat) * self.beat

    def add(self, x, t0, pan=0.0, rev=0.3, bus="dry", gain=1.0, delay=0.0):
        i = int(t0 * SR)
        if i >= self.N or len(x) == 0:
            return
        x = x[: self.N - i] * gain
        l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
        target = self.pad if bus == "pad" else self.dry
        target[0, i:i + len(x)] += x * l
        target[1, i:i + len(x)] += x * r
        if rev:
            self.send[0, i:i + len(x)] += x * l * rev
            self.send[1, i:i + len(x)] += x * r * rev
        if delay:
            self.delay[0, i:i + len(x)] += x * l * delay
            self.delay[1, i:i + len(x)] += x * r * delay


def env(n_s, a, r, total):
    """Linear-ish attack a, hold, release r (s) over total s - a smooth envelope."""
    t = np.arange(int(total * SR)) / SR
    e = np.minimum(1, t / max(a, 1e-3))
    e = e * np.clip((total - t) / max(r, 1e-3), 0, 1)
    return e ** 1.5


# --- instruments -----------------------------------------------------------------------------------

def pad_note(m, dur, rng, voices=5, detune=0.12, bright=1.0, a=2.0, r=2.5, shape="saw"):
    """A soft pad: detuned additive saws (or triangles), slow attack and release."""
    total = dur + r
    t = np.arange(int(total * SR)) / SR
    f0 = float(mtof(m))
    out = np.zeros_like(t)
    kmax = max(1, int(min(3500 * bright, 8000) / f0))   # (the pads are low-passed anyway)
    for v in range(voices):
        f = f0 * 2 ** (rng.uniform(-detune, detune) / 12)
        ph = rng.uniform(0, 2 * np.pi)
        drift = 1 + 0.0015 * np.sin(2 * np.pi * rng.uniform(0.1, 0.3) * t + rng.uniform(0, 6))
        base = 2 * np.pi * f * np.cumsum(drift) / SR + ph
        for k in range(1, kmax + 1):
            if shape == "tri":
                if k % 2 == 0:
                    continue
                amp = 1 / k ** 2
            else:
                amp = 1 / k
            out += np.sin(k * base) * amp
    return out / voices * env(None, a, r, total) * 0.3


def bell(m, rng, decay=3.0, ratio=3.5, index=2.5):
    """An FM bell: a sine modulated at a non-integer ratio, the brightness dying away."""
    total = decay * 2.2
    t = np.arange(int(total * SR)) / SR
    f = float(mtof(m))
    idx = index * np.exp(-t / (decay * 0.35))
    x = np.sin(2 * np.pi * f * t + idx * np.sin(2 * np.pi * f * ratio * t))
    x += 0.3 * np.sin(2 * np.pi * f * 2.01 * t) * np.exp(-t / (decay * 0.5))
    return x * np.exp(-t / decay) * np.minimum(1, t / 0.004) * 0.35


def pluck(m, rng, decay=1.2, bright=1.0, inharm=0.0004):
    """A plucked string (lyre / harp): harmonics, the higher ones dying faster."""
    total = decay * 3
    t = np.arange(int(total * SR)) / SR
    f = float(mtof(m))
    out = np.zeros_like(t)
    kmax = max(1, int(9000 * bright / f))
    for k in range(1, min(kmax, 24) + 1):
        fk = f * k * np.sqrt(1 + inharm * k * k)
        out += np.sin(2 * np.pi * fk * t + rng.uniform(0, 6)) * (1 / k ** 1.1) * np.exp(-t * (1 + 0.55 * (k - 1)) / decay)
    return out * np.minimum(1, t / 0.002) * 0.3


def sub(m, dur, a=0.3, r=0.8):
    total = dur + r
    t = np.arange(int(total * SR)) / SR
    f = float(mtof(m))
    x = np.sin(2 * np.pi * f * t) + 0.18 * np.sin(4 * np.pi * f * t)
    return x * env(None, a, r, total) * 0.5


def flute(m, dur, rng, vib=5.2):
    total = dur + 0.25
    t = np.arange(int(total * SR)) / SR
    f = float(mtof(m))
    vibd = 0.006 * np.clip((t - 0.35) / 0.5, 0, 1)
    ph = 2 * np.pi * f * np.cumsum(1 + vibd * np.sin(2 * np.pi * vib * t)) / SR
    x = np.sin(ph) + 0.22 * np.sin(2 * ph) + 0.08 * np.sin(3 * ph)
    breath = band_noise(len(t), rng, f * 0.8, f * 4) * 0.18
    e = env(None, 0.12, 0.25, total)
    return (x + breath) * e * 0.32


def band_noise(n_, rng, lo, hi):
    x = rng.standard_normal(n_)
    X = np.fft.rfft(x)
    fr = np.fft.rfftfreq(n_, 1 / SR)
    g = (1 / (1 + (lo / np.maximum(fr, 1)) ** 4)) * (1 / (1 + (fr / hi) ** 4))
    y = np.fft.irfft(X * g, n_)
    return y / (np.std(y) + 1e-9)


def drum(kind, rng):
    """Frame drum: 'dum' (deep, the middle of the skin) and 'tek' (the rim)."""
    if kind == "dum":
        t = np.arange(int(0.6 * SR)) / SR
        f = 70 + 60 * np.exp(-t / 0.03)
        x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.18)
        x += band_noise(len(t), rng, 80, 600) * np.exp(-t / 0.03) * 0.25
        return x * 0.8
    t = np.arange(int(0.25 * SR)) / SR
    x = band_noise(len(t), rng, 900, 5000) * np.exp(-t / 0.025) * 0.55
    x += np.sin(2 * np.pi * 420 * t) * np.exp(-t / 0.04) * 0.35
    return x


def shaker(rng, accent=1.0):
    t = np.arange(int(0.12 * SR)) / SR
    e = np.minimum(1, t / 0.008) * np.exp(-t / 0.03)
    return band_noise(len(t), rng, 4000, 12000) * e * 0.12 * accent


def ping(m, rng):
    t = np.arange(int(3.0 * SR)) / SR
    f = float(mtof(m))
    return (np.sin(2 * np.pi * f * t) + 0.2 * np.sin(2 * np.pi * f * 2.003 * t)) * np.exp(-t / 0.8) * np.minimum(1, t / 0.003) * 0.3


# --- effects -------------------------------------------------------------------------------------

def fftconv(x, ir):
    n_ = len(x) + len(ir) - 1
    size = 1 << (n_ - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[: len(x)]


def reverb(send, rng, seconds=6.0, predelay=0.03, dark=6000.0):
    """A stereo hall: decaying noise impulse responses (darker as they decay)."""
    out = np.zeros_like(send)
    n_ = int(seconds * SR)
    t = np.arange(n_) / SR
    for ch in range(2):
        ir = rng.standard_normal(n_) * np.exp(-t * 6.9 / seconds)
        # darken over time: blend a low-passed copy in
        lp = band_noise(n_, rng, 20, dark * 0.25) * np.exp(-t * 6.9 / seconds)
        mixw = np.clip(t / (seconds * 0.5), 0, 1)
        ir = ir * (1 - mixw) * 0.6 + lp * mixw * 0.9
        ir[: int(predelay * SR)] = 0
        ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
        out[ch] = fftconv(send[ch], ir)
    return out


def pingpong(x, delay_s, fb=0.45, taps=7):
    out = np.zeros_like(x)
    d = int(delay_s * SR)
    mono = (x[0] + x[1]) * 0.5
    for k in range(1, taps + 1):
        sh = d * k
        if sh >= x.shape[1]:
            break
        ch = k % 2
        out[ch, sh:] += mono[: x.shape[1] - sh] * fb ** k
    return out


def sweep_lowpass(x, fc_fn, frame=4096, hop=1024):
    """A low-pass whose cutoff follows fc_fn(t seconds) - STFT, overlap-add."""
    win = np.hanning(frame)
    fr = np.fft.rfftfreq(frame, 1 / SR)
    out = np.zeros_like(x)
    norm = np.zeros(x.shape[1])
    for s in range(0, x.shape[1] - frame, hop):
        fc = fc_fn((s + frame / 2) / SR)
        g = 1 / (1 + (fr / fc) ** 4)
        for ch in range(2):
            seg = x[ch, s:s + frame] * win
            out[ch, s:s + frame] += np.fft.irfft(np.fft.rfft(seg) * g, frame) * win
        norm[s:s + frame] += win ** 2
    return out / np.maximum(norm, 1e-6)


def compress(x, thresh_db=-20, ratio=2.0, win_s=0.08):
    mono = np.sqrt((x[0] ** 2 + x[1] ** 2) / 2)
    w = int(win_s * SR)
    c = np.cumsum(np.concatenate([[0], mono ** 2]))
    rms = np.sqrt(np.maximum((c[w:] - c[:-w]) / w, 1e-12))
    rms = np.concatenate([np.full(w - 1, rms[0]), rms])
    lvl = 20 * np.log10(rms + 1e-9)
    over = np.maximum(lvl - thresh_db, 0)
    gdb = -over * (1 - 1 / ratio)
    # smooth the gain (attack/release ~ 0.3 s)
    k = int(0.3 * SR)
    g = np.convolve(10 ** (gdb / 20), np.ones(k) / k, mode="same")
    return x * g


def master(mix, rng, delay_s, rev_s=6.0, target_db=-17.0):
    if np.any(mix.pad):
        mix.dry += mix.pad_filtered
    wet = reverb(mix.send, rng, rev_s)
    dl = pingpong(mix.delay, delay_s)
    wet += reverb(dl * 0.5, rng, rev_s * 0.6) * 0.5
    x = mix.dry + wet * 0.75 + dl
    # seamless loop: the tail past the loop's end back onto the start
    L = int(LOOP * SR)
    x[:, : x.shape[1] - L] += x[:, L:]
    x = x[:, :L]
    x -= x.mean(axis=1, keepdims=True)
    x = compress(x)
    rms = np.sqrt(np.mean(x ** 2))
    x *= 10 ** (target_db / 20) / (rms + 1e-9)
    ceil = 10 ** (-1 / 20)
    x = np.tanh(x / ceil) * ceil
    return x


# --- the tracks ----------------------------------------------------------------------------------

def track_menu():
    """'Atrapos' - 72 BPM, 36 bars of D minor: Dm9 - Bbmaj9 - Gm9 - Asus4, three bars each."""
    m = Mix(72, 101)
    rng = m.rng
    chords = [["D3", "F3", "A3", "C4", "E4"], ["Bb2", "D3", "F3", "A3", "C4"],
              ["G2", "Bb2", "D3", "F3", "A3"], ["A2", "D3", "E3", "G3", "B3"]]
    roots = ["D2", "Bb1", "G1", "A1"]
    bar = m.beat * 4
    for c in range(12):                                    # 12 chords x 3 bars = 36 bars
        ch = chords[c % 4]
        t0 = m.at(c * 3)
        for i, note in enumerate(ch):
            m.add(pad_note(n(note), bar * 3, rng, a=2.5, r=3.0), t0, pan=-0.6 + 1.2 * i / (len(ch) - 1), rev=0.5, bus="pad")
        m.add(sub(n(roots[c % 4]), bar * 3 - 0.2, a=1.0, r=1.5), t0, rev=0.05, gain=0.35)
        # the arpeggio: 16ths up through the chord, bars 6..30 (fading in and out)
        for b in range(3):
            barno = c * 3 + b
            level = np.clip((barno - 5) / 2, 0, 1) * np.clip((31 - barno) / 4, 0, 1)
            if level <= 0:
                continue
            seq = [n(x) + 12 for x in ch] + [n(ch[1]) + 24, n(ch[2]) + 24]
            for s in range(16):
                note = seq[[0, 1, 2, 3, 4, 5, 6, 4, 3, 2, 1, 2, 3, 4, 5, 3][s]]
                acc = 1.0 if s % 4 == 0 else 0.7
                m.add(pluck(note, rng, decay=0.5, bright=0.6), m.at(barno, s * 0.25),
                      pan=0.35 * np.sin(s * 0.7), rev=0.25, delay=0.35, gain=0.65 * level * acc)
    # the bells: a slow melody, bars 12..30
    melody = [(12, 0, "A4", 3), (12, 3, "C5", 1), (13, 0, "D5", 6), (14, 2, "F5", 2), (15, 0, "E5", 4),
              (16, 0, "D5", 3), (16, 3, "C5", 1), (17, 0, "A4", 8),
              (19, 0, "F5", 2), (19, 2, "E5", 2), (20, 0, "D5", 4), (21, 0, "C5", 2), (21, 2, "D5", 2), (22, 0, "E5", 8),
              (24, 0, "A4", 3), (24, 3, "C5", 1), (25, 0, "D5", 4), (26, 0, "F5", 2), (26, 2, "G5", 2),
              (27, 0, "A5", 6), (28, 2, "G5", 2), (29, 0, "F5", 4), (30, 0, "E5", 3), (30, 3, "D5", 1), (31, 0, "D5", 8)]
    for barno, beat, note, ln in melody:
        m.add(bell(n(note), rng, decay=2.2 + ln * 0.25), m.at(barno, beat), pan=0.15, rev=0.6, delay=0.25, gain=0.95)
    # air: soft wind, slowly breathing (24 s - five times a loop)
    tt = np.arange(m.N) / SR
    wind = band_noise(m.N, rng, 400, 4500) * (0.5 + 0.5 * np.sin(2 * np.pi * tt / 24.0)) * 0.035
    m.add(wind, 0.0, pan=0.0, rev=0.4)
    m.pad_filtered = sweep_lowpass(m.pad, lambda t: 2400 + 1300 * np.sin(2 * np.pi * t / 24.0 - 1.5))
    return master(m, rng, delay_s=m.beat * 0.75)


def track_space():
    """'Deep Drift' - 60 BPM, 30 bars of C minor: six chords, five bars each."""
    m = Mix(60, 202)
    rng = m.rng
    chords = [["C3", "G3", "D4", "Eb4"], ["Ab2", "Eb3", "G3", "D4"], ["Eb3", "Bb3", "D4", "G4"],
              ["Bb2", "F3", "C4", "D4"], ["F2", "C3", "Ab3", "G4"], ["G2", "D3", "C4", "F4"]]
    bar = m.beat * 4
    for c in range(6):
        t0 = m.at(c * 5)
        for i, note in enumerate(chords[c]):
            m.add(pad_note(n(note), bar * 5, rng, voices=6, detune=0.18, bright=0.6, a=5.0, r=5.0),
                  t0, pan=-0.7 + 1.4 * i / 3, rev=0.7, bus="pad")
    tt = np.arange(m.N) / SR
    # the drone: C1 and G1, breathing
    drone = (np.sin(2 * np.pi * float(mtof(n("C1"))) * tt) + 0.6 * np.sin(2 * np.pi * float(mtof(n("G1"))) * tt)
             + 0.25 * np.sin(2 * np.pi * float(mtof(n("C2"))) * 1.002 * tt))
    m.add(drone * (0.75 + 0.25 * np.sin(2 * np.pi * tt / 40.0)) * 0.055, 0.0, rev=0.2)
    # a slow pulse: a soft low C every two beats
    for k in range(int(LOOP / (m.beat * 2))):
        m.add(sub(n("C2"), 0.6, a=0.08, r=1.2), k * m.beat * 2, rev=0.3, gain=0.17 * (0.8 + 0.2 * (k % 2 == 0)))
    # twinkles: high bells from the chords, here and there
    for c in range(6):
        notes = [n(x) + 24 for x in chords[c]]
        for k in range(7):
            t0 = m.at(c * 5) + rng.uniform(0, bar * 5 - 1)
            m.add(bell(int(rng.choice(notes)), rng, decay=3.5, ratio=2.76, index=1.2), t0,
                  pan=rng.uniform(-0.9, 0.9), rev=0.85, gain=0.45)
    # sonar: a ping every 8 s, echoing away
    for k in range(15):
        m.add(ping(n("G5") if k % 2 == 0 else n("D5"), rng), k * 8.0 + 2.0, pan=-0.3 if k % 2 else 0.3, rev=0.6, delay=0.5, gain=0.55)
    # swells: filtered noise rising and falling every 20 s
    sw = band_noise(m.N, rng, 200, 3000)
    ph = (tt % 20.0) / 20.0
    m.add(sw * np.sin(np.pi * ph) ** 3 * 0.05, 0.0, rev=0.8)
    m.pad_filtered = sweep_lowpass(m.pad, lambda t: 1600 + 700 * np.sin(2 * np.pi * t / 40.0))
    return master(m, rng, delay_s=m.beat * 1.5, rev_s=8.0)


def track_surface():
    """'Minoan Shores' - 96 BPM, 48 bars: Am - G - F - E (two bars each), six times."""
    m = Mix(96, 303)
    rng = m.rng
    chords = [["A2", "E3", "A3", "C4"], ["G2", "D3", "G3", "B3"], ["F2", "C3", "F3", "A3"], ["E2", "B2", "E3", "G#3"]]
    roots = ["A1", "G1", "F1", "E1"]
    arps = [["A3", "C4", "E4", "A4"], ["G3", "B3", "D4", "G4"], ["F3", "A3", "C4", "F4"], ["E3", "G#3", "B3", "E4"]]
    bar = m.beat * 4
    for c in range(24):                                    # 24 chords x 2 bars = 48 bars
        ch = c % 4
        t0 = m.at(c * 2)
        for i, note in enumerate(chords[ch]):
            m.add(pad_note(n(note), bar * 2, rng, voices=3, detune=0.08, bright=0.5, a=1.2, r=1.8, shape="tri"),
                  t0, pan=-0.5 + i / 3, rev=0.35, bus="pad", gain=1.3)
        for b in range(2):
            barno = c * 2 + b
            # bass: the root on 1 and the "and" of 2
            for beat in (0.0, 1.5, 2.5):
                m.add(pluck(n(roots[ch]), rng, decay=0.9, bright=0.35), m.at(barno, beat), rev=0.1, gain=0.45)
            # the lyre: 8ths through the chord, bars 4..44
            level = np.clip((barno - 3) / 2, 0, 1) * np.clip((45 - barno) / 3, 0, 1)
            if level > 0:
                pat = [0, 1, 2, 3, 2, 1, 2, 3] if b == 0 else [3, 2, 1, 2, 0, 1, 2, 1]
                for s, idx in enumerate(pat):
                    m.add(pluck(n(arps[ch][idx]) + 12, rng, decay=1.1, bright=0.8), m.at(barno, s * 0.5),
                          pan=0.4 if s % 2 else -0.2, rev=0.3, delay=0.15, gain=0.65 * level * (1.0 if s % 2 == 0 else 0.75))
            # frame drum (dum . tek . . dum tek .) and a shaker, bars 8..40
            dl = np.clip((barno - 7) / 2, 0, 1) * np.clip((41 - barno) / 3, 0, 1)
            if dl > 0:
                for s, k in enumerate(["dum", None, "tek", None, None, "dum", "tek", None]):
                    if k:
                        m.add(drum(k, rng), m.at(barno, s * 0.5), pan=-0.1 if k == "dum" else 0.25, rev=0.25, gain=0.7 * dl)
                for s in range(16):
                    m.add(shaker(rng, 1.0 if s % 4 == 2 else 0.55), m.at(barno, s * 0.25), pan=0.5, rev=0.15, gain=dl)
    # the flute: a phrase in E Phrygian dominant (the E chord's G#), bars 16..40
    phrase = [(0, 0, "E5", 1), (0, 1, "F5", 1), (0, 2, "G#5", 2), (1, 0, "A5", 3), (1, 3, "G#5", 1),
              (2, 0, "F5", 2), (2, 2, "E5", 2), (3, 0, "E5", 4),
              (4, 0, "C6", 2), (4, 2, "B5", 1), (4, 3, "A5", 1), (5, 0, "B5", 4), (6, 0, "A5", 1), (6, 1, "G#5", 1),
              (6, 2, "F5", 2), (7, 0, "E5", 4)]
    for start in (16, 24, 32):
        for barno, beat, note, ln in phrase:
            m.add(flute(n(note) - (12 if start == 24 else 0), ln * m.beat, rng), m.at(start + barno, beat),
                  pan=-0.15, rev=0.45, delay=0.2, gain=1.1)
    # the sea: noise in slow waves (every 10 s)
    tt = np.arange(m.N) / SR
    sea = band_noise(m.N, rng, 150, 1800) * (0.35 + 0.65 * np.sin(np.pi * ((tt % 10.0) / 10.0)) ** 2) * 0.04
    m.add(sea, 0.0, pan=0.0, rev=0.3)
    m.pad_filtered = sweep_lowpass(m.pad, lambda t: 2600 + 800 * np.sin(2 * np.pi * t / 30.0))
    return master(m, rng, delay_s=m.beat * 0.75)


TRACKS = {"menu": ("Atrapos", track_menu), "space": ("Deep Drift", track_space), "surface": ("Minoan Shores", track_surface)}


# --- output, analysis -----------------------------------------------------------------------------

def write_ogg(x, path):
    pcm = (np.clip(x.T, -1, 1) * 32767).astype("<i2")
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as fh:
        tmp = fh.name
    with wave.open(tmp, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "4", path], check=True)
    os.remove(tmp)


def analyse(x):
    db = lambda v: 20 * np.log10(max(float(v), 1e-9))
    mono = x.mean(axis=0)
    rms = np.sqrt(np.mean(x ** 2))
    # the loop seam: the jump across it, against the typical sample-to-sample step
    step = np.median(np.abs(np.diff(mono[:SR])))
    seam = abs(mono[0] - mono[-1])
    # level over time (1 s windows): steady for a menu / background loop?
    w = SR
    lv = [db(np.sqrt(np.mean(mono[i:i + w] ** 2))) for i in range(0, len(mono) - w, w)]
    X = np.abs(np.fft.rfft(mono[: SR * 30]))
    f = np.fft.rfftfreq(SR * 30, 1 / SR)
    bands = {"sub <60": (0, 60), "bass 60-250": (60, 250), "low-mid 250-1k": (250, 1000), "mid 1-4k": (1000, 4000), "high 4k+": (4000, 22050)}
    tot = np.sum(X ** 2)
    share = {k: float(np.sum(X[(f >= a) & (f < b)] ** 2) / tot) for k, (a, b) in bands.items()}
    corr = float(np.corrcoef(x[0], x[1])[0, 1])
    return {"rms_db": db(rms), "peak_db": db(np.max(np.abs(x))), "seam": seam / (step + 1e-9), "lv_min": min(lv),
            "lv_max": max(lv), "share": share, "stereo_corr": corr, "levels": lv}


def picture(x, a, path, title):
    from PIL import Image, ImageDraw
    W, H = 1200, 260
    mono = x.mean(axis=0)
    nfft, cols = 2048, W
    hop = (len(mono) - nfft) // cols
    win = np.hanning(nfft)
    S = np.array([np.abs(np.fft.rfft(mono[i * hop:i * hop + nfft] * win)) for i in range(cols)]).T
    fr = np.fft.rfftfreq(nfft, 1 / SR)
    rows = np.geomspace(30, 16000, H)
    S = 20 * np.log10(S[np.clip(np.searchsorted(fr, rows), 0, len(fr) - 1)] + 1e-6)
    S = np.clip((S - (S.max() - 75)) / 75, 0, 1)[::-1]
    rgb = np.stack([np.clip(S * 2 - 0.5, 0, 1), np.clip(S * 1.5 - 0.2, 0, 1) ** 1.2, np.clip(S * 1.2, 0, 1) ** 0.6], -1)
    img = Image.new("RGB", (W + 20, H + 120), (12, 10, 18))
    img.paste(Image.fromarray((rgb * 255).astype(np.uint8)), (10, 30))
    d = ImageDraw.Draw(img)
    d.text((10, 8), "%s  -  %d s loop  ·  RMS %.1f dBFS  ·  peak %.1f  ·  seam jump %.1fx a normal step" % (title, LOOP, a["rms_db"], a["peak_db"], a["seam"]), fill=(235, 220, 190))
    lv = a["levels"]   # level curve under it
    y0 = H + 40
    for i in range(len(lv) - 1):
        x0, x1 = 10 + i * W / len(lv), 10 + (i + 1) * W / len(lv)
        d.line([(x0, y0 + 70 - (lv[i] + 40) * 2), (x1, y0 + 70 - (lv[i + 1] + 40) * 2)], fill=(120, 220, 255), width=2)
    d.text((10, y0 + 72), "level per second (dBFS, -40 .. -5)", fill=(150, 160, 180))
    img.save(path)


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(REPORT, exist_ok=True)
    which = sys.argv[1:] or list(TRACKS)
    lines = ["# The music - analysis", "", "tools/music_gen.py: stereo 44.1 kHz, Vorbis q4, each a seamless %d s loop." % LOOP,
             "seam = the jump across the loop point in units of a typical sample step (~1 = seamless);",
             "corr = left/right correlation (1 = mono, lower = wider).", "",
             "| track | RMS dBFS | peak | level range (1 s) | seam | corr | sub | bass | low-mid | mid | high | size |",
             "|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for key in which:
        title, fn = TRACKS[key]
        print("rendering", key, "...", flush=True)
        x = fn()
        path = os.path.join(OUT, key + ".ogg")
        write_ogg(x, path)
        a = analyse(x)
        picture(x, a, os.path.join(REPORT, key + ".png"), '%s - "%s"' % (key, title))
        s = a["share"]
        lines.append("| %s \"%s\" | %.1f | %.1f | %.1f .. %.1f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %d KB |" % (
            key, title, a["rms_db"], a["peak_db"], a["lv_min"], a["lv_max"], a["seam"], a["stereo_corr"],
            s["sub <60"], s["bass 60-250"], s["low-mid 250-1k"], s["mid 1-4k"], s["high 4k+"], os.path.getsize(path) // 1024))
        print(lines[-1], flush=True)
    if set(which) == set(TRACKS):
        with open(os.path.join(REPORT, "analysis.md"), "w") as fh:
            fh.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
