"""The androids' animations, 30 fps: each a list of poses of the kit's controls
(kit.DEFAULT), from key poses (kit.frames_of) or worked out per frame (the
walk and run cycles, breathing).

  clips(skin) -> {name: {"poses": [...], "loop": bool, "gun": bool, "marks": {...}}}

Without the rifle: idle, guard (the fighting stance), walk, run, the martial
arts - jab, cross, hook, uppercut, elbow, knee, front (kick), side (kick),
round (house kick), spin (back kick), sweep, flykick, palm - leap (a flip
through the air), cast_bolt / cast_sky / cast_dome / cast_summon (spells),
hit, block, ko, sit (on a 0.46 m chair), stool (on a 0.80 m bar stool, the
forearms on the counter), carry / carry_idle (a crate in both hands, the palms on its sides), put_down /
pick_up (squatting to set the crate on the floor / take it up - 1.4 s each; see PUT_RELEASE, PICK_GRIP), console (at a terminal:
typing on its panel, touching its screen), swim / swim_idle (at the surface: a head-up crawl, treading water - the
water line SWIM_LINE 1.25 m up the model, at the neck), dive / dive_idle (underwater: a breaststroke, hovering). With it:
gun_idle, gun_walk, gun_run, raise (to the shoulder), fire. "marks": the frame
a strike lands ("hit"), a spell lets go ("cast"), the feet leave / touch the ground ("off", "land"), the hands let go of the crate /
take it ("release": put_down frame 22 = 0.733 s, "grip": pick_up frame 18 = 0.6 s); "box": the crate's middle each
frame (put_down / pick_up; exported to model.json as points.box, [x, up, forward] m).
Positions are (to its left, forward, up) in metres; the one it fights stands
about 0.8 m in front.
"""
import math

import kit

TAU = 2 * math.pi


def P(base, **over):
    d = dict(base)
    d.update(over)
    return d


# ------------------------------------------------------------------ standing

STAND = dict(pelvis=(0, 0, -0.016), handL=("c", (0.285, 0.03, -0.65)), handR=("c", (-0.285, 0.03, -0.65)),
             footL=("w", (0.15, 0.0, 0)), footR=("w", (-0.15, 0.0, 0)), fyawL=13, fyawR=13, gripL=0.6, gripR=0.6)

# The fighting stance: the left side leading, fists up.
GUARD = dict(pelvis=(0.0, 0.0, -0.09), pyaw=-28, lean=7,
             footL=("w", (0.09, 0.21, 0)), fyawL=-12, footR=("w", (-0.13, -0.21, 0)), fyawR=48,
             handL=("c", (0.13, 0.33, -0.13)), elbowL=(0.4, -0.25, -1.0),
             handR=("c", (-0.12, 0.25, -0.10)), elbowR=(-0.6, -0.2, -1.0),     # (the rear fist off the chest, its elbow out)
             gripL=1.0, gripR=1.0, hpitch=5)


def breathe(base, n, amp=0.007, arms=0.006):
    out = []
    for i in range(n):
        s = math.sin(TAU * i / n)
        p = kit.full(base)
        pv = p["pelvis"]
        p["pelvis"] = (pv[0], pv[1], pv[2] + amp * s)
        p["lean"] = p["lean"] + 1.2 * s
        for h in ("handL", "handR"):
            sp, q = p[h]
            p[h] = (sp, (q[0], q[1], q[2] + arms * math.sin(TAU * i / n - 0.6)))
        out.append(p)
    return out


def bounce(base, n):
    """The stance, alive: a small bounce on the balls of the feet, the fists circling."""
    out = []
    for i in range(n):
        a = TAU * i / n
        p = kit.full(base)
        pv = p["pelvis"]
        p["pelvis"] = (pv[0], pv[1] + 0.012 * math.sin(a), pv[2] + 0.014 * math.cos(2 * a))
        p["twist"] = 3.0 * math.sin(a)
        sp, q = p["handL"]
        p["handL"] = (sp, (q[0], q[1] + 0.02 * math.sin(a + 0.5), q[2] + 0.012 * math.cos(a)))
        sp, q = p["handR"]
        p["handR"] = (sp, (q[0], q[1] + 0.012 * math.sin(a + 2.0), q[2] + 0.01 * math.cos(a + 1.0)))
        out.append(p)
    return out


# ------------------------------------------------------------------ walking and running

def _foot_walk(ph, L, lift):
    """A foot through a walk cycle (ph 0..1; 0 = heel strike in front): forward, up, pitch."""
    st = 0.58
    if ph < st:
        s = ph / st
        fwd = L * (0.5 - s)
        pitch = -14.0 * max(0.0, 1 - s / 0.18) + 28.0 * max(0.0, (s - 0.72) / 0.28)
        up = 0.035 * max(0.0, (s - 0.8) / 0.2)
        return fwd, up, pitch
    s = (ph - st) / (1 - st)
    e = s * s * (3 - 2 * s)
    fwd = L * (-0.5 + e)
    up = 0.035 * (1 - s) + lift * math.sin(math.pi * s) ** 1.2
    pitch = 28.0 * (1 - s) ** 2 * (1 - s) + 30.0 * math.sin(math.pi * s) * (1 - s) - 14.0 * s * s
    return fwd, up, pitch


def walk(n, gun=None, L=0.62, arm=0.17, hx=0.29, hz=-0.625, grip=0.35):
    """hx / hz: the hands' swing line (chest space; out clear of the thighs), grip: the fingers' curl."""
    out = []
    for i in range(n):
        u = i / n
        c, s2 = math.cos(TAU * u), math.sin(TAU * u)
        fl = _foot_walk(u % 1.0, L, 0.10)
        fr = _foot_walk((u + 0.5) % 1.0, L, 0.10)
        p = dict(
            pelvis=(0.012 * s2, 0.0, -0.04 + 0.018 * math.cos(2 * TAU * u + 0.5)),
            pyaw=-5.0 * c, proll=2.5 * s2, twist=11.0 * c, lean=4.0,
            footL=("w", (0.10, fl[0], fl[1])), fpitchL=fl[2], fyawL=6,
            footR=("w", (-0.10, fr[0], fr[1])), fpitchR=fr[2], fyawR=6,
            handL=("c", (hx, 0.03 - arm * c, hz + 0.03 * abs(c))),
            handR=("c", (-hx, 0.03 + arm * c, hz + 0.03 * abs(c))),
            gripL=grip, gripR=grip)
        if gun:
            p["gun"] = gun["gun"]
            p["twist"] = 4.0 * c
            g = p["gun"]
            p["gun"] = (g[0], (g[1][0], g[1][1], g[1][2] + 0.01 * math.cos(2 * TAU * u)), g[2], g[3], g[4])
        out.append(kit.full(p))
    return out


def _foot_run(ph, L, lift):
    st = 0.36
    if ph < st:
        s = ph / st
        return L * (0.36 - 0.86 * s), 0.02 * max(0.0, (s - 0.7) / 0.3), -8.0 * max(0.0, 1 - s / 0.2) + 45.0 * max(0.0, (s - 0.55) / 0.45)
    s = (ph - st) / (1 - st)
    e = s * s * (3 - 2 * s)
    fwd = L * (-0.5 + 0.86 * e)
    up = 0.02 + lift * math.sin(math.pi * min(1.0, s * 1.15)) ** 1.1 + 0.16 * math.sin(math.pi * s) * (1 - s)
    pitch = 45.0 * (1 - s) + 35.0 * math.sin(math.pi * s) - 8.0 * s
    return fwd, up, pitch


def run(n, gun=None, L=1.0):
    out = []
    for i in range(n):
        u = i / n
        c, s2 = math.cos(TAU * u), math.sin(TAU * u)
        fl = _foot_run(u % 1.0, L, 0.16)
        fr = _foot_run((u + 0.5) % 1.0, L, 0.16)
        p = dict(
            pelvis=(0.01 * s2, 0.02, -0.07 + 0.035 * math.cos(2 * TAU * u + 1.9)),
            pyaw=-9.0 * c, proll=3.0 * s2, twist=20.0 * c, lean=14.0, hpitch=-6,
            footL=("w", (0.085, fl[0], fl[1])), fpitchL=fl[2], fyawL=3,
            footR=("w", (-0.085, fr[0], fr[1])), fpitchR=fr[2], fyawR=3,
            kneeL=(0.05, 1.0, 0.0), kneeR=(-0.05, 1.0, 0.0),
            handL=("c", (0.25, 0.14 - 0.24 * c, -0.44 - 0.05 * c)), elbowL=(0.3, -1.0, -0.2),
            handR=("c", (-0.25, 0.14 + 0.24 * c, -0.44 + 0.05 * c)), elbowR=(-0.3, -1.0, -0.2),
            gripL=1.0, gripR=1.0)
        if gun:
            p["gun"] = gun["gun"]
            p["twist"] = 7.0 * c
            g = p["gun"]
            p["gun"] = (g[0], (g[1][0], g[1][1], g[1][2] + 0.018 * math.cos(2 * TAU * u)), g[2], g[3], g[4])
        out.append(kit.full(p))
    return out


