#!/usr/bin/env python3
"""Download HearthstoneJSON and write data/cards.json.

Keeps: set == VANILLA (no enchantments, FX dummies, puzzles), all TU4* tutorial
cards, and EXTRA ids (heroes, The Coin, tokens that VANILLA references by their
original ids). Run from the repo root: python3 tools/extract_cards.py
"""
import json
import pathlib
import urllib.request

URL = "https://api.hearthstonejson.com/v1/latest/all/cards.json"
OUT = pathlib.Path(__file__).resolve().parent.parent / "data" / "cards.json"
FIELDS = ["id", "dbfId", "set", "type", "cardClass", "rarity", "cost", "attack", "health",
          "durability", "overload", "spellDamage", "race", "mechanics", "referencedTags",
          "collectible", "elite", "name", "text"]
EXTRA = [f"HERO_0{i}" for i in range(1, 10)] + """
EX1_323h EX1_323w EX1_383t GAME_005 CS2_013t EX1_317t EX1_131t EX1_625t EX1_625t2 EX1_014t
NEW1_040t ds1_whelptoken EX1_116t hexfrog EX1_025t EX1_534t EX1_538t EX1_160t
Mekka1 Mekka2 Mekka3 Mekka4 Mekka4t PRO_001a PRO_001b PRO_001at
""".split()
JUNK_PREFIXES = ("Story_", "VAN_DFX_", "VAN_GAME_")


def keep(c):
    if c["id"] in EXTRA:
        return True
    if c["id"].startswith("TU4"):
        return c["type"] != "ENCHANTMENT"
    return (c.get("set") == "VANILLA" and c["type"] != "ENCHANTMENT"
            and not c["id"].startswith(JUNK_PREFIXES))


def main():
    req = urllib.request.Request(URL, headers={"User-Agent": "classic-hs-extract/1.0"})
    with urllib.request.urlopen(req) as r:
        cards = json.load(r)
    out = [{k: c[k] for k in FIELDS if k in c} for c in cards if keep(c)]
    for c in out:
        # HearthstoneJSON stores weapon durability in "health"; the engine reads "durability".
        if c["type"] == "WEAPON" and "health" in c:
            c["durability"] = c.pop("health")
    out.sort(key=lambda c: c["id"])
    missing = sorted(set(EXTRA) - {c["id"] for c in out})
    if missing:
        raise SystemExit(f"missing extra ids: {missing}")
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=0, sort_keys=True) + "\n")
    print(f"wrote {len(out)} cards to {OUT}")


if __name__ == "__main__":
    main()
