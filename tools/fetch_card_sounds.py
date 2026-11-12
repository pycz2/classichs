#!/usr/bin/env python3
"""Each card's original sound effects for its moments (cast, aim, missile, impacts, trigger, Secret reveal, Quest
completion, a choice) for the owner's LOCAL packs (never for git, never for a distributed pack: Blizzard's sounds).

Usage: python3 tools/fetch_card_sounds.py --set gvg [--out ~/ClassicHS-local] [--dry-run]
       (tools/fetch_set_assets.py --set <s> runs it after tools/fetch_original_sounds.py)

The Cargo table `Sound` of hearthstone.wiki.gg (what tools/fetch_original_sounds.py reads) only has a card's
play/attack/death and its voice. The other sounds of a card are files of the wiki named after the card
(Mage_ArcaneMissiles_Impact_1.wav, Warlock_Darkbomb_Missile_Sound_01.wav, AbyssalEnforcer_CFM_751_Play.wav):
this tool lists the wiki's .wav files once (<out>/audio-src/wiki_files.json), matches each file to a card by its
English name or id (a file whose other words are not all known role or filler words is left out: precision first)
and gives it a role by its words (role_of()). The trigger voice lines come from the Cargo table `CustomSound`
and the wiki's VO_<card id>_…Trigger… files.

Result in <out>/<set>/:
  set/<card id>_<role>.opus      roles: aim (a loop while aiming), missile, hit, hit_2 … (impacts), trigger,
                                 reveal (a Secret), complete (a Quest), choose; play for a spell, a hero power or
                                 a Secret only when tools/fetch_original_sounds.py gave it none
  voice/<lang>/<card id>_trigger.opus   the card's line as its effect fires (en, ru when the Russian files have it)
  <out>/audio-src/<set>/manifest.json   card id -> role -> [wiki files] (what each new file came from)
The originals are cached with the others in <out>/sounds/cache/wiki (a cached file is never downloaded again).
"""
import argparse
import bisect
import concurrent.futures as cf
import json
import re
import sys
import time
import urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audio_codec  # noqa: E402
import fetch_original_sounds as snd  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent

# A file's words (after the card's name or id) -> its role; the first role of ORDER found wins.
ROLE_WORDS = {
    "aim": {"idle", "loop", "channel", "aim", "aiming", "targeting", "hold"},
    "missile": {"missile", "missiles", "projectile", "travel", "fly", "flight", "mis"},
    "hit": {"impact", "impacts", "hit", "explode", "explosion", "ae", "aoe", "damage", "target", "targeted", "splash"},
    "trigger": {"trigger", "triggered", "battlecry", "deathrattle", "rattle", "proc", "activate", "effect"},
    "reveal": {"reveal", "revealed"},
    "complete": {"complete", "completed", "reward"},
    "progress": {"progress"},
    "choose": {"choose", "choice", "discover", "adapt"},
    "death": {"death", "destroy", "destroyed", "break", "destruction"},
    "attack": {"attack", "swing"},
    "play": {"cast", "precast", "start", "birth", "launch", "play", "enterplay", "summon", "customsummon",
             "customspawn", "spawn", "equip"},
}
ORDER = ["aim", "missile", "reveal", "complete", "progress", "choose", "hit", "trigger", "death", "attack", "play"]
# Words that say nothing of the role (or are the game's prefixes): allowed anywhere in a file's name.
FILLER = {"sound", "sounds", "sfx", "fx", "spell", "spells", "event", "small", "medium", "large", "big", "single",
          "v", "new", "a", "b", "c", "the", "of", "card", "custom", "custon", "base", "enter"}
# Names that are also the game's keywords: a file named so is the keyword's sound (Charge_Summon), not the card's.
KEYWORD_NAMES = {"charge", "taunt", "freeze", "windfury", "stealth", "battlecry", "deathrattle", "poisonous",
                 "lifesteal", "rush", "echo", "discover", "adapt", "overload", "combo", "secret", "quest", "inspire",
                 "enrage", "coin", "thecoin", "frog", "spell", "minion", "weapon", "hero"}
# Words allowed before the card's name (a class, the game's sound prefixes, set codes).
PREFIX = FILLER | {"mage", "priest", "warlock", "rogue", "shaman", "hunter", "druid", "paladin", "warrior", "shared",
                   "hero", "neutral", "basic", "minion", "weapon", "secret", "quest", "hs"}
