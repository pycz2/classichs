#!/usr/bin/env python3
"""Downloads the original card art from HearthstoneJSON (https://hearthstonejson.com/docs/images.html).

Usage: python3 tools/fetch_original_art.py [--workers 8]
Result: art/original/<card id>.jpg (256x256). The art belongs to Blizzard Entertainment:
the folder is kept out of git and out of the published web build; it is for local play.
Cards already downloaded are skipped.
"""
import argparse
import concurrent.futures as cf
import json
import os
import urllib.request

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "art", "original")
URL = "https://art.hearthstonejson.com/v1/256x/%s.jpg"


def fetch(card_id):
    dst = os.path.join(OUT, card_id + ".jpg")
    if os.path.exists(dst):
        return card_id, "have"
    for cid in (card_id, card_id.removeprefix("VAN_")):
        try:
            req = urllib.request.Request(URL % cid, headers={"User-Agent": "classic-hs-fan-remake/0.8"})
            data = urllib.request.urlopen(req, timeout=30).read()
            with open(dst, "wb") as f:
                f.write(data)
            with open(dst + ".import", "w") as f:  # Godot keeps the JPEG as it is
                f.write('[remap]\n\nimporter="keep"\n')
            return card_id, "ok"
        except Exception as e:  # try the id without VAN_, then give up
            err = str(e)
    return card_id, "missing: " + err


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workers", type=int, default=8)
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    data = json.load(open(os.path.join(ROOT, "data", "cards.json")))
    ids = [c["id"] for c in (data if isinstance(data, list) else data.values())]
    counts = {}
    with cf.ThreadPoolExecutor(a.workers) as pool:
        for cid, status in pool.map(fetch, ids):
            key = status.split(":")[0]
            counts[key] = counts.get(key, 0) + 1
            if key == "missing":
                print(cid, status, flush=True)
    print(counts)


if __name__ == "__main__":
    main()
