#!/usr/bin/env python3
"""Fills the English lines of data/voice_lines.json from hearthstone.wiki.gg (its Cargo
tables Sound and AudioText). Other languages, "translated" and cards already in the file
are kept. See tools/voice_lines.md.

Usage: python3 tools/fetch_voice_lines.py
"""
import json
import os
import re
import time
import urllib.parse
import urllib.request

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "data", "voice_lines.json")
API = "https://hearthstone.wiki.gg/api.php"
UA = "ClassicHSVoiceCollector/1.0 (hobby fan project)"  # wiki.gg blocks browser-like agents
# Hero emote in the sound file name (VO_HERO_08_Greetings_56.wav) -> our key.
HERO_KEYS = {"Start": "start", "Greetings": "greetings", "WellPlayed": "well_played",
             "Thanks": "thanks", "WOW": "wow", "Oops": "oops", "Threaten": "threaten",
             "Concede": "concede", "CONCEDE": "concede", "ConcedeALT": "concede"}


def cargo(table, fields, where):
    q = urllib.parse.urlencode({"action": "cargoquery", "tables": table, "fields": fields,
                                "where": where, "limit": 500, "format": "json"})
    time.sleep(1)
    req = urllib.request.Request(API + "?" + q, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        return [row["title"] for row in json.load(r)["cargoquery"]]


def quoted(items):
    return ",".join("'%s'" % s.replace("'", "''") for s in items)


def clean(line):
    """Wiki links -> their label; drops stage directions like <yawns> or <Snarl>."""
    line = re.sub(r"\[\[(?:[^|\]]*\|)?([^\]]*)\]\]", r"\1", line)
    line = re.sub(r"<[^>]*>", "", line).strip()
    return line if re.search(r"\w", line) else ""


def vo(field):
    return [f.strip() for f in (field or "").split(",") if f.strip().startswith("VO_")]


def main():
    cards = [c for c in json.load(open(os.path.join(ROOT, "data", "cards.json")))
             if c["type"] in ("MINION", "HERO", "WEAPON")]
    hs_id = {c["id"]: c["id"].removeprefix("VAN_") for c in cards}
    # The Classic (VAN_) card's own row first: some cards' sounds changed later (Illidan).
    ids = sorted(set(hs_id.values()) | set(hs_id))
    sounds = {}
    for i in range(0, len(ids), 50):
        for row in cargo("Sound", "id,BASIC_play,BASIC_play_VO,BASIC_attack,BASIC_death,VO",
                         "id in (%s)" % quoted(ids[i:i + 50])):
            sounds[row["id"]] = row
    wanted = {}  # card id -> {key: sound file}
    for c in cards:
        s = sounds.get(c["id"]) or sounds.get(hs_id[c["id"]], {})
        lines = {}
        for key, field in (("play", "BASIC play VO"), ("play", "BASIC play"),
                           ("attack", "BASIC attack"), ("death", "BASIC death")):
            files = vo(s.get(field))
            if files and key not in lines:
                lines[key] = files[0]
        for f in vo(s.get("VO")):
            part = (f.split("_") + ["", "", ""])[3]  # VO_HERO_08_Greetings_56, VO_EX1_323h_Oops_07
            if HERO_KEYS.get(part) and HERO_KEYS[part] not in lines:
                lines[HERO_KEYS[part]] = f
        if lines:
            wanted[c["id"]] = lines
    files = sorted({f for lines in wanted.values() for f in lines.values()})
    # The wiki spells some hero files "Well Played"; "<death sound>" lines have no text.
    names_asked = sorted(set(files) | {f.replace("WellPlayed", "Well Played") for f in files})
    text = {}
    for i in range(0, len(names_asked), 40):
        for row in cargo("AudioText", "file,text", "file in (%s)" % quoted(names_asked[i:i + 40])):
            line = clean(row["text"])
            if line:
                text.setdefault(row["file"].replace(" ", ""), line)
    found_all = {cid: {k: text[f] for k, f in lines.items() if f in text}
                 for cid, lines in wanted.items()}
    # Hero emotes: the client's own strings (GAMEPLAY_EMOTE_HERO_02_THANKS), whose sound
    # file names are spelled inconsistently (VO_Hero_02_Oops_03_ALT.wav).
    heroes = [c["id"] for c in cards if c["type"] == "HERO"]
    for row in cargo("AudioText", "tag,text", " or ".join(
            "tag like 'GAMEPLAY_EMOTE_%s_%%'" % h.replace("_", "\\_") for h in heroes)):
        for h in heroes:
            emote = row["tag"].removeprefix("GAMEPLAY_EMOTE_%s_" % h)
            if emote != row["tag"] and emote.lower() in HERO_KEYS.values() and clean(row["text"]):
                found_all.setdefault(h, {})[emote.lower()] = clean(row["text"])
    data = json.load(open(OUT, encoding="utf-8")) if os.path.exists(OUT) else {}
    names = {c["id"]: c["name"]["enUS"] for c in cards}
    for cid, found in found_all.items():
        if not found:
            continue
        entry = data.setdefault(cid, {})
        for key, line in found.items():
            entry.setdefault(key, {})["en"] = line
        entry["source"] = "https://hearthstone.wiki.gg/wiki/" + urllib.parse.quote(
            names[cid].replace(" ", "_")) + ("_(Classic)" if cid.startswith("VAN_") else "")
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2, sort_keys=True)
        fh.write("\n")
    missing = [f for f in files if f not in text]
    print(len(data), "cards;", len(missing), "sound files without text:", " ".join(missing))


if __name__ == "__main__":
    main()
