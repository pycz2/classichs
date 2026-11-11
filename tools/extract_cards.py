#!/usr/bin/env python3
"""Download HearthstoneJSON and write data/cards.json.

With --set <name> [file]: data/<name>_cards.json, the cards of a set after Classic (SETS: naxx, gvg, brm, …;
--naxx = --set naxx, which also writes data/naxx_texts.json).

Keeps: set == VANILLA (no enchantments, FX dummies, puzzles), all TU4* tutorial
cards, and EXTRA ids (heroes, The Coin, tokens that VANILLA references by their
original ids). Run from the repo root: python3 tools/extract_cards.py
"""
import json
import re
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
Mekka1 Mekka2 Mekka3 Mekka4 Mekka4t PRO_001a PRO_001b PRO_001at EX1_409t EX1_398t
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
    by_id = {c["id"]: c for c in cards}
    out = [{k: c[k] for k in FIELDS if k in c} for c in cards if keep(c)]
    for c in out:
        # Deck codes from 2014-era decks use the original cards' dbfIds (CS2_029, not VAN_CS2_029).
        orig = by_id.get(c["id"][4:]) if c["id"].startswith("VAN_") else None
        if orig:
            c["legacyDbfId"] = orig["dbfId"]
    for c in out:
        # HearthstoneJSON stores weapon durability in "health"; the engine reads "durability".
        if c["type"] == "WEAPON" and "health" in c:
            c["durability"] = c.pop("health")
        # Some entries carry a wrong spellDamage (Malygos: 1); the card text is authoritative.
        m = re.search(r"Spell Damage \+(\d+)", c.get("text", {}).get("enUS", ""))
        if m:
            c["spellDamage"] = int(m.group(1))
    out.sort(key=lambda c: c["id"])
    missing = sorted(set(EXTRA) - {c["id"] for c in out})
    if missing:
        raise SystemExit(f"missing extra ids: {missing}")
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=0, sort_keys=True) + "\n")
    print(f"wrote {len(out)} cards to {OUT}")


# --- Curse of Naxxramas (packs/naxx) ------------------------------------------------------------

NAXX_TOKENS = ["FP1_002t", "FP1_007t", "FP1_012t", "FP1_014t", "FP1_019t"]
## Texts as they were at the Naxxramas release (2014-07-22), taken from cards that still carry them
## (card id -> {field: donor id}); Webspinner's has no donor and is written out (WEBSPINNER).
NAXX_DONORS = {
    "FP1_008": {"text": "MAW_021e2"},       # Spectral Knight: "Can't be targeted by spells or Hero Powers." (Elusive came in 2024)
    "FP1_010": {"text": "VAN_EX1_170"},     # Maexxna: "Destroy any minion damaged by this minion." (Poisonous came in 2017)
    "FP1_025": {"text": "FP1_025_Puzzle"},  # Reincarnate: any minion (non-Legendary only since 2026)
    "FP1_012t": {"name": "OG_202c"},        # Slime (renamed Putrid Slime in 2020)
    "VAN_EX1_536": {"text": "EX1_536"},     # Eaglehorn Bow: only friendly Secrets (patch 1.1.0.6024)
    "VAN_CS2_038": {"text": "CS2_038"},     # Ancestral Spirit: "Deathrattle: Resummon this minion." (patch 1.1.0.6024)
}
WEBSPINNER = {
    "enUS": "<b>Deathrattle:</b> Add a random Beast card to your hand.",
    "ruRU": "<b>Предсмертный хрип:</b> вы получаете случайную карту зверя.",
    "deDE": "<b>Todesröcheln:</b> Fügt Eurer Hand eine zufällige Wildtierkarte hinzu.",
    "frFR": "<b>Râle d’agonie :</b> ajoute une carte Bête aléatoire dans votre main.",
    "esES": "<b>Último aliento:</b> añade una carta de bestia aleatoria a tu mano.",
    "ptBR": "<b>Último Suspiro:</b> Adiciona um card de Fera aleatório à sua mão.",
    "itIT": "<b>Rantolo di Morte:</b> aggiunge una carta Bestia casuale alla tua mano.",
    "plPL": "<b>Agonia:</b> Dodaje do twojej ręki losową kartę bestii.",
}


