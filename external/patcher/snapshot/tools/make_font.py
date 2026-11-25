#!/usr/bin/env python3
"""Atrapos Sans - the game's own typeface, built from code.

A wide, geometric "extended square" sans: round letters are rounded rectangles
(superellipse corners, flat sides), diagonals end in horizontal cuts, the
lowercase a and g are single-storey, the figures are tabular. Every glyph is
put together from a few primitives - rectangles, rounded-rectangle rings,
slanted strokes - combined with union / difference / intersection (a small
boolean engine below: all edges split where they cross, the pieces between
inside and outside kept, chained into clean contours with no overlaps).

    python3 -I tools/make_font.py            # writes assets/fonts/AtraposSans-{Regular,Bold}.ttf
    python3 -I tools/make_font.py --specimen <png>   # also renders a specimen (needs PIL)

Then `godot --headless --import`. Units per em 1000; cap height 680, x-height
470, ascenders = cap height, short descenders. Two weights: Regular (body
text) and Bold (headings, titles) - the same drawings with a heavier stroke.
"""
import math
import os
import sys
from multiprocessing import Pool

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.agl import UV2AGL

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "fonts")
FAMILY = "Atrapos Sans"
VERSION = "1.000"


# ---------------------------------------------------------------- geometry
class Region:
    def leaves(self):
        raise NotImplementedError

    def inside(self, x, y):
        raise NotImplementedError


class Poly(Region):
    """Filled area of closed contours (nonzero winding)."""

    def __init__(self, contours):
        self.contours = [c for c in contours if len(c) >= 3]
        xs = [p[0] for c in self.contours for p in c]
        ys = [p[1] for c in self.contours for p in c]
        self.bb = (min(xs), min(ys), max(xs), max(ys)) if xs else (0, 0, 0, 0)

    def leaves(self):
        return [self]

    def inside(self, x, y):
        b = self.bb
        if x < b[0] or x > b[2] or y < b[1] or y > b[3]:
            return False
        w = 0
        for c in self.contours:
            n = len(c)
            for i in range(n):
                x0, y0 = c[i]
                x1, y1 = c[(i + 1) % n]
                if y0 <= y:
                    if y1 > y and (x1 - x0) * (y - y0) - (x - x0) * (y1 - y0) > 0:
                        w += 1
                elif y1 <= y and (x1 - x0) * (y - y0) - (x - x0) * (y1 - y0) < 0:
                    w -= 1
        return w != 0

    def map(self, f):
        return Poly([[f(p) for p in c] for c in self.contours])


class Union(Region):
    def __init__(self, parts):
        self.parts = [p for p in parts if p is not None]

    def leaves(self):
        return [l for p in self.parts for l in p.leaves()]

    def inside(self, x, y):
        return any(p.inside(x, y) for p in self.parts)

    def map(self, f):
        return Union([p.map(f) for p in self.parts])


class Diff(Region):
    def __init__(self, a, subs):
        self.a, self.subs = a, [s for s in subs if s is not None]

    def leaves(self):
        return self.a.leaves() + [l for s in self.subs for l in s.leaves()]

    def inside(self, x, y):
        return self.a.inside(x, y) and not any(s.inside(x, y) for s in self.subs)

    def map(self, f):
        return Diff(self.a.map(f), [s.map(f) for s in self.subs])


class Inter(Region):
    def __init__(self, a, b):
        self.a, self.b = a, b

    def leaves(self):
        return self.a.leaves() + self.b.leaves()

    def inside(self, x, y):
        return self.a.inside(x, y) and self.b.inside(x, y)

    def map(self, f):
        return Inter(self.a.map(f), self.b.map(f))


def U(*parts):
    return Union(list(parts))


def D(a, *subs):
    return Diff(a, list(subs))


def I(a, b):
    return Inter(a, b)


def move(r, dx, dy=0.0):
    return r.map(lambda p: (p[0] + dx, p[1] + dy))


def scale(r, sx, sy=None, ox=0.0, oy=0.0):
    sy = sx if sy is None else sy
    return r.map(lambda p: (ox + (p[0] - ox) * sx, oy + (p[1] - oy) * sy))


def rot180(r, cx, cy):
    return r.map(lambda p: (2 * cx - p[0], 2 * cy - p[1]))


def mirror_x(r, cx):
    return r.map(lambda p: (2 * cx - p[0], p[1]))


def mirror_y(r, cy):
    return r.map(lambda p: (p[0], 2 * cy - p[1]))


def slant(r, k, oy=0.0):
    return r.map(lambda p: (p[0] + (p[1] - oy) * k, p[1]))


SUPER_N = 2.6        # superellipse exponent of the corners (2 = circle)
ARC_STEPS = 9


def _corner(cx, cy, r, q):
    """Quarter superellipse around (cx, cy), quadrant q (0 = bottom-right, CCW)."""
    pts = []
    for i in range(ARC_STEPS + 1):
        t = (i / ARC_STEPS) * math.pi / 2 + q * math.pi / 2 - math.pi / 2
        c, s = math.cos(t), math.sin(t)
        x = math.copysign(abs(c) ** (2 / SUPER_N), c)
        y = math.copysign(abs(s) ** (2 / SUPER_N), s)
        pts.append((cx + r * x, cy + r * y))
    return pts


def rr_pts(x0, y0, x1, y1, r, c=(1, 1, 1, 1)):
    """Rounded-rectangle contour, CCW. c = which corners round (bl, br, tr, tl)."""
    r = max(0.0, min(r, (x1 - x0) / 2, (y1 - y0) / 2))
    pts = []
    if c[0] and r > 0:
        pts += _corner(x0 + r, y0 + r, r, 3)[0:]
    else:
        pts.append((x0, y0))
    if c[1] and r > 0:
        pts += _corner(x1 - r, y1 - (y1 - y0) + r, r, 0)
    else:
        pts.append((x1, y0))
    if c[2] and r > 0:
        pts += _corner(x1 - r, y1 - r, r, 1)
    else:
        pts.append((x1, y1))
    if c[3] and r > 0:
        pts += _corner(x0 + r, y1 - r, r, 2)
    else:
        pts.append((x0, y1))
    return pts


def box(x0, y0, x1, y1):
    return Poly([[(x0, y0), (x1, y0), (x1, y1), (x0, y1)]])


def rbox(x0, y0, x1, y1, r, c=(1, 1, 1, 1)):
    return Poly([rr_pts(x0, y0, x1, y1, r, c)])


def poly(*pts):
    return Poly([list(pts)])


def diag(xa, ya, xb, yb, s):
    """A slanted stroke from (xa, ya) to (xb, yb), its ends cut horizontally,
    s thick across."""
    dy = abs(yb - ya)
    L = math.hypot(xb - xa, yb - ya)
    hw = s * L / max(dy, 1e-6) / 2
    return poly((xa - hw, ya), (xa + hw, ya), (xb + hw, yb), (xb - hw, yb))


def seg(xa, ya, xb, yb, s):
    """A straight stroke with square (butt) ends."""
    L = math.hypot(xb - xa, yb - ya)
    nx, ny = -(yb - ya) / L * s / 2, (xb - xa) / L * s / 2
    return poly((xa + nx, ya + ny), (xa - nx, ya - ny), (xb - nx, yb - ny), (xb + nx, yb + ny))


# ------------------------------------------------------------ the boolean
def _seg_inter(a, b, c, d):
    """Parameters on ab where cd crosses or touches it."""
    rx, ry = b[0] - a[0], b[1] - a[1]
    sx, sy = d[0] - c[0], d[1] - c[1]
    den = rx * sy - ry * sx
    qx, qy = c[0] - a[0], c[1] - a[1]
    rr = rx * rx + ry * ry
    out = []
    if abs(den) < 1e-9 * (rr + sx * sx + sy * sy):
        # parallel: collinear overlap -> c, d split ab
        if abs(qx * ry - qy * rx) < 1e-6 * math.sqrt(rr) and rr > 0:
            for p in (c, d):
                t = ((p[0] - a[0]) * rx + (p[1] - a[1]) * ry) / rr
                if 1e-9 < t < 1 - 1e-9:
                    out.append(t)
        return out
    t = (qx * sy - qy * sx) / den
    u = (qx * ry - qy * rx) / den
    if -1e-9 <= u <= 1 + 1e-9 and 1e-9 < t < 1 - 1e-9:
        out.append(t)
    return out


