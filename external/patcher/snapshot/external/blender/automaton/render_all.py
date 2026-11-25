#!/usr/bin/env python3
"""Renders a skin's sprites with several Blenders at once.

  python3 render_all.py <skin> [clip names] [--jobs 8]

-> renders/<skin>/<clip>_<dir>_<frame>.png + meta.json; then
   python3 tools/puppet_atlas.py <skin> packs them into art/<id>_clips/.
"""
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    args = sys.argv[1:]
    jobs = 8
    if "--jobs" in args:
        i = args.index("--jobs")
        jobs = int(args[i + 1])
        del args[i:i + 2]
    skin, names = args[0], args[1:]
    t = time.time()
    procs = []
    for j in range(jobs):
        cmd = ["blender", "-b", "--factory-startup", os.path.join(HERE, skin + ".blend"), "--python", os.path.join(HERE, "build.py"),
               "--", skin, "render"] + names + ["--jobs", "%d/%d" % (j, jobs)]
        procs.append(subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True))
    bad = 0
    for p in procs:
        out = p.communicate()[0]
        if p.returncode != 0 or "Traceback" in out:
            bad += 1
            print(out[-3000:])
    n = len([f for f in os.listdir(os.path.join(HERE, "renders", skin)) if f.endswith(".png")])
    print("%s: %d pictures in %.0f s%s" % (skin, n, time.time() - t, ", %d job(s) FAILED" % bad if bad else ""))
    sys.exit(1 if bad else 0)


main()