# ------------------------------------------------------------------ martial arts

def K(*keys):
    return kit.frames_of(list(keys))


G = GUARD
FWD = 0.82          # where the strikes land (m in front)


def jab():
    hit = P(G, pelvis=(0.0, 0.06, -0.10), pyaw=-36, twist=-10, lean=9,
            handL=("w", (0.03, FWD, 1.46)), elbowL=(0.6, -0.2, -0.8), handR=("c", (-0.12, 0.25, -0.09)))
    return K((0, G), (3, hit, "i"), (5, hit), (9, G, "o"))


def cross():
    wind = P(G, twist=-8, handR=("c", (-0.16, 0.24, -0.10)))
    hit = P(G, pelvis=(0.03, 0.12, -0.12), pyaw=4, twist=30, lean=10,
            footR=("w", (-0.12, -0.20, 0.03)), fyawR=10, fpitchR=38,
            handR=("w", (-0.03, FWD + 0.03, 1.47)), elbowR=(-0.6, -0.2, -0.8),
            handL=("c", (0.15, 0.24, -0.08)), elbowL=(0.6, -0.2, -1.0))
    return K((0, G), (2, wind), (5, hit, "i"), (7, hit), (11, G, "o"))


def hook():
    wind = P(G, twist=-22, pelvis=(0.02, 0.0, -0.12), handL=("c", (0.24, 0.20, -0.14)), elbowL=(1.0, -0.4, -0.3))
    mid = P(G, pelvis=(0.0, 0.05, -0.11), pyaw=-10, twist=10,
            handL=("c", (0.20, 0.36, -0.12)), elbowL=(1.0, 0.0, 0.1))
    hit = P(G, pelvis=(-0.02, 0.08, -0.11), pyaw=2, twist=38, fyawL=-45, fpitchL=10,
            handL=("c", (-0.06, 0.36, -0.11)), elbowL=(1.0, 0.2, 0.1), handR=("c", (-0.12, 0.24, -0.08)))
    return K((0, G), (3, wind), (5, mid, "i"), (7, hit, "l"), (8, hit), (12, G, "o"))


def uppercut():
    dip = P(G, pelvis=(-0.03, 0.02, -0.24), twist=-20, lean=18, handR=("c", (-0.27, 0.20, -0.46)), elbowR=(-0.8, -1.0, -0.2),
            hpitch=-8)
    hit = P(G, pelvis=(0.02, 0.10, -0.03), pyaw=0, twist=34, lean=-6,
            footR=("w", (-0.12, -0.18, 0.04)), fyawR=10, fpitchR=40, fpitchL=6,
            handR=("w", (0.0, 0.50, 1.68)), elbowR=(-0.5, -0.2, -1.0), handL=("c", (0.15, 0.23, -0.09)), elbowL=(0.6, -0.2, -1.0), hpitch=-4)
    rise = P(hit, pelvis=(0.0, 0.07, -0.10), twist=18, lean=4, handR=("w", (-0.10, 0.44, 1.32)), elbowR=(-0.7, -0.6, -0.5))   # (out in front of the chest on its way up)
    return K((0, G), (4, dip), (6, rise, "i"), (7, hit, "o"), (9, hit), (13, G, "o"))


def elbow():
    wind = P(G, twist=-15, handR=("c", (-0.22, 0.18, -0.14)))
    hit = P(G, pelvis=(0.02, 0.16, -0.13), pyaw=6, twist=42, lean=12,
            footR=("w", (-0.11, -0.16, 0.03)), fyawR=5, fpitchR=35,
            handR=("c", (0.06, 0.26, -0.12)), elbowR=(-0.5, 1.0, 0.15), handL=("c", (0.16, 0.22, -0.08)), elbowL=(0.6, -0.2, -1.0))
    return K((0, G), (2, wind), (5, hit, "i"), (7, hit), (10, G, "o"))


def knee():
    grab = P(G, pelvis=(0.0, 0.10, -0.08), pyaw=-10, lean=10,
             handL=("w", (0.14, 0.62, 1.52)), handR=("w", (-0.14, 0.62, 1.52)), gripL=0.3, gripR=0.3)
    hit = P(G, pelvis=(0.02, 0.20, -0.02), pyaw=8, lean=-12, fpitchL=18,
            footR=("p", (-0.02, 0.30, -0.36)), kneeR=(0.0, 1.0, 0.9), fpitchR=55,
            handL=("w", (0.12, 0.45, 1.25)), handR=("w", (-0.12, 0.45, 1.25)), gripL=0.6, gripR=0.6)
    return K((0, G), (3, grab), (6, hit, "i"), (8, hit), (12, G, "o"))


def front():
    # (the pelvis tipped back under the kick - the hip less folded, the thigh clear of the apron's top; the chest as before)
    chamber = P(G, pelvis=(0.02, 0.05, -0.05), pyaw=-8, ppitch=-12, lean=12,
                footR=("p", (-0.03, 0.11, -0.535)), kneeR=(0.0, 1.0, 0.8), fpitchR=40,
                handL=("c", (0.16, 0.28, -0.14)), handR=("c", (-0.24, 0.20, -0.20)), elbowR=(-0.7, -0.5, -0.6))
    hit = P(G, pelvis=(0.02, 0.12, -0.04), pyaw=4, ppitch=-25, lean=9,
            footR=("p", (-0.02, 0.76, -0.40)), kneeR=(0.0, 0.6, 1.0), fpitchR=-55,
            handL=("c", (0.20, 0.22, -0.16)), handR=("c", (-0.30, 0.04, -0.34)), elbowR=(-0.4, -1.0, -0.2))
    back = P(hit, ppitch=-20, lean=8, footR=("p", (-0.03, 0.50, -0.50)), kneeR=(0.0, 0.8, 1.0), fpitchR=-10)   # (drawn back the way it went)
    return K((0, G), (4, chamber), (6, hit, "i"), (8, hit), (9, back), (10, chamber), (13, G, "o"))


def side():
    turn = P(G, pelvis=(0.03, 0.04, -0.06), pyaw=50, twist=-10, fyawL=75,
             footR=("p", (-0.22, 0.10, -0.42)), kneeR=(-0.4, 1.0, 0.6), fpitchR=10,
             handL=("c", (0.16, 0.22, -0.12)), handR=("c", (-0.15, 0.27, -0.14)), elbowR=(-0.7, -0.3, -0.8))
    hit = P(G, pelvis=(0.05, 0.10, -0.06), pyaw=84, twist=-6, bend=30, fyawL=110, proll=-16,
            footR=("p", (-0.86, 0.0, -0.02)), kneeR=(0.0, 1.0, 0.3), fpitchR=-25,
            handL=("c", (0.18, 0.20, -0.10)), elbowL=(0.7, -0.3, -0.8), handR=("c", (-0.34, 0.04, -0.34)), elbowR=(-0.6, -0.8, -0.2))
    return K((0, G), (5, turn), (7, hit, "i"), (9, hit), (11, turn), (15, G, "o"))


def round_():
    chamber = P(G, pelvis=(0.03, 0.03, -0.05), pyaw=10, fyawL=40, bend=8,
                footR=("p", (-0.30, 0.02, -0.26)), kneeR=(-0.6, 1.0, 0.6), fpitchR=40,     # (the knee up in front: the thigh clear of the apron)
                handL=("c", (0.14, 0.24, -0.10)), handR=("c", (-0.28, 0.20, -0.20)), elbowR=(-0.9, -0.5, -0.4))
    hit = P(G, pelvis=(0.05, 0.08, -0.04), pyaw=74, twist=-4, bend=26, fyawL=115, proll=-18,
            footR=("p", (-0.84, 0.16, 0.22)), kneeR=(-0.3, 1.0, 0.3), fpitchR=50,
            handL=("c", (0.16, 0.22, -0.08)), handR=("c", (-0.34, -0.10, -0.30)), elbowR=(-0.3, -1.0, 0.0))
    past = P(hit, pyaw=96, footR=("p", (-0.70, 0.30, 0.10)))
    return K((0, G), (5, chamber), (8, hit, "i"), (9, past, "l"), (12, P(chamber, pyaw=40, kneeR=(-0.3, 1.0, 0.6))), (16, G, "o"))


