#!/usr/bin/env python3
"""Writes the landing page data (heroes and showcase cards with names and texts in
the game's 8 languages, Classic's and Neonfall's) and copies the heroes' portraits and
Neonfall's backdrop. Used by tools/build_site.sh.

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
## Neonfall (packs/neon): the cards floating in the header, drawn by tools/site_cards.gd too.
NEON_SHOWCASE = ["sable", "vulka", "archon", "last_free_mind", "enforcement_mech", "lattice_phantom"]
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


## The last releases of the changelog in each page language: [{version, date, items}].
def news(lang, count=4):
    path = os.path.join(ROOT, "CHANGELOG.md" if lang == "ru" else os.path.join("data", "changelog", lang + ".md"))
    out = []
    for line in open(path, encoding="utf-8"):
        m = re.match(r"## \[(\d[^\]]*)\] - (\S+)", line)
        if m:
            if len(out) == count:
                break
            out.append({"version": m.group(1), "date": m.group(2), "items": []})
        elif out and line.startswith("- "):
            out[-1]["items"].append(re.sub(r"[*`]", "", line[2:].strip()))
    return out


def neon(out):
    """Neonfall's name, description, champions (with their powers) and showcase cards, in every language."""
    src = os.path.join(ROOT, "packs", "neon")
    cards = {c["id"]: c for c in json.load(open(os.path.join(src, "cards.json")))}
    loc = {l: json.load(open(os.path.join(src, "locales", l + ".json"), encoding="utf-8")) for l in LANGS}

    def name(l, cid):
        return loc[l]["cards"].get(cid, {}).get("name") or loc["en"]["cards"][cid]["name"]

    champions = []
    for cls in json.load(open(os.path.join(src, "rules.json")))["classes"]:
        if "champion" in cls:
            c = cards[cls["champion"]]
            shutil.copy(os.path.join(src, "art", "default", c["id"] + ".jpg"), os.path.join(out, "art", c["id"] + ".jpg"))
            champions.append({"id": c["id"], "cls": cls["id"], "name": {l: name(l, c["id"]) for l in LANGS},
                              "class": {l: loc[l]["classes"].get(cls["id"], cls["id"]) for l in LANGS},
                              "power": {l: name(l, c["power"]) for l in LANGS}})
    shutil.copy(os.path.join(src, "art", "default", "menu.jpg"), os.path.join(out, "art", "neon_menu.jpg"))
    return {"name": {l: loc[l]["pack"]["name"] for l in LANGS},
            "description": {l: loc[l]["pack"]["description"] for l in LANGS},
            "power_term": {l: loc[l].get("terms", {}).get("POWER", "") for l in LANGS},
            "champions": champions, "cards": [{"id": cid, "name": {l: name(l, cid) for l in LANGS}} for cid in NEON_SHOWCASE],
            "total": sum(1 for c in cards.values() if c.get("collectible"))}


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
            "download_mb": download_mb(os.path.join(out, "play")),
            "version": re.search(r'config/version="([^"]+)"', open(os.path.join(ROOT, "project.godot")).read()).group(1),
            "tests": sum(len(re.findall(r"^func test_", open(os.path.join(ROOT, "tests", f)).read(), re.M))
                         for f in os.listdir(os.path.join(ROOT, "tests")) if f.endswith(".gd")),
            "news": {l: news(l) for l in LANGS}, "neon": neon(out)}
    site["date"] = site["news"]["en"][0]["date"] if site["news"]["en"] else ""
    json.dump(site, open(os.path.join(out, "data.json"), "w"), ensure_ascii=False)
    print(f"site data: {len(site['heroes'])} heroes, {len(site['cards'])} cards, download {site['download_mb']} MB")


if __name__ == "__main__":
    main(sys.argv[1])
