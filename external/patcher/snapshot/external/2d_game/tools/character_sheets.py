#!/usr/bin/env python3
"""Characters' pictures (SheetPuppet) from their labelled 8-view reference
sheets (two rows of four figures with angle labels, a legend panel on the left):
    pirate  external/images/npc_pirate_frame_1..4.png -> idle (rifle hanging),
            raise1 (across the body), raise2 (at the hip), aim
    player  external/images/player_on_foot_idle.png / _aim.png -> idle, aim
Writes art/<id>/<id>_<pose>_<dir>.png (no walk frames - SheetPuppet bobs and
sways them).

    python3 -I tools/character_sheets.py pirate|player

Each sheet is cut by tools/cut_sheet_views.py (frame 3's sheet has no legend
panel). The views: E = 270 deg, SE = 315, S = 0, SW = 45, W = E mirrored (the
sheets' 90 and 270 both face right), NW = 225, N = 180, NE = 135. Specks are
dropped (pieces under 0.2 % of the figure, apart from it); each frame is scaled
so its 8 views average HEIGHT px tall (the sheets are drawn at slightly different
scales - the hat and feet mustn't jump between frames).
"""
import os
import subprocess
import sys
import tempfile
from collections import deque

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMAGES = os.path.join(ROOT, "external", "images")
## Per character: its sheets in pose order [(sheet, pose, legend px - 0: no legend
## panel)], and views borrowed from another sheet {(sheet index, dir): sheet index}.
CHARACTERS = {
    "pirate": {
        "sheets": [("npc_pirate_frame_1.png", "idle", 140), ("npc_pirate_frame_2.png", "raise1", 140),
                   ("npc_pirate_frame_3.png", "raise2", 0), ("npc_pirate_frame_4.png", "aim", 140)],
        # Frame 2's back views (180, 135) are drawn without the hat - from behind the
        # rifle barely shows, so frame 3's (hat on) stand in.
        "borrow": {(1, "n"): 2, (1, "ne"): 2},
    },
    "player": {
        "sheets": [("player_on_foot_idle.png", "idle", 140), ("player_on_foot_aim.png", "aim", 140)],
        "borrow": {},
    },
}
VIEWS = {"e": (270, False), "se": (315, False), "s": (0, False), "sw": (45, False),
         "w": (270, True), "nw": (225, False), "n": (180, False), "ne": (135, False)}
HEIGHT = 255


def clean(im):
    """Only the figure: drop small pieces (specks) - its biggest piece and any
    piece of real size stay."""
    a = np.asarray(im)
    solid = a[:, :, 3] > 40
    h, w = solid.shape
    seen = np.zeros_like(solid)
    comps = []
    for y0, x0 in zip(*np.nonzero(solid)):
        if seen[y0, x0]:
            continue
        q = deque([(y0, x0)])
        seen[y0, x0] = True
        pix = []
        while q:
            y, x = q.popleft()
            pix.append((y, x))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < h and 0 <= xx < w and solid[yy, xx] and not seen[yy, xx]:
                        seen[yy, xx] = True
                        q.append((yy, xx))
        comps.append(pix)
    if not comps:
        return im
    total = sum(len(c) for c in comps)
    out = a.copy()
    for c in comps:
        if len(c) < 0.002 * total:
            # (and the soft edge round it)
            for y, x in c:
                out[max(0, y - 1):y + 2, max(0, x - 1):x + 2, 3] = 0
    return Image.fromarray(out)


def main():
    cid = sys.argv[1] if len(sys.argv) > 1 else ""
    if cid not in CHARACTERS:
        sys.exit("which character? " + " | ".join(CHARACTERS))
    conf = CHARACTERS[cid]
    out = os.path.join(ROOT, "art", cid)
    os.makedirs(out, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix="character_sheets_")
    cutter = os.path.join(ROOT, "tools", "cut_sheet_views.py")
    done = []                      # per sheet: {dir: the scaled picture}
    for f, (sheet, pose, legend) in enumerate(conf["sheets"]):
        d = os.path.join(tmp, str(f))
        os.makedirs(d)
        subprocess.run([sys.executable, "-I", cutter, os.path.join(IMAGES, sheet), d, "v", str(legend)],
                       check=True, stdout=subprocess.DEVNULL)
        views = {}
        for dr, (angle, mirror) in VIEWS.items():
            im = clean(Image.open(os.path.join(d, "v_%d.png" % angle)).convert("RGBA"))
            im = im.crop(im.getbbox())
            if mirror:
                im = im.transpose(Image.FLIP_LEFT_RIGHT)
            views[dr] = im
        k = HEIGHT / (sum(im.height for im in views.values()) / len(views))
        done.append({dr: im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)
                     for dr, im in views.items()})
    for (f, dr), g in conf["borrow"].items():
        done[f][dr] = done[g][dr]
    for f, (sheet, pose, legend) in enumerate(conf["sheets"]):
        for dr, im in done[f].items():
            im.save(os.path.join(out, "%s_%s_%s.png" % (cid, pose, dr)))
        print("%-7s %s" % (pose, " ".join("%s %dx%d" % (dr, v.width, v.height) for dr, v in done[f].items())))


if __name__ == "__main__":
    main()
