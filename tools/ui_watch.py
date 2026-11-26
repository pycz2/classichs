#!/usr/bin/env python3
"""The UI watch from the outside (docs/ui-watch.md): starts the game in a window in the watch mode, reads what it shows
and sends it commands through ~/ClassicHS-local/uiwatch (UI_WATCH_DIR).

  tools/ui_watch.py start [--real]      the game in the background (--real: the player's own profile); prints the pid
  tools/ui_watch.py state [--all]       the screen, the size, the language, its controls (--all: also those without
                                        text), the overlays, the last events and errors
  tools/ui_watch.py shot [name]         a picture of the window; prints its path
  tools/ui_watch.py goto CALL [ARG...]  main.CALL(ARGS) (each ARG as JSON when it parses, else as text)
  tools/ui_watch.py size W H | lang L | reload | restart | stop
"""
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIR = Path(os.environ.get("UI_WATCH_DIR") or Path.home() / "ClassicHS-local/uiwatch")


def read_state():
    try:
        return json.loads((DIR / "state.json").read_text())
    except (OSError, ValueError):
        return {}


def pid():
    try:
        p = int((DIR / "pid").read_text())
        os.kill(p, 0)
        return p
    except (OSError, ValueError):
        return None


def send(cmd, wait=5.0):
    """Writes cmd.json (temp + rename) once the last command was taken; waits until this one is taken too."""
    if not pid():
        sys.exit("the game is not running (tools/ui_watch.py start)")
    f = DIR / "cmd.json"
    until = time.monotonic() + wait
    while f.exists() and time.monotonic() < until:
        time.sleep(0.05)
    tmp = DIR / "cmd.json.tmp"
    tmp.write_text(json.dumps(cmd))
    tmp.rename(f)
    while f.exists() and time.monotonic() < until:
        time.sleep(0.05)
    if f.exists():
        sys.exit("the game did not take the command")


def wait_state(after, wait=3.0):
    """The first state after seq `after` (the game writes it within 0.3 s of a change)."""
    until = time.monotonic() + wait
    while time.monotonic() < until:
        s = read_state()
        if s.get("seq", 0) > after:
            return s
        time.sleep(0.05)
    return read_state()


def start(real):
    if pid():
        sys.exit(f"already running: pid {pid()}")
    DIR.mkdir(parents=True, exist_ok=True)
    (DIR / "pid").unlink(missing_ok=True)
    log = DIR / "godot.log"
    cmd = ["godot", "--path", str(ROOT), "--log-file", str(log), "res://ui/main.tscn", "--",
           "--ui-watch-real" if real else "--ui-watch"]
    p = subprocess.Popen(cmd, cwd=ROOT, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    until = time.monotonic() + 30
    while time.monotonic() < until and not (DIR / "pid").exists():
        if p.poll() is not None:
            sys.exit(f"the game stopped at once (exit {p.returncode}); see {log}")
        time.sleep(0.1)
    print(p.pid)


def fmt_controls(cs, everything):
    rows = []
    for c in cs:
        if not everything and "text" not in c and "tooltip" not in c:
            continue
        flags = "".join(x for x, k in (("D", "disabled"), ("F", "focus")) if c.get(k))
        x, y, w, h = c["rect"]
        text = c.get("text", "")
        if c.get("tooltip"):
            text += f"  [tip: {c['tooltip']}]"
        rows.append(f"  {c['type'][:16]:16} {x:5} {y:4} {w:4}x{h:<4} {flags:2} {c['path'][-40:]:40} {text}")
    return rows


def show_state(everything):
    s = read_state()
    if not s:
        sys.exit(f"no state in {DIR}: is the game running?")
    sc = s.get("screen", {})
    alive = "running" if pid() else "NOT RUNNING"
    print(f"seq {s['seq']}  pid {s.get('pid')} ({alive})  window {s['window'][0]}x{s['window'][1]}  lang {s['lang']}"
          f"  profile {s.get('profile')}")
    args = json.dumps(sc.get("args", []), ensure_ascii=False)
    print(f"screen {sc.get('type')} ({sc.get('name')})  opened by {sc.get('call') or '-'}{args if sc.get('call') else ''}")
    if s.get("error"):
        print("ERROR (not reloaded):\n  " + s["error"].replace("\n", "\n  "))
    cs = s.get("controls", [])
    print(f"controls ({len(cs)}{', cut' if s.get('controls_cut') else ''}; type x y size flags path text):")
    print("\n".join(fmt_controls(cs, everything)))
    for o in s.get("popups", []) + s.get("overlays", []):
        print(f"over the screen: {o['name']} {o.get('title', '')}")
        print("\n".join(fmt_controls(o["controls"], everything)))
    print("history: " + " > ".join(h.get("call") or h.get("screen", "?") for h in s.get("history", [])[-8:]))
    print("events:")
    for e in s.get("events", [])[-15:]:
        rest = {k: v for k, v in e.items() if k not in ("t", "at")}
        print(f"  {time.strftime('%H:%M:%S', time.localtime(e.get('at', 0)))} {e['t']:12} {json.dumps(rest, ensure_ascii=False)[:150]}")
    errs = [e for e in s.get("events", []) if e["t"] in ("error", "reload_failed")]
    if errs:
        print(f"errors in the last events: {len(errs)} (the last: {errs[-1].get('text') or errs[-1].get('error')})")


def shot(name):
    before = read_state().get("seq", 0)
    path = DIR / f"{name}.png"
    old = path.stat().st_mtime if path.exists() else 0
    send({"shot": name})
    until = time.monotonic() + 5
    while time.monotonic() < until:
        if path.exists() and path.stat().st_mtime > old:
            print(path)
            return
        s = wait_state(before, 0.2)
        if any(e["t"] == "shot_skipped" for e in s.get("events", [])[-3:]):
            sys.exit("no picture: the game runs without a window")
    sys.exit("no picture after 5 s")


def arg(a):
    try:
        return json.loads(a)
    except ValueError:
        return a


def main():
    a = sys.argv[1:]
    if not a or a[0] in ("-h", "--help"):
        print(__doc__)
        return
    what, rest = a[0], a[1:]
    if what == "start":
        start("--real" in rest)
    elif what == "state":
        show_state("--all" in rest)
    elif what == "shot":
        shot(rest[0] if rest else "shot")
    elif what in ("goto", "size", "lang", "reload", "restart"):
        if what == "goto":
            cmd = {"goto": rest[0], "args": [arg(x) for x in rest[1:]]}
        elif what == "size":
            cmd = {"size": [int(x) for x in rest[:2]]}
        elif what == "lang":
            cmd = {"lang": rest[0]}
        else:
            cmd = {what: True}
        before = read_state().get("seq", 0)
        send(cmd)
        if what != "restart":
            s = wait_state(before)
            print(f"seq {s.get('seq')}  screen {s.get('screen', {}).get('type')}"
                  + (f"  ERROR {s['error']}" if s.get("error") else ""))
    elif what == "stop":
        p = pid()
        if not p:
            sys.exit("the game is not running")
        os.kill(p, signal.SIGTERM)
        print(f"stopped {p}")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
