#!/usr/bin/env python3
"""Runs the game's tests in parallel: every test file split into small groups,
each group in its own headless Godot process (tests/run_tests.gd with a list of
test names), many at once. Each process gets its own user-data folder (a fresh
copy of a shared base that keeps the terrain tile cache), so the user's saves
and settings are never touched - no backup / restore needed.

    python3 tools/test.py                    # everything
    python3 tools/test.py test_surface       # files whose name contains this
    python3 tools/test.py test_surface cliff # ... and tests whose name contains this
    python3 tools/test.py -j 8               # at most 8 processes (default: cores / 2, max 16)

Prints each failing test with its messages, then the totals and the wall time.
Exit code 1 if anything failed.
"""
import os
import re
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.expanduser("~/.cache/space-atrapos-tests")
BASE = os.path.join(WORK, "base")
APP = os.path.join("godot", "app_userdata", "Space Atrapos")
GROUP = {"test_surface": 2, "test_play": 2, "test_paths": 1}   # tests per process for the slow files (default 4)


def tests_in(path):
    with open(path) as f:
        return re.findall(r"^func (test_\w+)\(", f.read(), re.M)


def main():
    args = sys.argv[1:]
    jobs_n = min(16, max(2, (os.cpu_count() or 4) // 2))
    if "-j" in args:
        i = args.index("-j")
        jobs_n = int(args[i + 1])
        del args[i:i + 2]
    file_filter = args[0] if args else ""
    name_filter = args[1] if len(args) > 1 else ""
    jobs = []
    for f in sorted(os.listdir(os.path.join(ROOT, "tests"))):
        if not (f.startswith("test_") and f.endswith(".gd")) or f == "test_case.gd" or file_filter not in f:
            continue
        stem = f[:-3]
        names = [n for n in tests_in(os.path.join(ROOT, "tests", f)) if name_filter in n]
        g = GROUP.get(stem, 4)
        for k in range(0, len(names), g):
            jobs.append((stem, names[k:k + g]))
    # The slow files' groups first (they set the wall time).
    jobs.sort(key=lambda j: 0 if j[0] in GROUP else 1)
    os.makedirs(os.path.join(BASE, APP), exist_ok=True)
    t0 = time.time()

    def run(idx_job):
        idx, (stem, names) = idx_job
        home = os.path.join(WORK, "run%d-job%d" % (os.getpid(), idx))   # (two runs at once don't share)
        shutil.rmtree(home, ignore_errors=True)
        shutil.copytree(BASE, home)
        env = dict(os.environ, XDG_DATA_HOME=home)
        p = subprocess.run(["godot", "--headless", "--path", ROOT, "-s", "tests/run_tests.gd", "--", stem, ",".join(names)],
                           env=env, capture_output=True, text=True, timeout=900)
        # Keep what it cached for the next runs (tile images): files the base
        # lacks or has older, each copied beside it and renamed into place - a
        # job copying the base meanwhile sees the old file or the new, never half.
        cache = os.path.join(home, APP, "tile_cache")
        keep = os.path.join(BASE, APP, "tile_cache")
        if os.path.isdir(cache):
            os.makedirs(keep, exist_ok=True)
            for f in os.listdir(cache):
                src, dst = os.path.join(cache, f), os.path.join(keep, f)
                if os.path.exists(dst) and os.path.getmtime(dst) >= os.path.getmtime(src):
                    continue
                tmp = os.path.join(BASE, ".%s.%d.%d.tmp" % (f, os.getpid(), idx))
                shutil.copy2(src, tmp)
                os.replace(tmp, dst)
        shutil.rmtree(home, ignore_errors=True)
        return stem, names, p.stdout + p.stderr

    passed, failed = 0, []
    with ThreadPoolExecutor(jobs_n) as ex:
        for stem, names, out in ex.map(run, enumerate(jobs)):
            ok = len(re.findall(r"^  ok    ", out, re.M))
            fails = re.findall(r"^  FAIL  (\w+).*\n((?:          .*\n)*)", out, re.M)
            passed += ok
            for name, msgs in fails:
                failed.append("%s.%s" % (stem, name))
                print("FAIL %s.%s\n%s" % (stem, name, msgs.rstrip()))
            if ok + len(fails) < len(names):   # (crashed, or didn't load)
                missing = len(names) - ok - len(fails)
                failed.append("%s (%d tests didn't run)" % (stem, missing))
                print("ERROR %s %s: %d tests didn't run\n%s" % (stem, ",".join(names), missing, out[-1500:]))
    print("\n%d passed, %d failed  (%.1f s, %d processes, %d at a time)" % (passed, len(failed), time.time() - t0, len(jobs), jobs_n))
    for f in failed:
        print("  failed: " + f)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
