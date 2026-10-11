#!/usr/bin/env python3
"""Generates card illustrations with the local Codex CLI (its built-in image tool).

Usage: python3 tools/gen_card_art.py [--batch 5] [--workers 3] [--limit N] [--ids ID ...]
Result: art/cards/<card id>.jpg (256x256, JPEG). Cards that already have a file are
skipped, so an interrupted run continues where it stopped. Codex works in
build/card_art/ and copies every generated image to build/card_art/out/<id>.png.
"""
import argparse
import concurrent.futures as cf
import json
import os
import re
import subprocess
import sys
import time

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "art", "cards")
WORK = os.path.join(ROOT, "build", "card_art")
CODEX = os.environ.get("CODEX", "/Applications/ChatGPT.app/Contents/Resources/codex")
SIZE = 256

STYLE = (
    "Style for every image: a painterly digital fantasy illustration for a collectible card game, "
    "warm saturated colours, soft rim light, rich detail, dramatic but friendly, slightly stylized "
    "proportions, one clear subject centred with breathing room, simple atmospheric background. "
    "Square 1:1. Absolutely no text, letters, numbers, card frames, borders, UI, watermarks or logos. "
    "Invent an original composition for each card: do not copy or imitate any existing card art, "
    "game screenshots or official character designs."
)


def english(v):
    return v.get("enUS", "") if isinstance(v, dict) else (v or "")


def describe(c):
    text = re.sub(r"<[^>]+>|[$#\[\]]|\{\d\}", "", english(c.get("text"))).replace("\n", " ").strip()
    kind = {"MINION": "creature", "SPELL": "spell effect", "WEAPON": "weapon", "HERO": "hero portrait",
            "HERO_POWER": "hero ability effect"}.get(c["type"], c["type"].lower())
    bits = [f'"{english(c["name"])}"', kind]
    if c.get("race"):
        bits.append(c["race"].lower())
    if c.get("cardClass") not in (None, "NEUTRAL"):
        bits.append(c["cardClass"].lower() + " class")
    if text:
        bits.append(f"effect: {text}")
    return "; ".join(bits)


def run_batch(batch):
    os.makedirs(os.path.join(WORK, "out"), exist_ok=True)
    lines = "\n".join(f"- ID {c['id']}: {describe(c)}" for c in batch)
    prompt = (
        f"Use your built-in image generation tool (not code, not other tools) to create {len(batch)} images, "
        "one per card listed below, in the given order. For each card, show what the card is: the creature "
        "or character, the weapon, or the visible magic of the spell.\n"
        f"{STYLE}\n"
        "After generating each image, copy the generated PNG file to ./out/<ID>.png (use the exact ID). "
        "Do not create any other files. Cards:\n" + lines
    )
    t0 = time.time()
    r = subprocess.run([CODEX, "exec", "--skip-git-repo-check", "--ephemeral", "-s", "workspace-write", "-C", WORK, prompt],
                       stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=1800)
    done = []
    for c in batch:
        src = os.path.join(WORK, "out", c["id"] + ".png")
        if os.path.exists(src):
            dst = os.path.join(OUT, c["id"] + ".jpg")
            subprocess.run(["sips", "-Z", str(SIZE), "-s", "format", "jpeg", "-s", "formatOptions", "75", src, "--out", dst],
                           capture_output=True)
            if os.path.exists(dst):
                with open(dst + ".import", "w") as f:  # Godot exports the JPEG as it is
                    f.write('[remap]\n\nimporter="keep"\n')
                done.append(c["id"])
                os.remove(src)
    tail = (r.stdout or "")[-300:].replace("\n", " ") if len(done) < len(batch) else ""
    return done, time.time() - t0, tail


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--batch", type=int, default=5)
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--ids", nargs="*")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    data = json.load(open(os.path.join(ROOT, "data", "cards.json")))
    cards = data if isinstance(data, list) else list(data.values())
    todo = [c for c in cards if (not a.ids or c["id"] in a.ids) and not os.path.exists(os.path.join(OUT, c["id"] + ".jpg"))]
    todo.sort(key=lambda c: (not c.get("collectible", False), c.get("dbfId", 0)))
    if a.limit:
        todo = todo[: a.limit]
    batches = [todo[i: i + a.batch] for i in range(0, len(todo), a.batch)]
    print(f"{len(todo)} cards in {len(batches)} batches, {a.workers} workers", flush=True)
    total = 0
    with cf.ThreadPoolExecutor(a.workers) as pool:
        for done, secs, tail in pool.map(run_batch, batches):
            total += len(done)
            print(f"+{len(done)} in {secs:.0f}s (total {total}/{len(todo)}) {tail}", flush=True)
    return 0 if total == len(todo) else 1


if __name__ == "__main__":
    sys.exit(main())
