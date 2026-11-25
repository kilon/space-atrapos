#!/usr/bin/env python3
"""Screenshots of the game for the guide, the tutorial and the encyclopedia.

The shots are listed in data/docs/shots.json (a caption, the files each one
shows, and its notes - an infographic drawn over it). This takes them in a
game window (tests/doc_shots.gd sets each moment up), draws the notes, and
saves data/docs/shots/<id>.jpg (1280 x 720) with a manifest of what each was
taken from - test_doc_shots fails when a shot is older than the files it shows.

  python3 tools/doc_shots.py            every shot
  python3 tools/doc_shots.py ID ...     just these
  python3 tools/doc_shots.py --stale    only the out-of-date ones (and missing)
  python3 tools/doc_shots.py --notes    redraw the notes only, from the raw shots
                                        kept in external/doc_shots_raw/

Pages show a shot where their text has  ![caption](shot:id)  (DocPictures).
"""
import hashlib, json, os, subprocess, sys, tempfile, time
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = os.path.join(ROOT, "data", "docs", "shots.json")
OUT = os.path.join(ROOT, "data", "docs", "shots")
RAW = os.path.join(ROOT, "external", "doc_shots_raw")
MANIFEST = os.path.join(OUT, "manifest.json")
FONT = os.path.join(ROOT, "assets", "fonts", "AtraposSans-Bold.ttf")
SIZE = (1280, 720)
AMBER = (255, 176, 64, 255)
INK = (255, 238, 205, 255)
PANEL = (16, 11, 6, 232)
DARK = (20, 12, 4, 255)


def load():
    return json.load(open(SHOTS))["shots"]


def sources_hash(srcs):
    h = hashlib.md5()
    for s in srcs:
        p = os.path.join(ROOT, s)
        h.update(s.encode())
        h.update(open(p, "rb").read() if os.path.exists(p) else b"-")
    return h.hexdigest()


def manifest():
    return json.load(open(MANIFEST)) if os.path.exists(MANIFEST) else {}


def stale(shots):
    m = manifest()
    return [k for k, v in shots.items()
            if m.get(k, {}).get("hash") != sources_hash(v["sources"]) or not os.path.exists(os.path.join(OUT, k + ".jpg"))]


def capture(ids):
    os.makedirs(RAW, exist_ok=True)
    with tempfile.TemporaryDirectory() as xdg:   # (the game's own user data, untouched)
        env = dict(os.environ, XDG_DATA_HOME=xdg)
        cmd = ["godot", "--path", ROOT, "--resolution", "1920x1080", "--position", "0,30", "-s", "tests/doc_shots.gd",
               "--"] + ids + ["--mute", "--bot", "--no-live", "--window-at=0,30", "--out=" + RAW]
        out = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=900).stdout
    done = []
    for line in out.splitlines():
        if line.startswith("DOC SHOTS: "):
            done = [x for x in line[len("DOC SHOTS: "):].split(",") if x]
    return done


def _font(size):
    return ImageFont.truetype(FONT, size)


def _arrow(d, a, b):
    d.line([a, b], fill=AMBER, width=5)
    r = 10
    d.ellipse([b[0] - r, b[1] - r, b[0] + r, b[1] + r], fill=AMBER, outline=DARK, width=3)


def _edge_point(box, to):
    """The point on the box's edge nearest `to` (where the arrow leaves)."""
    x0, y0, x1, y1 = box
    return (min(max(to[0], x0), x1), min(max(to[1], y0), y1))


def annotate(sid, shot):
    raw = Image.open(os.path.join(RAW, sid + ".png")).convert("RGBA")
    over = Image.new("RGBA", raw.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    f = _font(30)
    for n in shot.get("notes", []):
        t = n.get("t")
        if t == "box":
            x, y, w, h = n["rect"]
            d.rounded_rectangle([x, y, x + w, y + h], radius=10, outline=AMBER, width=5)
        elif t == "step":
            x, y = n["at"]
            r = 26
            d.ellipse([x - r, y - r, x + r, y + r], fill=AMBER, outline=DARK, width=3)
            d.text((x, y), str(n["n"]), font=_font(30), fill=DARK, anchor="mm")
        elif t == "label":
            x, y = n["at"]
            tw = d.textbbox((0, 0), n["text"], font=f)
            w, h = tw[2] - tw[0] + 32, tw[3] - tw[1] + 22
            x = min(max(x, 8), raw.size[0] - w - 8)   # (on the picture)
            y = min(max(y, 8), raw.size[1] - h - 8)
            box = (x, y, x + w, y + h)
            if "to" in n:
                _arrow(d, _edge_point(box, n["to"]), tuple(n["to"]))
            d.rounded_rectangle(box, radius=10, fill=PANEL, outline=AMBER, width=4)
            d.text((x + 16, y + 9 - tw[1]), n["text"], font=f, fill=INK)
    img = Image.alpha_composite(raw, over).convert("RGB").resize(SIZE, Image.LANCZOS)
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, sid + ".jpg"), quality=88, optimize=True)


def main():
    args = sys.argv[1:]
    shots = load()
    notes_only = "--notes" in args
    if "--stale" in args:
        ids = stale(shots)
    else:
        ids = [a for a in args if not a.startswith("--")] or list(shots)
    unknown = [i for i in ids if i not in shots]
    if unknown:
        sys.exit("unknown shots: " + ", ".join(unknown))
    if not ids:
        print("every shot is up to date")
        return
    if not notes_only:
        print("taking %d shot(s) in a game window..." % len(ids))
        done = capture(ids)
        missing = [i for i in ids if i not in done]
        if missing:
            print("NOT taken (see tests/doc_shots.gd): " + ", ".join(missing))
        ids = [i for i in ids if i in done]
    m = manifest()
    for sid in ids:
        annotate(sid, shots[sid])
        if not notes_only:
            m[sid] = {"hash": sources_hash(shots[sid]["sources"]), "taken": time.strftime("%Y-%m-%d %H:%M")}
        print("  %s.jpg" % sid)
    json.dump(m, open(MANIFEST, "w"), indent=1, sort_keys=True)
    # (Godot imports the pictures, so the game can show them)
    subprocess.run(["godot", "--headless", "--path", ROOT, "--import"], capture_output=True, timeout=600)
    print("done: %d shot(s) in data/docs/shots/" % len(ids))


if __name__ == "__main__":
    main()