def spin():
    # (turning to its right, the back to the target, the right leg thrown out behind)
    t1 = P(G, pelvis=(0.0, 0.03, -0.10), pyaw=-110, twist=-25, fyawL=-70, fyawR=10,
           footR=("w", (0.02, -0.02, 0.0)), handL=("c", (0.14, 0.22, -0.12)), handR=("c", (-0.14, 0.22, -0.12)), hyaw=-60)
    t2 = P(G, pelvis=(0.02, 0.06, -0.08), pyaw=-178, twist=-20, lean=18, fyawL=-150,
           footR=("p", (-0.06, -0.30, -0.42)), kneeR=(0.0, 1.0, 0.2), fpitchR=20,
           handL=("c", (0.16, 0.22, -0.12)), handR=("c", (-0.16, 0.20, -0.14)), hyaw=-80)
    hit = P(G, pelvis=(0.02, 0.10, -0.07), pyaw=-186, twist=-10, lean=40, fyawL=-170,
            footR=("p", (-0.03, -0.86, 0.05)), kneeR=(0.0, 1.0, -0.2), fpitchR=20,
            handL=("c", (0.20, 0.22, -0.14)), handR=("c", (-0.20, 0.20, -0.16)), hyaw=-95)
    t3 = P(G, pelvis=(0.0, 0.05, -0.08), pyaw=-290, twist=0, fyawL=-250, fyawR=40,
           footR=("w", (-0.10, 0.10, 0.02)), hyaw=-250, handL=("c", (0.14, 0.25, -0.12)))
    end = P(G, pyaw=-388, fyawL=-372, fyawR=48 , hyaw=-360)
    return K((0, G), (4, t1), (7, t2, "l"), (9, hit, "i"), (11, hit), (15, t3), (18, end, "o"))


def sweep():
    down = P(G, pelvis=(0.04, 0.02, -0.46), pyaw=-60, lean=24,
             footL=("w", (0.10, 0.12, 0)), fyawL=-30, fpitchL=18, kneeL=(0.4, 1.0, 0.0),
             footR=("p", (-0.40, -0.30, -0.36)), kneeR=(-0.5, 0.3, 1.0), fpitchR=10,
             handL=("w", (0.28, 0.34, 0.10)), gripL=0.2, wristL=-50, handR=("c", (-0.20, 0.16, -0.20)), hpitch=-10)
    s1 = P(down, pyaw=-10, footR=("p", (-0.84, -0.10, -0.40)), kneeR=(0.0, 0.3, 1.0), fpitchR=20)
    s2 = P(down, pyaw=80, footR=("p", (-0.84, 0.05, -0.40)), kneeR=(0.0, 0.3, 1.0), fpitchR=20,
           handL=("w", (0.22, 0.30, 0.10)))
    s3 = P(down, pyaw=140, footR=("p", (-0.70, 0.10, -0.40)), kneeR=(0.0, 0.3, 1.0))
    up = P(G, pelvis=(0.0, 0.0, -0.30), pyaw=-28 + 360, fyawL=-12, fyawR=48, hyaw=360)
    end = P(G, pyaw=-28 + 360, hyaw=360)
    return K((0, G), (5, down), (7, s1, "i"), (10, s2, "l"), (12, s3, "o"), (15, up), (18, end, "o"))


def flykick():
    crouch = P(G, pelvis=(0.0, 0.0, -0.30), lean=22, pyaw=-10, handL=("c", (0.24, -0.10, -0.40)), handR=("c", (-0.24, -0.10, -0.40)))
    rise = P(G, pelvis=(0.0, 0.08, 0.0), air=0.30, pyaw=0, lean=0,
             footL=("p", (0.03, 0.05, -0.62)), kneeL=(0.1, 1.0, 0.2), fpitchL=40,
             footR=("p", (-0.03, 0.25, -0.50)), kneeR=(0.0, 1.0, 0.6), fpitchR=40,
             handL=("c", (0.30, 0.20, -0.10)), handR=("c", (-0.30, 0.10, -0.20)))
    hit = P(G, pelvis=(0.0, 0.10, -0.02), air=0.62, pyaw=40, lean=-28, bend=6,
            footR=("p", (-0.22, 0.84, -0.02)), kneeR=(-0.2, 0.6, 1.0), fpitchR=-30,
            footL=("p", (0.10, 0.22, -0.40)), kneeL=(0.6, 1.0, 0.5), fpitchL=50,
            handL=("c", (0.34, 0.06, -0.20)), elbowL=(1.0, -0.5, 0.0), handR=("c", (-0.34, -0.14, -0.26)), elbowR=(-1, -1, 0))
    fall = P(hit, air=0.34, lean=-14)
    land = P(G, pelvis=(0.0, 0.04, -0.28), lean=20, handL=("c", (0.26, 0.20, -0.30)), handR=("c", (-0.26, 0.16, -0.30)))
    return K((0, G), (4, crouch), (7, rise, "o"), (9, hit, "i"), (12, hit), (14, fall), (16, land, "i"), (20, G, "o"))


def palm():
    wind = P(G, pelvis=(0.0, -0.05, -0.16), pyaw=-34, lean=4,
             handL=("c", (0.16, 0.08, -0.30)), handR=("c", (-0.16, 0.08, -0.30)), gripL=0.1, gripR=0.1, wristL=-50, wristR=-50)
    hit = P(G, pelvis=(0.0, 0.22, -0.20), pyaw=-10, lean=14,
            footL=("w", (0.10, 0.36, 0)), footR=("w", (-0.13, -0.24, 0.03)), fpitchR=34, fyawR=25,
            handL=("w", (0.07, FWD, 1.30)), handR=("w", (-0.07, FWD, 1.24)), elbowL=(1.0, -0.3, -0.5), elbowR=(-1.0, -0.3, -0.5),
            gripL=0.0, gripR=0.0, wristL=-75, wristR=-75)
    return K((0, G), (4, wind), (7, hit, "i"), (10, hit), (14, G, "o"))


# ------------------------------------------------------------------ the leap

def leap():
    crouch = P(G, pelvis=(0.0, -0.02, -0.34), pyaw=-8, lean=30, hpitch=-14,
               footL=("w", (0.10, 0.10, 0)), footR=("w", (-0.11, -0.10, 0.02)), fpitchR=20, fyawR=20,
               handL=("c", (0.26, -0.22, -0.34)), handR=("c", (-0.26, -0.22, -0.34)))
    launch = P(G, pelvis=(0.0, 0.10, 0.0), air=0.25, pyaw=0, lean=-4, ppitch=10,
               footL=("p", (0.02, -0.12, -0.84)), fpitchL=60, footR=("p", (-0.02, -0.20, -0.82)), fpitchR=60,
               handL=("c", (0.24, 0.30, 0.28)), handR=("c", (-0.24, 0.30, 0.28)), elbowL=(1, -0.3, -0.3), elbowR=(-1, -0.3, -0.3))
    tuck1 = P(G, pelvis=(0.0, 0.0, 0.0), air=0.95, pyaw=0, lean=40, ppitch=120, hpitch=20, hfree=1, hyaw=0,
              footL=("p", (0.06, 0.30, -0.36)), kneeL=(0.2, 1.0, 0.6), fpitchL=30,
              footR=("p", (-0.06, 0.30, -0.36)), kneeR=(-0.2, 1.0, 0.6), fpitchR=30,
              handL=("c", (0.20, 0.30, -0.50)), handR=("c", (-0.20, 0.30, -0.50)))
    tuck2 = P(tuck1, air=1.05, ppitch=250)
    open_ = P(G, pelvis=(0.0, 0.0, 0.0), air=0.50, pyaw=-10, lean=10, ppitch=350, hfree=0,
              footL=("p", (0.04, 0.16, -0.74)), fpitchL=20, footR=("p", (-0.06, -0.06, -0.78)), fpitchR=30,
              handL=("c", (0.36, 0.10, -0.20)), handR=("c", (-0.36, 0.10, -0.20)), elbowL=(1, -0.5, 0), elbowR=(-1, -0.5, 0))
    land = P(G, pelvis=(0.0, 0.02, -0.36), ppitch=360, lean=26, hpitch=-10,
             handL=("c", (0.28, 0.18, -0.36)), handR=("c", (-0.28, 0.10, -0.36)))
    end = P(G, ppitch=360)
    return K((0, G), (4, crouch), (7, launch, "o"), (11, tuck1, "l"), (14, tuck2, "l"), (17, open_, "l"), (19, land, "i"), (23, end, "o"))


# ------------------------------------------------------------------ jumping, falling, the jet pack
# (on foot in the 3D game: the walker rises and falls by itself - no "air" in
# these, the feet hang from the pelvis ("p") instead of standing on the ground)

AIR = dict(pelvis=(0.0, 0.0, -0.02), lean=4, hpitch=-4,
           footL=("p", (0.11, 0.04, -0.80)), fpitchL=28, fyawL=6, kneeL=(0.1, 1.0, 0.3),
           footR=("p", (-0.11, -0.04, -0.82)), fpitchR=28, fyawR=6, kneeR=(-0.1, 1.0, 0.3),
           handL=("c", (0.36, 0.06, -0.42)), elbowL=(1.0, -0.2, -0.4),
           handR=("c", (-0.36, 0.06, -0.42)), elbowR=(-1.0, -0.2, -0.4), gripL=0.5, gripR=0.5)


