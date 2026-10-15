#!/usr/bin/env python3
"""Checks the Neonfall pack source (packs/neon) and writes its card tables into DESIGN.md.

Usage: python3 tools/neon_check.py [--design]
Checks: card fields and references, keywords, the 8 locales (every card, keyword, class,
tribe and deck named everywhere), the decks (30 cards, class, copies, legendaries), the
art and sound files. With --design the tables between the <!-- cards --> markers of
packs/neon/DESIGN.md are regenerated (stats, text, engine primitives, value notes, curves).
Exit code 1 on any error.
"""
import json
import os
import re
import sys
from collections import Counter

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
PACK = os.path.join(ROOT, "packs", "neon")
LANGS = ["en", "ru", "de", "fr", "es", "pt_BR", "it", "pl"]
CLASSES = ["GHOST", "CHROME", "EXEC", "NEUTRAL"]
TRIBES = {"DRONE", "DAEMON"}
RARITIES = {"COMMON", "RARE", "EPIC", "LEGENDARY"}
TAGS = {"GUARD", "HASTE", "BARRIER", "DOUBLE_ATTACK", "STEALTH", "SPELLPROOF"}  # entity tags
KEYWORDS = TAGS | {"ON_PLAY", "ON_DEATH", "WOUNDED", "COMBO", "MANA_LOCK", "TRAP", "CHOICE", "SILENCE",
                   "FREEZE", "SPELL_POWER"}
# effect action -> engine primitive (rust/engine/src/state.rs, cards/mod.rs)
PRIM = {"damage": "damage", "heal": "heal", "draw": "draw", "summon": "summon", "summon_copy": "copy_minion",
        "buff": "buff", "buff_turn": "buff(eot)", "give": "set_tag", "silence": "silence", "freeze": "freeze",
        "destroy": "destroy", "transform": "transform", "return_to_hand": "return_to_hand",
        "take_control": "take_control", "equip": "equip", "armor": "gain_armor", "gain_mana": "gain_mana",
        "discard_random": "discard_random", "add_to_hand": "add_to_hand", "swap_stats": "set_stats", "if": "if"}
SOUNDS = ["click", "draw", "play_card", "attack", "damage", "trigger", "hit_big", "death", "spell", "hero_power",
          "turn_start", "heal", "armor", "equip", "secret", "freeze", "shield", "victory", "defeat"]
MUSIC = ["menu", "battle_1", "battle_2"]
EXTRA_ART = ["card_back", "board", "menu", "logo"]

errors = []


def err(msg):
    errors.append(msg)


def walk(actions, out):
    """Collects the action names of an effect list (nested ifs too) and the card ids it names."""
    for a in actions:
        out["prims"].add(PRIM.get(a[0], "?" + a[0]))
        if a[0] not in PRIM:
            err(f"unknown action {a[0]}")
        for x in a[1:]:
            if isinstance(x, str) and x.startswith("random"):
                out["prims"].add("random")
            if isinstance(x, dict) and "random" in x:
                out["prims"].add("random")
        if a[0] in ("summon", "add_to_hand", "equip") and isinstance(a[1], str):
            out["refs"].add(a[1])
        if a[0] == "transform":
            out["refs"].add(a[2])
        if a[0] == "if":
            walk(a[2], out)
            if len(a) > 3:
                walk(a[3], out)


def analyse(c):
    out = {"prims": set(), "refs": set(), "hooks": []}
    fx = c.get("effects", {})
    for hook in ("play", "combo", "death", "power"):
        if hook in fx:
            out["hooks"].append({"play": "spell" if c["type"] == "SPELL" else "on_play", "death": "on_death"}.get(hook, hook))
            walk(fx[hook], out)
    for t in fx.get("on", []):
        out["hooks"].append("on:" + t["event"])
        walk(t["do"], out)
    if "trap" in fx:
        out["hooks"].append("trap:" + fx["trap"]["event"])
        walk(fx["trap"]["do"], out)
    if "aura" in fx:
        out["hooks"].append("aura")
        out["prims"].add("aura_add")
    if "cost_aura" in fx:
        out["hooks"].append("cost_aura")
    if c.get("options"):
        out["hooks"].append("options")
        out["refs"].update(c["options"])
    if c.get("power"):
        out["refs"].add(c["power"])
    if "combo_target" in c or "target" in c:
        out["prims"].add("targets")
    for k in c.get("keywords", []):
        if k in TAGS:
            out["prims"].add(k)
    if c.get("mana_lock"):
        out["prims"].add("MANA_LOCK")
    if c.get("spell_power"):
        out["prims"].add("SPELL_POWER")
    return out


