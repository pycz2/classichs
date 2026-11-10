#!/usr/bin/env python3
"""Download HearthstoneJSON and write data/cards.json.

With --naxx [file]: data/naxx_cards.json and data/naxx_texts.json for packs/naxx (see naxx()).

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


def naxx(cards):
    """data/naxx_cards.json: every Naxxramas card (FP1_*, the 30 collectible and the tokens they make) as
    HearthstoneJSON has it today; data/naxx_texts.json: the release-time names and texts (packs/naxx's
    recipe applies them over these; its cards.patch.json restores the release stats and tribes)."""
    by_id = {c["id"]: c for c in cards}
    local = {c["id"]: c for c in json.loads(OUT.read_text())}
    out = [{k: c[k] for k in FIELDS if k in c} for c in cards
           if c["id"].startswith("FP1_") and c["type"] != "ENCHANTMENT"
           and (c.get("collectible") or c["id"] in NAXX_TOKENS)]
    for c in out:
        if c["type"] == "WEAPON" and "health" in c:
            c["durability"] = c.pop("health")
    out.sort(key=lambda c: c["id"])
    texts = {cid: {f: (local.get(src) or by_id[src])[f] for f, src in fields.items()} for cid, fields in NAXX_DONORS.items()}
    texts["FP1_011"] = {"text": WEBSPINNER}
    (OUT.parent / "naxx_cards.json").write_text(json.dumps(out, ensure_ascii=False, indent=0, sort_keys=True) + "\n")
    (OUT.parent / "naxx_texts.json").write_text(json.dumps(texts, ensure_ascii=False, indent=1, sort_keys=True) + "\n")
    print(f"wrote {len(out)} Naxxramas cards and {len(texts)} release texts")


if __name__ == "__main__":
    import sys
    if "--naxx" in sys.argv:  # python3 tools/extract_cards.py --naxx [HearthstoneJSON cards.json]
        args = [a for a in sys.argv[1:] if a != "--naxx"]
        if args:
            naxx(json.loads(pathlib.Path(args[0]).read_text()))
        else:
            req = urllib.request.Request(URL, headers={"User-Agent": "classic-hs-extract/1.0"})
            with urllib.request.urlopen(req) as r:
                naxx(json.load(r))
    else:
        main()