def jump():
    """Off the ground, upright: a quick push (arms swing up), the knees drawn up a
    little at the top - then the "fall" pose. No flip."""
    push = P(AIR, lean=-2, hpitch=6,
             footL=("p", (0.10, -0.06, -0.86)), fpitchL=55, footR=("p", (-0.10, -0.10, -0.85)), fpitchR=55,
             handL=("c", (0.30, 0.18, -0.10)), elbowL=(1.0, -0.4, -0.2), handR=("c", (-0.30, 0.18, -0.10)), elbowR=(-1.0, -0.4, -0.2))
    top = P(AIR, lean=8,
            footL=("p", (0.11, 0.14, -0.66)), fpitchL=20, kneeL=(0.1, 1.0, 0.6),
            footR=("p", (-0.11, 0.06, -0.70)), fpitchR=24, kneeR=(-0.1, 1.0, 0.6),
            handL=("c", (0.38, 0.12, -0.34)), handR=("c", (-0.38, 0.12, -0.34)))
    return K((0, push), (5, top, "o"), (12, AIR, "io"))


def fall(n=24):
    """In the air, falling: the arms out for balance, the legs a little apart, stirring."""
    out = []
    for i in range(n):
        s = math.sin(TAU * i / n)
        c = math.cos(TAU * i / n)
        p = kit.full(AIR)
        p["handL"] = ("c", (0.40 + 0.03 * s, 0.06, -0.36 + 0.04 * c))
        p["handR"] = ("c", (-0.40 - 0.03 * s, 0.06, -0.36 - 0.04 * c))
        p["footL"] = ("p", (0.12, 0.05 + 0.04 * s, -0.79))
        p["footR"] = ("p", (-0.12, -0.03 - 0.04 * s, -0.81))
        p["lean"] = 4 + 2 * s
        out.append(p)
    return out


def jet(n=30):
    """Hovering on the jet pack: upright, the legs together and hanging a little back
    (the toes pointed), the arms down and out from the sides, palms back - steering;
    a slow bob and sway as the thrust breathes."""
    base = dict(pelvis=(0.0, 0.0, 0.0), lean=6, hpitch=-6,
                footL=("p", (0.07, -0.10, -0.86)), fpitchL=48, fyawL=2, kneeL=(0.05, 1.0, 0.2),
                footR=("p", (-0.07, -0.14, -0.85)), fpitchR=50, fyawR=2, kneeR=(-0.05, 1.0, 0.2),
                handL=("c", (0.42, -0.10, -0.50)), elbowL=(1.0, 0.2, -0.3), wristL=20,
                handR=("c", (-0.42, -0.10, -0.50)), elbowR=(-1.0, 0.2, -0.3), wristR=20, gripL=0.15, gripR=0.15)
    out = []
    for i in range(n):
        s = math.sin(TAU * i / n)
        c = math.cos(TAU * i / n)
        p = kit.full(base)
        p["pelvis"] = (0.006 * c, 0.0, 0.012 * s)
        p["proll"] = 2.0 * c
        p["lean"] = 6 + 1.5 * s
        p["handL"] = ("c", (0.42 + 0.02 * c, -0.10, -0.50 + 0.03 * s))
        p["handR"] = ("c", (-0.42 + 0.02 * c, -0.10, -0.50 - 0.03 * s))
        p["footL"] = ("p", (0.07, -0.10 - 0.02 * s, -0.86))
        p["footR"] = ("p", (-0.07, -0.14 + 0.02 * s, -0.85))
        out.append(p)
    return out


# ------------------------------------------------------------------ sitting, carrying
# (the pelvis comes down onto the seat over the root; the feet and the resting hands
# are root-space ("w") targets, so they stay put while the chest breathes)

SIT_PELVIS = -0.44      # the pelvis's drop for a 0.46 m chair seat (the automaton's frame)
STOOL_PELVIS = -0.10    # ... and for a 0.80 m bar stool
MINOAN_BODY = ("minoan", "guard", "athenian", "spartan", "mycenaean", "ionian", "cycladic")
MINOAN_SEAT = 0.015     # (the Minoan android's body is a little deeper under the hips: sat that much higher)
MINOAN_HAND_UP = 0.04   # (... and its hands on its knees that much higher)
MINOAN_FWD = 0.08       # (the Minoan android - with a quiver on its back, its cape over the chair's - sat that much forward)

SIT = dict(seat="sit", pelvis=(0.0, 0.0, SIT_PELVIS), lean=-4, hpitch=4,
           footL=("w", (0.13, 0.44, 0)), fyawL=8, kneeL=(0.1, 1.0, 0.2),
           footR=("w", (-0.13, 0.44, 0)), fyawR=8, kneeR=(-0.1, 1.0, 0.2),
           handL=("w", (0.14, 0.33, 0.67)), elbowL=(0.3, -1.0, -0.2), wristL=8,
           handR=("w", (-0.14, 0.33, 0.67)), elbowR=(-0.3, -1.0, -0.2), wristR=8, gripL=0.35, gripR=0.35)

# The left foot's ball on the stool's rail (0.30 m up), the right hanging free; leaning on the counter.
STOOL = dict(seat="stool", pelvis=(0.0, 0.0, STOOL_PELVIS), lean=24, hpitch=-14,
             footL=("w", (0.12, 0.34, 0.415)), fyawL=8, fpitchL=40, kneeL=(0.1, 1.0, 0.3),
             footR=("w", (-0.13, 0.42, 0.30)), fyawR=10, fpitchR=28, kneeR=(-0.1, 1.0, 0.2),
             handL=("w", (0.10, 0.58, 1.14)), elbowL=(0.6, -0.2, -1.0), wristL=4,
             handR=("w", (-0.10, 0.58, 1.14)), elbowR=(-0.6, -0.2, -1.0), wristR=4, gripL=0.4, gripR=0.4)


# (the Minoan android's body: its thighs' painted bosses stand out further - the hands hang wider of them, a little forward, fingers easier)
MINOAN_HANDS = dict(handL=("c", (0.32, 0.05, -0.62)), handR=("c", (-0.32, 0.05, -0.62)))
MINOAN_WALK = dict(hx=0.32, hz=-0.61, grip=0.3)


COATED = ("pirate", "kilon")
COAT_SEAT = 0.09        # (in a long coat: sat further forward on a chair, upright - its back (the hoses) clear of the chair's, and the tails)


def on_seat(base, skin):
    pv = base["pelvis"]
    if skin in COATED and base.get("seat") == "sit":
        return P(base, pelvis=(pv[0], pv[1] + COAT_SEAT, pv[2]), lean=8)
    if skin not in MINOAN_BODY:
        return base
    base = P(base, pelvis=(pv[0], pv[1], pv[2] + MINOAN_SEAT))
    if base.get("seat") == "sit":       # (the hands resting a little higher: over the thighs' bosses)
        for h in ("handL", "handR"):
            sp, q = base[h]
            base = P(base, **{h: (sp, (q[0], q[1] + (MINOAN_FWD if skin == "minoan" else 0.0), q[2] + MINOAN_HAND_UP))})
        if skin == "minoan":            # (a little forward: the quiver on its back clear of the chair's)
            base = P(base, pelvis=(pv[0], pv[1] + MINOAN_FWD, pv[2] + MINOAN_SEAT))
    return base


# ------------------------------------------------------------------ a crate in both hands
# The crate as the game holds it (CosmosHangar / the walker: EmpireKit.crate_mesh scaled (0.33, 0.36, 0.25)):
# 0.396 m wide, 0.317 high, 0.325 deep; carried with its middle at CARRY_BOX (the game's CARRY_AT = (0, 1.06, 0.33)
# in the character's space). The palms lie flat on its two sides (fitted, frame by frame: box_hands), the fingers
# along the side, a little curled - the arms' planes upright, so the palms face each other.
BOX_SIZE = (0.396, 0.317, 0.325)            # (wide, high, deep; m)
CARRY_BOX = (0.0, 0.33, 1.06)               # the crate's middle while carried (left, forward, up)
FLOOR_BOX = (0.0, 0.50, BOX_SIZE[1] * 0.5)  # ... and set down on the ground: its bottom on the floor, 0.50 m in front (its near side 0.34, just clear of the knees)
PALM_GAP = 0.006                            # (m: the palms off the crate's sides - the fingers' slight curl meets it)
HOLD_AT = (-0.02, -0.01)                    # (where on a side the palm goes: from its middle, forward / up)
PALM = (0.02, 0.035, 0.004)                 # (the palm's inner face from the wrist, in the hand bone's axes: x * side = inward)


def _palm(mats, s):
    sx = 1.0 if s == "L" else -1.0
    return mats["hand." + s] @ kit.Vector((PALM[0] * sx, PALM[1], PALM[2]))


LOW_GRIP = 0.06    # (m: on the floor the palms hold the sides that much higher - nearer the top edges; up at the hold, the middle)


