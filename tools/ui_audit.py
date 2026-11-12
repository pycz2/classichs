#!/usr/bin/env python3
"""Runs one group of the UI audit (tools/ui_audit.gd) in a window, with its own user dir.

Usage: tools/ui_audit.py <group> [--sizes 1280x720,844x390] [--langs ru,en] [--only a,b] [--packs p1,p2]
Shots: ~/ClassicHS-local/ui-audit/shots/<group>/ (its checks.jsonl there too; a run starts it anew).
The main pack: ~/ClassicHS-local/loot-custom-art.cardpack (every card up to Kobolds & Catacombs, with art).
"""
import argparse, json, os, shutil, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCAL = Path.home() / "ClassicHS-local"
OUT = LOCAL / "ui-audit" / "shots"
SIZES = "1280x720,844x390,390x844"
MAIN = LOCAL / "loot-custom-art.cardpack"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("group")
    ap.add_argument("--sizes", default=SIZES)
    ap.add_argument("--langs", default="ru,en")
    ap.add_argument("--only", default="")
    ap.add_argument("--packs", default=str(MAIN), help="cardpack files to install, the last one is the main pack")
    ap.add_argument("--keep", action="store_true", help="keep the shots and checks of earlier runs")
    ap.add_argument("--timeout", type=int, default=1800)
    a = ap.parse_args()
    out = OUT / a.group
    if not a.keep and out.exists() and not a.only:
        shutil.rmtree(out)
    out.mkdir(parents=True, exist_ok=True)
    job = {"group": a.group, "out": str(out), "langs": a.langs.split(","),
           "sizes": [[int(x) for x in s.split("x")] for s in a.sizes.split(",")],
           "packs": [p for p in a.packs.split(",") if p]}
    if a.only:
        job["only"] = a.only.split(",")
    tmp = Path(tempfile.mkdtemp(prefix="uiaudit-"))
    (tmp / "job.json").write_text(json.dumps(job))
    env = dict(os.environ, AUDIT_USER_DIR=f"classichs-audit/{a.group}-{os.getpid()}")
    godot = shutil.which("godot") or "godot"
    log = out / "run.log"
    with open(log, "w") as f:
        r = subprocess.run([godot, "--path", str(ROOT), "--script", "res://tools/ui_audit.gd", "--", str(tmp / "job.json")],
                           env=env, stdout=f, stderr=subprocess.STDOUT, timeout=a.timeout)
    shutil.rmtree(tmp, ignore_errors=True)
    # the run's own user dir (its installed packs are big)
    user = Path.home() / ("Library/Application Support" if sys.platform == "darwin" else ".local/share") / env["AUDIT_USER_DIR"]
    if user.exists():
        shutil.rmtree(user, ignore_errors=True)
    tail = log.read_text().splitlines()[-3:]
    print("\n".join(tail))
    return r.returncode


if __name__ == "__main__":
    sys.exit(main())
