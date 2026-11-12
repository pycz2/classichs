#!/usr/bin/env python3
"""Runs the Godot tests (tests/run.gd) in several godot processes at once; ./run_tests.sh calls it after the builds
and the import.

  tools/run_tests.py [-j N] [-- name]   N processes (default: TEST_JOBS, else the cores less 2; -j 1: one process);
                                        name: only the tests whose "file:method" contains it

First a smoke test (tests/test_smoke.gd, at most 15 s) checks that godot starts at all (and lists every test).
Then each process takes a share of the tests (balanced by the last full run's times, build/test_times.json; a file's
tests may go to different processes), its own user:// (<the OS's data folder>/classichs-tests/<run>/<process>:
run.gd's TEST_USER_DIR) and two limits: TEST_TIMEOUT seconds (default 600) and TEST_MAX_LOG_MB of output (default
200: a test that loops printing an error fills the disk in a minute); a process over either is stopped and the test
it was on is named. Godot's log goes to the run's temporary folder, never to the shared user://logs. One summary at
the end; the run's folders are removed unless something failed (then their paths are printed, and of each log only
its last KEEP_LOG bytes are kept). Exit code 1 on any failure.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TIMES = ROOT / "build/test_times.json"
SMOKE_TIMEOUT = 15
MAX_LOG = int(os.environ.get("TEST_MAX_LOG_MB") or 200) * 2**20  # one process's output (stdout and godot's log)
KEEP_LOG = 5 * 2**20  # what is kept of each log of a failed run
SUMMARY = re.compile(r"^(\d+) tests, (\d+) failed$")


class Shard:
    def __init__(self, name, only, filt, logs, run, **env):
        self.name = name
        self.log = logs / f"{name}.log"
        self.godot_log = logs / f"{name}.godot.log"
        self.progress = logs / f"{name}.progress"
        env = dict(os.environ, TEST_USER_DIR=f"classichs-tests/{run}/{name}", TEST_ONLY=" ".join(only),
                   TEST_PROGRESS=str(self.progress), **env)
        cmd = ["godot", "--headless", "--log-file", str(self.godot_log), "--path", str(ROOT),
               "--script", "res://tests/run.gd"] + (["--", filt] if filt else [])
        with open(self.log, "w") as out:
            self.proc = subprocess.Popen(cmd, cwd=ROOT, env=env, stdout=out, stderr=subprocess.STDOUT,
                                         stdin=subprocess.DEVNULL)
        self.stopped = ""  # why it was stopped (a time or log limit)

    def size(self):
        return sum(f.stat().st_size for f in (self.log, self.godot_log) if f.exists())

    def stop(self, why):
        self.proc.kill()
        self.proc.wait()
        self.stopped = why

    def now(self):
        """(user dir, the test it is on) from run.gd's progress file."""
        try:
            lines = self.progress.read_text().splitlines()
        except OSError:
            return "", "(godot did not get to the first test)"
        return (lines + ["", ""])[0], (lines + ["", ""])[1]

    def output(self):
        return self.log.read_text(errors="replace").splitlines()


def watch(shards, limit):
    """Waits for the shards; stops one that runs over limit seconds or whose output passes MAX_LOG."""
    deadline = time.monotonic() + limit
    while any(s.proc.poll() is None for s in shards):
        for s in shards:
            if s.proc.poll() is not None:
                continue
            if time.monotonic() > deadline:
                s.stop(f"over {limit:.0f} s")
            elif s.size() > MAX_LOG:
                s.stop(f"its output passed {MAX_LOG // 2**20} MiB")
        time.sleep(0.2)


def trim(f, keep=KEEP_LOG):
    """Only the end of a long log is kept."""
    if f.exists() and f.stat().st_size > keep:
        with open(f, "rb") as x:
            x.seek(-keep, os.SEEK_END)
            tail = x.read()
        f.write_bytes(b"(the start is cut)\n" + tail)


