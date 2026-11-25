"""Final analysis products of the reference picture, written into analysis/.

  python -I analyze.py <raw dir> [--water water_mask.png]

<raw dir> holds the depth models' outputs (depth_estimate.py): depth_dav2s.npy (the detail map) and
depth_dav1l.npy (the second opinion). Steps: calibrate both against the valley floor (calibrate.py),
fuse them (fuse_depth.py), then:

  camera.json     the camera (cvlib.Camera)
  depth.npy       float32 (941, 1672): metres along the camera axis, 0 = sky. Nothing below the
                  horizon is farther than the z = 0 plane; nothing is farther than FAR.
  height.npy      world z of every land pixel (NaN in the sky)
  sky.png         255 = sky (the planet, moons and clouds are sky)
  floor.png       255 = valley floor (low, near z = 0): the river, its banks, the plain
  water.png       255 = water (river and ponds; from sam_mask.py, cleaned)
  veg.png         0..255 red vegetation cover (from colour)
  moss.png        0..255 yellow-green moss / lichen on rock tops (from colour)
  mist.png        0..255 pale mist and waterfall spray (from colour and softness)
  overview.png    the masks drawn over the picture, to check them
"""
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image
from scipy import ndimage as ndi
from skimage import color

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import cvlib  # noqa: E402

FAR = 9000.0          # the farthest any land is put (m)
MIN_HEIGHT = -0.3     # land below the horizon is not put under this height (m)


def run(*args):
    subprocess.run([sys.executable, "-I", *args], check=True)


def save_mask(name, m):
    a = (np.clip(m, 0, 1) * 255).astype(np.uint8) if m.dtype != np.bool_ else (m * 255).astype(np.uint8)
    Image.fromarray(a).save(os.path.join(cvlib.ANALYSIS, name))


