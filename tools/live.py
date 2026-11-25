#!/usr/bin/env python3
"""Live coding with the running game - the client of scripts/core/live_link.gd
(the game, port 6070) and external/live_debugger/debugger.gd (the debugger
daemon, port 6071).

Start the game with LiveLink (and, to debug, with the debugger daemon first):
    python3 tools/live.py debugger &            # the daemon (for breakpoints etc.)
    godot --path . --remote-debug tcp://127.0.0.1:6007 -- --live
  (--remote-debug only when the daemon runs; --live[=PORT] turns LiveLink on)

The game (LiveLink):
    live.py ping | state | tree [PATH] [DEPTH]
    live.py eval 'ship.hull / ship.max_hull'
    live.py set ship hull 50                      # target, property, value (expressions)
    live.py run 'for e in tree.get_nodes_in_group("enemies"): e.hull = 1'
    live.py run -f fix.gd                         # statements, or a script with func run()
    live.py reload scripts/hydra_head.gd ...      # hot reload now (keeps the objects)
    live.py hot on|off                            # hot reload changed files automatically
    live.py shot [PATH]                           # screenshot of the game's view
    live.py pause [on|off] | speed X
    live.py inspect 'site'                        # open the Inspector window on it
    live.py log [--follow] [--since N]            # prints, errors, reloads
The debugger (the daemon):
    live.py dbg status | events [--follow] [--warnings]
    live.py dbg break scripts/hydra_beast.gd 120 [off] | clear
    live.py dbg pause | step | next | out | continue
    live.py dbg stack | vars [FRAME] | eval EXPR [FRAME]
    live.py dbg reload [PATHS...]                 # Godot's own reload_scripts
    live.py dbg errors on|off                     # stop at script errors
"""
import json
import os
import socket
import subprocess
import sys
import time

GAME = int(os.environ.get("LIVE_PORT", "6070"))
DBG = 6071
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def ask(port, req, timeout=15.0):
    try:
        s = socket.create_connection(("127.0.0.1", port), timeout=timeout)
    except OSError:
        who = "the game (start it with -- --live)" if port != DBG else \
            "the debugger daemon (python3 tools/live.py debugger)"
        sys.exit("can't reach %s on port %d" % (who, port))
    s.sendall((json.dumps(req) + "\n").encode())
    buf = b""
    s.settimeout(timeout)
    while not buf.endswith(b"\n"):
        try:
            chunk = s.recv(65536)
        except socket.timeout:
            sys.exit("no reply in %.0f s (is the game stopped at a breakpoint?)" % timeout)
        if not chunk:
            break
        buf += chunk
    s.close()
    if not buf:
        sys.exit("the connection closed with no reply")
    return json.loads(buf.decode())


def show(r):
    if not r.get("ok"):
        print("error:", r.get("error"), file=sys.stderr)
        sys.exit(1)
    v = r.get("result")
    if isinstance(v, str):
        print(v)
    else:
        print(json.dumps(v, indent=1, ensure_ascii=False))


def on_off(args, i, default=True):
    if len(args) <= i:
        return default
    return args[i].lower() in ("on", "1", "true", "yes")


def fmt_event(e):
    d = e.get("text", e.get("data"))
    if isinstance(d, dict) and "error" in d and "file" in d:
        s = "%s:%s %s: %s %s" % (d["file"], d["line"], d["function"], d["error"], d.get("description", ""))
        for f in d.get("stack", [])[:8]:
            s += "\n      at %s:%s (%s)" % (f["file"], f["line"], f["function"])
        d = s
    elif isinstance(d, dict) and "stack" in d:
        s = "stopped (%s)" % d.get("reason", "")
        for f in d["stack"][:12]:
            s += "\n      at %s:%s (%s)" % (f.get("file"), f.get("line"), f.get("function"))
        d = s
    elif not isinstance(d, str):
        d = json.dumps(d, ensure_ascii=False)
    return "%5d %8.2f %-8s %s" % (e["seq"], e["t"], e["kind"], d)


