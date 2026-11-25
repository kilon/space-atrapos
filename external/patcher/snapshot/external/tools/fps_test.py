#!/usr/bin/env python3
"""The frame-rate test: runs tests/fps_tour.gd in a real window (vsync off,
no frame cap) - every area and way of playing, a few seconds each - and fails
if any scenario is under 600 FPS (average, and 95% of its frames), stutters
(a frame over 50 ms), or has fallen to under 3/4 of its baseline frame rate
(tests/fps_baseline.json - this machine's numbers: an RTX 2070 Super, 1920x1080;
only scenarios under 1200 FPS are judged by it), or a loading step (a change of
scene, a first opening) has a frame over 33 ms.
Run it after anything that changes what runs each frame.

    python3 tools/fps_test.py                 # the whole tour (~5 min)
    python3 tools/fps_test.py surface         # scenarios whose name contains this
                                              # (title, space, site, landing, surface, thalassa, ...)
    python3 tools/fps_test.py --res 2560x1440 # another window size (default 1920x1080)
    python3 tools/fps_test.py --target=240    # judge against another frame rate (default 600)
    python3 tools/fps_test.py loading         # only the loading steps (scene changes, first openings)
    python3 tools/fps_test.py --cores 4       # as on a quad core (the game on 4 of this machine's
                                              # cores, told it has 4); judged by the same bar
    python3 tools/fps_test.py --render-thread separate   # try Godot's other rendering thread model
                                              # (2026-11: errors - screen read-backs - and no gain)
    python3 tools/fps_test.py --save-baseline # store this run as the baseline (after a speed-up,
                                              # or on another machine)
    python3 tools/fps_test.py space --shots   # + a screenshot of each scenario (fps/shots/)
    python3 tools/fps_test.py space --profile # + where the scripts' time goes (Godot's
                                              # profiler): each scenario's top functions

Uses its own user data (a copy of the tests' base, which keeps the terrain
tile cache): your saves and settings are never touched. Nothing else heavy
should run meanwhile (the test suite, a build) - it shares the machine.
Results: printed, and saved as ~/.cache/space-atrapos-tests/fps/last.json.
Exit code 1 if anything was too slow or slower than its baseline (or the tour failed).
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.expanduser("~/.cache/space-atrapos-tests")
BASE = os.path.join(WORK, "base")
DATA = os.path.join(WORK, "fps")
APP = os.path.join("godot", "app_userdata", "Space Atrapos")


PROFILE_PORT = 6017


def report_profile(path, top=12):
    """Each scenario's functions by their own time per frame (ms)."""
    import json
    if not os.path.exists(path):
        print("(no profile)")
        return
    with open(path) as f:
        data = json.load(f)
    for scen, d in data.items():
        n = max(1, d["frames"])
        rows = sorted(d["funcs"].items(), key=lambda kv: -kv[1][1])[:top]
        print("\n%s - %d frames profiled; own ms per frame (total incl. calls), calls per frame:" % (scen, n))
        for name, (calls, self_ms, total_ms) in rows:
            print("  %6.2f ms (%6.2f)  %7.1f  %s" % (self_ms / n, total_ms / n, calls / n, name))