def box_hands(pose, centre, out=0.0, up=0.0):
    """The pose with its wrists (root-space targets) moved so the palms lie on the sides of a crate whose middle
    is at `centre` (left, forward, up) - `out` m off them (letting go / reaching for it), `up` m higher."""
    p = kit.full(pose)
    up += LOW_GRIP * max(0.0, min(1.0, (CARRY_BOX[2] - centre[2]) / (CARRY_BOX[2] - FLOOR_BOX[2])))
    want = {}
    for s, sx in (("L", 1.0), ("R", -1.0)):
        want[s] = kit.V(centre[0] + sx * (BOX_SIZE[0] * 0.5 + PALM_GAP + out), centre[1] + HOLD_AT[0], centre[2] + HOLD_AT[1] + up)
        w = want[s] + kit.Vector((sx * 0.02, 0.03, 0.03))         # (a first guess: the wrist a little out, back and up)
        p["hand" + s] = ("w", (w.x, -w.y, w.z))
    for _ in range(10):
        mats = kit.solve(p, extra=False)
        for s in ("L", "R"):
            e = want[s] - _palm(mats, s)
            q = p["hand" + s][1]
            p["hand" + s] = ("w", (q[0] + e.x, q[1] - e.y, q[2] + e.z))
    return p


def box_path(c0, c1, t, fwd_lead=0.0):
    """The crate's middle from c0 to c1 (t 0..1, eased); fwd_lead > 0: it comes forward that much ahead of coming
    down (< 0: it goes up first, then back) - an arc round the knees."""
    e = kit._ease("io", t)
    tf = t * (1 + fwd_lead) if fwd_lead > 0 else (t * (1 - fwd_lead) + fwd_lead)
    ef = kit._ease("io", max(0.0, min(1.0, tf)))
    return (c0[0] + (c1[0] - c0[0]) * e, c0[1] + (c1[1] - c0[1]) * ef, c0[2] + (c1[2] - c0[2]) * e)


def _fit(poses, centres):
    """box_hands on each frame where the crate is in the hands (centres[i] not None): the palms stay on its sides
    all the way, however the body's key poses blend."""
    return [box_hands(p, c, up=0.0) if c is not None else p for p, c in zip(poses, centres)]


# The hold (carry, carry_idle): the elbows down at the sides, a little out and back; the fingers forward along the sides.
CARRY_ARMS = dict(elbowL=(0.15, -0.45, -1.0), elbowR=(-0.15, -0.45, -1.0), wristL=12, wristR=12, gripL=0.12, gripR=0.12)
CARRY_HANDS = dict(CARRY_ARMS, handL=("c", (0.22, 0.30, -0.52)), handR=("c", (-0.22, 0.30, -0.52)))   # (a first guess; fitted)


def seated(base, n):
    """Sitting still: the chest breathing slowly, the head now and then looking a little aside."""
    out = []
    for i, p in enumerate(breathe(base, n, amp=0.0, arms=0.0)):
        a = TAU * i / n
        p["hyaw"] = 7.0 * math.sin(a) * abs(math.sin(a))
        p["hpitch"] = p["hpitch"] + 1.0 * math.sin(2 * a)
        out.append(p)
    return out


def carry(n=30):
    """Walking with a crate held in both hands: no arm swing, the shoulders kept square, leaning back a little;
    the palms stay on the crate's sides (the game holds it still at CARRY_AT while the body bobs)."""
    out = []
    for i, p in enumerate(walk(n, L=0.56)):
        u = i / n
        p.update(CARRY_HANDS)
        p["twist"] = 3.0 * math.cos(TAU * u)
        p["pyaw"] = -3.5 * math.cos(TAU * u)
        p["lean"] = -3.0
        out.append(p)
    return _fit(out, [CARRY_BOX] * n)


def carry_idle(n=48):
    return _fit(breathe(P(STAND, lean=-3, **CARRY_HANDS), n, arms=0.0), [CARRY_BOX] * n)


# Setting the crate down / picking it up: a squat - the knees and hips bent deep, the back straight but leaning
# (the pelvis back, the chest over the knees), the head up, the feet planted where they stand (root-space, the same
# in every key: no sliding). Each 1.4 s (43 frames, 30 fps), not looping. "box": the crate's middle each frame.
SQUAT = P(STAND, pelvis=(0.0, -0.20, -0.56), ppitch=40, lean=22, hpitch=-36,
          kneeL=(0.05, 1.0, 0.0), kneeR=(-0.05, 1.0, 0.0),
          elbowL=(0.12, -1.0, 0.3), elbowR=(-0.12, -1.0, 0.3), wristL=-4, wristR=-4, gripL=0.12, gripR=0.12)
RISE = P(STAND, pelvis=(0.0, -0.07, -0.26), ppitch=16, lean=8, hpitch=-12,
         handL=("c", (0.28, 0.16, -0.60)), handR=("c", (-0.28, 0.16, -0.60)), gripL=0.4, gripR=0.4)
PUT_RELEASE = 22    # put_down: the frame the hands let go (0.733 s) - the crate is on the floor at FLOOR_BOX from frame 16
PICK_GRIP = 18      # pick_up: the frame the hands close on it (0.6 s) - it leaves the floor at frame 22


def _hold():
    return box_hands(P(STAND, lean=-3, **CARRY_HANDS), CARRY_BOX)


def put_down():
    """From the carry hold: down into the squat (the crate's bottom touches the floor at frame 16, FLOOR_BOX), the
    palms let go at PUT_RELEASE (frame 22, 0.733 s: the game leaves the crate there), out off its sides and up,
    standing again empty-handed (STAND - the idle's pose) at frame 42 (1.4 s)."""
    down = box_hands(SQUAT, FLOOR_BOX)
    let = box_hands(P(SQUAT, gripL=0.0, gripR=0.0, wristL=-14, wristR=-14), FLOOR_BOX, out=0.06, up=0.04)
    poses = K((0, _hold()), (16, down), (PUT_RELEASE, down), (27, let, "o"), (34, RISE), (42, STAND, "o"))
    box = [box_path(CARRY_BOX, FLOOR_BOX, min(1.0, i / 16.0), 0.5) for i in range(len(poses))]
    return _fit(poses, [b if i < PUT_RELEASE else None for i, b in enumerate(box)]), box


def pick_up():
    """From standing (STAND): down into the squat, the open hands to the crate's sides (it on the floor, FLOOR_BOX),
    gripping it at PICK_GRIP (frame 18, 0.6 s: the game takes it then), lifting it from frame 22 to the carry hold
    (carry_idle's pose) at frame 42 (1.4 s)."""
    reach = box_hands(P(SQUAT, gripL=0.0, gripR=0.0, wristL=-14, wristR=-14), FLOOR_BOX, out=0.06, up=0.04)
    down = box_hands(SQUAT, FLOOR_BOX)
    lift = 22
    poses = K((0, STAND), (8, RISE), (13, reach), (PICK_GRIP, down, "o"), (lift, down), (42, _hold()))
    box = [box_path(FLOOR_BOX, CARRY_BOX, max(0.0, (i - lift) / 20.0), -0.5) for i in range(len(poses))]
    return _fit(poses, [b if i >= PICK_GRIP else None for i, b in enumerate(box)]), box


# ------------------------------------------------------------------ at a console
# A terminal in front of it: a sloped desk top (keys, a touch panel) ~1.06 m up, 0.30-0.45 m in front of the
# feet, and a tilted screen above it (1.5-2.1 m up, 0.5 m forward). The wrists are root-space ("w") targets
# on the panel - they stay put while the body breathes and shifts its weight.

CONSOLE_WRIST = (0.155, 0.305, 1.085)    # (the left wrist; the palm ~6 cm further on, ~1.06 m up, ~0.36 m forward)
CONSOLE = dict(pelvis=(0.0, 0.02, -0.025), lean=8, hpitch=17,
               footL=("w", (0.14, 0.01, 0)), fyawL=12, footR=("w", (-0.15, -0.03, 0)), fyawR=15,
               handL=("w", CONSOLE_WRIST), elbowL=(0.32, -0.40, -1.0), wristL=-8, gripL=0.35,
               handR=("w", (-CONSOLE_WRIST[0], CONSOLE_WRIST[1], CONSOLE_WRIST[2])), elbowR=(-0.32, -0.40, -1.0),
               wristR=-8, gripR=0.35)