# Words that mark another owner's version (a hero skin's coloured Fireblast, a cancelled cast): never matched.
NEVER = {"fizzle", "cancel", "spellcancel", "blue", "green", "purple", "gold", "golden", "premium", "heroskin",
         "skin", "boss", "tutorial", "opponent", "vo", "underlay", "stinger", "legendarystinger", "socket"}
ALL_ROLE = set().union(*ROLE_WORDS.values())


def words(stem):
    """A file name's (or card name's) lowercase words: split on _, spaces and dashes, then on capitals and digits
    (Mage_ArcaneMissiles_Impact_1 -> mage arcane missiles impact 1)."""
    return [w for w, _, _ in seg_words(stem)]


def seg_words(stem):
    """[(word, starts a part, ends a part)]: the words of words() and where the parts between _ begin and end."""
    out = []
    for part in re.split(r"[_\s\-.,:!?]+", stem.replace("'", "")):
        ws = [w.lower() for w in re.findall(r"[A-Z]+(?![a-z])|[A-Z]?[a-z]+|\d+", part)]
        out += [(w, k == 0, k == len(ws) - 1) for k, w in enumerate(ws)]
    return out


def name_keys(name):
    """The joined lowercase forms a file may give a card's name: whole, before a comma, without "The"; plurals too."""
    keys = set()
    for n in (name, name.split(",")[0], re.sub(r"^the\s+", "", name, flags=re.I)):
        k = "".join(words(n))
        if len(k) >= 3:
            keys |= {k, k[:-1] if k.endswith("s") and len(k) > 4 else k}
    return keys - KEYWORD_NAMES


def role_of(rest):
    """The role of a file from its words other than the card's name/id ("" when none is said)."""
    found = {r for r, ws in ROLE_WORDS.items() if ws & set(rest)}
    return next((r for r in ORDER if r in found), "")


def file_info(file):
    """(words with part bounds, the card ids in the name) of a sound effect file; None for a voice line, a
    non-.wav or a file of NEVER."""
    if file.upper().startswith("VO_") or not file.lower().endswith(".wav"):
        return None
    sw = seg_words(file[:-4])
    if NEVER & {w for w, _, _ in sw}:
        return None
    ids = {m.upper() for m in re.findall(r"(?:^|_)([A-Z]{2,5}\d?_\d{2,3}[a-z0-9]*)(?=_|$)", file[:-4])}
    return sw, ids


def match(file, name, cid, info=None, others=frozenset(), keys=None):
    """The role of file for the card (name, id), "" when the file is not that card's or says no role; "+<role>"
    when the card's name or id is followed by words of its own then the role, "*<role>" when those words come first
    (an effect of the card: AcidicSwampOoze_AcidGlobThrow_Cast_1).
    The card's name (or id) must be whole parts of the file's name (between _ or capitals), the words before it
    prefixes, the words after it role or filler words (or, for a long name or the id, any words then a role word).
    A file naming another card's id, or another card's name (others: name keys) besides, is not the card's.
    info: file_info(file) when known; keys: card_keys(name) when known."""
    info = file_info(file) if info is None else info
    if not info:
        return ""
    sw, ids = info
    base = cid.removeprefix("VAN_")
    if ids and base.upper() not in ids:
        return ""
    w = [x for x, _, _ in sw]
    idw = words(base)
    keys = name_keys(name) if keys is None else keys
    idkey = "".join(idw)
    nw = set(words(name))
    njoined = "".join(words(name))
    longest = max([len(idkey)] + [len(k) for k in keys])
    for i in range(len(w)):
        if not sw[i][1]:
            continue
        joined = ""
        for j in range(i, len(w)):
            joined += w[j]
            if len(joined) > longest:
                break
            if not sw[j][2] or (joined not in keys and joined != idkey):
                continue
            if not all(x in PREFIX or x.isdigit() or x in idw for x in w[:i]):
                continue
            if _names_other(sw, i, j, others - keys):
                return ""
            after = w[j + 1:]
            extra = [x for x in after if not (x in FILLER or x in ALL_ROLE or x.isdigit() or x in idw or x in nw
                                              or x in njoined)]
            if not extra:  # (the card's own words say no role: Target Dummy)
                return role_of([x for x in w[:i] + after if x not in nw])
            if (len(joined) >= 8 or joined == idkey) and role_of(after):
                # a long name (or the id) then words of its own: "+" a role word first (Name_Play_Extra), "*" an
                # effect's words first (AcidicSwampOoze_AcidGlobThrow_Cast_1, Name_SpawnToHand)
                # (after the id, words before the role are the card's old name: UNG_063_SproutingSporling_Play)
                first = next(k for k, x in enumerate(after) if x in ALL_ROLE)
                effect = any(x not in FILLER and not x.isdigit() for x in after[:first]) and joined != idkey \
                    or after[first:first + 2] == ["spawn", "to"]
                return ("*" if effect else "+") + role_of(after)
    return ""