def outline(region):
    """The region's boundary as clean contours (CCW outside, CW holes)."""
    segs = []
    for leaf in region.leaves():
        for c in leaf.contours:
            n = len(c)
            for i in range(n):
                a, b = c[i], c[(i + 1) % n]
                if abs(a[0] - b[0]) + abs(a[1] - b[1]) > 1e-7:
                    segs.append((a, b))
    bbs = [(min(a[0], b[0]) - 1e-6, min(a[1], b[1]) - 1e-6, max(a[0], b[0]) + 1e-6, max(a[1], b[1]) + 1e-6) for a, b in segs]
    pieces = []
    for i, (a, b) in enumerate(segs):
        bi = bbs[i]
        ts = [0.0, 1.0]
        for j, (c, d) in enumerate(segs):
            if i == j:
                continue
            bj = bbs[j]
            if bj[0] > bi[2] or bj[2] < bi[0] or bj[1] > bi[3] or bj[3] < bi[1]:
                continue
            ts += _seg_inter(a, b, c, d)
        ts.sort()
        for k in range(len(ts) - 1):
            t0, t1 = ts[k], ts[k + 1]
            if t1 - t0 < 1e-9:
                continue
            p = (a[0] + (b[0] - a[0]) * t0, a[1] + (b[1] - a[1]) * t0)
            q = (a[0] + (b[0] - a[0]) * t1, a[1] + (b[1] - a[1]) * t1)
            L = math.hypot(q[0] - p[0], q[1] - p[1])
            if L < 1e-6:
                continue
            mx, my = (p[0] + q[0]) / 2, (p[1] + q[1]) / 2
            e = 0.02
            nx, ny = -(q[1] - p[1]) / L * e, (q[0] - p[0]) / L * e
            inl = region.inside(mx + nx, my + ny)
            inr = region.inside(mx - nx, my - ny)
            if inl != inr:
                pieces.append((p, q) if inl else (q, p))
    # dedupe, then chain
    def key(p):
        return (round(p[0], 3), round(p[1], 3))
    seen = set()
    starts = {}
    edges = []
    for p, q in pieces:
        k = (key(p), key(q))
        if k in seen or k[0] == k[1]:
            continue
        seen.add(k)
        edges.append((p, q))
        starts.setdefault(k[0], []).append(len(edges) - 1)
    used = [False] * len(edges)
    loops = []
    for i in range(len(edges)):
        if used[i]:
            continue
        loop = []
        cur = i
        while cur is not None and not used[cur]:
            used[cur] = True
            p, q = edges[cur]
            loop.append(p)
            nxt = [j for j in starts.get(key(q), []) if not used[j]]
            if not nxt:
                cur = None
            elif len(nxt) == 1:
                cur = nxt[0]
            else:   # pinch point: take the sharpest right turn
                dx, dy = q[0] - p[0], q[1] - p[1]
                h = math.atan2(dy, dx)

                def turn(j):
                    a, b = edges[j]
                    t = math.atan2(b[1] - a[1], b[0] - a[0]) - h
                    while t <= -math.pi:
                        t += 2 * math.pi
                    while t > math.pi:
                        t -= 2 * math.pi
                    return t
                cur = min(nxt, key=turn)
        if len(loop) >= 3:
            loops.append(loop)
    return [c for c in (_clean(l) for l in loops) if c]


def _area(c):
    return sum(c[i][0] * c[(i + 1) % len(c)][1] - c[(i + 1) % len(c)][0] * c[i][1] for i in range(len(c))) / 2


def _clean(loop):
    pts = [(int(round(x)), int(round(y))) for x, y in loop]
    changed = True
    while changed and len(pts) >= 3:
        changed = False
        out = []
        n = len(pts)
        for i in range(n):
            a, b, c = pts[i - 1], pts[i], pts[(i + 1) % n]
            if b == c:
                changed = True
                continue
            cr = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
            if cr == 0 and (b[0] - a[0]) * (c[0] - b[0]) + (b[1] - a[1]) * (c[1] - b[1]) >= 0:
                changed = True
                continue
            out.append(b)
        if len(out) < len(pts):
            pts = out
            # rebuild from scratch each pass so neighbours are re-checked
    if len(pts) < 3 or abs(_area(pts)) < 4:
        return None
    return pts


# ---------------------------------------------------------------- the face
class M:
    """Metrics and strokes of one weight."""

    def __init__(self, bold):
        self.bold = bold
        self.C = 680          # cap height
        self.X = 470          # x-height
        self.A = 690          # ascender
        self.Dd = 200         # descender depth
        self.S = 114 if bold else 96          # vertical stems
        self.H = round(self.S * 0.9)          # horizontal strokes
        self.R = 150 if bold else 140         # outer corner radius, caps
        self.r = 120 if bold else 112         # outer corner radius, lowercase
        # Generous spacing (the wide, flat-sided letters need air to read at
        # 13-16 px): ~21% of the cap height between capitals, ~26% of the
        # x-height between lowercase, more round narrow letters (below).
        self.sb = 74 if bold else 70          # side bearing, caps
        self.sbl = 64 if bold else 60         # side bearing, lowercase
        self.narrow = 14                      # extra each side of the one-stem letters (i l I 1 ! j .)
        self.dg = self.S * 0.96               # diagonal strokes
        self.WO = 712 if bold else 692        # width of round capitals
        self.wo = 520 if bold else 506        # width of round lowercase
        self.WD = 584 if bold else 570        # width of the figures

    def ri(self, R, s=None):
        """The inner corner radius of a ring of outer radius R."""
        return max(R - (min(self.S, self.H) if s is None else s), R * 0.32)

    def ring(self, x0, y0, x1, y1, R=None, c=(1, 1, 1, 1), sx=None, sy=None):
        R = self.R if R is None else R
        sx = self.S if sx is None else sx
        sy = self.H if sy is None else sy
        ri = self.ri(R, min(sx, sy))
        outer = rr_pts(x0, y0, x1, y1, R, c)
        inner = list(reversed(rr_pts(x0 + sx, y0 + sy, x1 - sx, y1 - sy, ri, c)))
        return Poly([outer, inner])

    def lring(self, x0, y0, x1, y1, c=(1, 1, 1, 1), R=None):
        return self.ring(x0, y0, x1, y1, self.r if R is None else R, c)


def mark_shapes(m):
    """Diacritics, drawn centred on x = 0, their bottom at y = 0."""
    S, H = m.S, m.H
    d = S * 0.95
    h = 120 if not m.bold else 128
    return {
        "grave": diag(-S * 0.9, h, S * 0.6, 0, S * 0.82),
        "acute": diag(S * 0.9, h, -S * 0.6, 0, S * 0.82),
        "circ": U(diag(-130, 0, 0, h * 0.85, S * 0.75), diag(130, 0, 0, h * 0.85, S * 0.75)),
        "caron": U(diag(-130, h * 0.85, 0, 0, S * 0.75), diag(130, h * 0.85, 0, 0, S * 0.75)),
        "tilde": U(box(-160, 0, -160 + S * 0.8, h * 0.6), box(-160, h * 0.6 - H * 0.8, 0 + S * 0.4, h * 0.6),
                   box(-S * 0.4, 0, 160, H * 0.8), box(160 - S * 0.8, 0, 160, h * 0.6)),
        "dier": U(box(-60 - d * 1.5, 0, -60 - d * 0.5, d), box(60 + d * 0.5, 0, 60 + d * 1.5, d)),
        "ring": m.ring(-95, 0, 95, 150, 50, sx=S * 0.7, sy=S * 0.62),
        "macron": box(-150, 0, 150, H * 0.85),
        "dot": box(-d / 2, 0, d / 2, d),
        "cedilla": U(box(-S * 0.45, -110, S * 0.45, 10), box(-S * 0.45 - 60, -110, S * 0.45, -110 + H * 0.75)),
        "ogonek": U(box(-S * 0.45, -150, S * 0.45, 10)),
    }


