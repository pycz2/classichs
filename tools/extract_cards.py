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
          "collectible", "elite", "name", "text", "classes"]
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


## Goblins vs Gnomes' tokens at its release (build 7234): the options, Gallywix's Coin, the Mine, the Boom Bot,
## V-07-TR-0N, … and the seven Spare Parts (today's set also has GVG_COIN, a later coin skin).
GVG_TOKENS = """GVG_028t GVG_030a GVG_030b GVG_032a GVG_032b GVG_041a GVG_041b GVG_045t GVG_056t GVG_080t GVG_092t
GVG_110t GVG_111t PART_001 PART_002 PART_003 PART_004 PART_005 PART_006 PART_007""".split()

## Blackrock Mountain's tokens at its release (build 8311, patch 2.4.0.8311 of 2015-03-31, two days before the first
## wing): the Imp, Druid of the Flame's options and forms, the Black Whelp, Ragnaros the hero and his power, Tail Swipe
## (Nefarian against a hero without a class). Not the boss cards (BRM_004t, BRM_027pH: the adventure's).
BRM_TOKENS = "BRM_006t BRM_010a BRM_010b BRM_010t BRM_010t2 BRM_022t BRM_027h BRM_027p BRM_030t".split()

## The League of Explorers' tokens at its release (build 10833, patch 4.0.0.10833 of 2015-11-10, two days before the
## first wing): the Roaring Torch, Cursed!, the Scarab, the Map and the Golden Monkey, the Runts, the Ancient Curse,
## Raven Idol's options and Arch-Thief Rafaam's three Artifacts (with Mirror of Doom's Mummy Zombie). Not the
## adventure's boss cards (Eye of Hakkar, the Rock, the Rolling Boulder, LOE_030).
LOE_TOKENS = """LOE_002t LOE_007t LOE_009t LOE_019t LOE_019t2 LOE_089t LOE_089t2 LOE_089t3 LOE_110t LOE_115a LOE_115b
LOEA16_3 LOEA16_4 LOEA16_5 LOEA16_5t""".split()

## Whispers of the Old Gods' tokens at its release (build 12574, patch 5.0.0.12574 of 2016-04-24, two days before the
## release): the Choose One options, the Toxins, the Tentacles, Slimes, Wisps, the Ancient One, Vek'nilash, the Tidal Hand
## and its Murloc, and Fandral Staghelm's combined forms (OG_044a-c, in older sets' data). Not OG_279 (C'Thun's stand-in
## for the corner portrait) nor OG_270a (a Nerubian Soldier no card makes).
OG_TOKENS = """OG_006a OG_006b OG_031a OG_044a OG_044b OG_044c OG_047a OG_047b OG_058 OG_061t OG_080b OG_080c OG_080d OG_080e
OG_080f OG_114a OG_156a OG_173a OG_195a OG_195b OG_195c OG_202a OG_202b OG_202c OG_216a OG_241a OG_249a OG_272t OG_314b
OG_318t OG_319""".split()

## One Night in Karazhan's tokens at its release (build 13921, patch 6.0.0.13921 of 2016-08-09, two days before the
## first wing): the Panther, the Big Bad Wolf, the Whelps, Kara Kazham!'s Candle, Broom and Teapot, the Pawn, the Cellar
## Spider, the Steward, the Sharp Fork, Atiesh and the Animated Shield. Not the adventure's boss cards (KAR_A*, KAR_a10*)
## nor the unused Moonglade Portal options (KAR_003a-b).
KARA_TOKENS = "KAR_004a KAR_005a KAR_010a KAR_025a KAR_025b KAR_025c KAR_026t KAR_030 KAR_044a KAR_094a KAR_097t KAR_710m".split()