def check_cards(cards):
    ids = Counter(c["id"] for c in cards)
    for i, n in ids.items():
        if n > 1:
            err(f"duplicate id {i}")
    for c in cards:
        i = c["id"]
        if not re.fullmatch(r"[a-z0-9_]+", i):
            err(f"{i}: id must be snake_case")
        if c["class"] not in CLASSES:
            err(f"{i}: class {c['class']}")
        if c.get("race") and c["race"] not in TRIBES:
            err(f"{i}: race {c['race']}")
        if c.get("rarity", "COMMON") not in RARITIES:
            err(f"{i}: rarity {c['rarity']}")
        if c["type"] == "MINION" and not ("attack" in c and "health" in c):
            err(f"{i}: minion needs attack and health")
        if c["type"] == "WEAPON" and not ("attack" in c and "durability" in c):
            err(f"{i}: weapon needs attack and durability")
        if c["type"] not in ("CHAMPION",) and "cost" not in c:
            err(f"{i}: no cost")
        if not c.get("look"):
            err(f"{i}: no art concept (look)")
        for k in c.get("keywords", []) + c.get("refs", []):
            if k not in KEYWORDS:
                err(f"{i}: keyword {k}")
        a = analyse(c)
        for r in a["refs"]:
            if r not in ids:
                err(f"{i}: refers to unknown card {r}")
        if c.get("collectible") and not c.get("note"):
            err(f"{i}: no value note")
    coll = [c for c in cards if c.get("collectible")]
    if len(coll) > 60:
        err(f"{len(coll)} collectible cards (max 60)")


def check_locales(cards, decks):
    want = {
        "cards": {c["id"] for c in cards},
        "mechanics": KEYWORDS | {"ARMOR", "FATIGUE"},
        "classes": set(CLASSES),
        "races": TRIBES,
        "decks": set(decks),
        "rarities": RARITIES,
    }
    en = json.load(open(os.path.join(PACK, "locales", "en.json")))
    for lang in LANGS:
        path = os.path.join(PACK, "locales", lang + ".json")
        if not os.path.exists(path):
            err(f"missing locale {lang}")
            continue
        d = json.load(open(path))
        for sec, keys in want.items():
            have = set(d.get(sec, {}))
            for k in keys - have:
                err(f"{lang}: {sec}.{k} missing")
            for k in have - keys:
                err(f"{lang}: {sec}.{k} unknown")
        if set(d.get("terms", {})) != set(en["terms"]):
            err(f"{lang}: terms differ from en")
        if not d.get("pack", {}).get("name") or not d["pack"].get("description"):
            err(f"{lang}: pack name/description")
        for i, v in d.get("cards", {}).items():
            if not v.get("name") or "text" not in v:
                err(f"{lang}: card {i} needs name and text")
            # the same numbers as English (stats in text, costs, damage)
            if lang != "en" and i in en["cards"]:
                nums = lambda s: sorted(re.findall(r"[$#]?\d+(?:/\d+)?", re.sub(r"<[^>]+>", "", s)))
                if nums(v["text"]) != nums(en["cards"][i]["text"]):
                    err(f"{lang}: card {i} numbers differ from en: {v['text']}")
            if v.get("text", "").count("<b>") != v.get("text", "").count("</b>"):
                err(f"{lang}: card {i} unbalanced <b>")


def check_decks(cards):
    by_id = {c["id"]: c for c in cards}
    decks = {}
    for f in sorted(os.listdir(os.path.join(PACK, "decks"))):
        d = json.load(open(os.path.join(PACK, "decks", f)))
        decks[d["id"]] = d
        champ = by_id.get(d["champion"])
        if not champ or champ["type"] != "CHAMPION":
            err(f"deck {f}: champion {d['champion']}")
            continue
        if len(d["cards"]) != 30:
            err(f"deck {f}: {len(d['cards'])} cards")
        for i, n in Counter(d["cards"]).items():
            c = by_id.get(i)
            if not c or not c.get("collectible"):
                err(f"deck {f}: {i} is not a collectible card")
                continue
            if c["class"] not in ("NEUTRAL", champ["class"]):
                err(f"deck {f}: {i} is a {c['class']} card")
            if n > (1 if c.get("unique") else 2):
                err(f"deck {f}: {n} copies of {i}")
    return decks


def check_files(cards):
    missing = [c["id"] for c in cards if not os.path.exists(os.path.join(PACK, "art", "default", c["id"] + ".jpg"))]
    missing += [i for i in EXTRA_ART if not os.path.exists(os.path.join(PACK, "art", "default", i + ".jpg"))]
    if missing:
        err(f"art missing: {' '.join(missing)}")
    for s in SOUNDS:
        if not os.path.exists(os.path.join(PACK, "sounds", "default", s + ".ogg")):
            err(f"sound missing: {s}")
    for m in MUSIC:
        if not os.path.exists(os.path.join(PACK, "music", "default", m + ".ogg")):
            err(f"music missing: {m}")