def main():
    args = sys.argv[1:]
    res = "1920x1080"
    if "--res" in args:
        i = args.index("--res")
        res = args[i + 1]
        del args[i:i + 2]
    profile = "--profile" in args
    if profile:
        args.remove("--profile")
    if "--save-baseline" in args:
        args.remove("--save-baseline")
    extra = []
    if "--render-thread" in args:   # (try a rendering thread model: safe / separate)
        i = args.index("--render-thread")
        extra = ["--render-thread", args[i + 1]]
        del args[i:i + 2]
    cores = 0
    if "--cores" in args:
        i = args.index("--cores")
        cores = int(args[i + 1])
        del args[i:i + 2]
    shutil.rmtree(DATA, ignore_errors=True)
    if os.path.isdir(BASE):
        shutil.copytree(BASE, DATA, symlinks=True)
    os.makedirs(os.path.join(DATA, APP), exist_ok=True)
    env = dict(os.environ, XDG_DATA_HOME=DATA)
    cmd = ["godot"] + extra + ["--path", ROOT, "--resolution", res, "--position", "0,30", "-s", "tests/fps_tour.gd", "--", "--mute", "--bot", "--window-at=0,30"] + args   # (bot runs: upper-left, muted)
    prof = None
    prof_out = os.path.join(DATA, "profile.json")
    if profile:
        prof = subprocess.Popen(["godot", "--headless", "--path", os.path.join(ROOT, "external", "live_debugger"),
                                 "-s", "profiler.gd", "--", str(PROFILE_PORT), prof_out],
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        for line in prof.stdout:   # (until it listens)
            if line.startswith("profiler:"):
                break
        cmd[1:1] = ["--remote-debug", "tcp://127.0.0.1:%d" % PROFILE_PORT]
    if cores:
        # A machine with fewer cores: the game on that many of this one's (one
        # thread each), told it has that many (BgWork: its background threads).
        cmd = ["taskset", "-c", "0-%d" % (cores - 1)] + cmd + ["--cores=%d" % cores]
    p = subprocess.run(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=1800)
    show = False
    for line in p.stdout.splitlines():
        if line.startswith("FPS tour"):
            show = True
        if show or "ERROR" in line or "SCRIPT ERROR" in line:
            print(line)
    if prof:
        try:
            prof.wait(timeout=300)   # (it may still be reading its backlog)
        except subprocess.TimeoutExpired:
            prof.kill()
        report_profile(prof_out)
    shots = os.path.join(DATA, APP, "fps_shots")
    if os.path.isdir(shots):
        shutil.rmtree(os.path.join(DATA, "shots"), ignore_errors=True)
        shutil.copytree(shots, os.path.join(DATA, "shots"))
        print("Screenshots: " + os.path.join(DATA, "shots"))
    out = os.path.join(DATA, APP, "fps_tour.json")
    if os.path.exists(out):
        shutil.copy(out, os.path.join(DATA, "last.json"))
        # (A --cores run stands in for another machine: not judged by this one's baseline.)
        rc = 0 if cores else compare_baseline(out, save="--save-baseline" in sys.argv[1:])
        sys.exit(p.returncode or rc)
    sys.exit(p.returncode or 1)


BASELINE = os.path.join(ROOT, "tests", "fps_baseline.json")
SLOWER = 0.75   # a scenario under this share of its baseline frame rate: flagged...
HEADROOM = 1200  # ...unless it's still above this (twice the bar: those vary a lot run to run)


def compare_baseline(results_path, save=False):
    """Each scenario's frame rate against tests/fps_baseline.json (this machine's
    numbers when it was saved): one that's fallen to under SLOWER of it is a
    regression even while it's above the bar. --save-baseline stores this run's
    (the scenarios it ran) as the new baseline. 1 if anything regressed. (Scenarios
    still over HEADROOM aren't judged: at 500-1000 fps the random galaxy alone moves
    them by a third.)"""
    import json
    with open(results_path) as f:
        results = json.load(f)
    base = {}
    if os.path.exists(BASELINE):
        with open(BASELINE) as f:
            base = json.load(f)
    results = [r for r in results if not r.get("load")]   # (loading: judged by its longest frame alone)
    if save:
        for r in results:
            base[r["name"]] = {"fps": round(r["fps"], 1), "p95_ms": round(r["p95_ms"], 2)}
        with open(BASELINE, "w") as f:
            json.dump(base, f, indent="\t", sort_keys=True)
        print("Saved %d scenarios as the baseline (%s)." % (len(results), BASELINE))
        return 0
    worse = []
    for r in results:
        b = base.get(r["name"])
        if b and r["fps"] < b["fps"] * SLOWER and r["fps"] < HEADROOM:
            worse.append("%s: %.0f fps (baseline %.0f)" % (r["name"], r["fps"], b["fps"]))
    if not base:
        print("No baseline yet: python3 tools/fps_test.py --save-baseline stores one.")
    elif worse:
        print("\n%d slower than their baseline (under %d%% of it, and under %d fps):" % (len(worse), SLOWER * 100, HEADROOM))
        for w in worse:
            print("  - " + w)
    else:
        print("No scenario slower than its baseline.")
    return 1 if worse else 0


if __name__ == "__main__":
    main()