## The build of each set's release day (HearthSim hsdata, HearthstoneJSON keeps every build): `--set <s>` also
## writes packs/<s>/cards.texts.json, the names and texts of that day in every language for each card of the pack's
## chain (Classic's VAN_ cards by their 2014 ids) where today's differ. Confirm a build on the wiki's patch page.
RELEASE_BUILDS = {"gvg": 7234, "brm": 8311, "tgt": 9786, "loe": 10833, "og": 12574, "kara": 13921, "msg": 15590, "ungoro": 18336, "icc": 20457, "loot": 22611, "gil": 23966}
## Sets whose own cards come from the release build itself, not from today's data: today's The Grand Tournament
## was reworked in 2023 (dozens of costs, stats and texts) and lost its upgraded hero powers (AT_132_*, now
## HERO_0Xbp2 skins), so its patch would restate most of the set. Today's data only adds what the old builds lack
## (dbfId, elite, the TRIGGER_VISUAL mark; referencedTags where the English text is unchanged). The League of
## Explorers too: today's data changed a third of it (Naga Sea Witch 8 mana, Keeper of Uldaman 3, Tomb Pillager 6/4,
## Ancient Curse "Casts When Drawn", tribes added later…).
## Whispers of the Old Gods too: C'Thun and its cards, Cho'gall, Usher of Souls, Addled Grizzly, Hallazeal… changed later.
## One Night in Karazhan too: reworked in 2021-22 (Barnes 5, The Curator 5, Ivory Knight 4, Firelands Portal 6 damage…).
## Mean Streets of Gadgetzan too: nerfed and reworked since (Small-Time Buccaneer, Patches, Jade Spirit, Kazakus…).
## Journey to Un'Goro and Knights of the Frozen Throne too (Spreading Plague 6, Shadow Essence 7, Leeching Poison 1 since).
## Kobolds & Catacombs too (build 22611, patch 10.0.0.22611): Corridor Creeper, Kobold Illusionist, Cataclysm, Twig of the
## World Tree, Sleepy Dragon, Elven Minstrel, Arcane Artificer changed later; Ixlid lost its Elemental tribe, others got one.
## The Witchwood too (build 23966, patch 11.0.0.23966): Fiendish Circle 3, Witch's Apprentice 0, Darius Crowley 4/5, Tess
## Greymane 7, Witchwood Apple, Rotten Applebaum, Snap Freeze, Blazing Invocation, Woodcutter's Axe changed since; the
## Undead tribe came later.
FROM_RELEASE = {"tgt", "loe", "og", "kara", "msg", "ungoro", "icc", "loot", "gil"}
LANGS = ["enUS", "ruRU", "deDE", "frFR", "esES", "ptBR", "itIT", "plPL"]
## Classic's Hero Powers had other ids in the old builds (VAN_HERO_06bp was CS2_017; the upgraded ones AT_132_*).
_CLASSES = ["WARRIOR", "SHAMAN", "ROGUE", "PALADIN", "HUNTER", "DRUID", "WARLOCK", "MAGE", "PRIEST"]
POWERS = {**{f"VAN_HERO_0{i}bp": p for i, p in enumerate(
    "CS2_102 CS2_049 CS2_083b CS2_101 DS1h_292 CS2_017 CS2_056 CS2_034 CS1h_001".split(), 1)},
    **{f"VAN_HERO_0{i}bp2": f"AT_132_{k}" for i, k in enumerate(_CLASSES, 1)}}


def _norm(t):
    """A text without what only lays it out today ([x], no-break spaces, runs of spaces)."""
    return re.sub(r"\s+", " ", (t or "").replace(" ", " ").replace("[x]", "")).strip()