def log(port, req_cmd, args):
    follow = "--follow" in args or "-f" in args
    since = 0
    if "--since" in args:
        since = int(args[args.index("--since") + 1])
    while True:
        r = ask(port, {"cmd": req_cmd, "since": since})
        if not r.get("ok"):
            show(r)
        for e in r["result"]["events"]:
            if not isinstance(e, dict):
                continue
            if e["kind"] == "warning" and "--warnings" not in args:
                continue
            print(fmt_event(e), flush=True)
        since = r["result"]["last"]
        if not follow:
            break
        time.sleep(0.3)


def debugger(args):
    gd = os.environ.get("GODOT", "godot")
    cmd = [gd, "--headless", "--path", os.path.join(ROOT, "external", "live_debugger"), "-s", "debugger.gd"]
    if args:
        cmd += ["--"] + args
    os.execvp(gd, cmd)


def dbg(args):
    if not args:
        sys.exit(__doc__)
    c, a = args[0], args[1:]
    if c == "events":
        return log(DBG, "events", a)
    if c == "break":
        return show(ask(DBG, {"cmd": "break", "file": a[0], "line": int(a[1]), "on": on_off(a, 2)}))
    if c == "vars":
        return show(ask(DBG, {"cmd": "vars", "frame": int(a[0]) if a else 0}))
    if c == "eval":
        req = {"cmd": "eval", "expr": a[0]}
        if len(a) > 1:
            req["frame"] = int(a[1])
        return show(ask(DBG, req))
    if c == "reload":
        return show(ask(DBG, {"cmd": "reload", "paths": a}))
    if c == "errors":
        return show(ask(DBG, {"cmd": "errors", "on": on_off(a, 0)}))
    show(ask(DBG, {"cmd": c}))


def main(argv):
    if not argv or argv[0] in ("-h", "--help", "help"):
        print(__doc__)
        return
    c, a = argv[0], argv[1:]
    if c == "debugger":
        return debugger(a)
    if c == "dbg":
        return dbg(a)
    if c == "log":
        return log(GAME, "events", a)
    if c in ("ping", "state"):
        return show(ask(GAME, {"cmd": c}))
    if c == "eval":
        return show(ask(GAME, {"cmd": "eval", "expr": " ".join(a)}))
    if c == "set":
        return show(ask(GAME, {"cmd": "set", "target": a[0], "prop": a[1], "value": " ".join(a[2:])}))
    if c == "run":
        code = open(a[1]).read() if a and a[0] == "-f" else (sys.stdin.read() if not a or a[0] == "-" else " ".join(a))
        return show(ask(GAME, {"cmd": "run", "code": code}, timeout=120))
    if c == "reload":
        return show(ask(GAME, {"cmd": "reload", "paths": [os.path.relpath(os.path.abspath(p), ROOT) for p in a]}))
    if c == "hot":
        return show(ask(GAME, {"cmd": "watch", "on": on_off(a, 0)}))
    if c == "tree":
        return show(ask(GAME, {"cmd": "tree", "path": a[0] if a else "main", "depth": int(a[1]) if len(a) > 1 else 2}))
    if c == "shot":
        return show(ask(GAME, {"cmd": "shot", "path": os.path.abspath(a[0]) if a else "user://live_shot.png"}))
    if c == "pause":
        req = {"cmd": "pause"}
        if a:
            req["on"] = on_off(a, 0)
        return show(ask(GAME, req))
    if c == "speed":
        return show(ask(GAME, {"cmd": "speed", "scale": float(a[0]) if a else 1.0}))
    if c == "inspect":
        return show(ask(GAME, {"cmd": "inspect", "expr": " ".join(a) if a else "ship"}))
    sys.exit("unknown command %s - live.py help" % c)


if __name__ == "__main__":
    main(sys.argv[1:])
