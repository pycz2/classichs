#!/usr/bin/env python3
"""The Beasts Deathstalker Rexxar's Build-A-Beast offers (Knights of the Frozen Throne), written into
packs/icc/scripts/icc.lua between `-- @@ZOMBEAST_POOLS@@` and `-- @@END@@` (packs/gil: scripts/gil.lua, the Beasts of
Kobolds & Catacombs and The Witchwood too since patch 11.0.0.23966).

hearthstone.wiki.gg (Deathstalker Rexxar, Notes): the collectible Hunter and neutral Beasts of 5 Mana or less; the
first Discover offers the ones with card text (an effect), the second the ones with only keywords or no text; a Beast with
both a keyword and an effect is in neither. The Beasts of the pack's constructed sets (the cards as the built pack has them,
English text of that day). Usage: python3 tools/zombeast_pools.py [packs/icc | packs/gil]"""
import json
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import pack  # noqa: E402

# a keyword a Beast can have and its words in its text (2017): what is left after its own keywords is an effect
KEYWORD_TEXT = {"TAUNT": r"<b>Taunt</b>", "CHARGE": r"<b>Charge</b>", "STEALTH": r"<b>Stealth</b>",
                "WINDFURY": r"<b>Windfury</b>", "DIVINE_SHIELD": r"<b>Divine Shield</b>", "POISONOUS": r"<b>Poisonous</b>",
                "LIFESTEAL": r"<b>Lifesteal</b>", "ELUSIVE": r"Can't be targeted by spells or Hero Powers\.",
                "SPELLPOWER": r"<b>Spell Damage \+\d</b>", "RUSH": r"<b>Rush</b>", "ECHO": r"<b>Echo</b>"}


def kind(text, keywords):
    """'none' (no text), 'keywords' (only its keywords), 'effect' (an effect, no keyword), 'both'."""
    t = re.sub(r"\[x\]|\n", " ", text or "")
    if not t.strip():
        return "none"
    own = [k for k in keywords if k in KEYWORD_TEXT]
    rest = t
    for k in own:
        rest = re.sub(KEYWORD_TEXT[k], " ", rest)
    rest = re.sub(r"[\s.,]+", "", rest)
    if not rest:
        return "keywords"
    return "both" if own else "effect"


def pools(src):
    files, r = pack.build(src)
    if r.errors:
        raise SystemExit(r.errors)
    cards = json.loads(files["cards.json"])
    rules = json.loads(files["rules.json"])
    en = json.loads(files["locales/en.json"])["cards"]
    sets = rules["modes"]["constructed"]["sets"]
    first, second = [], []
    for c in cards:
        if not (c.get("collectible") and c["type"] == "MINION" and c.get("race") == "BEAST" and c.get("set") in sets
                and c["class"] in ("HUNTER", "NEUTRAL") and c.get("cost", 0) <= 5):
            continue
        k = kind(en.get(c["id"], {}).get("text"), c.get("keywords", []))
        if k == "effect":
            first.append(c["id"])
        elif k in ("none", "keywords"):
            second.append(c["id"])
    return sorted(first), sorted(second)


def lua_list(name, ids):
    lines, line = [], f"local {name} = {{"
    for i in ids:
        item = f' "{i}",'
        if len(line) + len(item) > 118:
            lines.append(line)
            line = " "
        line += item
    lines.append(line.rstrip(",") + " }")
    return "\n".join(lines)


def main():
    src = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "packs/icc")
    first, second = pools(src)
    lua = src / "scripts" / f"{src.name}.lua"
    text = lua.read_text()
    a, b = text.index("-- @@ZOMBEAST_POOLS@@\n"), text.index("-- @@END@@")
    block = "-- @@ZOMBEAST_POOLS@@\n" + lua_list("ZOMBEAST_FIRST", first) + "\n" + lua_list("ZOMBEAST_SECOND", second) + "\n"
    lua.write_text(text[:a] + block + text[b:])
    print(f"{len(first)} Beasts with an effect, {len(second)} with only keywords or none")


if __name__ == "__main__":
    main()