def release_texts(name, then):
    """packs/<name>/cards.texts.json from `then` (HearthstoneJSON of RELEASE_BUILDS[name]): card id ->
    {name?, text?: {lang: text}} for every card of the chain (data/cards.json, the earlier sets' data files and
    this set's) whose name or text that day differs from today's in some language. A Classic card (VAN_<id>) is
    matched to <id> only when both are the same kind of card (type, with or without a text): VAN_EX1_tk9 is a plain
    Treant, EX1_tk9 was Force of Nature's. A later set's card keeps its id: its text of that day counts even when
    today's has none (Druid of the Flame's options were spells)."""
    old = {c["id"]: c for c in then}
    sets = list(SETS)[:list(SETS).index(name) + 1]
    chain = [OUT] + [OUT.parent / f"{s}_cards.json" for s in sets]
    # what an earlier pack of the chain overrides (its texts of an older day) is restated with this day's, even
    # where this day's equals today's: the later texts file wins only for the cards it names
    earlier = {}
    for f in [OUT.parent / "naxx_texts.json"] + [OUT.parent.parent / "packs" / s / "cards.texts.json" for s in sets[:-1]]:
        if f.exists():
            for cid, fields in json.loads(f.read_text()).items():
                earlier.setdefault(cid, set()).update(fields)
    out = {}
    for f in chain:
        for c in json.loads(f.read_text()):
            o = old.get(POWERS.get(c["id"]) or (c["id"][4:] if c["id"].startswith("VAN_") else c["id"]))
            if not o or (c["id"].startswith("VAN_") and (o["type"] != c["type"] or bool(o.get("text")) != bool(c.get("text")))):
                continue
            if not c["id"].startswith("VAN_") and o.get("text") and not c.get("text"):
                c = dict(c, text={})  # the same card, whose text today's data lost (Druid of the Flame's options)
            for field in ("name", "text"):
                now, was = c.get(field) or {}, o.get(field) or {}
                if was and (field in earlier.get(c["id"], ()) or any(_norm(now.get(l)) != _norm(was.get(l)) for l in LANGS)):
                    out.setdefault(c["id"], {})[field] = {l: was.get(l) or now.get(l, "") for l in LANGS}
    dst = OUT.parent.parent / "packs" / name / "cards.texts.json"
    dst.write_text(json.dumps(out, ensure_ascii=False, indent=1, sort_keys=True) + "\n")
    print(f"wrote {len(out)} cards' texts of build {RELEASE_BUILDS[name]} to {dst}")


## The sets after Classic, one pack each, in order (docs/superpowers/plans/2026-11-11-expansions.md): pack name ->
## (HearthstoneJSON set, card id prefixes, tokens). The cards of a set: every collectible card whose id has one of the
## prefixes, and its tokens: the listed ids, or (None) every other card of that HearthstoneJSON set with a prefix
## (not enchantments). tools/fetch_set_assets.py downloads the art and sounds of the same cards.
SETS = {
    "naxx": ("NAXX", ["FP1_"], NAXX_TOKENS),
    "gvg": ("GVG", ["GVG_", "PART_"], GVG_TOKENS),
    "brm": ("BRM", ["BRM_"], BRM_TOKENS),
    "tgt": ("TGT", ["AT_"], None),
    "loe": ("LOE", ["LOE_", "LOEA"], LOE_TOKENS),  # (LOEA10_3: Murloc Tinyfin; LOEA16_*: the Artifacts)
    "og": ("OG", ["OG_"], OG_TOKENS),
    "kara": ("KARA", ["KAR_"], KARA_TOKENS),
    "msg": ("GANGS", ["CFM_"], None),
    "ungoro": ("UNGORO", ["UNG_"], None),
    "icc": ("ICECROWN", ["ICC_"], None),
    "loot": ("LOOTAPALOOZA", ["LOOT_"], None),
    "gil": ("GILNEAS", ["GIL_"], None),
}


## Cards of the data that are no card of the game: Val'anyr's re-equip dummy (Kobolds & Catacombs).
DUMMIES = {"LOOT_500d"}
## Tokens of a set made with another set's prefix: Deathstalker Rexxar's new Zombeast parts of patch 11.0.0.23966 (the
## Kobolds & Catacombs and Witchwood Beasts his Build-A-Beast offers from then on).
EXTRA_TOKENS = {"gil": {"ICC_828t4", "ICC_828t5", "ICC_828t6", "ICC_828t7"}}


def set_cards(cards, name):
    """The cards of set `name` (SETS) in data/cards.json's shape, sorted by id."""
    code, prefixes, tokens = SETS[name]
    prefixes = tuple(prefixes)

    def keep(c):
        if c["id"] in EXTRA_TOKENS.get(name, ()):
            return True
        if not c["id"].startswith(prefixes) or c["type"] == "ENCHANTMENT" or "puzzle" in c["id"].lower() or c["id"] in DUMMIES:
            return False  # (puzzles are Boomsday's puzzle lab copies)
        if c.get("collectible"):
            return True
        return c["id"] in tokens if tokens is not None else c.get("set") == code

    out = [{k: c[k] for k in FIELDS if k in c} for c in cards if keep(c)]
    for c in out:
        if c["type"] == "WEAPON" and "health" in c:  # HearthstoneJSON keeps durability in "health"
            c["durability"] = c.pop("health")
    return sorted(out, key=lambda c: c["id"])