def curve(cards, cls):
    cs = [min(c["cost"], 7) for c in cards if c.get("collectible") and c["class"] == cls]
    n = Counter(cs)
    return " | ".join(f"{k if k < 7 else '7+'}: {n.get(k, 0)}" for k in range(0, 8)) + f" | total {len(cs)}"


def stat(c):
    if c["type"] == "MINION":
        return f"{c['attack']}/{c['health']}"
    if c["type"] == "WEAPON":
        return f"{c['attack']}/{c['durability']}"
    return "-"


def tables(cards):
    en = json.load(open(os.path.join(PACK, "locales", "en.json")))
    rar = en["rarities"]
    strip = lambda s: re.sub(r"[$#](\d)", r"\1", re.sub(r"</?b>", "**", s)).replace("|", "/")
    out = []
    for cls in CLASSES:
        out.append(f"\n### {en['classes'][cls]} ({cls})\n\nCurve: {curve(cards, cls)}\n")
        out.append("| Card | Type | Rarity | Cost | Stats | Text | Engine primitives | Value note |")
        out.append("|---|---|---|---|---|---|---|---|")
        for c in sorted((c for c in cards if c.get("collectible") and c["class"] == cls), key=lambda c: (c["cost"], c["id"])):
            a = analyse(c)
            prims = ", ".join(sorted(a["prims"] | set(a["hooks"])))
            tribe = f" ({en['races'][c['race']]})" if c.get("race") else ""
            out.append(f"| **{en['cards'][c['id']]['name']}** `{c['id']}` | {c['type'].title()}{tribe} | {rar[c['rarity']]} | "
                       f"{c['cost']} | {stat(c)} | {strip(en['cards'][c['id']]['text'])} | {prims} | {c.get('note', '')} |")
    out.append("\n### Tokens, champions and powers\n")
    out.append("| Card | Type | Cost | Stats | Text | Engine primitives |")
    out.append("|---|---|---|---|---|---|")
    for c in cards:
        if not c.get("collectible"):
            a = analyse(c)
            prims = ", ".join(sorted(a["prims"] | set(a["hooks"])))
            st = f"{c['health']} HP" if c["type"] == "CHAMPION" else stat(c)
            out.append(f"| **{en['cards'][c['id']]['name']}** `{c['id']}` | {c['type'].title()} ({c['class']}) | {c.get('cost', '-')} | "
                       f"{st} | {strip(en['cards'][c['id']]['text'])} | {prims} |")
    out.append("\n### Starter decks\n")
    for f in sorted(os.listdir(os.path.join(PACK, "decks"))):
        d = json.load(open(os.path.join(PACK, "decks", f)))
        by = {c["id"]: c for c in cards}
        cnt = Counter(d["cards"])
        ids = sorted(cnt, key=lambda i: (by[i]["cost"], by[i]["class"] == "NEUTRAL", i))
        dc = Counter(min(by[i]["cost"], 7) for i in d["cards"])
        out.append(f"**{en['decks'][d['id']]}** (`decks/{f}`, {en['cards'][d['champion']]['name']}): "
                   + ", ".join(f"{cnt[i]}x {en['cards'][i]['name']} ({by[i]['cost']})" for i in ids))
        out.append("\nCurve: " + " | ".join(f"{k if k < 7 else '7+'}: {dc.get(k, 0)}" for k in range(8))
                   + f" | minions {sum(cnt[i] for i in cnt if by[i]['type'] == 'MINION')}, spells "
                   + f"{sum(cnt[i] for i in cnt if by[i]['type'] == 'SPELL')}, weapons {sum(cnt[i] for i in cnt if by[i]['type'] == 'WEAPON')}\n")
    return "\n".join(out) + "\n"


def main():
    cards = json.load(open(os.path.join(PACK, "cards.json")))
    check_cards(cards)
    decks = check_decks(cards)
    check_locales(cards, decks)
    check_files(cards)
    for cls in CLASSES:
        print(f"{cls:8} {curve(cards, cls)}")
    if "--design" in sys.argv:
        path = os.path.join(PACK, "DESIGN.md")
        s = open(path).read()
        a, b = "<!-- cards:begin -->", "<!-- cards:end -->"
        s = s[: s.index(a) + len(a)] + "\n" + tables(cards) + s[s.index(b):]
        open(path, "w").write(s)
        print("DESIGN.md tables updated")
    for e in errors:
        print("ERROR", e)
    print(f"{len(errors)} errors")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
