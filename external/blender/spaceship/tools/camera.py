"""The reference picture's camera, worked out from its two lift fans:  python -I camera.py fit | at <px> <py> <axis> <value> ...

The fans are two equal circles (radius FAN_R, level, either side of the centre line), so the way the
picture squashes and sizes them fixes where the camera is. `fit` solves for it and writes camera.json
(the ship's frame: x forward, y to port, z up, the origin midway between the fans' centres).
`at px py axis value` tells where the picture's pixel (px, py) is on the plane axis = value (e.g.
"at 1745 765 y 0" = the nose tip, on the centre plane) - how the ship's sizes are read off the picture."""
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "camera.json")
W, H = 1774, 887
FAN_R = 2.6
# the top lip of each fan's ring in the picture: its leftmost and rightmost points, its top and bottom rows
NEAR = dict(left=(341, 404), right=(633, 396), top=340, bottom=450)       # the starboard fan (y < 0)
FAR = dict(left=(934, 228), right=(1160, 258), top=211, bottom=282)


def basis(p):
    az, el, dist, tx, ty, tz, f, roll = p[:8]
    t = np.array([tx, ty, tz])
    c = t + dist * np.array([math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el)])
    fw = (t - c) / np.linalg.norm(t - c)
    right = np.cross(fw, [0, 0, 1.0])
    right /= np.linalg.norm(right)
    up = np.cross(right, fw)
    r2 = right * math.cos(roll) + up * math.sin(roll)
    u2 = -right * math.sin(roll) + up * math.cos(roll)
    return c, fw, r2, u2, f


def project(p, pts):
    c, fw, right, up, f = basis(p)
    d = np.asarray(pts, float) - c
    z = d @ fw
    return np.stack([W / 2 + f * (d @ right) / z, H / 2 - f * (d @ up) / z], axis=1)


def circle(y, n=180):
    a = np.linspace(0, 2 * math.pi, n, endpoint=False)
    return np.stack([FAN_R * np.cos(a), y + FAN_R * np.sin(a), np.zeros(n)], axis=1)


def residual(p):
    out = []
    for obs, y in ((NEAR, -p[8]), (FAR, p[8])):
        q = project(p, circle(y))
        i, j = q[:, 0].argmin(), q[:, 0].argmax()
        out += [q[i, 0] - obs["left"][0], q[i, 1] - obs["left"][1], q[j, 0] - obs["right"][0], q[j, 1] - obs["right"][1],
                q[:, 1].min() - obs["top"], q[:, 1].max() - obs["bottom"]]
    return np.array(out)


def fit():
    from scipy.optimize import least_squares
    p0 = [math.radians(-45), math.radians(24), 38.0, 2.0, 0.0, 0.0, 1500.0, 0.0, 5.5]
    r = least_squares(residual, p0, x_scale=[0.1, 0.1, 5, 1, 1, 1, 200, 0.05, 1])
    p = r.x
    c, fw, right, up, f = basis(p)
    print("residuals (px):", np.round(r.fun, 1))
    print("azimuth %.1f, elevation %.1f, distance %.1f, focal %.0f px (lens %.1f mm), roll %.2f, fans at y = +-%.2f"
          % (math.degrees(p[0]), math.degrees(p[1]), p[2], p[6], p[6] * 36 / W, math.degrees(p[7]), p[8]))
    with open(OUT, "w") as fh:
        json.dump(dict(params=list(map(float, p)), location=list(map(float, c)), forward=list(map(float, fw)), up=list(map(float, up)),
                       lens=float(p[6] * 36 / W), fan_y=float(p[8]), fan_r=FAN_R, size=[W, H]), fh, indent=1)


def at(px, py, axis, value):
    with open(OUT) as fh:
        p = json.load(fh)["params"]
    c, fw, right, up, f = basis(p)
    d = fw + right * ((px - W / 2) / f) + up * ((H / 2 - py) / f)
    k = "xyz".index(axis)
    t = (value - c[k]) / d[k]
    return c + d * t


if __name__ == "__main__":
    if sys.argv[1] == "fit":
        fit()
    elif sys.argv[1] == "at":
        a = sys.argv[2:]
        for i in range(0, len(a), 4):
            q = at(float(a[i]), float(a[i + 1]), a[i + 2], float(a[i + 3]))
            print("(%s, %s) on %s = %s:  x %.2f  y %.2f  z %.2f" % (a[i], a[i + 1], a[i + 2], a[i + 3], *q))


def rectify(axis, value, u_rng, v_rng, out, ppm=40):
    """The picture as it would look drawn flat on the plane axis = value (a plan for z, an elevation
    for y): out is a picture of the plane's other two axes over the given ranges, a line every metre."""
    from PIL import Image, ImageDraw
    ref = np.asarray(Image.open(os.path.join(os.path.dirname(HERE), "reference", "reference.png")).convert("RGBA")).astype(np.float32)
    with open(OUT) as fh:
        p = json.load(fh)["params"]
    k = "xyz".index(axis)
    ua, va = [i for i in range(3) if i != k]
    us = np.arange(u_rng[0], u_rng[1], 1.0 / ppm)
    vs = np.arange(v_rng[1], v_rng[0], -1.0 / ppm)
    uu, vv = np.meshgrid(us, vs)
    pts = np.zeros(uu.shape + (3,))
    pts[..., k], pts[..., ua], pts[..., va] = value, uu, vv
    q = project(p, pts.reshape(-1, 3)).reshape(uu.shape + (2,))
    xi, yi = np.round(q[..., 0]).astype(int), np.round(q[..., 1]).astype(int)
    ok = (xi >= 0) & (xi < W) & (yi >= 0) & (yi < H)
    img = np.zeros(uu.shape + (3,), np.float32) + 40
    px = ref[yi.clip(0, H - 1), xi.clip(0, W - 1)]
    a = px[..., 3:4] / 255 * ok[..., None]
    img = img * (1 - a) + px[..., :3] * a
    im = Image.fromarray(img.astype(np.uint8))
    d = ImageDraw.Draw(im, "RGBA")
    for u in range(int(math.ceil(u_rng[0])), int(u_rng[1]) + 1):
        X = (u - u_rng[0]) * ppm
        d.line([(X, 0), (X, im.height)], fill=(0, 255, 255, 160 if u % 5 == 0 else 50))
        if u % 5 == 0:
            d.text((X + 2, 2), "%s %d" % ("xyz"[ua], u), fill=(0, 255, 255, 255))
    for v in range(int(math.ceil(v_rng[0])), int(v_rng[1]) + 1):
        Y = (v_rng[1] - v) * ppm
        d.line([(0, Y), (im.width, Y)], fill=(0, 255, 255, 160 if v % 5 == 0 else 50))
        if v % 5 == 0:
            d.text((2, Y + 2), "%s %d" % ("xyz"[va], v), fill=(0, 255, 255, 255))
    im.save(out)


if __name__ == "__main__" and sys.argv[1] == "rectify":
    a = sys.argv[2:]
    rectify(a[0], float(a[1]), (float(a[2]), float(a[3])), (float(a[4]), float(a[5])), a[6], int(a[7]) if len(a) > 7 else 40)
