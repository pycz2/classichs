#!/usr/bin/env python3
"""Draws the art of the Neonfall pack (packs/neon) with the local Codex CLI, batched
like tools/gen_card_art.py: one picture per entry of packs/neon/cards.json (its "look"),
plus the card back, the logo, the board and the menu backgrounds.

Usage: python3 tools/neon_art.py [--batch 5] [--workers 3] [--ids ID ...]
Result: packs/neon/art/default/<id>.jpg (cards 512x512; board/menu 1920x1080; card_back
512x768; logo 1280x720). Existing pictures are kept, so a second run only retries failures.
"""
import argparse
import concurrent.futures as cf
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
from gen_card_art import CODEX  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
PACK = os.path.join(ROOT, "packs", "neon")
OUT = os.path.join(PACK, "art", "default")
WORK = os.environ.get("NEON_WORK", os.path.join(ROOT, "build", "neon_art"))

STYLE = (
    "One shared style for every image: cyberpunk noir digital painting of a rain-soaked neon megacity at night; "
    "wet reflective surfaces, chrome and glass, glowing magenta, cyan and amber neon light, volumetric haze and "
    "falling rain, high contrast, cinematic rim light, painterly but crisp, deep blue-black shadows. "
    "One clear subject, large in the frame, readable even when very small. "
    "Absolutely no text, letters, numbers, signs with writing, card frames, borders, UI, watermarks or logos "
    "(neon signs show only abstract glowing shapes). Invent an original design: do not copy or imitate any "
    "existing game, film, comic or brand."
)
KIND = {"MINION": "a character or creature", "SPELL": "the visible effect of an action or program",
        "WEAPON": "a weapon", "CHAMPION": "a champion portrait, head and shoulders", "POWER": "an ability effect"}
# id: (aspect, size for sips -z "h w" after cropping, what to draw)
EXTRA = {
    "card_back": ("portrait 2:3", (768, 512), "the back of a playing card: a symmetrical emblem of a stylized rain drop "
                  "made of neon circuitry, magenta and cyan, centred on dark brushed chrome with thin glowing lines"),
    "board": ("landscape 16:9", (1080, 1920), "a top-down view of a wide game table: a dark wet metal and glass surface "
                                              "with subtle glowing cyan grid lines and magenta edge lights, a calm empty centre, "
                                              "rain drops on the glass, no objects in the middle"),
    "menu": ("landscape 16:9", (1080, 1920), "a sweeping view of a vertical neon megacity built on stilts over a drowned "
                                             "coast at night, endless rain, flying vehicles, huge holograms, a rooftop in the foreground"),
    "result_victory": ("landscape 16:9", (1080, 1920), "the moment of victory: a lone silhouetted figure on a rain-swept rooftop "
                       "raising a fist as the whole neon skyline lights up in celebration, fireworks of cyan and gold data sparks"),
    "result_defeat": ("landscape 16:9", (1080, 1920), "the moment of defeat: a shattered chrome helmet lying in a dark flooded alley, "
                      "flickering broken neon, red warning glow reflected in puddles, heavy rain"),
    "result_draw": ("landscape 16:9", (1080, 1920), "a stalemate: two empty chairs facing each other across a wet metal table "
                    "under a single humming neon lamp, rain on the window, everything in balance"),
    "logo": ("landscape 16:9", (720, 1280), "a game logo: the single word NEONFALL in bold glowing magenta and cyan neon tube "
                                            "letters with falling rain streaks and a chrome bevel, on a plain pure black background. "
                                            "This one image must contain exactly the word NEONFALL and no other text"),
}


def jobs():
    cards = json.load(open(os.path.join(PACK, "cards.json")))
    out = [(c["id"], "square 1:1", (512, 512), f'{KIND[c["type"]]}: {c["look"]}') for c in cards]
    out += [(k, a, s, d) for k, (a, s, d) in EXTRA.items()]
    return out


def finish(src, dst, size):
    """Crops the picture to the target aspect and scales it to size (h, w) as a JPEG q80."""
    h, w = size
    out = subprocess.run(["sips", "-g", "pixelHeight", "-g", "pixelWidth", src], capture_output=True, text=True).stdout
    sh, sw = [int(l.split()[-1]) for l in out.splitlines()[1:3]]
    if sw * h > sh * w:  # too wide
        cw, ch = sh * w // h, sh
    else:
        cw, ch = sw, sw * h // w
    subprocess.run(["sips", "-c", str(ch), str(cw), src], capture_output=True)  # crop first, sips mixes up -c with -z
    subprocess.run(["sips", "-z", str(h), str(w), "-s", "format", "jpeg", "-s", "formatOptions", "80", src, "--out", dst],
                   capture_output=True)
    return os.path.exists(dst)


def run_batch(batch):
    work = os.path.join(WORK, batch[0][0])
    os.makedirs(os.path.join(work, "out"), exist_ok=True)
    lines = "\n".join(f"- ID {i} ({aspect}): {desc}" for i, aspect, _, desc in batch)
    prompt = (
        f"Use your built-in image generation tool (not code, not other tools) to create {len(batch)} images, "
        "one per entry listed below, in the given order, each in its own aspect ratio.\n"
        f"{STYLE}\n"
        "After generating each image, copy the generated PNG file to ./out/<ID>.png (use the exact ID). "
        "Do not create any other files. Entries:\n" + lines
    )
    t0 = time.time()
    r = subprocess.run([CODEX, "exec", "--skip-git-repo-check", "--ephemeral", "-s", "workspace-write", "-C", work, prompt],
                       stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=2400)
    done = []
    for i, _, size, _ in batch:
        src = os.path.join(work, "out", i + ".png")
        if os.path.exists(src) and finish(src, os.path.join(OUT, i + ".jpg"), size):
            done.append(i)
    tail = (r.stdout + r.stderr)[-300:].replace("\n", " ") if len(done) < len(batch) else ""
    return done, time.time() - t0, tail


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--batch", type=int, default=5)
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--ids", nargs="*")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    todo = [j for j in jobs() if (not a.ids or j[0] in a.ids) and not os.path.exists(os.path.join(OUT, j[0] + ".jpg"))]
    batches = [todo[k:k + a.batch] for k in range(0, len(todo), a.batch)]
    print(f"{len(todo)} pictures in {len(batches)} batches, {a.workers} workers", flush=True)
    total = 0
    with cf.ThreadPoolExecutor(a.workers) as pool:
        for done, secs, tail in pool.map(run_batch, batches):
            total += len(done)
            print(f"+{len(done)} in {secs:.0f}s (total {total}/{len(todo)}) {done} {tail}", flush=True)
    return 0 if total == len(todo) else 1


if __name__ == "__main__":
    sys.exit(main())