def glyphs(m):
    """{char: (region, advance)} for one weight."""
    C, X, A, Dd, S, H, R, r = m.C, m.X, m.A, m.Dd, m.S, m.H, m.R, m.r
    dg = m.dg
    KI = m.ri(R) + 1      # cuts that open a ring reach past its inner corner arcs
    sb, sbl = m.sb, m.sbl
    WO, wo = m.WO, m.wo
    out = {}

    def put(ch, region, w, lsb=None, rsb=None):
        l = sb if lsb is None else lsb
        rr_ = (sb if rsb is None else rsb)
        if w < S * 2.2:     # a lone stem or dot: more air, so il1, l. read apart
            l += m.narrow
            rr_ += m.narrow
        out[ch] = (move(region, l) if region is not None else None, round(l + w + rr_))

    def putl(ch, region, w, lsb=None, rsb=None):
        put(ch, region, w, sbl if lsb is None else lsb, sbl if rsb is None else rsb)

    # ---- capitals
    W = WO
    put("O", m.ring(0, 0, W, C), W)
    put("Q", U(m.ring(0, 0, W, C), diag(W * 0.6, C * 0.3, W * 0.74, -C * 0.13, dg)), W)
    put("C", D(m.ring(0, 0, W, C), box(W - S - KI, H, W + 1, C - H)), W)
    put("G", U(D(m.ring(0, 0, W, C), box(W - S - KI, C * 0.5, W + 1, C - H)), box(W * 0.48, C * 0.5 - H, W, C * 0.5)), W)
    put("D", m.ring(0, 0, W, C, c=(0, 1, 1, 0)), W)
    Wb = W * 0.96
    put("B", U(m.ring(0, 0, Wb, C * 0.5 + H / 2, c=(0, 1, 1, 0)),
               m.ring(0, C * 0.5 - H / 2, Wb - S * 0.35, C, R * 0.9, c=(0, 1, 1, 0))), Wb)
    put("P", U(box(0, 0, S, C), m.ring(0, C * 0.42, Wb, C, c=(0, 1, 1, 0))), Wb)
    put("R", U(box(0, 0, S, C), m.ring(0, C * 0.42, Wb, C, c=(0, 1, 1, 0)),
               I(diag(Wb * 0.5, C * 0.42 + H, Wb - dg * 0.55, 0, dg), box(0, 0, Wb, C * 0.42 + H))), Wb)
    We = W * 0.88
    put("E", U(box(0, 0, S, C), box(0, 0, We, H), box(0, C - H, We, C), box(0, C * 0.5 - H / 2, We * 0.9, C * 0.5 + H / 2)), We)
    put("F", U(box(0, 0, S, C), box(0, C - H, We, C), box(0, C * 0.48 - H / 2, We * 0.9, C * 0.48 + H / 2)), We * 0.97)
    put("L", U(box(0, 0, S, C), box(0, 0, We, H)), We)
    put("H", U(box(0, 0, S, C), box(W - S, 0, W, C), box(0, C * 0.5 - H / 2, W, C * 0.5 + H / 2)), W)
    put("I", box(0, 0, S, C), S)
    Wj = W * 0.84
    put("J", U(D(I(m.ring(0, 0, Wj, C * 1.2), box(-1, -1, Wj + 1, C)), box(-1, C * 0.3, S + 1, C + 1))), Wj)
    Wk = W * 0.93
    put("K", U(box(0, 0, S, C), I(diag(S * 0.5, C * 0.42, Wk - dg * 0.6, C, dg), box(0, 0, Wk, C)),
               I(diag(Wk * 0.42, C * 0.56, Wk - dg * 0.6, 0, dg), box(0, 0, Wk, C))), Wk)
    Wm = W * 1.2
    put("M", U(box(0, 0, S, C), box(Wm - S, 0, Wm, C), I(U(diag(S * 0.55, C, Wm / 2, C * 0.18, dg),
                                                          diag(Wm - S * 0.55, C, Wm / 2, C * 0.18, dg)), box(0, 0, Wm, C))), Wm)
    put("N", U(box(0, 0, S, C), box(W - S, 0, W, C), I(diag(S * 0.55, C, W - S * 0.55, 0, dg), box(0, 0, W, C))), W)
    Ws = W * 0.96
    put("S", U(D(m.ring(0, C * 0.5 - H / 2, Ws, C), box(Ws - S - KI, C * 0.5 + H / 2, Ws + 1, C - H)),
               D(m.ring(0, 0, Ws, C * 0.5 + H / 2), box(-1, H, S + KI, C * 0.5 - H / 2))), Ws)
    Wt = W * 0.94
    put("T", U(box(0, C - H, Wt, C), box(Wt / 2 - S / 2, 0, Wt / 2 + S / 2, C)), Wt)
    put("U", I(m.ring(0, 0, W, C * 1.6), box(-1, -1, W + 1, C)), W)
    Wv = W * 1.02
    clipc = box(-200, 0, Wv + 200, C)
    put("V", I(U(diag(dg * 0.6, C, Wv / 2, 0, dg), diag(Wv - dg * 0.6, C, Wv / 2, 0, dg)), clipc), Wv)
    put("A", U(I(U(diag(dg * 0.6, 0, Wv / 2, C, dg), diag(Wv - dg * 0.6, 0, Wv / 2, C, dg)), clipc),
               I(box(0, C * 0.24, Wv, C * 0.24 + H), poly((0, 0), (Wv, 0), (Wv / 2 + dg, C), (Wv / 2 - dg, C)))), Wv)
    Ww = W * 1.36
    put("W", I(U(diag(dg * 0.55, C, Ww * 0.26, 0, dg), diag(Ww / 2, C, Ww * 0.26, 0, dg),
                 diag(Ww / 2, C, Ww * 0.74, 0, dg), diag(Ww - dg * 0.55, C, Ww * 0.74, 0, dg)), box(-200, 0, Ww + 200, C)), Ww)
    put("X", I(U(diag(dg * 0.6, C, Wv - dg * 0.6, 0, dg), diag(Wv - dg * 0.6, C, dg * 0.6, 0, dg)), clipc), Wv)
    put("Y", U(I(U(diag(dg * 0.6, C, Wv / 2, C * 0.42, dg), diag(Wv - dg * 0.6, C, Wv / 2, C * 0.42, dg)), clipc),
               box(Wv / 2 - S / 2, 0, Wv / 2 + S / 2, C * 0.45)), Wv)
    Wz = W * 0.92
    put("Z", U(box(0, C - H, Wz, C), box(0, 0, Wz, H), I(diag(Wz - dg * 0.62, C - H, dg * 0.62, H, dg), box(0, 0, Wz, C))), Wz)

    # ---- lowercase
    w = wo
    putl("o", m.lring(0, 0, w, X), w)
    putl("c", D(m.lring(0, 0, w, X), box(w - S - KI, H, w + 1, X - H)), w)
    putl("e", U(D(m.lring(0, 0, w, X), box(w - S - KI, H, w + 1, X * 0.47 - H / 2)),
                box(0, X * 0.47 - H / 2, w, X * 0.47 + H / 2)), w)
    putl("b", U(box(0, 0, S, A), m.lring(0, 0, w, X, c=(0, 1, 1, 0))), w)
    putl("d", U(box(w - S, 0, w, A), m.lring(0, 0, w, X, c=(1, 0, 0, 1))), w)
    putl("p", U(box(0, -Dd, S, X), m.lring(0, 0, w, X, c=(0, 1, 1, 0))), w)
    putl("q", U(box(w - S, -Dd, w, X), m.lring(0, 0, w, X, c=(1, 0, 0, 1))), w)
    putl("a", U(m.lring(0, 0, w, X * 0.56, c=(1, 0, 0, 1)),
                D(I(m.lring(0, 0, w, X, c=(1, 0, 1, 1)), box(-1, X * 0.4, w + 1, X + 1)), box(-1, X * 0.4, S + KI, X - H)),
                box(w - S, 0, w, X * 0.6)), w)
    putl("g", U(m.lring(0, 0, w, X, c=(1, 0, 0, 1)), box(w - S, -Dd * 0.3, w, X),
                D(I(m.lring(0, -Dd, w, X, c=(1, 1, 0, 1)), box(-1, -Dd - 1, w + 1, 0)), box(-1, -Dd + H, S + KI, 1))), w)
    wn = w * 0.98
    arch = I(m.lring(0, -X, wn, X, c=(1, 1, 1, 0)), box(-1, 0, wn + 1, X + 1))
    putl("n", U(box(0, 0, S, X), arch), wn)
    putl("h", U(box(0, 0, S, A), arch), wn)
    putl("u", U(I(m.lring(0, 0, wn, X * 2, c=(1, 0, 1, 1)), box(-1, -1, wn + 1, X)), box(wn - S, 0, wn, X)), wn)
    wm = w * 1.5
    putl("m", U(box(0, 0, S, X), I(m.lring(0, -X, wm / 2 + S / 2, X, c=(1, 1, 1, 0)), box(-1, 0, wm, X + 1)),
                I(m.lring(wm / 2 - S / 2, -X, wm, X, c=(1, 1, 1, 0)), box(-1, 0, wm + 1, X + 1))), wm)
    wr = w * 0.62
    putl("r", U(box(0, 0, S, X), I(m.lring(0, -X, wr, X, c=(1, 1, 1, 0)), box(-1, X - H, wr + 1, X + 1))), wr, rsb=sbl + 26)   # (open on the right: rn not m)
    putl("i", U(box(0, 0, S, X), box(0, X + S * 0.7, S, X + S * 1.7)), S)
    putl("ı", box(0, 0, S, X), S)
    putl("j", U(D(I(m.lring(-w * 0.38, -Dd, S, X * 1.5, c=(1, 1, 1, 1)), box(-w, -Dd - 1, S + 1, X)), box(-w, -Dd + H, -w * 0.38 + S, X + 1)),
                box(0, X + S * 0.7, S, X + S * 1.7)), S, lsb=sbl + w * 0.2)
    wl = w * 0.42
    hook = lambda x0, x1, top, rad: D(rbox(x0, 0, x1, top, rad, (1, 0, 0, 0)), rbox(x0 + S, H, x1 + 500, top + 500, m.ri(rad), (1, 0, 0, 0)))
    putl("l", hook(0, wl, A, r * 0.85), wl, rsb=sbl * 0.9)
    wt = w * 0.6
    putl("t", U(hook(wt * 0.15, wt, A * 0.88, r * 0.85), box(0, X - H, wt, X)), wt)
    wf = w * 0.6
    putl("f", U(D(I(m.lring(wf * 0.15, -A, wf, A, R=r * 0.85), box(-1, 0, wf + 1, A + 1)), box(wf * 0.15 + S, -A, wf + 1, A - H)),
                box(0, X - H, wf * 0.92, X)), wf)
    wk = w * 0.9
    putl("k", U(box(0, 0, S, A), I(diag(S * 0.5, X * 0.38, wk - dg * 0.55, X, dg * 0.95), box(0, 0, wk, X)),
                I(diag(wk * 0.4, X * 0.56, wk - dg * 0.55, 0, dg * 0.95), box(0, 0, wk, X))), wk)
    wv = w * 1.0
    clipx = box(-200, 0, wv + 200, X)
    putl("v", I(U(diag(dg * 0.55, X, wv / 2, 0, dg), diag(wv - dg * 0.55, X, wv / 2, 0, dg)), clipx), wv)
    putl("x", I(U(diag(dg * 0.55, X, wv - dg * 0.55, 0, dg), diag(wv - dg * 0.55, X, dg * 0.55, 0, dg)), clipx), wv)
    k = (wv - dg * 0.55 - wv / 2) / X
    putl("y", U(I(diag(dg * 0.55, X, wv / 2, 0, dg), clipx),
                I(diag(wv - dg * 0.55, X, wv / 2 - k * Dd, -Dd, dg), box(-300, -Dd, wv + 200, X))), wv)
    ww = w * 1.42
    putl("w", I(U(diag(dg * 0.5, X, ww * 0.26, 0, dg), diag(ww / 2, X, ww * 0.26, 0, dg),
                  diag(ww / 2, X, ww * 0.74, 0, dg), diag(ww - dg * 0.5, X, ww * 0.74, 0, dg)), box(-200, 0, ww + 200, X)), ww)
    wz = w * 0.92
    putl("z", U(box(0, X - H, wz, X), box(0, 0, wz, H), I(diag(wz - dg * 0.6, X - H, dg * 0.6, H, dg), box(0, 0, wz, X))), wz)
    wsl = w * 0.98
    putl("s", U(D(m.lring(0, X * 0.5 - H / 2, wsl, X, R=r * 0.8), box(wsl - S - KI, X * 0.5 + H / 2, wsl + 1, X - H)),
                D(m.lring(0, 0, wsl, X * 0.5 + H / 2, R=r * 0.8), box(-1, H, S + KI, X * 0.5 - H / 2))), wsl)

    # ---- figures (tabular)
    Wd = m.WD
    adv_d = Wd + 2 * sb
    def putd(ch, region, w_=Wd):
        out[ch] = (move(region, sb + (Wd - w_) / 2), adv_d)
    putd("0", m.ring(0, 0, Wd, C))
    x1l = Wd * 0.56 - S / 2
    putd("1", U(box(x1l, 0, x1l + S, C), poly((x1l + 1, C), (Wd * 0.16, C * 0.7), (Wd * 0.16, C * 0.7 - S * 1.05), (x1l + 1, C - S * 1.25))))
    mid = C * 0.5
    putd("2", U(D(m.ring(0, mid - H / 2, Wd, C), box(-1, mid + H / 2, S + KI, C - H)),
                D(m.ring(0, 0, Wd, mid + H / 2, c=(0, 0, 0, 1)), box(Wd - S - 1, -1, Wd + 1, mid - H / 2))))
    putd("3", D(U(m.ring(0, mid - H / 2, Wd, C), m.ring(0, 0, Wd, mid + H / 2)),
                box(-1, H, S + KI, C - H), box(-1, mid - H, Wd * 0.22, mid + H)))
    putd("4", U(box(Wd * 0.72 - S / 2, 0, Wd * 0.72 + S / 2, C), box(0, C * 0.3 - H / 2 + 0.0, Wd, C * 0.3 + H / 2),
                I(diag(Wd * 0.72, C, dg * 0.55, C * 0.3, dg), box(0, C * 0.3 - H / 2, Wd, C))))
    putd("5", U(box(0, C - H, Wd, C), box(0, mid - H / 2, S, C),
                D(m.ring(0, 0, Wd, mid + H / 2, c=(1, 1, 1, 0)), box(-1, H, S + KI, mid - H / 2))))
    six = U(m.ring(0, 0, Wd, mid + H / 2), D(m.ring(0, 0, Wd, C), box(Wd - S - KI, mid, Wd + 1, C - H)))
    putd("6", six)
    putd("9", rot180(six, Wd / 2, C / 2))
    putd("7", U(box(0, C - H, Wd, C), I(diag(Wd - dg * 0.6, C - H, Wd * 0.3, 0, dg), box(0, 0, Wd, C))))
    putd("8", U(m.ring(Wd * 0.04, mid - H / 2, Wd * 0.96, C), m.ring(0, 0, Wd, mid + H / 2)))

    # ---- punctuation and symbols
    dot = S * 1.02
    put(".", box(0, 0, dot, dot), dot, sbl, sbl)
    put(",", U(box(0, 0, dot, dot), I(diag(dot * 0.5, dot * 0.5, -dot * 0.1, -dot * 1.3, dot * 0.7), box(-dot, -dot * 1.4, dot, dot))), dot, sbl, sbl)
    put(":", U(box(0, 0, dot, dot), box(0, X - dot, dot, X)), dot, sbl, sbl)
    put(";", U(box(0, X - dot, dot, X), box(0, 0, dot, dot),
               I(diag(dot * 0.5, dot * 0.5, -dot * 0.1, -dot * 1.3, dot * 0.7), box(-dot, -dot * 1.4, dot, dot))), dot, sbl, sbl)
    put("!", U(box(0, dot * 1.7, S, C), box(0, 0, dot, dot)), dot, sbl, sbl)
    Wq = W * 0.8
    put("?", U(D(I(m.ring(0, C * 0.38, Wq, C), box(-1, C * 0.38 - 1, Wq + 1, C + 1)), box(-1, C * 0.38 - 1, S + KI, C - H),
                 box(-1, C * 0.38 - 1, Wq * 0.5 - S / 2, C * 0.38 + H)),
               box(Wq * 0.5 - S / 2, dot * 1.7, Wq * 0.5 + S / 2, C * 0.38 + H), box(Wq * 0.5 - dot / 2, 0, Wq * 0.5 + dot / 2, dot)), Wq)
    put("¡", move(rot180(U(box(0, dot * 1.7, S, C), box(0, 0, dot, dot)), dot / 2, C / 2), 0, -C + X), dot, sbl, sbl)
    out["¿"] = (rot180(out["?"][0], out["?"][1] / 2, C / 2).map(lambda p: (p[0], p[1] - C + X)), out["?"][1])
    qh = C * 0.3
    put("'", box(0, C - qh, S * 0.8, C), S * 0.8, sbl, sbl)
    put('"', U(box(0, C - qh, S * 0.8, C), box(S * 1.6, C - qh, S * 2.4, C)), S * 2.4, sbl, sbl)
    tick = lambda x: diag(x + S * 0.75, C, x + S * 0.2, C - qh, S * 0.7)
    tick_o = lambda x: diag(x + S * 0.2, C, x + S * 0.75, C - qh, S * 0.7)
    put("’", tick(0), S, sbl, sbl)
    put("‘", rot180(tick(0), S * 0.47, C - qh / 2), S, sbl, sbl)
    put("”", U(tick(0), tick(S * 1.4)), S * 2.4, sbl, sbl)
    put("“", rot180(U(tick(0), tick(S * 1.4)), S * 1.2, C - qh / 2), S * 2.4, sbl, sbl)
    put("‚", move(tick(0), 0, -C + qh * 0.6), S, sbl, sbl)
    put("„", move(U(tick(0), tick(S * 1.4)), 0, -C + qh * 0.6), S * 2.4, sbl, sbl)
    put("`", diag(-S * 0.6, A, S * 0.8, A - 120, S * 0.8), S * 0.8, sbl * 2, sbl)
    put("´", diag(S * 0.6, A, -S * 0.6 + 50, A - 120, S * 0.8), S * 0.8, sbl * 2, sbl)
    pw = W * 0.36
    top, bot = C + 60, -Dd * 0.7
    paren = I(m.ring(0, bot, pw * 2.4, top, R=pw * 1.15), box(-1, bot - 1, pw, top + 1))
    put("(", paren, pw, sbl * 1.2, sbl)
    put(")", mirror_x(paren, pw / 2), pw, sbl, sbl * 1.2)
    put("[", U(box(0, bot, S, top), box(0, bot, pw, bot + H), box(0, top - H, pw, top)), pw, sbl * 1.2, sbl)
    put("]", U(box(pw - S, bot, pw, top), box(0, bot, pw, bot + H), box(0, top - H, pw, top)), pw, sbl, sbl * 1.2)
    my = (top + bot) / 2
    brace = U(box(pw * 0.4, bot, pw * 0.4 + S, top), box(pw * 0.4, bot, pw * 1.1, bot + H), box(pw * 0.4, top - H, pw * 1.1, top),
              box(0, my - H / 2, pw * 0.4 + S, my + H / 2))
    put("{", brace, pw * 1.1, sbl, sbl)
    put("}", mirror_x(brace, pw * 0.55), pw * 1.1, sbl, sbl)
    sl = W * 0.5
    put("/", I(diag(sl - dg * 0.5, top, dg * 0.5, bot, dg), box(-100, bot, sl + 100, top)), sl, sbl, sbl)
    put("\\", I(diag(dg * 0.5, top, sl - dg * 0.5, bot, dg), box(-100, bot, sl + 100, top)), sl, sbl, sbl)
    put("|", box(0, bot - 20, S * 0.9, top + 20), S * 0.9, sbl * 1.6, sbl * 1.6)
    put("¦", U(box(0, bot - 20, S * 0.9, my - 40), box(0, my + 40, S * 0.9, top + 20)), S * 0.9, sbl * 1.6, sbl * 1.6)
    put("_", box(0, -Dd * 0.6, W * 0.8, -Dd * 0.6 + H), W * 0.8, 0, 0)
    ow = W * 0.72      # operators
    oc = C * 0.42
    put("-", box(0, oc - H / 2, ow * 0.62, oc + H / 2), ow * 0.62, sbl, sbl)
    put("‐", box(0, oc - H / 2, ow * 0.62, oc + H / 2), ow * 0.62, sbl, sbl)
    put("–", box(0, oc - H / 2, W * 0.86, oc + H / 2), W * 0.86, sbl * 0.6, sbl * 0.6)
    put("—", box(0, oc - H / 2, W * 1.4, oc + H / 2), W * 1.4, sbl * 0.6, sbl * 0.6)
    put("−", box(0, oc - H / 2, ow, oc + H / 2), ow)
    put("+", U(box(0, oc - H / 2, ow, oc + H / 2), box(ow / 2 - S / 2, oc - ow / 2, ow / 2 + S / 2, oc + ow / 2)), ow)
    put("±", U(box(0, oc + 30 - H / 2, ow, oc + 30 + H / 2), box(ow / 2 - S / 2, oc + 30 - ow / 2 + 40, ow / 2 + S / 2, oc + 30 + ow / 2),
               box(0, -20, ow, -20 + H)), ow)
    put("=", U(box(0, oc + H * 0.6, ow, oc + H * 1.6), box(0, oc - H * 1.6, ow, oc - H * 0.6)), ow)
    put("×", U(seg(ow * 0.12, oc - ow * 0.38, ow * 0.88, oc + ow * 0.38, S * 0.95), seg(ow * 0.12, oc + ow * 0.38, ow * 0.88, oc - ow * 0.38, S * 0.95)), ow)
    put("÷", U(box(0, oc - H / 2, ow, oc + H / 2), box(ow / 2 - dot / 2, oc + H / 2 + 50, ow / 2 + dot / 2, oc + H / 2 + 50 + dot),
               box(ow / 2 - dot / 2, oc - H / 2 - 50 - dot, ow / 2 + dot / 2, oc - H / 2 - 50)), ow)
    put("¬", U(box(0, oc, ow, oc + H), box(ow - S, oc - 140, ow, oc + H)), ow)

    def chevron(x0, x1, y0, y1, t):
        """Left-pointing chevron, tip at x0, arms to x1 between y0 and y1."""
        ym = (y0 + y1) / 2
        L = math.hypot(x1 - x0, (y1 - y0) / 2)
        vt = t * L / (x1 - x0)          # vertical thickness of an arm
        ht = t * L / ((y1 - y0) / 2)    # horizontal thickness at the tip
        return poly((x0, ym), (x1, y0), (x1, y0 + vt), (x0 + ht, ym), (x1, y1 - vt), (x1, y1))
    put("<", chevron(0, ow, oc - ow * 0.45, oc + ow * 0.45, S * 0.95), ow)
    put(">", mirror_x(chevron(0, ow, oc - ow * 0.45, oc + ow * 0.45, S * 0.95), ow / 2), ow)
    gw = W * 0.42
    put("‹", chevron(0, gw, X * 0.1, X * 0.9, S * 0.9), gw, sbl, sbl)
    put("›", mirror_x(chevron(0, gw, X * 0.1, X * 0.9, S * 0.9), gw / 2), gw, sbl, sbl)
    put("«", U(chevron(0, gw, X * 0.1, X * 0.9, S * 0.9), chevron(gw * 0.9, gw * 1.9, X * 0.1, X * 0.9, S * 0.9)), gw * 1.9, sbl, sbl)
    put("»", mirror_x(U(chevron(0, gw, X * 0.1, X * 0.9, S * 0.9), chevron(gw * 0.9, gw * 1.9, X * 0.1, X * 0.9, S * 0.9)), gw * 0.95), gw * 1.9, sbl, sbl)
    put("^", I(U(diag(dg * 0.5, C * 0.5, ow / 2, C, dg * 0.9), diag(ow - dg * 0.5, C * 0.5, ow / 2, C, dg * 0.9)), box(-100, C * 0.5, ow + 100, C)), ow)
    tl = [(0, oc - 50), (ow * 0.3, oc + 60), (ow * 0.7, oc - 60), (ow, oc + 50)]
    put("~", I(U(*[seg(tl[i][0], tl[i][1], tl[i + 1][0], tl[i + 1][1], S * 0.85) for i in range(3)]), box(0, 0, ow, C)), ow)
    dw = W * 0.4
    put("°", m.ring(0, C - dw, dw, C, R * 0.5, sx=S * 0.85, sy=S * 0.8), dw, sbl, sbl)
    pr = W * 0.36
    put("%", U(m.ring(0, C - pr * 1.05, pr, C, R * 0.5, sx=S * 0.8, sy=S * 0.75), m.ring(W * 1.0 - pr, 0, W * 1.0, pr * 1.05, R * 0.5, sx=S * 0.8, sy=S * 0.75),
               I(diag(W * 0.84, C, W * 0.16, 0, dg * 0.85), box(0, 0, W, C))), W)
    Wa = W * 0.94
    put("&", U(D(m.ring(Wa * 0.06, C * 0.52, Wa * 0.68, C, R * 0.8), box(Wa * 0.06 - 1, C * 0.52 - 1, Wa * 0.06 + S + KI, C * 0.62)),
               D(m.ring(0, 0, Wa * 0.84, C * 0.6), box(Wa * 0.84 - S - KI, C * 0.35, Wa * 0.84 + 1, C * 0.61)),
               box(Wa * 0.84 - S, C * 0.35 - 0, Wa, C * 0.35 + H),
               I(diag(Wa * 0.06 + S * 0.5, C * 0.6, Wa - dg * 0.5, 0, dg), box(0, 0, Wa, C * 0.62))), Wa)
    ast = U(seg(0, -150, 0, 150, S * 0.8), seg(-130, -75, 130, 75, S * 0.8), seg(-130, 75, 130, -75, S * 0.8))
    put("*", move(ast, 140, C - 160), 280)
    Wat = W * 1.1
    put("@", U(D(m.ring(0, -C * 0.12, Wat, C * 0.92), box(Wat - S - KI, -C * 0.12 + H, Wat + 1, C * 0.2)),
               m.ring(Wat * 0.26, C * 0.18, Wat * 0.74, C * 0.62, R * 0.6, sx=S * 0.9, sy=H * 0.9),
               box(Wat * 0.74 - S * 0.9, C * 0.18, Wat - S, C * 0.18 + H * 0.9),
               box(Wat * 0.74 - S * 0.9, C * 0.18, Wat * 0.74, C * 0.62)), Wat)
    Wh = W * 0.86
    put("#", I(U(diag(Wh * 0.38, C, Wh * 0.26, 0, S * 0.9), diag(Wh * 0.78, C, Wh * 0.66, 0, S * 0.9),
                 box(0, C * 0.62, Wh, C * 0.62 + H * 0.9), box(0, C * 0.3, Wh, C * 0.3 + H * 0.9)), box(-100, 0, Wh + 100, C)), Wh)
    Wc = W * 0.92
    put("€", U(D(m.ring(Wc * 0.12, 0, Wc, C), box(Wc - S - KI, H, Wc + 1, C - H)),
               box(0, C * 0.56, Wc * 0.68, C * 0.56 + H * 0.85), box(0, C * 0.32, Wc * 0.62, C * 0.32 + H * 0.85)), Wc)
    put("£", U(D(I(m.ring(Wc * 0.12, -C, Wc, C), box(-1, H, Wc + 1, C + 1)), box(Wc - S - KI, -C, Wc + 1, C - H * 2.2)),
               box(Wc * 0.12, 0, Wc * 0.12 + S, C * 0.5), box(0, 0, Wc, H), box(0, C * 0.44, Wc * 0.7, C * 0.44 + H)), Wc)
    sS = out["S"][0]
    put("$", U(move(sS, -sb), box(Ws / 2 - S * 0.4, -90, Ws / 2 + S * 0.4, C + 90)), Ws)
    put("¥", U(move(out["Y"][0], -sb), box(Wv * 0.15, C * 0.28, Wv * 0.85, C * 0.28 + H * 0.85)), Wv)
    put("¢", U(D(m.lring(0, 0, w, X), box(w - S - KI, H, w + 1, X - H)), box(w / 2 - S * 0.4, -90, w / 2 + S * 0.4, X + 90)), w)
    put("§", U(D(m.lring(0, C * 0.45, w, C, R=r * 0.8), box(w - S - KI, C * 0.45, w + 1, C - H)),
               D(m.lring(0, 0, w, C * 0.55, R=r * 0.8), box(-1, H, S + KI, C * 0.55)),
               m.lring(0, C * 0.25, w, C * 0.75, R=r * 0.8)), w)
    put("¶", U(box(w * 0.55, 0, w * 0.55 + S, C), box(w - S, 0, w, C), box(w * 0.2, C - H, w, C),
               rbox(0, C * 0.45, w * 0.6, C, r, (1, 0, 0, 1))), w)
    put("©", U(m.ring(0, 0, W, C), move(scale(D(m.lring(0, 0, w, X), box(w - S - KI, H, w + 1, X - H)), 0.62), W / 2 - w * 0.31, C / 2 - X * 0.31)), W)
    put("®", U(m.ring(0, 0, W, C), move(scale(move(out["R"][0], -sb), 0.5), W / 2 - Wb * 0.25, C / 2 - C * 0.25)), W)
    put("™", U(scale(move(out["T"][0], -sb), 0.42, 0.42, 0, C), move(scale(move(out["M"][0], -sb), 0.42, 0.42, 0, C), Wt * 0.5)), Wt * 0.5 + Wm * 0.42)
    put("·", box(0, oc - dot / 2, dot, oc + dot / 2), dot, sbl, sbl)
    bd = dot * 1.6
    put("•", rbox(0, oc - bd / 2, bd, oc + bd / 2, bd * 0.3), bd, sbl, sbl)
    put("…", U(box(0, 0, dot, dot), box(dot * 2, 0, dot * 3, dot), box(dot * 4, 0, dot * 5, dot)), dot * 5, sbl, sbl)
    put("µ", U(box(0, -Dd, S, X), I(m.lring(0, 0, wn, X * 2, c=(1, 0, 1, 1)), box(-1, -1, wn + 1, X)), box(wn - S, 0, wn, X)), wn, sbl, sbl)
    put("ª", scale(move(out["a"][0], -sbl), 0.6, 0.6, 0, C), w * 0.6, sbl, sbl)
    put("º", scale(move(out["o"][0], -sbl), 0.6, 0.6, 0, C), w * 0.6, sbl, sbl)
    for ch, sup in (("1", "¹"), ("2", "²"), ("3", "³")):
        put(sup, scale(move(out[ch][0], -sb), 0.55, 0.55, 0, C), Wd * 0.55, sbl, sbl)
    put("¤", U(m.ring(ow * 0.15, oc - ow * 0.35, ow * 0.85, oc + ow * 0.35, R * 0.6, sx=S * 0.8, sy=S * 0.8),
               seg(0, oc - ow * 0.5, ow * 0.2, oc - ow * 0.3, S * 0.7), seg(ow, oc - ow * 0.5, ow * 0.8, oc - ow * 0.3, S * 0.7),
               seg(0, oc + ow * 0.5, ow * 0.2, oc + ow * 0.3, S * 0.7), seg(ow, oc + ow * 0.5, ow * 0.8, oc + ow * 0.3, S * 0.7)), ow)
    for frac, (a_, b_) in (("¼", ("1", "4")), ("½", ("1", "2")), ("¾", ("3", "4"))):
        na = scale(move(out[a_][0], -sb), 0.46, 0.46, 0, C)
        nb = move(scale(move(out[b_][0], -sb), 0.46, 0.46, 0, 0), Wd * 0.62)
        put(frac, U(na, nb, I(diag(Wd * 0.95, C, Wd * 0.15, 0, dg * 0.7), box(0, 0, Wd * 1.1, C))), Wd * 1.1)
    put("ß", U(box(0, 0, S, A * 0.6), m.lring(0, A * 0.45 - H / 2, w * 0.9, A, c=(0, 1, 1, 1)),
               m.lring(0, 0, w, A * 0.45 + H / 2, c=(0, 1, 1, 0))), w, sbl, sbl)

    # ---- more Latin letters
    put("Æ", U(I(diag(dg * 0.6, 0, W * 0.55, C, dg), box(-200, 0, W, C)), box(W * 0.5, C - H, W * 1.32, C), box(W * 0.5, 0, W * 1.32, H),
               box(W * 0.5, C * 0.5 - H / 2, W * 1.25, C * 0.5 + H / 2), box(W * 0.5, 0, W * 0.5 + S, C),
               box(W * 0.2, C * 0.24, W * 0.55, C * 0.24 + H)), W * 1.32)
    putl("æ", U(move(out["a"][0], -sbl), move(out["e"][0], w - S - sbl)), w * 2 - S)
    put("Œ", U(m.ring(0, 0, W, C, c=(1, 0, 0, 1)), box(W - S, 0, W * 1.6, H), box(W - S, C - H, W * 1.6, C),
               box(W - S, C * 0.5 - H / 2, W * 1.5, C * 0.5 + H / 2)), W * 1.6)
    putl("œ", U(move(out["o"][0], -sbl), move(out["e"][0], w - S - sbl)), w * 2 - S)
    put("Ø", U(move(out["O"][0], -sb), I(diag(W * 1.02, C * 1.06, -W * 0.02, -C * 0.06, dg * 0.8), box(-W, -C * 0.06, W * 2, C * 1.06))), W)
    putl("ø", U(move(out["o"][0], -sbl), I(diag(w * 1.04, X * 1.08, -w * 0.04, -X * 0.08, dg * 0.8), box(-w, -X * 0.08, w * 2, X * 1.08))), w)
    put("Ð", U(move(out["D"][0], -sb + S * 0.5), box(0, C * 0.5 - H / 2, S * 2.2, C * 0.5 + H / 2)), W + S * 0.5)
    put("Đ", U(move(out["D"][0], -sb + S * 0.5), box(0, C * 0.5 - H / 2, S * 2.2, C * 0.5 + H / 2)), W + S * 0.5)
    putl("ð", U(move(out["o"][0], -sbl), box(w - S, X * 0.5, w, A * 0.95), box(w * 0.3, A * 0.75, w + 40, A * 0.75 + H * 0.85)), w)
    putl("đ", U(move(out["d"][0], -sbl), box(w * 0.45, A - H * 0.85 - 40, w + 60, A - 40)), w + 40)
    put("Þ", U(box(0, 0, S, C), m.ring(0, C * 0.2, Wb, C * 0.8, c=(0, 1, 1, 0))), Wb)
    putl("þ", U(box(0, -Dd, S, A), m.lring(0, 0, w, X, c=(0, 1, 1, 0))), w)
    put("Ł", U(move(out["L"][0], -sb + S * 0.6), I(diag(0, C * 0.3, S * 3, C * 0.62, S * 0.8), box(0, 0, S * 3, C))), We + S * 0.6)
    putl("ł", U(move(out["l"][0], -sbl + S * 0.6), I(diag(0, A * 0.32, S * 2.8, A * 0.65, S * 0.8), box(0, 0, S * 3, A))), w * 0.42 + S * 0.6, rsb=sbl * 0.9)

    # ---- Greek
    G = {}
    G["Γ"] = (U(box(0, 0, S, C), box(0, C - H, We, C)), We * 0.95)
    G["Δ"] = (U(I(U(diag(dg * 0.6, 0, Wv / 2, C, dg), diag(Wv - dg * 0.6, 0, Wv / 2, C, dg)), clipc), box(0, 0, Wv, H)), Wv)
    G["Θ"] = (U(m.ring(0, 0, W, C), box(W * 0.25, C * 0.5 - H / 2, W * 0.75, C * 0.5 + H / 2)), W)
    G["Λ"] = (I(U(diag(dg * 0.6, 0, Wv / 2, C, dg), diag(Wv - dg * 0.6, 0, Wv / 2, C, dg)), clipc), Wv)
    G["Ξ"] = (U(box(0, 0, We, H), box(0, C - H, We, C), box(We * 0.12, C * 0.5 - H / 2, We * 0.88, C * 0.5 + H / 2)), We)
    G["Π"] = (U(box(0, 0, S, C), box(W - S, 0, W, C), box(0, C - H, W, C)), W)
    G["Σ"] = (U(box(0, 0, We, H), box(0, C - H, We, C), I(U(diag(dg * 0.6, C - H, We * 0.52, C * 0.5, dg), diag(dg * 0.6, H, We * 0.52, C * 0.5, dg)),
                                                       box(0, H, We * 0.56, C - H))), We)
    G["Φ"] = (U(m.ring(0, C * 0.14, W, C * 0.86, R * 0.9), box(W / 2 - S / 2, 0, W / 2 + S / 2, C)), W)
    G["Ψ"] = (U(I(m.ring(0, C * 0.3, W, C * 1.6), box(-1, 0, W + 1, C)), box(W / 2 - S / 2, 0, W / 2 + S / 2, C)), W)
    ob = C * 0.22
    G["Ω"] = (U(D(m.ring(0, ob, W, C), box(W * 0.34, ob - 1, W * 0.66, ob + H + 1)),
                box(W * 0.34 - S, 0, W * 0.34, ob + H), box(W * 0.66, 0, W * 0.66 + S, ob + H),
                box(0, 0, W * 0.34, H), box(W * 0.66, 0, W, H)), W)
    for k_, v_ in G.items():
        put(k_, *v_)
    for gk, lat in zip("ΑΒΕΖΗΙΚΜΝΟΡΤΥΧ", "ABEZHIKMNOPTYX"):
        out[gk] = out[lat]
    g = {}
    g["α"] = (U(m.lring(0, 0, w, X, c=(1, 0, 0, 1)), box(w - S, 0, w + S * 0.6, X)), w + S * 0.6)
    g["β"] = (U(box(0, -Dd, S, A * 0.8), D(m.lring(0, X * 0.55, w * 0.9, A, c=(0, 1, 1, 1)), box(-1, X * 0.55, S + KI, A * 0.8)),
                m.lring(0, 0, w, X * 0.6 + H / 2, c=(0, 1, 1, 0))), w)
    g["γ"] = (U(I(U(diag(dg * 0.55, X, wv / 2, 0, dg), diag(wv - dg * 0.55, X, wv / 2, 0, dg)), clipx), box(wv / 2 - S / 2, -Dd, wv / 2 + S / 2, 10)), wv)
    g["δ"] = (U(m.lring(0, 0, w, X * 1.02), box(w * 0.12, X, w * 0.12 + S, A), box(w * 0.12, A - H, w, A)), w)
    g["ε"] = (U(D(m.lring(0, 0, w * 0.92, X), box(w * 0.92 - S - KI, H, w + 1, X - H)), box(0, X * 0.5 - H / 2, w * 0.7, X * 0.5 + H / 2)), w * 0.92)
    g["ζ"] = (U(box(0, A - H, wz, A), I(diag(wz - dg * 0.6, A - H, dg * 0.6, H, dg), box(0, 0, wz, A)), box(0, 0, wz, H),
                box(wz - S, -Dd * 0.75, wz, H)), wz)
    g["η"] = (U(box(0, 0, S, X), I(m.lring(0, -X, wn, X, c=(1, 1, 1, 0)), box(-1, 0, wn + 1, X + 1)), box(wn - S, -Dd, wn, X * 0.5)), wn)
    g["θ"] = (U(m.lring(0, 0, w, A), box(0, A * 0.5 - H / 2, w, A * 0.5 + H / 2)), w)
    g["ι"] = (hook(0, wl, X, r * 0.85), wl)
    g["κ"] = (U(box(0, 0, S, X), I(diag(S * 0.5, X * 0.38, wk - dg * 0.55, X, dg * 0.95), box(0, 0, wk, X)),
                                                       I(diag(wk * 0.4, X * 0.56, wk - dg * 0.55, 0, dg * 0.95), box(0, 0, wk, X))), wk)
    g["λ"] = (U(I(diag(dg * 0.55, 0, wv * 0.5, X * 0.85, dg), box(-100, 0, wv, A)), I(diag(dg * 0.3, A, wv - dg * 0.55, 0, dg), box(-100, 0, wv + 100, A))), wv)
    g["μ"] = (U(box(0, -Dd, S, X), I(m.lring(0, 0, wn, X * 2, c=(1, 0, 1, 1)), box(-1, -1, wn + 1, X)), box(wn - S, 0, wn, X)), wn)
    g["ν"] = (I(U(diag(dg * 0.55, X, wv / 2, 0, dg), diag(wv - dg * 0.55, X, wv / 2, 0, dg)), clipx), wv)
    g["ξ"] = (U(box(0, A - H, wz, A), box(0, X * 0.5, wz * 0.85, X * 0.5 + H), box(0, 0, wz, H), box(0, 0, S, A),
                box(wz - S, -Dd * 0.75, wz, H)), wz)
    g["ο"] = (move(out["o"][0], -sbl), w)
    g["π"] = (U(box(0, X - H, w * 1.1, X), box(w * 0.15, 0, w * 0.15 + S, X), box(w * 0.85 - S, 0, w * 0.85, X)), w * 1.1)
    g["ρ"] = (move(out["p"][0], -sbl), w)
    g["σ"] = (U(m.lring(0, 0, w, X, c=(1, 1, 0, 1)), box(w * 0.5, X - H, w * 1.12, X)), w * 1.12)
    g["ς"] = (U(D(m.lring(0, 0, w * 0.92, X), box(w * 0.92 - S - KI, H, w + 1, X - H)), box(w * 0.92 - S, -Dd * 0.75, w * 0.92, H)), w * 0.92)
    g["τ"] = (U(box(0, X - H, w, X), D(I(m.lring(w * 0.5 - S / 2, 0, w, X * 2, R=r * 0.8), box(-1, -1, w + 1, X)), box(w * 0.5 + S / 2, H, w + 1, X + 1))), w)
    g["υ"] = (I(m.lring(0, 0, wn, X * 2), box(-1, -1, wn + 1, X)), wn)
    g["φ"] = (U(m.lring(0, 0, w * 1.1, X), box(w * 0.55 - S / 2, -Dd, w * 0.55 + S / 2, A)), w * 1.1)
    g["χ"] = (I(U(diag(dg * 0.55, X, wv - dg * 0.55, -Dd, dg), diag(wv - dg * 0.55, X, dg * 0.55, -Dd, dg)), box(-200, -Dd, wv + 200, X)), wv)
    g["ψ"] = (U(I(m.lring(0, 0, w * 1.1, X * 2), box(-1, -1, w * 1.1 + 1, X)), box(w * 0.55 - S / 2, -Dd, w * 0.55 + S / 2, A)), w * 1.1)
    g["ω"] = (U(I(m.lring(0, 0, w * 1.5, X * 2), box(-1, -1, w * 1.5 + 1, X)), box(w * 0.75 - S / 2, 0, w * 0.75 + S / 2, X * 0.62)), w * 1.5)
    for k_, v_ in g.items():
        putl(k_, *v_)

    # ---- accented letters (base + mark)
    mk = mark_shapes(m)
    gap = 50

    def accent(ch, base, mark, upper=None, dx=0.0):
        b_reg, adv = out[base]
        is_up = base.isupper() or base in "ΑΒΕΖΗΙΚΜΝΟΡΤΥΧΓΔΘΛΞΠΣΦΨΩ"
        if upper is None:
            upper = is_up
        cx = adv / 2 + dx
        if base in "ij":   # dotless base
            b_reg = out["ı"][0] if base == "i" else D(b_reg, box(-1000, X + 1, 1000, X + 400))
            cx = sbl + m.narrow + S / 2
        if mark == "cedilla":
            mreg = move(mk[mark], cx, 0)
        elif mark == "ogonek":
            mreg = move(mk[mark], adv - sb - S / 2, 0)
        else:
            top = (C + gap * 0.8) if upper else (X + gap)
            mreg = move(mk[mark], cx, top)
            if upper:
                mreg = scale(mreg, 1.0, 0.8, 0, top)
        out[ch] = (U(b_reg, mreg), adv)

    table = {
        "grave": "ÀAÈEÌIÒOÙUàaèeìiòoùu",
        "acute": "ÁAÉEÍIÓOÚUÝYáaéeíióoúuýyĆCćcŃNńnŚSśsŹZźz",
        "circ": "ÂAÊEÎIÔOÛUâaêeîiôoûu",
        "tilde": "ÃAÑNÕOãañnõo",
        "dier": "ÄAËEÏIÖOÜUŸYäaëeïiöoüuÿy",
        "ring": "ÅAåa",
        "cedilla": "ÇCçcŞSşs",
        "caron": "ŠSšsŽZžzČCčcŘRřrĚEěeĎDŤTŇNňn",
        "macron": "ĀAāaĒEēeĪIīiŌOōoŪUūu",
        "dot": "ŻZżzĖEė" + "e",
    }
    for mark, pairs in table.items():
        for i in range(0, len(pairs), 2):
            accent(pairs[i], pairs[i + 1], mark)
    # Greek with tonos / dialytika
    for ch, base in zip("άέήίόύώ", "αεηιουω"):
        accent(ch, base, "acute", upper=False)
    for ch, base in zip("ϊϋ", "ιυ"):
        accent(ch, base, "dier", upper=False)
    for ch, base in zip("ΪΫ", "ΙΥ"):
        accent(ch, base, "dier", upper=True)
    for ch, base in zip("ΆΈΉΊΌΎΏ", "ΑΕΗΙΟΥΩ"):
        b_reg, adv = out[base]
        t = move(scale(mk["acute"], 0.85), sb * 0.6 + S * 0.6, C - 110)
        out[ch] = (U(move(b_reg, S * 1.5), t), round(adv + S * 1.5))
    out[" "] = (None, round(W * 0.42))
    out[" "] = out[" "]
    out[" "] = (None, round(W * 0.2))
    out[" "] = (None, adv_d)
    return out


