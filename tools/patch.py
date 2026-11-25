#!/usr/bin/env python3
"""Patch tracking for the Patcher (Talos > Patcher): everything changed since
the last published patch, and the code review for the next one.

The baseline is the game as it was at the last published patch:
  external/patcher/snapshot/   a copy of every tracked text file (scripts, scenes,
                       shaders, data, docs, tests, tools, project.godot)
  external/patcher/manifest.json  {"patch", "date", "files": {path: md5}, "mtimes":
                       {path: modified time}} for every tracked file, art and
                       sounds included (the Patcher reads it too)
Changes are found by comparing the project with it - however they were made.
external/patcher/pending.md is the plain-language log of what changed and why.

  python3 tools/patch.py status
      What changed since the last patch: modified / new / deleted files
      (text files with lines added and removed).
  python3 tools/patch.py notes-template <notes.json>
      A notes file to fill in: one entry per changed text file, one
      [title, note] per hunk (with the hunk's header to see which is which).
      A hunk can also get explanation bubbles - [title, note, [[at, text]...]]:
      each points at the first diff line containing `at` (added lines first)
      and explains how that part of the code works (the Patcher draws them
      beside the code, with an arrow). Give the code's key parts bubbles.
  python3 tools/patch.py review <notes.json> data/patches/<id>_<name>.json
      Adds the code review (diffs against the snapshot, each hunk with its
      note) to a patch entry. Changed art / sounds are listed without diffs.
  python3 tools/patch.py baseline <patch id>
      After publishing a patch: it joins the open version (the version file
      with "open": true, else the newest - a page for it, its line in the
      summary; see assign_to_version); then the project as it is now becomes
      the new baseline; pending.md is archived as history/<id>.md and emptied.

Run from the project folder.
"""
import datetime, difflib, hashlib, json, os, shutil, sys

ROOT = "."
TRACK = os.path.join("external", "patcher")
SNAP = os.path.join(TRACK, "snapshot")
MANIFEST = os.path.join(TRACK, "manifest.json")
PENDING = os.path.join(TRACK, "pending.md")
TEXT = (".gd", ".tscn", ".tres", ".gdshader", ".gdshaderinc", ".json", ".md", ".cfg", ".py", ".godot", ".txt", ".svg")
BINARY = (".png", ".jpg", ".jpeg", ".webp", ".wav", ".ogg", ".mp3", ".ttf", ".otf")
SKIP_DIRS = {".godot", ".git", ".import", "__pycache__"}
ROOT_SKIP = {"build", "export"}   # (build outputs - only at the project's root: scripts/world/build is code)
SKIP_PATHS = {os.path.join("external", "patcher")}   # (the tracking itself)
# Folders of intermediate files, not changes in themselves: raw renders (rebuilt
# from the .blend in minutes) and backups of replaced art.
SKIP_NAMES = {"renders", "previous_art"}


def tracked():
    """Every tracked file (relative paths): text and binary assets."""
    out = []
    for root, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.startswith(".")
                   and not (d in ROOT_SKIP and os.path.samefile(root, ROOT))
                   and not (d in SKIP_NAMES and os.path.relpath(root, ROOT).startswith("external"))
                   and os.path.relpath(os.path.join(root, d), ROOT) not in SKIP_PATHS]
        for f in files:
            if f.endswith(TEXT + BINARY) and not f.endswith(".import"):
                out.append(os.path.relpath(os.path.join(root, f), ROOT))
    return sorted(out)


def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def is_text(path):
    return path.endswith(TEXT)