def pack_cards(cards, name):
    """The cards of set `name` as its pack has them: data/<name>_cards.json for a FROM_RELEASE set (today's data lacks
    some of its ids), else set_cards of today's data (tools/fetch_set_assets.py: the art and sounds to fetch)."""
    if name in FROM_RELEASE:
        return json.loads((OUT.parent / f"{name}_cards.json").read_text())
    return set_cards(cards, name)


def release_cards(then, now):
    """The release build's cards in today's shape (FROM_RELEASE): cardClass for playerClass (NEUTRAL when none),
    and from today's data the dbfId, elite, TRIGGER_VISUAL and (same English text only) referencedTags."""
    today = {c["id"]: c for c in now}
    out = []
    for c in then:
        c = dict(c, cardClass=c.get("cardClass") or c.get("playerClass") or "NEUTRAL")
        t = today.get(c["id"], {})
        for k in ("dbfId", "elite"):
            if k in t:
                c[k] = t[k]
        if "TRIGGER_VISUAL" in t.get("mechanics", []) and "TRIGGER_VISUAL" not in c.get("mechanics", []):
            c["mechanics"] = c.get("mechanics", []) + ["TRIGGER_VISUAL"]
        if t.get("referencedTags") and _norm((t.get("text") or {}).get("enUS")) == _norm((c.get("text") or {}).get("enUS")):
            c["referencedTags"] = t["referencedTags"]
        out.append(c)
    return out


def extract_set(cards, name, then=None):
    """data/<name>_cards.json: every card of the set as HearthstoneJSON has it today (the pack's cards.patch.json
    restores the stats and tribes of the release day, its *.texts.json the texts), or as the release build has it
    (FROM_RELEASE). Naxxramas also writes data/naxx_texts.json (its release-time names and texts, taken from cards
    that still carry them)."""
    if name in FROM_RELEASE:
        then = then if then is not None else hsjson(RELEASE_BUILDS[name])
    out = set_cards(release_cards(then, cards) if name in FROM_RELEASE else cards, name)
    (OUT.parent / f"{name}_cards.json").write_text(json.dumps(out, ensure_ascii=False, indent=0, sort_keys=True) + "\n")
    print(f"wrote {len(out)} cards of {name} ({SETS[name][0]})")
    if name == "naxx":
        by_id = {c["id"]: c for c in cards}
        local = {c["id"]: c for c in json.loads(OUT.read_text())}
        texts = {cid: {f: (local.get(src) or by_id[src])[f] for f, src in fields.items()} for cid, fields in NAXX_DONORS.items()}
        texts["FP1_011"] = {"text": WEBSPINNER}
        (OUT.parent / "naxx_texts.json").write_text(json.dumps(texts, ensure_ascii=False, indent=1, sort_keys=True) + "\n")
        print(f"wrote {len(texts)} Naxxramas release texts")
    if name in RELEASE_BUILDS:
        release_texts(name, then if then is not None else hsjson(RELEASE_BUILDS[name]))


def hsjson(build="latest"):
    req = urllib.request.Request(URL.replace("latest", str(build)), headers={"User-Agent": "classic-hs-extract/1.0"})
    with urllib.request.urlopen(req) as r:
        return json.load(r)


if __name__ == "__main__":
    import sys
    # python3 tools/extract_cards.py --set gvg [HearthstoneJSON cards.json [the release build's]]   (--naxx = --set naxx)
    args = ["--set", "naxx"] + [a for a in sys.argv[1:] if a != "--naxx"] if "--naxx" in sys.argv else sys.argv[1:]
    if args[:1] == ["--set"]:
        if len(args) < 2 or args[1] not in SETS:
            raise SystemExit(f"--set wants one of: {', '.join(SETS)}")
        read = lambda i: json.loads(pathlib.Path(args[i]).read_text()) if args[i:] else None  # noqa: E731
        extract_set(read(2) or hsjson(), args[1], read(3))
    else:
        main()