# ------------------------------------------------------------- building
def _job(args):
    bold, ch = args
    m = M(bold)
    reg, adv = _all(bold)[ch]
    if reg is None:
        return ch, [], adv
    return ch, outline(reg), adv


_cache = {}


def _all(bold):
    if bold not in _cache:
        _cache[bold] = glyphs(M(bold))
    return _cache[bold]


def gname(ch):
    cp = ord(ch)
    return UV2AGL.get(cp, "uni%04X" % cp)


def build(bold, pool):
    m = M(bold)
    chars = sorted(_all(bold).keys())
    res = pool.map(_job, [(bold, c) for c in chars], chunksize=4)
    order = [".notdef"]
    cmap = {}
    glyf = {}
    metrics = {}
    # .notdef: a hollow box
    pen = TTGlyphPen(None)
    for c in outline(m.ring(0, 0, 500, m.C, 0, sx=60, sy=60)):
        _draw(pen, [(x + 50, y) for x, y in c])
    glyf[".notdef"] = pen.glyph()
    metrics[".notdef"] = (600, 50)
    names = {}
    for ch, contours, adv in res:
        n = gname(ch)
        if n in names.values():
            n = "uni%04X" % ord(ch)
        names[ch] = n
        if n not in glyf:
            order.append(n)
            pen = TTGlyphPen(None)
            for c in contours:
                _draw(pen, c)
            glyf[n] = pen.glyph()
            xs = [p[0] for c in contours for p in c]
            metrics[n] = (adv, min(xs) if xs else 0)
        cmap[ord(ch)] = n
    style = "Bold" if bold else "Regular"
    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf(glyf)
    fb.setupHorizontalMetrics(metrics)
    asc, desc = 930, 270
    fb.setupHorizontalHeader(ascent=asc, descent=-desc)
    fb.setupNameTable({
        "familyName": FAMILY,
        "styleName": style,
        "uniqueFontIdentifier": "%s %s %s" % (FAMILY, style, VERSION),
        "fullName": "%s %s" % (FAMILY, style),
        "psName": "AtraposSans-" + style,
        "version": "Version " + VERSION,
        "copyright": "Made for Space Atrapos by tools/make_font.py",
    })
    fb.setupOS2(sTypoAscender=asc, sTypoDescender=-desc, sTypoLineGap=0, usWinAscent=asc + 30, usWinDescent=desc + 40,
                sxHeight=m.X, sCapHeight=m.C, usWeightClass=700 if bold else 400,
                fsSelection=(0x20 if bold else 0x40) | 0x80, achVendID="ATRP", version=4)
    fb.setupPost()
    fb.setupHead(unitsPerEm=1000, macStyle=1 if bold else 0)
    path = os.path.join(OUT_DIR, "AtraposSans-%s.ttf" % style)
    fb.save(path)
    return path, len(order)


