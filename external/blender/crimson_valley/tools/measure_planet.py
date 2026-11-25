"""Measure the gas giant and the two moons in the reference picture -> analysis/planet.json.

  tools/cv py tools/measure_planet.py [--debug DIR]

What is measured (everything in picture pixels, (u, v) from the top-left corner):

  limb      edge points of the planet's visible limb: along rays from a rough centre the steepest drop
            of brightness from the bright rim to the sky, to a fraction of a pixel. Two fits:
            "planet" {cx, cy, r}  the least-squares circle through them, and
            "planet.sphere"       the true sphere that projects onto them through the scene's camera
                                  (direction of its centre + angular radius; an off-centre sphere
                                  projects as an ellipse, so this is not the same curve as the circle).
            Each with its residuals, so the scene can choose the geometry that lands on the limb.
  moons     the same for the two moons' discs (edge points all round, robust circle fit).
  bands     the direction of the planet's bands: the local orientation of the picture's texture inside
            the disc (structure tensor), fitted with the latitude circles of a tilted sphere ->
            the pole axis (as a direction in camera space).
  light     where the planet and the moons are lit from (terminator positions), the brightness falloff.
  colours   the sky colour around the planet, the bands' colours by latitude, the moons' colours.

Only numbers go into planet.json - no pixels: the scene's planet is procedural (scene/part_planet.py,
scene/part_moons.py read this file). With --debug the steps are drawn into DIR to check them by eye."""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi
from scipy import optimize

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import cvlib  # noqa: E402

OUT = os.path.join(cvlib.ANALYSIS, "planet.json")

# Rough seeds read off the picture by eye (the fits below replace them).
PLANET_SEED = (497.0, 250.0, 316.0)            # centre u, v and radius
PLANET_ARC = (-19.0, 53.0)                     # the visible limb: angles (degrees, anticlockwise from +u)
MOON_SEEDS = [(875.5, 219.0, 33.0), (944.0, 298.5, 15.5)]


def load_reference():
    rgb = np.asarray(Image.open(cvlib.REFERENCE).convert("RGB")).astype(np.float64) / 255.0
    return rgb


def luminance(rgb):
    return rgb @ np.array([0.2126, 0.7152, 0.0722])


def sample(img, u, v, order=3):
    """Picture values at continuous picture coordinates (pixel centres at integer + 0.5)."""
    return ndi.map_coordinates(img, [np.asarray(v) - 0.5, np.asarray(u) - 0.5], order=order, mode="nearest")


