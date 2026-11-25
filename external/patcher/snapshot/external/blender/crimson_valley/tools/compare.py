"""Compare a render with the reference picture: a side-by-side image and numbers.

  python -I compare.py <render.png> <out.png> [--region x0 y0 x1 y1] [--mask sky|land|floor|water|<file.png>]
                       [--zoom 1.0] [--label text]

The render may be any size with the picture's aspect (a half-size preview is fine): it is resized to
1672 x 941 first, and --region is in the reference's pixels. The output shows reference | render |
difference (brighter = more different; the masked-out area dimmed). Numbers printed (inside the region
and the mask):
  dE        mean colour difference (CIE76 in Lab; ~2 is barely visible, 10 clearly different, 25+ wrong)
  dL        mean lightness of the render minus the reference (+ = render brighter), Lab L 0..100
  dC        mean chroma of the render minus the reference (+ = render more saturated)
  hue       mean hue angle of each (degrees, for colours with some chroma)
  ssim      structural similarity of the lightness (1 = identical structure), at 1/2 size
  edges     how well outlines line up: correlation of the edge strength maps (1 = same edges)
  mean RGB  of each, 0..255"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as ndi
from skimage import color
from skimage.metrics import structural_similarity

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import cvlib  # noqa: E402


def load_mask(name):
    path = name if os.path.exists(name) else os.path.join(cvlib.ANALYSIS, name + ".png")
    if name == "land":
        return np.asarray(Image.open(os.path.join(cvlib.ANALYSIS, "sky.png")).convert("L")) < 128
    return np.asarray(Image.open(path).convert("L").resize((cvlib.W, cvlib.H), Image.NEAREST)) > 127


def metrics(ref, ren, mask):
    """ref, ren float RGB 0..1 (h, w, 3); mask bool (h, w)."""
    la, lb = color.rgb2lab(ref), color.rgb2lab(ren)
    m = mask if mask.any() else np.ones(mask.shape, bool)
    de = np.sqrt(((la - lb) ** 2).sum(-1))
    ca, cb = np.hypot(la[..., 1], la[..., 2]), np.hypot(lb[..., 1], lb[..., 2])

    def hue(l, c):
        k = m & (c > 8)
        if not k.any():
            return float("nan")
        return float(np.degrees(np.arctan2(l[..., 2][k].mean(), l[..., 1][k].mean())))
    out = {"dE": float(de[m].mean()), "dL": float((lb[..., 0] - la[..., 0])[m].mean()),
           "dC": float((cb - ca)[m].mean()), "hue_ref": hue(la, ca), "hue_render": hue(lb, cb),
           "L_ref": float(la[..., 0][m].mean()), "L_render": float(lb[..., 0][m].mean()),
           "rgb_ref": [int(round(255 * ref[..., i][m].mean())) for i in range(3)],
           "rgb_render": [int(round(255 * ren[..., i][m].mean())) for i in range(3)]}
    h, w = mask.shape
    if h >= 16 and w >= 16:
        a = ndi.zoom(la[..., 0], 0.5, order=1) if min(h, w) >= 32 else la[..., 0]
        b = ndi.zoom(lb[..., 0], 0.5, order=1) if min(h, w) >= 32 else lb[..., 0]
        win = min(7, (min(a.shape) // 2) * 2 - 1)
        out["ssim"] = float(structural_similarity(a, b, data_range=100.0, win_size=max(3, win)))
        ea = ndi.gaussian_gradient_magnitude(la[..., 0], 1.2)
        eb = ndi.gaussian_gradient_magnitude(lb[..., 0], 1.2)
        if ea[m].std() > 1e-6 and eb[m].std() > 1e-6:
            out["edges"] = float(np.corrcoef(ea[m], eb[m])[0, 1])
    return out, de


def main():
    a = sys.argv[1:]
    src, out = a[0], a[1]
    region, mask_name, zoom, label = None, None, 1.0, ""
    i = 2
    while i < len(a):
        if a[i] == "--region":
            region = [int(v) for v in a[i + 1:i + 5]]
            i += 5
        elif a[i] == "--mask":
            mask_name = a[i + 1]
            i += 2
        elif a[i] == "--zoom":
            zoom = float(a[i + 1])
            i += 2
        elif a[i] == "--label":
            label = a[i + 1]
            i += 2
        else:
            i += 1
    ref = Image.open(cvlib.REFERENCE).convert("RGB")
    ren = Image.open(src).convert("RGB")
    if ren.size != ref.size:
        ren = ren.resize(ref.size, Image.LANCZOS)
    x0, y0, x1, y1 = region or (0, 0, cvlib.W, cvlib.H)
    mask = load_mask(mask_name) if mask_name else np.ones((cvlib.H, cvlib.W), bool)
    r = np.asarray(ref).astype(np.float32)[y0:y1, x0:x1] / 255
    n = np.asarray(ren).astype(np.float32)[y0:y1, x0:x1] / 255
    mk = mask[y0:y1, x0:x1]
    m, de = metrics(r, n, mk)
    diff = np.clip(de / 60.0, 0, 1)[..., None] * np.array([1.0, 0.9, 0.3])
    diff = np.where(mk[..., None], diff, diff * 0.25)
    tiles = [r, n, diff]
    names = ["reference", "render", "difference"]
    w, h = x1 - x0, y1 - y0
    s = zoom if zoom != 1.0 else min(1.0, 1900 / (3 * w))
    tw, th = max(1, int(w * s)), max(1, int(h * s))
    sheet = Image.new("RGB", (tw * 3 + 8, th + 22), (20, 20, 20))
    d = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("/usr/share/fonts/TTF/DejaVuSans.ttf", 14)
    except OSError:
        font = ImageFont.load_default()
    for k, (t, nm) in enumerate(zip(tiles, names)):
        im = Image.fromarray((np.clip(t, 0, 1) * 255).astype(np.uint8)).resize((tw, th), Image.LANCZOS)
        sheet.paste(im, (k * (tw + 4), 22))
        d.text((k * (tw + 4) + 4, 3), nm + (("  " + label) if label and k == 1 else ""), fill=(255, 255, 255), font=font)
    sheet.save(out)
    print(f"region {x0},{y0} - {x1},{y1}  mask {mask_name or 'none'} ({int(mk.sum())} px)")
    print("  dE {dE:.1f}   dL {dL:+.1f} (L ref {L_ref:.1f}, render {L_render:.1f})   dC {dC:+.1f}   hue ref {hue_ref:.0f} render {hue_render:.0f}".format(**m))
    print("  ssim {:.3f}   edges {:.3f}   mean RGB ref {} render {}".format(m.get("ssim", float("nan")), m.get("edges", float("nan")), m["rgb_ref"], m["rgb_render"]))
    print("  wrote", out)


if __name__ == "__main__":
    main()