def lines(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read().splitlines()


def changes():
    """[(path, "modified" / "new" / "deleted")] since the baseline."""
    man = json.load(open(MANIFEST))["files"]
    now = tracked()
    out = []
    for p in now:
        if p not in man:
            if p.startswith("data/patches/"):
                continue   # (a patch entry being written is the publication, not a change)
            out.append((p, "new"))
        elif md5(p) != man[p]:
            out.append((p, "modified"))
    for p in man:
        if p not in now:
            out.append((p, "deleted"))
    return sorted(out)


def old_lines(path):
    snap = os.path.join(SNAP, path)
    return lines(snap) if os.path.exists(snap) else []


def hunks(old, new):
    out = []
    for g in difflib.SequenceMatcher(None, old, new, autojunk=False).get_grouped_opcodes(3):
        i1, i2, j1, j2 = g[0][1], g[-1][2], g[0][3], g[-1][4]
        ctx = ""
        for l in range(min(j1, len(new) - 1), -1, -1):
            if new[l].startswith(("func ", "class ", "static func ", "# ", "## ")):
                ctx = new[l].split("(")[0][:60]
                break
        head = ["@@ -%d,%d +%d,%d @@ %s" % (i1 + 1, i2 - i1, j1 + 1, j2 - j1, ctx)]
        body, add, rem = [], 0, 0
        for t, a1, a2, b1, b2 in g:
            if t == "equal":
                body += [" " + l for l in old[a1:a2]]
            if t in ("delete", "replace"):
                body += ["-" + l for l in old[a1:a2]]
                rem += a2 - a1
            if t in ("insert", "replace"):
                body += ["+" + l for l in new[b1:b2]]
                add += b2 - b1
        out.append({"diff": "\n".join(head + body), "added": add, "removed": rem})
    return out


def file_hunks(path, kind):
    if not is_text(path):
        return []
    new = [] if kind == "deleted" else lines(path)
    return hunks(old_lines(path), new)


def cmd_status():
    man = json.load(open(MANIFEST))
    ch = changes()
    print("Changes since patch %s (%s): %d files" % (man.get("patch"), man.get("date"), len(ch)))
    for p, kind in ch:
        if is_text(p):
            hs = file_hunks(p, kind)
            print("  %-9s %-55s +%d -%d" % (kind, p, sum(h["added"] for h in hs), sum(h["removed"] for h in hs)))
        else:
            print("  %-9s %s" % (kind, p))
    if os.path.exists(PENDING):
        sections = [l for l in lines(PENDING) if l.startswith("## ")]
        print("pending.md: %d logged change(s)%s" % (len(sections), "".join("\n  " + s[3:] for s in sections)))


def cmd_notes_template(out):
    notes = {"_intro": "", "_assets": ""}
    for p, kind in changes():
        hs = file_hunks(p, kind)
        notes[p] = {"kind": kind, "explanation": "",
                    "hunks": [[h["diff"].split("\n")[0], ""] for h in hs]}
    json.dump(notes, open(out, "w"), indent=1)
    print("wrote", out, "-", sum(len(v["hunks"]) for k, v in notes.items() if not k.startswith("_")), "hunks to describe")


def cmd_review(notes_path, patch_path):
    notes = json.load(open(notes_path))
    files = []
    for p, kind in changes():
        hs = file_hunks(p, kind)
        meta = notes.get(p)
        if meta is None or not meta.get("explanation"):
            sys.exit("%s (%s): no explanation in the notes" % (p, kind))
        if len(meta.get("hunks", [])) != len(hs):
            sys.exit("%s: %d notes for %d hunks" % (p, len(meta.get("hunks", [])), len(hs)))
        for h, n in zip(hs, meta["hunks"]):
            if not n[0] or not n[1] or n[0].startswith("@@"):
                sys.exit("%s: a hunk without its title / note (%s)" % (p, h["diff"].split("\n")[0]))
            h["title"], h["note"] = n[0], n[1]
            if len(n) > 2 and n[2]:
                lines = [l for l in h["diff"].split("\n") if not l.startswith("@@")]
                for at, _text in n[2]:
                    if not any(at in l for l in lines):
                        sys.exit("%s: a bubble's `at` isn't in its hunk: %r" % (p, at))
                h["bubbles"] = [{"at": at, "text": text} for at, text in n[2]]
        files.append({"path": p, "kind": kind, "explanation": meta["explanation"], "hunks": hs,
                      "added": sum(h["added"] for h in hs), "removed": sum(h["removed"] for h in hs)})
    p = json.load(open(patch_path))
    p["review"] = {"intro": notes.get("_intro", ""), "files": files}
    json.dump(p, open(patch_path, "w"), indent=1)
    print("review added to", patch_path, ":", len(files), "files,", sum(len(f["hunks"]) for f in files), "hunks")


PATCHES = os.path.join("data", "patches")


def open_version():
    """The version new patches go into: the version file marked "open": true,
    else the newest version. (path, data) or (None, None)."""
    best = None
    for f in sorted(os.listdir(PATCHES)):
        if not (f.startswith("version_") and f.endswith(".json")):
            continue
        path = os.path.join(PATCHES, f)
        v = json.load(open(path))
        key = tuple(int(x) for x in str(v.get("id", "0")).split(".") if x.isdigit())
        if v.get("open"):
            return path, v
        if best is None or key > best[0]:
            best = (key, path, v)
    return (best[1], best[2]) if best else (None, None)


def assign_to_version(patch_id):
    """A patch being published joins the open version (unless it's in a
    version already): its id, a page (its title, its steps as badges, its
    summary's opening), and a line in the version's summary."""
    patch_file = next((f for f in os.listdir(PATCHES) if f.startswith(patch_id + "_") and f.endswith(".json")), None)
    if patch_file is None:
        return
    for f in os.listdir(PATCHES):
        if f.startswith("version_") and f.endswith(".json"):
            if patch_id in json.load(open(os.path.join(PATCHES, f))).get("patches", []):
                return
    path, v = open_version()
    if path is None:
        return
    p = json.load(open(os.path.join(PATCHES, patch_file)))
    title = p.get("title", patch_id)
    sentences = p.get("summary", "").replace("\n", " ").split(". ")
    text = ". ".join(sentences[:2]).strip()
    text = text if text.endswith(".") else text + "."
    diagram = [{"t": "box", "rect": [200, 40, 600, 80], "label": "PATCH %s\n%s" % (patch_id, title), "size": 18, "stroke": "gold"}]
    for i, st in enumerate(p.get("steps", [])[:6]):
        diagram.append({"t": "badge", "at": [210 + (i % 3) * 290, 200 + (i // 3) * 90], "text": st.get("title", "")[:34],
                        "color": ["cyan", "green", "purple", "gold", "red", "blue"][i % 6], "size": 15, "delay": 0.3 + 0.15 * i})
    if len(p.get("steps", [])) > 6:
        diagram.append({"t": "text", "at": [500, 400], "text": "... and %d more steps" % (len(p["steps"]) - 6), "size": 15, "color": "dim", "align": "center"})
    v.setdefault("patches", []).append(patch_id)
    v.setdefault("steps", []).append({"patch": patch_id, "title": "Patch %s - %s" % (patch_id, title), "text": text, "diagram": diagram})
    v["summary"] = v.get("summary", "").rstrip() + " Then %s (patch %s)." % (title[0].lower() + title[1:] if title else title, patch_id)
    json.dump(v, open(path, "w"), indent=1)
    print("version %s: patch %s added (%s)" % (v.get("id"), patch_id, os.path.basename(path)))


def cmd_baseline(patch_id):
    # Into the open version first (the baseline then includes it).
    assign_to_version(patch_id)
    # The log of what went into this patch is kept: history/<id>.md.
    if os.path.exists(PENDING):
        os.makedirs(os.path.join(TRACK, "history"), exist_ok=True)
        shutil.copy2(PENDING, os.path.join(TRACK, "history", "%s.md" % patch_id))
    if os.path.exists(SNAP):
        shutil.rmtree(SNAP)
    files = {}
    times = {}
    for p in tracked():
        files[p] = md5(p)
        times[p] = int(os.path.getmtime(p))
        if is_text(p):
            dst = os.path.join(SNAP, p)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(p, dst)
    json.dump({"patch": patch_id, "date": datetime.date.today().isoformat(), "files": files, "mtimes": times},
              open(MANIFEST, "w"), indent=0)
    with open(PENDING, "w") as fh:
        fh.write("# Pending changes (since patch %s, %s)\n" % (patch_id, datetime.date.today().isoformat()))
    print("baseline: patch", patch_id, "-", len(files), "files tracked; pending.md emptied")


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a or a[0] not in ("status", "notes-template", "review", "baseline"):
        print(__doc__)
        sys.exit(1)
    {"status": lambda: cmd_status(), "notes-template": lambda: cmd_notes_template(a[1]),
     "review": lambda: cmd_review(a[1], a[2]), "baseline": lambda: cmd_baseline(a[1])}[a[0]]()