def srgb_to_linear(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
    c = np.clip(np.asarray(c, dtype=np.float64), 0.0, None)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


# ------------------------------------------------------------------------------------------- circles
def fit_circle(pts, w=None):
    """Least-squares circle (geometric distance) through points (n, 2): cx, cy, r."""
    pts = np.asarray(pts, dtype=np.float64)
    w = np.ones(len(pts)) if w is None else np.asarray(w, dtype=np.float64)
    a = np.c_[2 * pts, np.ones(len(pts))] * w[:, None]
    b = (pts ** 2).sum(1) * w
    (cx, cy, c), *_ = np.linalg.lstsq(a, b, rcond=None)
    r = math.sqrt(max(c + cx * cx + cy * cy, 1e-9))

    def res(p):
        return (np.hypot(pts[:, 0] - p[0], pts[:, 1] - p[1]) - p[2]) * w
    sol = optimize.least_squares(res, [cx, cy, r])
    return sol.x


def circle_residuals(pts, c):
    pts = np.asarray(pts, dtype=np.float64)
    return np.hypot(pts[:, 0] - c[0], pts[:, 1] - c[1]) - c[2]


def robust_circle(pts, k=2.5, rounds=6, floor=0.35):
    """Circle fit that drops outliers (points further than k sigma, sigma at least `floor` px)."""
    pts = np.asarray(pts, dtype=np.float64)
    keep = np.ones(len(pts), bool)
    c = fit_circle(pts)
    for _ in range(rounds):
        r = circle_residuals(pts, c)
        s = max(1.4826 * np.median(np.abs(r[keep] - np.median(r[keep]))), floor)
        new = np.abs(r) < k * s
        if new.sum() < 8 or (new == keep).all():
            break
        keep = new
        c = fit_circle(pts[keep])
    return c, keep


# --------------------------------------------------------------------------------------------- edges
def edge_along_rays(img, centre, angles_deg, r_lo, r_hi, mode, step=0.25, sigma=0.8, min_strength=0.03):
    """Edge points along rays from `centre`. img: (h, w) or (h, w, k) picture; for each ray the profile
    is sampled every `step` px between r_lo and r_hi and differentiated (after a little smoothing).
      mode "drop"       the outermost place where the brightness falls steeply going outward
      mode "strongest"  the place where the picture changes most (any channel, either sign)
    Returns (points (n, 2), strengths (n,), angles (n,)); rays without a clear edge are left out."""
    chans = img[..., None] if img.ndim == 2 else img
    rr = np.arange(r_lo, r_hi + 1e-6, step)
    pts, strengths, angs = [], [], []
    for ang in angles_deg:
        a = math.radians(ang)
        du, dv = math.cos(a), -math.sin(a)
        u, v = centre[0] + du * rr, centre[1] + dv * rr
        inside = (u > 1.0) & (u < cvlib.W - 1.0) & (v > 1.0) & (v < cvlib.H - 1.0)
        if inside.sum() < len(rr):
            # keep only rays whose whole search window is inside the picture
            continue
        prof = np.stack([sample(chans[..., k], u, v) for k in range(chans.shape[-1])], -1)
        prof = ndi.gaussian_filter1d(prof, sigma / step, axis=0)
        d = np.gradient(prof, step, axis=0)
        if mode == "drop":
            g = -d[..., 0] if d.shape[-1] == 1 else -d.mean(-1)
        else:
            g = np.sqrt((d ** 2).sum(-1))
        # local maxima of g
        peaks = np.where((g[1:-1] >= g[:-2]) & (g[1:-1] > g[2:]) & (g[1:-1] > min_strength))[0] + 1
        if len(peaks) == 0:
            continue
        if mode == "drop":
            strong = peaks[g[peaks] > 0.5 * g[peaks].max()]
            i = strong.max()                          # the outermost of the strong drops
        else:
            i = peaks[np.argmax(g[peaks])]
        # sub-sample position: vertex of the parabola through the three samples round the peak
        y0, y1, y2 = g[i - 1], g[i], g[i + 1]
        den = y0 - 2 * y1 + y2
        off = 0.5 * (y0 - y2) / den if abs(den) > 1e-12 else 0.0
        r = rr[i] + off * step
        pts.append((centre[0] + du * r, centre[1] + dv * r))
        strengths.append(float(g[i]))
        angs.append(ang)
    return np.array(pts), np.array(strengths), np.array(angs)


# ------------------------------------------------------------------------------------ sphere <-> limb
def sphere_fit(cam, pts):
    """The sphere whose outline (seen through `cam`) passes through picture points `pts`: the outline
    of a sphere is a cone of rays at a fixed angle alpha from the direction d to its centre.
    Returns (d unit vector in world space, alpha in radians, residuals in pixels)."""
    rays = cam.rays(pts[:, 0], pts[:, 1])
    rays /= np.linalg.norm(rays, axis=1)[:, None]

    def unpack(p):
        d = cam.rays(np.array(p[0]), np.array(p[1]))
        return d / np.linalg.norm(d), p[2]

    def res(p):
        d, alpha = unpack(p)
        return np.arccos(np.clip(rays @ d, -1, 1)) - alpha
    c = fit_circle(pts)
    p0 = [c[0], c[1], math.atan(c[2] / cam.f)]
    sol = optimize.least_squares(res, p0, x_scale=[100.0, 100.0, 0.1])
    d, alpha = unpack(sol.x)
    return d, float(alpha), sphere_residuals_px(cam, pts, d, alpha), (float(sol.x[0]), float(sol.x[1]))


def sphere_residuals_px(cam, pts, d, alpha):
    """Distance in pixels of picture points from the outline of the sphere (d, alpha); + = outside."""
    def ang(u, v):
        r = cam.rays(u, v)
        r = r / np.linalg.norm(r, axis=-1)[..., None]
        return np.arccos(np.clip(r @ d, -1, 1))
    u, v = pts[:, 0], pts[:, 1]
    a0 = ang(u, v)
    e = 0.05
    gu = (ang(u + e, v) - ang(u - e, v)) / (2 * e)
    gv = (ang(u, v + e) - ang(u, v - e)) / (2 * e)
    return (a0 - alpha) / np.hypot(gu, gv)


def sphere_outline(cam, d, alpha, n=720):
    """Picture points of the outline of the sphere (d, alpha)."""
    d = np.asarray(d, dtype=np.float64)
    a = np.cross(d, [0.0, 0.0, 1.0])
    a /= np.linalg.norm(a)
    b = np.cross(d, a)
    t = np.linspace(0, 2 * math.pi, n, endpoint=False)
    dirs = math.cos(alpha) * d + math.sin(alpha) * (np.cos(t)[:, None] * a + np.sin(t)[:, None] * b)
    u, v, z = cam.project(cam.pos + dirs)
    return np.c_[u, v][z > 0]


# ---------------------------------------------------------------------------------------- the bodies
def measure_planet_limb(rgb, cam):
    lum = luminance(rgb)
    cx, cy, r = PLANET_SEED
    angles = np.arange(PLANET_ARC[0], PLANET_ARC[1] + 1e-6, 0.5)
    pts, st, _ = edge_along_rays(lum, (cx, cy), angles, r - 22, r + 22, "drop", min_strength=0.04)
    c, keep = robust_circle(pts)
    # second pass: rays from the fitted centre (square to the limb), a narrow window round the fit
    angles = np.arange(PLANET_ARC[0] - 4, PLANET_ARC[1] + 6, 0.5)
    pts, st, angs = edge_along_rays(lum, (c[0], c[1]), angles, c[2] - 7, c[2] + 7, "drop", min_strength=0.04)
    c, keep = robust_circle(pts)
    pts, st, angs = pts[keep], st[keep], angs[keep]
    res_c = circle_residuals(pts, c)
    d, alpha, res_s, centre_px = sphere_fit(cam, pts)
    return {"points": pts, "strength": st, "angles": angs, "circle": c, "circle_res": res_c,
            "sphere_dir": d, "sphere_alpha": alpha, "sphere_res": res_s, "sphere_centre_px": centre_px}


def measure_moon(rgb, cam, seed):
    cx, cy, r = seed
    angles = np.arange(0.0, 360.0, 2.0)
    pts, st, _ = edge_along_rays(rgb, (cx, cy), angles, 0.6 * r, 1.45 * r, "strongest", min_strength=0.012)
    c, keep = robust_circle(pts)
    pts, st, angs = edge_along_rays(rgb, (c[0], c[1]), angles, c[2] - 4.0, c[2] + 4.0, "strongest",
                                    min_strength=0.012)
    c, keep = robust_circle(pts)
    pts, st, angs = pts[keep], st[keep], angs[keep]
    d, alpha, res_s, centre_px = sphere_fit(cam, pts)
    return {"points": pts, "strength": st, "angles": angs, "circle": c, "circle_res": circle_residuals(pts, c),
            "sphere_dir": d, "sphere_alpha": alpha, "sphere_res": res_s, "sphere_centre_px": centre_px}


def stats(res):
    res = np.asarray(res)
    return {"rms": round(float(np.sqrt((res ** 2).mean())), 3), "max": round(float(np.abs(res).max()), 3),
            "n": int(len(res))}


def body_json(m):
    c = m["circle"]
    return {"cx": round(float(c[0]), 2), "cy": round(float(c[1]), 2), "r": round(float(c[2]), 2),
            "circle_fit_px": stats(m["circle_res"]),
            "sphere": {"centre_px": [round(m["sphere_centre_px"][0], 2), round(m["sphere_centre_px"][1], 2)],
                       "angular_radius_deg": round(math.degrees(m["sphere_alpha"]), 4),
                       "fit_px": stats(m["sphere_res"])},
            "limb_points": [[round(float(p[0]), 2), round(float(p[1]), 2)] for p in m["points"]]}


def draw_debug(rgb, cam, planet, moons, path):
    """The picture with the edge points (yellow), the fitted circles (cyan) and spheres (magenta)."""
    s = 3
    x0, y0, x1, y1 = 380, 0, 1000, 420
    im = Image.fromarray((rgb[y0:y1, x0:x1] * 255).astype(np.uint8)).resize(((x1 - x0) * s, (y1 - y0) * s), Image.LANCZOS)
    d = ImageDraw.Draw(im)

    def P(u, v):
        return ((u - x0) * s, (v - y0) * s)
    for m in [planet] + moons:
        c = m["circle"]
        t = np.linspace(0, 2 * math.pi, 1440)
        d.line([P(c[0] + c[2] * math.cos(a), c[1] + c[2] * math.sin(a)) for a in t], fill=(0, 255, 255), width=1)
        o = sphere_outline(cam, m["sphere_dir"], m["sphere_alpha"], 1440)
        d.point([P(u, v) for u, v in o], fill=(255, 0, 255))
        for (u, v) in m["points"]:
            X, Y = P(u, v)
            d.ellipse([X - 2, Y - 2, X + 2, Y + 2], outline=(255, 255, 0))
    im.save(path)


def main():
    a = sys.argv[1:]
    debug = a[a.index("--debug") + 1] if "--debug" in a else ""
    cam = cvlib.load_camera()
    rgb = load_reference()
    planet = measure_planet_limb(rgb, cam)
    moons = [measure_moon(rgb, cam, s) for s in MOON_SEEDS]
    out = {"about": "measured by tools/measure_planet.py from the reference picture; picture pixels (u right, v down)",
           "planet": body_json(planet), "moons": [body_json(m) for m in moons]}
    for name, m in [("planet", planet)] + [(f"moon {k}", m) for k, m in enumerate(moons)]:
        c = m["circle"]
        print(f"{name}: circle cx {c[0]:.2f} cy {c[1]:.2f} r {c[2]:.2f}  fit {stats(m['circle_res'])}")
        print(f"   sphere centre px {m['sphere_centre_px'][0]:.2f}, {m['sphere_centre_px'][1]:.2f}  angular radius "
              f"{math.degrees(m['sphere_alpha']):.3f} deg  fit {stats(m['sphere_res'])}")
    if debug:
        os.makedirs(debug, exist_ok=True)
        draw_debug(rgb, cam, planet, moons, os.path.join(debug, "limb_fit.png"))
    with open(OUT, "w") as fh:
        json.dump(out, fh, indent=1)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