def _names_other(sw, i, j, others):
    """True when the file's parts other than words i..j name another card (a whole run of parts, 6 letters or
    more, not inside i..j: Death_Speaker_Blackthorn_Play is Deathspeaker Blackthorn's, not Deathspeaker's)."""
    if not others:
        return False
    for a in range(len(sw)):
        if not sw[a][1]:
            continue
        joined = ""
        for b in range(a, min(len(sw), a + 10)):
            joined += sw[b][0]
            if sw[b][2] and len(joined) >= 6 and joined in others and not (i <= a and b <= j):
                return True
    return False


def card_keys(name, others=()):
    """name_keys of a card less a short form (before a comma, without "The") that begins another card's name
    (others: other_names(), sorted): "Deathwing, Dragonlord" is not "Deathwing" (nor "Deathwing, Mad Aspect")."""
    full = words(name)
    keys = set()
    for n in (name, name.split(",")[0], re.sub(r"^the\s+", "", name, flags=re.I)):
        ws = words(n)
        k = "".join(ws)
        if len(k) < 3 or k in KEYWORD_NAMES:
            continue
        forms = {k, k[:-1] if k.endswith("s") and len(k) > 4 else k}
        if ws != full:
            short = " ".join(ws)
            i = bisect.bisect_left(others, short)
            while i < len(others) and others[i].startswith(short):
                if others[i] != " ".join(full) and (others[i] == short or others[i].startswith(short + " ")):
                    forms = set()
                    break
                i += 1
        keys |= forms
    return keys


def family(f):
    """A file's name without its variant number (Mage_ArcaneMissiles_Impact_2.wav -> mage_arcanemissiles_impact)."""
    return re.sub(r"[_\s]*\d+$", "", f[:-4]).lower()


def natural(f):
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", f)]


PLAY_PICK = ["cast", "start", "launch", "precast", "birth", "play", "enterplay", "customsummon", "summon",
             "customspawn", "spawn", "equip"]