## The sets after Classic, one pack each, in order (docs/superpowers/plans/2026-11-11-expansions.md): pack name ->
## (HearthstoneJSON set, card id prefixes, tokens). The cards of a set: every collectible card whose id has one of the
## prefixes, and its tokens: the listed ids, or (None) every other card of that HearthstoneJSON set with a prefix
## (not enchantments). tools/fetch_set_assets.py downloads the art and sounds of the same cards.
SETS = {
    "naxx": ("NAXX", ["FP1_"], NAXX_TOKENS),
    "gvg": ("GVG", ["GVG_", "PART_"], None),
    "brm": ("BRM", ["BRM_"], None),
    "tgt": ("TGT", ["AT_"], None),
    "loe": ("LOE", ["LOE_"], None),
    "og": ("OG", ["OG_"], None),
    "kara": ("KARA", ["KAR_"], None),
    "msg": ("GANGS", ["CFM_"], None),
    "ungoro": ("UNGORO", ["UNG_"], None),
    "icc": ("ICECROWN", ["ICC_"], None),
    "loot": ("LOOTAPALOOZA", ["LOOT_"], None),
    "gil": ("GILNEAS", ["GIL_"], None),
}


def set_cards(cards, name):
    """The cards of set `name` (SETS) in data/cards.json's shape, sorted by id."""
    code, prefixes, tokens = SETS[name]
    prefixes = tuple(prefixes)

    def keep(c):
        if not c["id"].startswith(prefixes) or c["type"] == "ENCHANTMENT" or "puzzle" in c["id"].lower():
            return False  # (puzzles are Boomsday's puzzle lab copies)
        if c.get("collectible"):
            return True
        return c["id"] in tokens if tokens is not None else c.get("set") == code

    out = [{k: c[k] for k in FIELDS if k in c} for c in cards if keep(c)]
    for c in out:
        if c["type"] == "WEAPON" and "health" in c:  # HearthstoneJSON keeps durability in "health"
            c["durability"] = c.pop("health")
    return sorted(out, key=lambda c: c["id"])


def extract_set(cards, name):
    """data/<name>_cards.json: every card of the set as HearthstoneJSON has it today (the pack's cards.patch.json
    restores the stats and tribes of the release day, its *.texts.json the texts). Naxxramas also writes
    data/naxx_texts.json (its release-time names and texts, taken from cards that still carry them)."""
    out = set_cards(cards, name)
    (OUT.parent / f"{name}_cards.json").write_text(json.dumps(out, ensure_ascii=False, indent=0, sort_keys=True) + "\n")
    print(f"wrote {len(out)} cards of {name} ({SETS[name][0]})")
    if name == "naxx":
        by_id = {c["id"]: c for c in cards}
        local = {c["id"]: c for c in json.loads(OUT.read_text())}
        texts = {cid: {f: (local.get(src) or by_id[src])[f] for f, src in fields.items()} for cid, fields in NAXX_DONORS.items()}
        texts["FP1_011"] = {"text": WEBSPINNER}
        (OUT.parent / "naxx_texts.json").write_text(json.dumps(texts, ensure_ascii=False, indent=1, sort_keys=True) + "\n")
        print(f"wrote {len(texts)} Naxxramas release texts")


def hsjson():
    req = urllib.request.Request(URL, headers={"User-Agent": "classic-hs-extract/1.0"})
    with urllib.request.urlopen(req) as r:
        return json.load(r)


if __name__ == "__main__":
    import sys
    # python3 tools/extract_cards.py --set gvg [HearthstoneJSON cards.json]   (--naxx = --set naxx)
    args = ["--set", "naxx"] + [a for a in sys.argv[1:] if a != "--naxx"] if "--naxx" in sys.argv else sys.argv[1:]
    if args[:1] == ["--set"]:
        if len(args) < 2 or args[1] not in SETS:
            raise SystemExit(f"--set wants one of: {', '.join(SETS)}")
        extract_set(json.loads(pathlib.Path(args[2]).read_text()) if args[2:] else hsjson(), args[1])
    else:
        main()