def main():
    a = sys.argv[1:]
    raw = a[0]
    water_src = a[a.index("--water") + 1] if "--water" in a else os.path.join(cvlib.ANALYSIS, "water.png")
    os.makedirs(cvlib.ANALYSIS, exist_ok=True)
    tmp = os.path.join(raw, "calibrated")
    run(os.path.join(HERE, "calibrate.py"), os.path.join(raw, "depth_dav2s.npy"), tmp, "--tag", "v2s")
    run(os.path.join(HERE, "calibrate.py"), os.path.join(raw, "depth_dav1l.npy"), tmp, "--tag", "v1l")
    run(os.path.join(HERE, "fuse_depth.py"), os.path.join(tmp, "depth_v2s.npy"), os.path.join(tmp, "depth_v1l.npy"),
        os.path.join(tmp, "depth_fused.npy"), "--weight", "0.5")
    with open(os.path.join(tmp, "camera.json")) as fh:
        cam = cvlib.Camera(**json.load(fh))
    z = np.load(os.path.join(tmp, "depth_fused.npy")).astype(np.float64)
    H, W = z.shape
    u, v = cvlib.pixel_grid(W, H)

    # --- sky: the detail model's zero, minus specks; the two moons are sky -----------------------
    land = z > 0
    lab, n = ndi.label(land)
    sizes = ndi.sum(land, lab, range(1, n + 1))
    land = lab == (1 + int(np.argmax(sizes)))                       # the one big piece of land
    holes, nh = ndi.label(~land)                                     # pinholes in the land -> land
    hs = ndi.sum(~land, holes, range(1, nh + 1))
    for i in np.nonzero(hs < 40)[0]:
        land |= holes == i + 1
    # Land that the specks rule added needs a depth: nearest valid one.
    need = land & ~(z > 0)
    if need.any():
        idx = ndi.distance_transform_edt(~(z > 0), return_distances=False, return_indices=True)
        z[need] = z[idx[0][need], idx[1][need]]
    z[~land] = 0.0

    # --- depth limits ---------------------------------------------------------------------------
    zmax_plane = cam.ground_z(v, MIN_HEIGHT)                         # inf above the horizon
    z = np.where(land, np.minimum(np.minimum(z, zmax_plane), FAR), 0.0)
    p = cam.unproject(u, v, np.where(land, z, 1.0))
    height = np.where(land, p[..., 2], np.nan)
    rng = np.hypot(p[..., 0], p[..., 1])

    # --- valley floor: low land -----------------------------------------------------------------
    floor = land & (np.nan_to_num(height, nan=1e9) < 2.5 + 0.012 * rng)
    floor = ndi.binary_opening(floor, iterations=2)
    fl, nf = ndi.label(floor)
    fs = ndi.sum(floor, fl, range(1, nf + 1))
    floor = np.isin(fl, 1 + np.nonzero(fs > 400)[0])                 # no specks of "floor" on rocks
    floor &= v > cam.horizon_v + 1

    # --- water (SAM), cleaned -------------------------------------------------------------------
    water = np.asarray(Image.open(water_src).convert("L")) > 127
    water &= land & (v > cam.horizon_v + 20)
    water = ndi.binary_opening(water, iterations=1)
    wl, nw = ndi.label(water)
    ws = ndi.sum(water, wl, range(1, nw + 1))
    water = np.isin(wl, 1 + np.nonzero(ws > 90)[0])
    floor |= water

    # --- colour classes -------------------------------------------------------------------------
    ref = np.asarray(Image.open(cvlib.REFERENCE).convert("RGB")).astype(np.float32) / 255
    labc = color.rgb2lab(ref)
    L, A, B = labc[..., 0], labc[..., 1], labc[..., 2]
    chroma = np.hypot(A, B)
    hue = np.degrees(np.arctan2(B, A))
    # red plants: strongly red, hue between magenta-red and red-orange (sunlit rock is orange: hue > 45)
    veg = np.clip((A - 9) / 14, 0, 1) * np.clip((47 - hue) / 9, 0, 1) * np.clip((hue + 15) / 10, 0, 1)
    veg = np.where(land & ~water, veg, 0.0)
    veg = ndi.gaussian_filter(veg, 0.7)
    # moss: yellow-green, on land
    moss = np.clip((chroma - 18) / 12, 0, 1) * np.clip((hue - 72) / 8, 0, 1) * np.clip((125 - hue) / 10, 0, 1)
    moss = np.where(land & ~water, ndi.gaussian_filter(moss, 0.7), 0.0)
    # mist: pale, colourless, soft (little local contrast), on land and not water
    soft = ndi.gaussian_filter(np.abs(L - ndi.gaussian_filter(L, 3.0)), 4.0)
    mist = np.clip((L - 52) / 14, 0, 1) * np.clip((16 - chroma) / 8, 0, 1) * np.clip((4.5 - soft) / 2.0, 0, 1)
    mist = np.where(land & ~water, ndi.gaussian_filter(mist, 2.0), 0.0)

    np.save(os.path.join(cvlib.ANALYSIS, "depth.npy"), z.astype(np.float32))
    np.save(os.path.join(cvlib.ANALYSIS, "height.npy"), height.astype(np.float32))
    with open(os.path.join(cvlib.ANALYSIS, "camera.json"), "w") as fh:
        json.dump(cam.to_dict(), fh, indent=1)
    save_mask("sky.png", ~land)
    save_mask("floor.png", floor)
    save_mask("water.png", water)
    save_mask("veg.png", veg)
    save_mask("moss.png", moss)
    save_mask("mist.png", mist)

    ov = ref * 255
    ov[~land] = ov[~land] * 0.5 + np.array([60, 90, 200]) * 0.5
    fo = floor & ~water
    ov[fo] = ov[fo] * 0.6 + np.array([0, 200, 255]) * 0.4
    ov[water] = ov[water] * 0.35 + np.array([0, 60, 255]) * 0.65
    ov = ov * (1 - 0.6 * veg[..., None]) + np.array([255, 0, 200]) * 0.6 * veg[..., None]
    ov = ov * (1 - 0.7 * moss[..., None]) + np.array([255, 255, 0]) * 0.7 * moss[..., None]
    ov = ov * (1 - 0.7 * mist[..., None]) + np.array([255, 255, 255]) * 0.7 * mist[..., None]
    Image.fromarray(np.clip(ov, 0, 255).astype(np.uint8)).save(os.path.join(cvlib.ANALYSIS, "overview.png"))
    print("land", round(float(land.mean()), 3), "floor", round(float(floor.mean()), 3), "water", round(float(water.mean()), 4),
          "veg", round(float(veg.mean()), 4), "moss", round(float(moss.mean()), 4), "mist", round(float(mist.mean()), 4))
    print("depth percentiles (m):", [round(float(np.percentile(z[land], q)), 1) for q in (0, 5, 25, 50, 75, 95, 100)])
    print("height percentiles (m):", [round(float(np.nanpercentile(height, q)), 1) for q in (0, 5, 25, 50, 75, 95, 100)])


if __name__ == "__main__":
    main()