def plan(cards, files, have=frozenset(), max_hits=5, others=frozenset()):
    """cards: [(id, type, English name)], files: the wiki's .wav names, have: the "<id>_<role>" names
    tools/fetch_original_sounds.py gives already, others: other_names() of every card of the game (a file naming
    another card is not this card's). -> {card id: {role: [files]}} (hit: up to max_hits variants of one family,
    other roles one file; play/attack/death only where `have` has none)."""
    out = {}
    joined_others = {o.replace(" ", "") for o in others}
    osorted = sorted(others)
    infos = [(f, info, "".join(x for x, _, _ in info[0])) for f in files for info in [file_info(f)] if info]
    for cid, ctype, name in cards:
        if not name:
            continue
        ck = card_keys(name, osorted)
        keys = ck | {"".join(words(cid.removeprefix("VAN_")))}
        roles = {}
        for f, info, joined in infos:
            if not any(k in joined for k in keys):  # (quick: match() needs one of them as a run of words)
                continue
            m = match(f, name, cid, info, joined_others, ck)
            r, loose = m.lstrip("+*"), m[:1] in "+*" and m != ""
            if m.startswith("*"):  # an effect of the card after its name (its Battlecry's cast, a card it makes)
                if r in ("attack", "death"):
                    r = ""
                elif r == "play" and ctype != "SPELL":
                    r = "trigger"
            if r in ("death", "attack") and ctype == "SPELL":  # a spell's "death" is what it does to its target
                r = "hit" if r == "death" else ""
            if r == "hit" and ctype != "SPELL" and {"customsummon", "customspawn", "summon", "spawn", "socket"} & \
                    {x for x, _, _ in info[0]}:
                r = ""  # (the landing of a minion's or hero's entrance: its play sound has it)
            if r == "reveal" and ctype != "SPELL":
                r = "trigger"  # (only a Secret is revealed; Kingsbane's reveal in the deck is its Deathrattle)
            if r:
                roles.setdefault(r, []).append((loose, f))
        got = {}
        for r, lf in roles.items():
            if r in ("play", "attack", "death") and (f"{cid}_{r}" in have or cid.removeprefix("VAN_") in snd.ORIGINAL):
                continue  # (fetch_original_sounds gave it one; an ORIGINAL card keeps its 2014 sounds only)
            pick = {f: (loose, min((PLAY_PICK.index(x) for x in words(f[:-4]) if x in PLAY_PICK), default=99)
                        if r == "play" else 0) for loose, f in lf}
            fs = sorted(pick, key=lambda f: (pick[f], natural(f)))  # exact names first
            if r == "hit":  # the variants of one family (Mage_ArcaneMissiles_Impact_1…3), the hand-picked one's first
                picked = (snd.SPELLS.get(cid.removeprefix("VAN_")) or [None, None])[1]
                fam = family(picked) if picked else family(fs[0])
                fs = ([picked] if picked else []) + sorted((f for f in fs if family(f) == fam and f != picked), key=natural)
            got[r] = fs[:max_hits] if r == "hit" else fs[:1]
        if got:
            out[cid] = got
    return out


def set_names(cid, roles):
    """[(our name, wiki file)] of a card's manifest entry: hit, hit_2, …; the others by role."""
    out = []
    for r, fs in roles.items():
        for k, f in enumerate(fs):
            out.append((f"{cid}_{r}" if k == 0 else f"{cid}_{r}_{k + 1}", f))
    return out


def custom_triggers(ids):
    """card id -> its first trigger line of the Cargo table CustomSound (a VO_<id>_… file only)."""
    out = {}
    want = sorted({i.removeprefix("VAN_") for i in ids})
    for i in range(0, len(want), 50):
        for r in snd.cargo("CustomSound", "id,triggers", "id in (%s)" % ",".join("'%s'" % x for x in want[i:i + 50])):
            fs = [f for f in snd.files_of(r.get("triggers")) if f.upper().startswith("VO_" + r["id"].upper() + "_")]
            if fs:
                out[r["id"]] = sorted(fs, key=natural)[0]
    return {cid: out[cid.removeprefix("VAN_")] for cid in ids if cid.removeprefix("VAN_") in out}


def vo_triggers(ids, files):
    """card id -> its first trigger line among the wiki's files (VO_<id>_…Trigger…, the id whole)."""
    out = {}
    for f in sorted(files, key=natural):
        m = re.match(r"VO_([A-Za-z0-9]+_[A-Za-z0-9]+?)_(.+)\.wav$", f)
        if m and "trigger" in words(m.group(2)):
            out.setdefault(m.group(1).upper(), f)
    return {cid: out[cid.removeprefix("VAN_").upper()] for cid in ids if cid.removeprefix("VAN_").upper() in out}


def wiki_files(out):
    """The wiki's .wav files (cached in <out>/audio-src/wiki_files.json: {name: [size, seconds]})."""
    p = out / "audio-src" / "wiki_files.json"
    if p.exists():
        return json.loads(p.read_text())
    files, cont = {}, {}
    while True:
        q = {"action": "query", "list": "allimages", "aimime": "audio/wav", "ailimit": 500, "aiprop": "size",
             "format": "json", **cont}
        d = json.loads(snd.get(snd.API + "?" + urllib.parse.urlencode(q)))
        for f in d["query"]["allimages"]:
            files[f["name"]] = [f.get("size", 0), round(f.get("duration", 0) or 0, 3)]
        if "continue" not in d:
            break
        cont = d["continue"]
        time.sleep(1.0)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(files, sort_keys=True))
    return files