def _draw(pen, c):
    # contours come CCW (inside on the left); TrueType wants outer contours clockwise
    pts = list(reversed(c))
    pen.moveTo(pts[0])
    for p in pts[1:]:
        pen.lineTo(p)
    pen.closePath()


def specimen(paths, png):
    from PIL import Image, ImageDraw, ImageFont
    lines = [
        (paths[1], 72, "ABCDEFGHIJKLMNOPQRSTUVWXYZ"),
        (paths[0], 64, "abcdefghijklmnopqrstuvwxyz"),
        (paths[1], 72, "0123456789"),
        (paths[0], 48, ".,:;!?'\"“”‘’()[]{}/\\|_-+=<>°%&*@#€£$~^`"),
        (paths[0], 48, "ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩ αβγδεζηθικλμνξοπρσςτυφχψω"),
        (paths[0], 48, "ÀÁÂÃÄÅÇÈÉÊËÑÖØÜß àáâãäåçèéêëñöøüÿ ŠšŽžČč"),
        (paths[0], 32, "Regular: Dock at Athens Station, sell 12 t of olive oil for 1,480 cr. Shields 87% · hull 100%"),
        (paths[1], 32, "Bold: THE AUTOMATON · INVENTORY · MISSIONS · STATION MARKET"),
        (paths[0], 18, "Small text, 18 px: Sparta's patrol saw a pirate near the gate (2.4 km). Press F to dock."),
        (paths[0], 14, "Smaller, 14 px: The quick brown fox jumps over the lazy dog - 0123456789 - Μυκήνες, Αθήνα."),
    ]
    img = Image.new("RGB", (2400, 1020), (8, 5, 2))
    d = ImageDraw.Draw(img)
    y = 30
    for path, size, text in lines:
        f = ImageFont.truetype(path, size)
        d.text((40, y), text, font=f, fill=(255, 140, 40))
        y += int(size * 1.45) + 10
    img.save(png)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    with Pool() as pool:
        paths = []
        for bold in (False, True):
            p, n = build(bold, pool)
            paths.append(p)
            print("%s: %d glyphs" % (os.path.relpath(p, ROOT), n))
    if "--specimen" in sys.argv:
        specimen(paths, sys.argv[sys.argv.index("--specimen") + 1])


if __name__ == "__main__":
    main()