def console(n=120):
    """Working a console (a 4 s loop): typing / touching the panel, the left hand sliding out along it and back,
    a glance up at the screen and the right hand reaching up to touch it once, the weight shifting between the feet."""
    b = CONSOLE
    wl, wr = b["handL"][1], b["handR"][1]
    slide = P(b, handL=("w", (wl[0] + 0.09, wl[1] + 0.02, wl[2] - 0.004)), hyaw=6, hpitch=19)
    look = P(b, hpitch=-3, lean=7)
    reach = P(look, twist=-4, handR=("w", (-0.10, 0.43, 1.555)), elbowR=(-1.0, -0.2, -0.5), wristR=-18, gripR=0.55)
    touch = P(reach, handR=("w", (-0.10, 0.445, 1.56)))
    keys = K((0, b), (28, b), (40, slide), (48, slide), (60, b), (66, b), (72, look, "o"), (83, reach),
             (87, touch, "o"), (90, reach), (103, look), (110, b), (n, b))[:n]
    # how much each hand is typing (on the panel, not on its way)
    def on(i, spans):
        for a, c in spans:
            if a - 4 <= i <= c + 4:
                return max(a - i, i - c, 0) / 4.0
        return 1.0
    out = []
    for i, p in enumerate(keys):
        t = i / float(n)
        p = dict(p)
        # the weight from one foot to the other and back, one breath
        p["pelvis"] = (p["pelvis"][0] + 0.016 * math.sin(TAU * t), p["pelvis"][1], p["pelvis"][2] + 0.004 * math.sin(TAU * 2 * t))
        p["proll"] = p["proll"] + 1.6 * math.sin(TAU * t)
        p["lean"] = p["lean"] + 0.9 * math.sin(TAU * t + 1.0)
        p["hpitch"] = p["hpitch"] + 1.2 * math.sin(TAU * 3 * t)
        # the fingers' taps: short lifts of the wrist and quick curls, at rates that come round in the loop
        for s, rate, ph, spans in (("L", 13, 0.0, ((30, 58),)), ("R", 17, 1.7, ((68, 106),))):
            w = on(i, spans) * (0.65 + 0.35 * math.sin(TAU * 3 * t + ph))
            tap = max(0.0, math.sin(TAU * rate * t + ph)) ** 6
            tap2 = max(0.0, math.sin(TAU * (rate + 6) * t + ph * 2.3)) ** 8
            sp, q = p["hand" + s]
            p["hand" + s] = (sp, (q[0] + 0.004 * w * math.sin(TAU * 5 * t + ph), q[1] + 0.003 * w * tap2, q[2] + 0.011 * w * tap))
            p["wrist" + s] = p["wrist" + s] + 5.0 * w * tap - 3.0 * w * tap2
            p["grip" + s] = p["grip" + s] + 0.14 * w * tap2 + 0.06 * w * tap
        out.append(p)
    return out


# ------------------------------------------------------------------ spells

def cast_bolt():
    """Gathers it at the hip, thrusts it out with both palms (a beam, a fireball)."""
    wind = P(G, pelvis=(-0.02, -0.06, -0.20), pyaw=-50, twist=-22, lean=4,
             handR=("c", (-0.24, 0.10, -0.44)), handL=("c", (-0.10, 0.20, -0.40)), elbowL=(0.6, -0.4, -0.6),
             gripL=0.25, gripR=0.25, wristR=-30, hyaw=0)
    out = P(G, pelvis=(0.0, 0.20, -0.20), pyaw=-14, twist=6, lean=12,
            footL=("w", (0.10, 0.38, 0)), footR=("w", (-0.14, -0.26, 0.03)), fpitchR=30, fyawR=30,
            handR=("w", (-0.05, 0.78, 1.27)), handL=("w", (0.07, 0.76, 1.37)), elbowL=(1.0, -0.3, -0.5), elbowR=(-1.0, -0.3, -0.5),
            gripL=0.0, gripR=0.0, wristL=-70, wristR=-70)
    kick = P(out, pelvis=(0.0, 0.16, -0.20), handR=("w", (-0.05, 0.72, 1.28)), handL=("w", (0.07, 0.70, 1.38)))
    return K((0, G), (5, wind), (8, wind), (10, out, "i"), (11, kick, "l"), (13, out), (16, out), (20, G, "o"))


def cast_sky():
    """An arm thrown up to the sky, then brought down at the target (lightning)."""
    up = P(G, pelvis=(0.0, 0.0, -0.04), pyaw=-10, twist=10, lean=-8, hpitch=-26,
           handR=("w", (-0.22, 0.10, 2.22)), elbowR=(-1.0, -0.3, 0.0), gripR=0.0, wristR=-20,
           handL=("c", (0.24, 0.10, -0.40)), gripL=1.0)
    down = P(G, pelvis=(0.0, 0.14, -0.18), pyaw=-4, twist=30, lean=20, hpitch=6,
             footR=("w", (-0.13, -0.22, 0.03)), fpitchR=30, fyawR=25,
             handR=("w", (-0.06, 0.74, 1.12)), elbowR=(-1.0, -0.2, 0.3), gripR=0.3,
             handL=("c", (0.26, -0.06, -0.36)))
    return K((0, G), (5, up, "o"), (9, up), (12, down, "i"), (16, down), (20, G, "o"))


def cast_dome():
    """The arms crossed over the chest, then thrown wide (a dome of force around it)."""
    cross_ = P(STAND, pelvis=(0.0, 0.0, -0.22), lean=18, hpitch=14,
               footL=("w", (0.17, 0.02, 0)), footR=("w", (-0.17, -0.02, 0)), fyawL=18, fyawR=18,
               handL=("c", (-0.12, 0.20, -0.16)), handR=("c", (0.12, 0.24, -0.20)), gripL=1.0, gripR=1.0,
               elbowL=(0.6, 0.0, -1.0), elbowR=(-0.6, 0.0, -1.0))
    wide = P(STAND, pelvis=(0.0, 0.0, -0.10), lean=-10, hpitch=-12,
             footL=("w", (0.22, 0.02, 0)), footR=("w", (-0.22, -0.02, 0)), fyawL=22, fyawR=22,
             handL=("w", (0.74, 0.06, 1.62)), handR=("w", (-0.74, 0.06, 1.62)), gripL=0.0, gripR=0.0,
             elbowL=(0.3, -0.3, -1.0), elbowR=(-0.3, -0.3, -1.0), wristL=-30, wristR=-30)
    return K((0, G), (5, cross_), (8, cross_), (11, wide, "i"), (16, wide), (21, G, "o"))


def cast_summon():
    """Down on one knee, a palm on the ground (calling something up out of it)."""
    kneel = P(G, pelvis=(0.0, 0.06, -0.50), pyaw=-16, lean=30, hpitch=8,
              footL=("w", (0.12, 0.30, 0)), fyawL=-5, kneeL=(0.2, 1.0, 0.0),
              footR=("w", (-0.13, -0.34, 0.10)), fpitchR=75, fyawR=5, kneeR=(-0.1, 1.0, -0.5),
              handR=("w", (-0.12, 0.52, 0.10)), gripR=0.0, wristR=-70, elbowR=(-1.0, -0.2, 0.2),
              handL=("c", (0.20, 0.26, -0.44)), gripL=1.0)
    pulse = P(kneel, pelvis=(0.0, 0.06, -0.47), lean=26, hpitch=-6, handR=("w", (-0.12, 0.52, 0.16)))
    return K((0, G), (6, kneel), (9, kneel), (12, pulse, "o"), (17, kneel), (19, kneel), (24, G, "o"))


# ------------------------------------------------------------------ taking it

def hit_():
    back = P(G, pelvis=(0.02, -0.10, -0.12), pyaw=-40, twist=-16, lean=-18, hpitch=-16, htilt=10,
             handL=("c", (0.26, 0.18, -0.22)), handR=("c", (-0.30, 0.16, -0.26)), elbowR=(-0.8, -0.7, -0.5), fpitchL=-12)
    return K((0, G), (2, back, "snap"), (4, back), (8, G, "o"))


def block():
    up = P(G, pelvis=(0.0, -0.03, -0.16), lean=12, hpitch=12,
           handL=("c", (0.02, 0.27, -0.03)), handR=("c", (-0.07, 0.28, -0.09)), elbowL=(0.5, 0.1, -1.0), elbowR=(-0.5, 0.1, -1.0))
    return K((0, G), (3, up, "snap"), (6, up))


