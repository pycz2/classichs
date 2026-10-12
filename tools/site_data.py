#!/usr/bin/env python3
"""Writes the landing page data (heroes and showcase cards with names and texts in
the game's 8 languages) and copies the heroes' portraits. Used by tools/build_site.sh.

Usage: python3 tools/site_data.py <out dir>
"""
import gzip
import json
import os
import re
import shutil
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
LANGS = {"en": "enUS", "ru": "ruRU", "de": "deDE", "fr": "frFR", "es": "esES", "pt_BR": "ptBR", "it": "itIT", "pl": "plPL"}
HEROES = ["HERO_08", "HERO_01", "HERO_05", "HERO_06", "HERO_03", "HERO_09", "HERO_04", "HERO_02", "HERO_07"]
## The page shows the first 6 floating in the header and the first 9 in the fan;
## tools/site_cards.gd draws their pictures.
SHOWCASE = ["VAN_CS2_029", "VAN_CS2_182", "VAN_CS2_033", "VAN_EX1_298", "VAN_CS2_022", "VAN_CS2_112", "VAN_EX1_116",
            "VAN_CS2_042", "VAN_CS2_200"]


def text(v, lang):
    s = v.get(LANGS[lang], v.get("enUS", "")) if isinstance(v, dict) else (v or "")
    return re.sub(r"<[^>]+>|[$#\[\]]|\{\d\}", "", s).replace("\n", " ").strip()


## What a browser downloads on the first start: the game files as the server
## sends them (compressed), in MB.
def download_mb(play):
    files = ["index.wasm", "index.pck", "index.js"]
    size = sum(len(gzip.compress(open(os.path.join(play, f), "rb").read(), 6)) for f in files)
    return round(size / 1e6)


def main(out):
    data = json.load(open(os.path.join(ROOT, "data", "cards.json")))
    cards = {c["id"]: c for c in (data if isinstance(data, list) else data.values())}
    os.makedirs(os.path.join(out, "art"), exist_ok=True)

    def entry(cid):
        c = cards[cid]
        src = os.path.join(ROOT, "art", "cards", cid + ".jpg")
        if not os.path.exists(src):
            return None
        if c["type"] == "HERO":  # hero portraits; the cards are pictures drawn by the game
            shutil.copy(src, os.path.join(out, "art", cid + ".jpg"))
        e = {"id": cid, "type": c["type"], "cls": c.get("cardClass", "NEUTRAL"), "rarity": c.get("rarity", ""),
             "cost": c.get("cost"), "atk": c.get("attack"), "hp": c.get("health", c.get("durability")),
             "name": {l: text(c["name"], l) for l in LANGS}, "text": {l: text(c.get("text"), l) for l in LANGS}}
        if c["type"] == "HERO":
            power = cards.get("VAN_" + cid + "bp") or cards.get(cid + "bp")
            if power:
                e["power"] = {l: text(power["name"], l) for l in LANGS}
        return e

    site = {"heroes": [e for e in map(entry, HEROES) if e], "cards": [e for e in map(entry, SHOWCASE) if e],
            "total": sum(1 for c in cards.values() if c.get("collectible") and c["type"] != "HERO"),
            "download_mb": download_mb(os.path.join(out, "play"))}
    json.dump(site, open(os.path.join(out, "data.json"), "w"), ensure_ascii=False)
    print(f"site data: {len(site['heroes'])} heroes, {len(site['cards'])} cards, download {site['download_mb']} MB")


if __name__ == "__main__":
    main(sys.argv[1])