def shares(tests, jobs):
    """tests ("file:method") into jobs lists of about the same time (the longest first, each to the least loaded one)."""
    try:
        known = json.loads(TIMES.read_text())
    except (OSError, ValueError):
        known = {}
    guess = sum(known.values()) / len(known) if known else 1.0
    load = [[0.0, []] for _ in range(min(jobs, len(tests)))]
    for f in sorted(tests, key=lambda f: -known.get(f, guess)):
        least = min(load, key=lambda x: x[0])
        least[0] += known.get(f, guess)
        least[1].append(f)
    return [sorted(fs) for _, fs in load]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-j", "--jobs", type=int, default=int(os.environ.get("TEST_JOBS") or max(1, (os.cpu_count() or 3) - 2)))
    ap.add_argument("filter", nargs="?", default="")
    a = ap.parse_args()
    timeout = float(os.environ.get("TEST_TIMEOUT") or 600)
    logs = Path(tempfile.mkdtemp(prefix="classichs-tests-"))
    run = logs.name
    started = time.monotonic()
    shards = []
    ok = False
    try:
        listed = logs / "tests.txt"
        smoke = Shard("smoke", ["test_smoke.gd"], "", logs, run, TEST_LIST=str(listed))
        shards.append(smoke)
        watch([smoke], SMOKE_TIMEOUT)
        if smoke.stopped or smoke.proc.returncode != 0:
            trim(smoke.log)
            print("\n".join(smoke.output()[-20:]))
            why = f"hangs ({smoke.stopped})" if smoke.stopped else f"fails (exit code {smoke.proc.returncode})"
            print(f"tests/test_smoke.gd {why}: the test run does not start: check rules/bin "
                  f"(tools/build_rules.sh), the import (godot --headless --path . --import), a hung godot")
            return 1
        # every test, from the smoke's run.gd ("file" alone: a file that does not load, its FAIL says why)
        tests = [t for t in listed.read_text().split() if a.filter in t or ":" not in t]
        parts = shares(tests, max(1, a.jobs))
        # (one process with them all: no list, an environment variable has a size limit on Windows)
        work = [Shard(f"shard{i}", [] if len(parts) == 1 else ts, a.filter, logs, run) for i, ts in enumerate(parts)]
        shards += work
        watch(work, timeout)
        total = failed = 0
        times = {}
        for s in work:
            trim(s.log)
            out = s.output()
            fail_block = False
            summary = None
            for line in out:
                m = SUMMARY.match(line)
                if m:
                    summary = m
                elif line.startswith("TIME "):
                    _, f, ms = line.split()
                    times[f] = int(ms) / 1000
                elif line.startswith("FAIL "):
                    fail_block = True
                    print(line)
                elif fail_block and line.startswith("    "):
                    print(line)
                else:
                    fail_block = False
            if s.stopped:
                failed += 1
                print(f"STOPPED {s.name}: {s.stopped} (TEST_TIMEOUT, TEST_MAX_LOG_MB), on {s.now()[1]}")
            elif summary is None:
                failed += 1
                print(f"CRASH {s.name} (exit code {s.proc.returncode}) on {s.now()[1]}; the end of its output:")
                print("\n".join("    " + x for x in out[-15:]))
            else:
                total += int(summary.group(1))
                failed += int(summary.group(2))
        if not a.filter and not any(s.stopped for s in work):
            TIMES.parent.mkdir(exist_ok=True)
            tmp = TIMES.with_name(f"{TIMES.name}.{os.getpid()}.tmp")
            tmp.write_text(json.dumps(times, indent=1, sort_keys=True))
            tmp.replace(TIMES)
        print(f"{total} tests, {failed} failed ({len(work)} processes, {time.monotonic() - started:.0f} s)")
        ok = failed == 0 and total > 0
        return 0 if ok else 1
    finally:
        for s in shards:
            if s.proc.poll() is None:
                s.proc.kill()
                s.proc.wait()
        user = Path(shards[0].now()[0]).parent if shards and shards[0].now()[0] else None
        if user and user.name != run:
            user = None  # (never remove what is not this run's own folder)
        if ok:
            shutil.rmtree(logs, ignore_errors=True)
            if user:
                shutil.rmtree(user, ignore_errors=True)
                try:
                    user.parent.rmdir()  # classichs-tests, when no other run is there
                except OSError:
                    pass
        else:
            for f in logs.glob("*.log"):
                trim(f)
            print(f"kept for a look: the logs {logs}" + (f", the user:// folders {user}" if user else ""))


if __name__ == "__main__":
    sys.exit(main())