def ko(guard=G):
    reel = P(guard, pelvis=(0.0, -0.14, -0.10), pyaw=-20, lean=-28, hpitch=-22,
             handL=("c", (0.34, 0.10, -0.10)), handR=("c", (-0.34, 0.06, -0.14)), fpitchL=-14, gripL=0.4, gripR=0.4, gun=None)
    fall = P(guard, pelvis=(0.0, -0.44, -0.46), pyaw=-10, ppitch=-55, lean=-10, hpitch=-10, hfree=1, hyaw=0,
             footL=("p", (0.12, 0.30, -0.70)), footR=("p", (-0.14, 0.10, -0.80)), fpitchL=30, fpitchR=30,
             handL=("c", (0.44, 0.10, -0.06)), handR=("c", (-0.44, 0.06, -0.10)), gripL=0.3, gripR=0.3, gun=None)
    flat = P(guard, pelvis=(0.0, -0.80, -0.83), pyaw=-6, ppitch=-90, lean=-2, hpitch=-6, hfree=1, hyaw=0,
             footL=("p", (0.14, 0.02, -0.84)), footR=("p", (-0.16, 0.06, -0.82)), fpitchL=50, fpitchR=40, fyawL=20, fyawR=25,
             kneeL=(0.3, 1.0, 0.0), kneeR=(-0.3, 1.0, 0.0),
             handL=("c", (0.50, -0.02, -0.20)), handR=("c", (-0.46, -0.02, -0.32)), elbowL=(1, -0.2, 0), elbowR=(-1, -0.2, 0),
             gripL=0.3, gripR=0.3, gun=None)
    settle = P(flat, pelvis=(0.0, -0.80, -0.80), footL=("p", (0.14, 0.08, -0.84)))
    return K((0, guard), (4, reel, "snap"), (8, fall, "i"), (12, flat, "i"), (14, settle, "o"), (17, flat), (20, flat))


# ------------------------------------------------------------------ swimming
# (the player in water - CosmosWalker: at the surface its origin is SWIM_DEPTH = 1.25 m under the water, so the
# water line is 1.25 m up the model: "swim" (a head-up crawl) and "swim_idle" (treading water) keep the head and
# the shoulders' tops over it. "dive" (an underwater breaststroke) and "dive_idle" (hovering) lie at the same
# height, the body ~1 m up, centred over the origin. The feet hang from the pelvis ("p"); the rifle is away.)

SWIM_LINE = 1.25         # the water line (m up the model, at the surface)


def _loop_path(keys, u):
    """A smooth closed path through keys [(t 0..1, (values...))...] (a periodic Catmull-Rom) at u (0..1)."""
    n = len(keys)
    u = u % 1.0
    i = max(k for k in range(n) if keys[k][0] <= u) if u >= keys[0][0] else n - 1
    t0, t1 = keys[i][0], keys[(i + 1) % n][0] + (1.0 if i + 1 >= n else 0.0)
    uu = u if u >= t0 else u + 1.0
    s = (uu - t0) / (t1 - t0)
    p0, p1, p2, p3 = (keys[(i + d) % n][1] for d in (-1, 0, 1, 2))
    s2, s3 = s * s, s * s * s
    return tuple(0.5 * (2 * b + (-a + c) * s + (2 * a - 5 * b + 4 * c - d) * s2 + (-a + 3 * b - 3 * c + d) * s3)
                 for a, b, c, d in zip(p0, p1, p2, p3))


# The left arm's head-up crawl (chest space: left, forward (= down, lying), up the spine (= ahead)), its elbow's
# side, the wrist's bend: the hand goes in ahead of the shoulder, catches, pulls under the chest (the elbow high),
# pushes back by the hip, comes out and swings forward over the water, the elbow up. (The right: mirrored, half a
# stroke later.)
CRAWL_ARM = [
    (0.00, (0.20, 0.32, 0.33, 0.8, -0.3, 0.5, 10.0)),      # in, ahead of the shoulder
    (0.13, (0.22, 0.46, 0.14, 1.0, -0.4, 0.3, 18.0)),      # the catch
    (0.30, (0.13, 0.47, -0.15, 1.0, -0.4, 0.1, 14.0)),     # the pull, under the chest
    (0.47, (0.24, 0.30, -0.56, 0.8, -0.6, -0.2, 0.0)),     # the push, by the hip
    (0.58, (0.31, -0.13, -0.46, 0.8, -1.0, -0.2, -6.0)),   # out of the water
    (0.76, (0.39, -0.18, -0.04, 0.7, -1.0, 0.1, 0.0)),     # over it, the elbow up
    (0.90, (0.26, -0.03, 0.30, 0.6, -1.0, 0.4, 6.0)),      # reaching ahead
]


def swim(n=42):
    """Swimming at the surface, a head-up crawl: the body lying ~25 degrees from level, the chest arched up out of
    the water and the head up looking ahead; the arms stroke in turn, the body rolling a little with them; a
    flutter kick from the hips, the knees easy, the toes pointed (two kicks a leg a stroke). 1.4 s."""
    out = []
    for i in range(n):
        u = i / n
        a = TAU * u
        p = dict(pelvis=(0.0, -0.22, 0.10 + 0.012 * math.cos(2 * a)), ppitch=76 + 1.5 * math.cos(2 * a), lean=-18,
                 twist=9.0 * math.sin(a + 0.6), hpitch=-36 - 2.0 * math.cos(2 * a), gripL=0.12, gripR=0.12)
        for s, sx, ph in (("L", 1.0, 0.0), ("R", -1.0, 0.5)):
            x, f, up, ex, ey, ez, wr = _loop_path(CRAWL_ARM, u + ph)
            p["hand" + s] = ("c", (x * sx, f, up))
            p["elbow" + s] = (ex * sx, ey, ez)
            p["wrist" + s] = wr
            k = TAU * (2 * u + (0.0 if s == "L" else 0.5))       # (the kick: down (forward, lying) and up, the legs in turn)
            down = math.sin(k)
            bend = max(0.0, math.sin(k + 1.2))                 # (the knee gives as the leg starts down)
            p["foot" + s] = ("p", (0.095 * sx, 0.10 * down - 0.03 - 0.05 * bend, -0.835 + 0.06 * bend))
            p["knee" + s] = (0.1 * sx, 1.0, 0.0)
            p["fpitch" + s] = 74 + 10 * math.sin(k - 0.5)
            p["fyaw" + s] = 6
        out.append(kit.full(p))
    return out


def swim_idle(n=60):
    """Treading water: upright and a little forward, the water at the collar; the hands scull out and in under the
    surface, wide and in front (palms tilting), the knees up and wide, the shins circling in turn (an egg-beater);
    a slow bob. 2 s."""
    out = []
    for i in range(n):
        u = i / n
        a = TAU * u
        p = dict(pelvis=(0.0, 0.0, -0.22 + 0.014 * math.sin(2 * a)), ppitch=6, lean=7 + 1.5 * math.sin(2 * a), hpitch=-10,
                 gripL=0.1, gripR=0.1)
        for s, sx, ph in (("L", 1.0, 0.0), ("R", -1.0, 0.5)):
            b = TAU * 2 * u                                      # (the hands scull together, twice a loop)
            p["hand" + s] = ("c", ((0.50 + 0.12 * math.sin(b)) * sx, 0.30 + 0.05 * math.sin(2 * b), -0.34 + 0.02 * math.cos(b)))
            p["elbow" + s] = (1.0 * sx, -0.5, -0.3)
            p["wrist" + s] = 14 * math.cos(b)
            c = TAU * (2 * u + ph)                               # (the legs: circles in turn)
            p["foot" + s] = ("p", ((0.24 + 0.05 * math.sin(c)) * sx, 0.22 + 0.10 * math.cos(c), -0.62 + 0.08 * math.sin(c)))
            p["knee" + s] = (0.8 * sx, 1.0, 0.0)
            p["fpitch" + s] = 30 + 12 * math.sin(c)
            p["fyaw" + s] = 30
        out.append(kit.full(p))
    return out


# Underwater: the body level (pitched 90 degrees), the pelvis 0.35 m back of the origin.
DIVE = dict(pelvis=(0.0, -0.35, 0.02), ppitch=90, lean=0, hpitch=-30, gripL=0.1, gripR=0.1,
            footL=("p", (0.06, 0.0, -0.86)), fpitchL=80, fyawL=4, kneeL=(0.1, 1.0, 0.0),
            footR=("p", (-0.06, 0.0, -0.86)), fpitchR=80, fyawR=4, kneeR=(-0.1, 1.0, 0.0))


def _arms(x, f, up, elbow=(1.0, -0.3, 0.3), wrist=0.0):
    return dict(handL=("c", (x, f, up)), handR=("c", (-x, f, up)), elbowL=elbow, elbowR=(-elbow[0], elbow[1], elbow[2]),
                wristL=wrist, wristR=wrist)


def _legs(x, f, up, pitch, yaw, knee=(0.1, 1.0, 0.0)):
    return dict(footL=("p", (x, f, up)), footR=("p", (-x, f, up)), fpitchL=pitch, fpitchR=pitch, fyawL=yaw, fyawR=yaw,
                kneeL=knee, kneeR=(-knee[0], knee[1], knee[2]))