def other_names():
    """The names (lowercase words, space-joined) of the game's minions, spells, weapons, heroes and hero powers
    (HearthstoneJSON and Classic's data), less names made only of role or filler words ("Battlecry")."""
    out = set()
    for c in snd.hsjson() + json.loads((ROOT / "data/cards.json").read_text()):
        if c.get("type") not in ("MINION", "SPELL", "WEAPON", "HERO", "HERO_POWER"):
            continue
        n = c.get("name")
        ws = words(n.get("enUS", "") if isinstance(n, dict) else (n or ""))
        if len("".join(ws)) >= 3 and not set(ws) <= ALL_ROLE | PREFIX | KEYWORD_NAMES:
            out.add(" ".join(ws))
    return out


def cards_named(game):
    """[(id, type, English name)] of a set (as fetch_original_sounds.cards_of)."""
    if game == "classic":
        cs = json.loads((ROOT / "data/cards.json").read_text())
    else:
        import extract_cards
        cs = extract_cards.pack_cards(snd.hsjson(), game)
    out = []
    for c in cs:
        n = c.get("name")
        out.append((c["id"], c.get("type", ""), n.get("enUS", "") if isinstance(n, dict) else (n or "")))
    return out


def run(game, out, ru, dry=False):
    dest = out / game
    cache = out / "sounds" / "cache"
    files = wiki_files(out)
    cards = cards_named(game)
    rows = snd.wiki_sounds([c for c, _, _ in cards])  # what fetch_original_sounds gives each card (its plan_card)
    have = {name for c, t, _ in cards for k, name, _ in snd.plan_card(c, rows[c], t) if k == "set"}
    manifest = plan(cards, sorted(files), have, others=other_names())
    trig = {**vo_triggers([c for c, _, _ in cards], files), **custom_triggers([c for c, _, _ in cards])}
    for cid, f in trig.items():
        manifest.setdefault(cid, {})["voice_trigger"] = [f]
    mp = out / "audio-src" / game / "manifest.json"
    mp.parent.mkdir(parents=True, exist_ok=True)
    mp.write_text(json.dumps(manifest, indent=1, sort_keys=True))
    jobs = []  # (url, raw, dst, kind)
    for cid, roles in manifest.items():
        for name, f in set_names(cid, {r: fs for r, fs in roles.items() if r != "voice_trigger"}):
            jobs.append((snd.FILES + urllib.parse.quote(f), cache / "wiki" / f, dest / "set" / f"{name}.opus", "sound"))
        for f in roles.get("voice_trigger", []):
            jobs.append((snd.FILES + urllib.parse.quote(f), cache / "wiki" / f, dest / "voice/en" / f"{cid}_trigger.opus",
                         "voice"))
            rid = ru.get(f.lower().replace(" ", "_"))
            if rid:
                jobs.append(("https://drive.google.com/uc?export=download&id=" + rid, cache / "ru" / f,
                             dest / "voice/ru" / f"{cid}_trigger.opus", "voice"))
    print(f"{game}: {len(manifest)} cards, {len(jobs)} files ({sum(1 for j in jobs if not j[1].exists())} to download)")
    if dry:
        return manifest
    with cf.ThreadPoolExecutor(4) as pool:  # (snd.get keeps the downloads at 2 a second)
        got = list(pool.map(lambda j: snd.fetch(*j), jobs))
    missing = [j[0] for j, ok in zip(jobs, got) if not ok]
    print(f"{game}: {sum(got)} files in {dest}, {len(missing)} not found" + "".join(f"\n  {m}" for m in missing))
    return manifest


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--set", required=True)
    ap.add_argument("--out", default="~/ClassicHS-local")
    ap.add_argument("--no-ru", action="store_true")
    ap.add_argument("--dry-run", action="store_true", help="write the manifest only")
    ap.add_argument("--ffmpeg", default="/opt/homebrew/bin/ffmpeg" if Path("/opt/homebrew/bin/ffmpeg").exists() else "ffmpeg")
    a = ap.parse_args()
    out = Path(a.out).expanduser().resolve()
    if ROOT in out.parents or out == ROOT:
        raise SystemExit("--out must be outside the repository (these files never go into git)")
    snd.pick_encoder(a.ffmpeg)
    run(a.set, out, {} if a.no_ru else snd.ru_for(a.set, out / "sounds/cache"), a.dry_run)


if __name__ == "__main__":
    main()
