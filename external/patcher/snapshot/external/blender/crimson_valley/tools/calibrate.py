"""Turn the depth model's relative depth into distances, using the valley floor as the ruler.

  python -I calibrate.py <model depth.npy> <out dir> [--horizon 432] [--lens 24] [--cam-h 20] [--tag name]

How: the river and the valley floor lie (nearly) in one horizontal plane, z = 0. For a camera with a
known horizon row, the ray through picture row v meets that plane at a known depth. In every row below
the horizon the FARTHEST thing the picture shows is that floor (everything else stands on it, nearer),
so the per-row far envelope of the model's disparity, paired with the plane's true disparity for that
row, is a calibration curve: model value -> true disparity. It is monotone but not a straight line
(the model squeezes the far distance), so it is kept as a table and interpolated.

Writes into <out dir>:
  camera.json          the camera (see cvlib.Camera)
  depth_<tag>.npy      float32 (H, W): depth along the camera axis in metres; 0 = sky
  calib_<tag>.json     the curve (model value -> pixels below the horizon on the z = 0 plane)"""
import json
import os
import sys

import numpy as np
from scipy import ndimage as ndi

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cvlib  # noqa: E402


def main():
    a = sys.argv[1:]
    src, out = a[0], a[1]
    opt = {"--horizon": 432.0, "--lens": 24.0, "--cam-h": 20.0, "--tag": "main", "--far-px": 0.5}
    i = 2
    while i < len(a):
        opt[a[i]] = a[i + 1] if a[i] == "--tag" else float(a[i + 1])
        i += 2
    d = np.load(src).astype(np.float64)
    H, W = d.shape
    f = W * opt["--lens"] / 36.0
    pitch = float(np.arctan((H / 2 - opt["--horizon"]) / f))
    cam = cvlib.Camera(f=f, cx=W / 2, cy=H / 2, pitch=pitch, cam_h=opt["--cam-h"], w=W, h=H)

    sky_thr = 0.002 * float(np.percentile(d, 99.5))
    notsky = d > sky_thr
    # Far envelope per row (1st percentile of the non-sky values), from just under the horizon down.
    rows = np.arange(int(opt["--horizon"]) + 6, H - 4)
    env = np.full(len(rows), np.nan)
    for k, v in enumerate(rows):
        r = d[v][notsky[v]]
        if len(r) > 50:
            env[k] = np.percentile(r, 1.0)
    ok = np.isfinite(env)
    rows, env = rows[ok], env[ok]
    env = ndi.median_filter(env, size=9, mode="nearest")
    env = ndi.gaussian_filter1d(env, 4.0, mode="nearest")
    env = np.maximum.accumulate(env)                       # monotone: lower rows are nearer
    below = (rows + 0.5) - cam.horizon_v                   # pixels below the horizon = true disparity * f*h/cos
    # Table: model value -> pixels below the horizon. Below the first knot (the far distance the floor
    # does not reach) go linearly down to `far-px` at the sky threshold, so far ridges stay far apart.
    xs = np.concatenate([[sky_thr], env])
    ys = np.concatenate([[opt["--far-px"]], below])
    keep = np.concatenate([[True], np.diff(xs) > 1e-9])
    xs, ys = xs[keep], ys[keep]
    # Above the last knot (nearer than the lowest floor row): continue with the last slope.
    slope = (ys[-1] - ys[-40]) / (xs[-1] - xs[-40])
    px = np.interp(d, xs, ys)
    over = d > xs[-1]
    px[over] = ys[-1] + (d[over] - xs[-1]) * slope
    z = cam.f * cam.cam_h / (np.cos(cam.pitch) * np.maximum(px, 1e-6))
    z[~notsky] = 0.0
    os.makedirs(out, exist_ok=True)
    np.save(os.path.join(out, f"depth_{opt['--tag']}.npy"), z.astype(np.float32))
    with open(os.path.join(out, "camera.json"), "w") as fh:
        json.dump(cam.to_dict(), fh, indent=1)
    with open(os.path.join(out, f"calib_{opt['--tag']}.json"), "w") as fh:
        json.dump({"sky_threshold": sky_thr, "model_value": [float(x) for x in xs[::8]],
                   "px_below_horizon": [float(y) for y in ys[::8]], "near_slope": float(slope)}, fh)
    print("camera", json.dumps(cam.to_dict()))
    print("sky threshold", sky_thr, "sky fraction", round(float((~notsky).mean()), 4))
    zz = z[notsky]
    print("depth percentiles (m):", [round(float(np.percentile(zz, p)), 1) for p in (0, 1, 5, 25, 50, 75, 95, 99, 100)])
    for (u, v, name) in [(1560, 880, "water bottom right"), (1150, 620, "river mid"), (1000, 555, "river far"),
                         (1080, 480, "big arch pillar"), (600, 300, "mid spires"), (300, 330, "far-left spires"),
                         (800, 405, "far mountains"), (1560, 150, "right tower"), (300, 250, "left arch inner wall"),
                         (600, 700, "foreground boulder"), (300, 880, "foreground slab"), (1500, 620, "waterfall cliff"),
                         (700, 500, "mid ridge"), (1250, 290, "city deck"), (1100, 850, "outcrop bottom right")]:
        p = cam.unproject(u, v, z[v, u])
        print(f"  {name:22s} ({u:4d},{v:3d}) depth {z[v, u]:8.1f} m  world x {p[0]:8.1f} y {p[1]:8.1f} z {p[2]:7.1f}")


if __name__ == "__main__":
    main()