def dive(n=48):
    """Swimming underwater, a breaststroke: streamlined in a glide (the arms together ahead, the legs together);
    the hands sweep out and pull round under the shoulders (the elbows high, the chest lifting a little), come
    together under the chin and shoot ahead as the heels, drawn up and turned out, kick round and together; the
    glide again. 1.6 s."""
    glide = P(DIVE, **_arms(0.10, 0.06, 0.44, wrist=4))
    out_ = P(DIVE, ppitch=88, **_arms(0.40, 0.10, 0.36, wrist=-14))
    pull = P(DIVE, ppitch=82, lean=-6, hpitch=-36, **_arms(0.30, 0.36, 0.06, elbow=(1.0, -0.6, 0.4), wrist=22))
    chin = P(DIVE, ppitch=84, lean=-4, hpitch=-34, **_arms(0.15, 0.22, 0.10, elbow=(0.6, 0.5, -0.6), wrist=10),
             **_legs(0.17, -0.12, -0.44, 8, 44, knee=(0.75, 1.0, 0.0)))
    shoot = P(DIVE, **_arms(0.10, 0.07, 0.40, wrist=4), **_legs(0.26, 0.02, -0.83, 50, 26, knee=(0.6, 1.0, 0.0)))
    keys = [(0, glide), (12, out_), (20, pull), (27, chin), (34, shoot, "o"), (40, glide, "o"), (n, glide)]
    return K(*keys)[:-1]


def dive_idle(n=60):
    """Hovering underwater: tipped well forward, the hands sculling slowly in front of the chest, the knees easy and
    the legs stirring in a slow kick; drifting up and down a little. 2 s."""
    out = []
    for i in range(n):
        u = i / n
        a = TAU * u
        p = dict(pelvis=(0.0, -0.18, 0.0 + 0.018 * math.sin(a)), ppitch=46 + 2.0 * math.sin(a), lean=6, hpitch=-32,
                 gripL=0.15, gripR=0.15)
        for s, sx, ph in (("L", 1.0, 0.0), ("R", -1.0, 0.5)):
            b = TAU * 2 * u
            p["hand" + s] = ("c", ((0.34 + 0.09 * math.sin(b)) * sx, 0.32 + 0.04 * math.sin(2 * b), -0.32 + 0.02 * math.cos(b)))
            p["elbow" + s] = (1.0 * sx, -0.4, -0.4)
            p["wrist" + s] = 12 * math.cos(b)
            k = TAU * (u + ph)
            p["foot" + s] = ("p", (0.11 * sx, -0.06 + 0.07 * math.sin(k), -0.835 + 0.025 * max(0.0, math.sin(k + 1.2))))
            p["knee" + s] = (0.1 * sx, 1.0, 0.0)
            p["fpitch" + s] = 62 + 8 * math.sin(k - 0.5)
            p["fyaw" + s] = 8
        out.append(kit.full(p))
    return out


# ------------------------------------------------------------------ with the rifle

GUNS = {
    # the rifle carried / aimed: (space, grip (left, fwd, up), muzzle direction, top, hands)
    "automaton": dict(
        # (carried a little high and forward, aimed a little out from the chest: the forearms clear of it, the thighs of the hands)
        idle=dict(gun=("c", (-0.15, 0.28, -0.42), (0.80, 0.52, -0.30), (0.15, 0.1, 1.0), "both"), pelvis=(0, 0, -0.018), twist=-6,
                  footL=("w", (0.155, 0.02, 0)), footR=("w", (-0.155, -0.02, 0)), fyawL=14, fyawR=14),
        aim=dict(gun=("c", (-0.18, 0.29, -0.215), (0.12, 1.0, 0.0), (0, 0, 1), "both"), pelvis=(0, 0.0, -0.07), pyaw=-22, twist=14,
                 lean=5, footL=("w", (0.12, 0.16, 0)), fyawL=0, footR=("w", (-0.14, -0.14, 0)), fyawR=30, hpitch=3)),
    # (the towns' people - the Minoan android, the palace guard, Kilon Alios: the automaton's way of carrying)
    "pirate": dict(
        idle=dict(gun=("c", (-0.30, 0.10, -0.66), (0.10, 0.42, -1.0), (0.0, 1.0, 0.4), "right"), pelvis=(0, 0, -0.018),
                  handL=("c", (0.285, 0.03, -0.65)), footL=("w", (0.15, 0.0, 0)), footR=("w", (-0.15, 0.0, 0)), fyawL=13, fyawR=13),
        aim=dict(gun=("c", (-0.17, 0.24, -0.26), (0.14, 1.0, 0.0), (0, 0, 1), "both"), pelvis=(0, 0.0, -0.08), pyaw=-24, twist=14,
                 lean=7, footL=("w", (0.12, 0.17, 0)), fyawL=0, footR=("w", (-0.14, -0.15, 0)), fyawR=30, hpitch=3)),
}


def gun_clips(skin):
    g = GUNS.get(skin, GUNS["automaton"])
    idle, aim = kit.full(g["idle"]), kit.full(g["aim"])
    ga = aim["gun"]
    rec = P(aim, gun=(ga[0], (ga[1][0], ga[1][1] - 0.045, ga[1][2] + 0.008), (ga[2][0], ga[2][1], 0.07), ga[3], ga[4]), lean=aim["lean"] - 3)
    return {
        "gun_idle": dict(poses=breathe(idle, 24, arms=0.0), loop=True, gun=True),
        "gun_walk": dict(poses=walk(30, gun=g["idle"]), loop=True, gun=True),
        "gun_run": dict(poses=run(24, gun=g["idle"]), loop=True, gun=True),
        "raise": dict(poses=K((0, idle), (6, aim, "o")), gun=True),
        "fire": dict(poses=K((0, aim), (1, rec, "l"), (2, rec), (5, aim, "o")), gun=True, marks={"hit": 0}),
    }


# ------------------------------------------------------------------ the lot

def clips(skin="automaton"):
    c = {
        "idle": dict(poses=breathe(P(STAND, **MINOAN_HANDS) if skin in MINOAN_BODY else STAND, 24), loop=True),
        "guard": dict(poses=bounce(GUARD, 16), loop=True),
        "walk": dict(poses=walk(30, **(MINOAN_WALK if skin in MINOAN_BODY else {})), loop=True),
        "run": dict(poses=run(24), loop=True),
        "jab": dict(poses=jab(), marks={"hit": 3}),
        "cross": dict(poses=cross(), marks={"hit": 5}),
        "hook": dict(poses=hook(), marks={"hit": 7}),
        "uppercut": dict(poses=uppercut(), marks={"hit": 7}),
        "front": dict(poses=front(), marks={"hit": 6}),
        "round": dict(poses=round_(), marks={"hit": 8}),
        "hit": dict(poses=hit_()),
        "block": dict(poses=block()),
        "ko": dict(poses=ko()),
        "sit": dict(poses=seated(on_seat(SIT, skin), 90), loop=True),
        "stool": dict(poses=seated(on_seat(STOOL, skin), 90), loop=True),
        "carry": dict(poses=carry(30), loop=True),
        "carry_idle": dict(poses=carry_idle(48), loop=True),
        "put_down": dict(zip(("poses", "box"), put_down()), marks={"release": PUT_RELEASE}),
        "pick_up": dict(zip(("poses", "box"), pick_up()), marks={"grip": PICK_GRIP}),
        "console": dict(poses=console(120), loop=True),
    }
    if skin == "automaton":
        c.update({
            "elbow": dict(poses=elbow(), marks={"hit": 5}),
            "knee": dict(poses=knee(), marks={"hit": 6}),
            "side": dict(poses=side(), marks={"hit": 7}),
            "spin": dict(poses=spin(), marks={"hit": 9}),
            "sweep": dict(poses=sweep(), marks={"hit": 8}),
            "flykick": dict(poses=flykick(), marks={"hit": 9, "off": 5, "land": 16}),
            "palm": dict(poses=palm(), marks={"hit": 7}),
            "leap": dict(poses=leap(), marks={"off": 5, "land": 19}),
            "jump": dict(poses=jump()),
            "fall": dict(poses=fall(), loop=True),
            "jet": dict(poses=jet(), loop=True),
            "swim": dict(poses=swim(), loop=True),
            "swim_idle": dict(poses=swim_idle(), loop=True),
            "dive": dict(poses=dive(), loop=True),
            "dive_idle": dict(poses=dive_idle(), loop=True),
            "cast_bolt": dict(poses=cast_bolt(), marks={"cast": 10}),
            "cast_sky": dict(poses=cast_sky(), marks={"cast": 12}),
            "cast_dome": dict(poses=cast_dome(), marks={"cast": 11}),
            "cast_summon": dict(poses=cast_summon(), marks={"cast": 12}),
        })
    elif skin == "pirate":
        c.update({
            "side": dict(poses=side(), marks={"hit": 7}),
            "sweep": dict(poses=sweep(), marks={"hit": 8}),
        })
        del c["idle"], c["run"]         # (a pirate without its rifle up is in its fighting stance, and walks)
    else:                               # (the towns' people: they stand, walk, run - and guards fight)
        c.update({"side": dict(poses=side(), marks={"hit": 7})})
    c.update(gun_clips(skin))
    if skin == "pirate":
        del c["gun_run"]
    for name in c:
        c[name].setdefault("loop", False)
        c[name].setdefault("gun", False)
        c[name].setdefault("marks", {})
    return c
