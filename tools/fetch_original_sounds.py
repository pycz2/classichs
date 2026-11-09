#!/usr/bin/env python3
"""Downloads the original Hearthstone sounds for the owner's LOCAL packs (never for git, never for a
distributed pack: they belong to Blizzard Entertainment).

Usage: python3 tools/fetch_original_sounds.py [--out ~/ClassicHS-local/sounds] [--only classic|naxx] [--no-ru]

Result (per game: classic = data/cards.json, naxx = the FP1_* cards of HearthstoneJSON):
  <out>/<game>/set/<name>.ogg            a sound set for `tools/pack.py build … --sound-set original=<out>/<game>/set`:
      the board's sounds by name (play_card, attack, death, draw, turn_start, …, spell_<element>,
      hit_<element>) and each card's own: <card id>_play (a minion entering, a spell cast, a weapon),
      <card id>_attack, <card id>_death, <card id>_hit (a spell's impact)
  <out>/<game>/voice/<lang>/<card id>_<kind>.ogg   spoken lines for `--voice <out>/<game>/voice`:
      minions and weapons: play, attack, death; heroes: start, greetings, well_played, thanks, wow,
      oops, threaten, sorry, concede, attack, death, time, thinking1-3, low_cards, no_cards, error_*
  <out>/cache/                            the downloaded originals (.wav), kept for the next run
  <out>/<game>/SOURCES.md                 what came from where, counts per language

Sources:
- hearthstone.wiki.gg: the Cargo table `Sound` (the sound files of each card: BASIC_play, _attack,
  _death, their underlays, VO for heroes) and the files themselves (https://hearthstone.wiki.gg/images/<file>).
  Cards whose sounds changed after 2014 get the 2014 files the wiki keeps (ORIGINAL below).
  The board's sounds and spell sounds: hand-picked files of the wiki (GENERIC, ELEMENTS, SPELLS).
- Russian voice: a public Google Drive collection of the Russian client's files (RU_DRIVE, linked from
  the Russian Blizzard forum thread "Файлы звуков карт из Hearthstone"); the files carry the same names
  as the English ones. No public source was found for de, fr, es, pt_BR, it, pl (they fall back to English).
Needs ffmpeg for the .wav conversion: Ogg Vorbis (libvorbis), else MP3 (libmp3lame), --ffmpeg picks the binary. wiki.gg rejects browser user agents.
"""
import argparse
import concurrent.futures as cf
import html
import json
import os
import re
import subprocess
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
API = "https://hearthstone.wiki.gg/api.php"
FILES = "https://hearthstone.wiki.gg/images/"
UA = "ClassicHSVoiceCollector/1.0 (hobby fan project)"
HSJSON = "https://api.hearthstonejson.com/v1/latest/enUS/cards.json"

# The board's sounds (names the client plays) -> a wiki file.
GENERIC = {
    "play_card": "Play_card_from_hand_1.wav", "summon": "FX_MinionSummon_Drop.wav",
    "attack": "FX_Minion_AttackImpact.wav", "hit_big": "FX_Minion_AttackImpactLarge.wav",
    "damage": "FX_Minion_AttackImpactMid.wav", "death": "Minion_Death_01.wav", "draw": "Draw_card_1.wav",
    "turn_start": "ALERT_YourTurn_0v2.wav", "heal": "Holy_Heal_Cast_01.wav", "armor": "Shared_Armor_Equip_1.wav",
    "equip": "Hero_weapon_unsheathe.wav", "weapon_break": "Weapon_Destruction_01.wav",
    "secret": "FX_Secret_Trigger.wav", "secret_play": "FX_Secret_Birth.wav",
    "freeze": "Ice_FrozenMinion_Impact_Sound.wav", "spell": "Shared_Generic_Cast_1.wav",
    "hero_power": "Hero_power_icon_flip_off.wav", "victory": "Victory_screen_start.wav",
    "defeat": "Defeat_screen_start.wav", "fatigue": "Fatigue_ReaperStrike_01.wav",
    "burn": "Fatigue_DismissPoof_01.wav",
}
# A spell's element (its fx.element) -> [cast, impact]: spell_<element>, hit_<element>.
ELEMENTS = {
    "fire": ["Shared_Fire_Cast_1.wav", "Shared_Fire_Impact.wav"],
    "arcane": ["Shared_Arcane_Start_1.wav", "Arcane_Impact_04_Sound_01.wav"],
    "moon": ["Shared_Arcane_Start_1.wav", "Arcane_Impact_04_Sound_01.wav"],
    "ice": ["Shared_Frost_Cast_1.wav", "Shared_Frost_Impact_1.wav"],
    "holy": ["Spell_holy_cast_1.wav", "Spell_holy_damage_heavy_impact_1.wav"],
    "shadow": ["Warlock_ShadowBolt_Cast_1.wav", "Warlock_ShadowBolt_Impact_1.wav"],
    "nature": ["Shared_Nature_Cast_1.wav", "Nature_Impact_Leaves_01_Sound.wav"],
    "poison": ["Shared_Nature_Cast_1.wav", "Rogue_DeadlyPoison_Impact_1.wav"],
    "lightning": ["Shared_Nature_Cast_1.wav", "Shared_Lightning_Impact_1.wav"],
}
# Classic spells (ids without VAN_) -> [cast or None, impact or None], picked from the wiki's files.
SPELLS = {
    "CS2_041": [None, "Shaman_AncestralHealing_Impact.wav"], "NEW1_031": ["Hunter_Animal_Companion.wav", None],
    "CS2_025": ["Mage_ArcaneExplosion_AE_1.wav", None], "CS2_023": ["Mage_ArcaneIntellect_Cast_1.wav", None],
    "EX1_277": [None, "Mage_ArcaneMissiles_Impact_1.wav"], "CS2_076": [None, "Rogue_Assassinate_Impact_1.wav"],
    "EX1_384": ["AvengingWrath_cast.wav", None], "EX1_320": [None, "Shared_WarlockBaneOfDoom_Impact_1.wav"],
    "CS2_233": ["Rogue_BladeFlurry_Cast_1.wav", "Rogue_BladeFlurry_Impact_1.wav"],
    "EX1_355": [None, "Spell_BlessedChampion_target_1.wav"], "CS2_092": [None, "Spell_BlessingOfKings_target_1.wav"],
    "CS2_087": [None, "Spell_BlessingOfMight_target_1.wav"], "EX1_363": [None, "Spell_BlessingOfWisdom_target_1.wav"],
    "CS2_046": ["Shaman_Bloodlust_PreCast.wav", "Shaman_Bloodlust_Impact.wav"], "EX1_407": ["Brawl_Start_01.wav", None],
    "EX1_621": ["CircleOfHealing_cast.wav", None], "NEW1_036": ["Rage_CommandingShout_Cast_Horn_Sound.wav", None],
    "EX1_275": ["Mage_ConeOfCold_Cast_1.wav", None], "CS2_093": ["Spell_Consecration_impact_1.wav", None],
    "CS2_063": [None, "Warlock_Corruption_Impact_1.wav"], "EX1_287": ["Mage_CounterSpell_Cast_1.wav", None],
    "CS2_074": [None, "Rogue_DeadlyPoison_Impact_1.wav"], "CS2_061": ["Warlock_DrainLife_Cast_1.wav", None],
    "EX1_245": [None, "Shaman_EarthShock_Impact.wav"], "EX1_619": [None, "Spell_Equality_target_1.wav"],
    "EX1_124": ["Rogue_Eviscerate_Cast_1.wav", "Rogue_Eviscerate_Impact_1.wav"],
    "EX1_537": [None, "Arrow_Explosive_Shot_Explode_01.wav"],
    "EX1_129": ["Rogue_FanOfKnives_Cast_1.wav", "Rogue_FanOfKnives_Impact_1.wav"],
    "CS2_053": ["Shaman_FarSight_PreCast.wav", None], "EX1_248": ["FeralSpirit_CustomSpawn_1.wav", None],
    "CS2_029": ["FX_FireballEvent01_BirthStart_01.wav", "FX_FireballEvent04_SpellImpact_01.wav"],
    "EX1_544": ["Hunter_Flare_Launch.wav", None], "CS2_026": ["Mage_FrostNova_Cast_1.wav", None],
    "CS2_024": [None, "FrostBoltHit1.wav"], "CS2_062": ["Warlock_Hellfire_Cast_1.wav", None],
    "EX1_624": [None, "Spell_holyfire_target.wav"], "CS2_089": ["Spell_HolyLight_cast_1.wav", None],
    "CS1_112": ["Holy_Nova_cast.wav", None], "CS1_130": ["Holy_Smite_Cast_01.wav", "Holy_Smite_Impact_01.wav"],
    "EX1_360": [None, "Spell_Humility_target_1.wav"], "CS2_084": ["Hunters_Mark_cast.wav", None],
    "EX1_289": ["Mage_IceBarrier_Impact_1.wav", None], "EX1_295": ["Mage_IceBlock_Impact_1.wav", None],
    "EX1_607": [None, "Shared_Rage_InnerRage_Impact_1.wav"], "EX1_354": [None, "Spell_LayOnHands_target_1.wav"],
    "EX1_626": ["Mass_Dispell_cast.wav", None], "CS1_113": [None, "Priest_MindControl_Impact_1.wav"],
    "EX1_294": ["Mirror_entity_cast.wav", None], "EX1_533": ["Misdirection_cast_01.wav", None],
    "CS2_022": [None, "Shared_PolymorphHex_Impact.wav"], "EX1_246": [None, "Shared_PolymorphHex_Impact.wav"],
    "EX1_316": [None, "Warlock_PowerOverwhelming_Impact_1.wav"], "EX1_136": ["Spell_Redemption_target_1.wav", None],
    "CS2_057": ["Warlock_ShadowBolt_Cast_1.wav", "Warlock_ShadowBolt_Impact_1.wav"],
    "CS2_234": [None, "Priest_ShadowWordPain_Impact_1.wav"], "EX1_303": [None, "Shared_ShadowFlameAE_Impact_1.wav"],
    "EX1_625": ["Priest_Shadowform_Cast_1.wav", None], "EX1_332": [None, "Silence_target_1.wav"],
    "EX1_309": ["Warlock_SiphonSoul_Cast_1.wav", "Warlock_SiphonSoul_TargetImpact_1.wav"],
    "EX1_554": ["Snake_trap_spread.wav", None], "GAME_005": ["The_coin_card.wav", None],
    "EX1_244": ["Shaman_TotemicMight_PreCast.wav", "Shaman_TotemicMight_Impact.wav"],
    "EX1_312": ["Warlock_TwistingNether_Impact_1.wav", None], "NEW1_004": ["Rogue_Vanish_Impact_1.wav", None],
    "CS2_039": [None, "Shaman_Windfury_Impact.wav"],
}
# Cards whose sounds changed after June 2014 -> their 2014 files (the wiki keeps them on the card's page).
ORIGINAL = {
    "EX1_306": {"play": "VO_EX1_306_Play_01.wav", "attack": "VO_EX1_306_Attack_02.wav", "death": "VO_EX1_306_Death_03.wav"},
    "EX1_080": {"play": "VO_EX1_080_Play_Original.wav", "attack": "VO_EX1_080_Attack_Original.wav",
                "death": "VO_EX1_080_Death_Original.wav"},
    "EX1_100": {"play": "VO_EX1_100_Play_Original.wav", "attack": "VO_EX1_100_Attack_Original.wav",
                "death": "VO_EX1_100_Death_Original.wav"},
}
# A hero's line in the file name (VO_HERO_08_Greetings_56.wav) -> our kind.
HERO_KINDS = {"greetings": "greetings", "wellplayed": "well_played", "well played": "well_played", "oops": "oops",
              "threaten": "threaten", "thanks": "thanks", "sorry": "sorry", "concede": "concede", "start": "start",
              "time": "time", "thinking1": "thinking1", "thinking2": "thinking2", "thinking3": "thinking3",
              "lowcards": "low_cards", "nocards": "no_cards", "wow": "wow", "attack": "attack", "death": "death"}
# ERROR01..12 of a hero, in the client's order of emote types (checked against the wiki's transcripts).
ERRORS = ["need_weapon", "need_mana", "minion_attacked", "i_attacked", "summon_sickness", "hand_full",
          "full_minions", "stealth", "play", "target", "taunt", "generic"]
# The Russian collection: the root folder and the folders of it searched (by name).
RU_DRIVE = "1jwjkNVFcfyBiWZ8Yx_Bp5FuNWqlUz1W3"
RU_FOLDERS = ("Классика", "Зал Славы", "Герои", "Обучение", "Core Set", "[2014.07.22] Проклятие Наксрамаса")


def get(url, ua=UA, tries=4):
    for k in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": ua})
            return urllib.request.urlopen(req, timeout=90).read()
        except Exception:
            if k == tries - 1:
                raise
            time.sleep(2 * (k + 1))


def cargo(table, fields, where):
    q = urllib.parse.urlencode({"action": "cargoquery", "tables": table, "fields": fields, "where": where,
                                "limit": 500, "format": "json"})
    time.sleep(0.5)
    return [r["title"] for r in json.loads(get(API + "?" + q))["cargoquery"]]


def files_of(field):
    return [f.strip() for f in (field or "").split(",") if f.strip().lower().endswith(".wav")]


def wiki_sounds(ids):
    """card id -> the Sound row (the project's id first: VAN_ cards keep their 2014 sounds, then without VAN_)."""
    want = sorted(set(ids) | {i.removeprefix("VAN_") for i in ids})
    rows = {}
    for i in range(0, len(want), 50):
        for r in cargo("Sound", "id,BASIC_play,BASIC_play_underlay,BASIC_attack,BASIC_attack_underlay,"
                       "BASIC_death,BASIC_death_underlay,VO", "id in (%s)" % ",".join("'%s'" % x for x in want[i:i + 50])):
            rows[r["id"]] = r
    return {cid: rows.get(cid) or rows.get(cid.removeprefix("VAN_")) or {} for cid in ids}


def plan_card(cid, row, card_type):
    """[(kind: "set"|"voice", our name, wiki file)] for one card."""
    out = []
    base = cid.removeprefix("VAN_")
    old = ORIGINAL.get(base, {})
    for slot in ("play", "attack", "death"):
        main = [old[slot]] if slot in old else files_of(row.get("BASIC " + slot))
        under = files_of(row.get("BASIC %s underlay" % slot))
        vo = [f for f in main if f.startswith("VO_")]
        sfx = [f for f in main if not f.startswith("VO_")] or under
        if vo:
            out.append(("voice", f"{cid}_{slot}", vo[0]))
        if sfx:
            out.append(("set", f"{cid}_{slot}", sfx[0]))
    if card_type == "HERO":
        for f in files_of(row.get("VO")):
            m = re.match(r"VO_[A-Za-z0-9]+_[A-Za-z0-9]+_(.+?)_\d+\.wav$", f)
            if not m:
                continue
            key = m.group(1).lower()
            if re.fullmatch(r"error\d\d", key):
                n = int(key[5:])
                if 1 <= n <= len(ERRORS):
                    out.append(("voice", f"{cid}_error_{ERRORS[n - 1]}", f))
            elif key in HERO_KINDS:
                out.append(("voice", f"{cid}_{HERO_KINDS[key]}", f))
    if card_type == "SPELL" and base in SPELLS:
        cast, hit = SPELLS[base]
        if cast:
            out.append(("set", f"{cid}_play", cast))
        if hit:
            out.append(("set", f"{cid}_hit", hit))
    seen, uniq = set(), []
    for k, name, f in out:  # first wins (a hero's "Well Played" comes twice)
        if (k, name) not in seen:
            seen.add((k, name))
            uniq.append((k, name, f))
    return uniq


def drive_ls(folder):
    t = get("https://drive.google.com/embeddedfolderview?id=" + folder, ua="Mozilla/5.0").decode()
    out = []
    for href, name in re.findall(r'<a href="([^"]+)"[^>]*>.*?<div class="flip-entry-title">([^<]*)</div>', t, re.S):
        m = re.search(r"/(folders|file/d)/([-\w]{25,})", href)
        if m:
            out.append((m.group(1) == "folders", m.group(2), html.unescape(name)))
    return out


def ru_index(cache):
    """file name (lowercase, spaces as _) -> Drive file id, for the folders RU_FOLDERS (cached)."""
    p = cache / "ru_index.json"
    if p.exists():
        return json.loads(p.read_text())
    index = {}

    def walk(fid):
        for is_dir, cid, name in drive_ls(fid):
            if is_dir:
                time.sleep(0.15)
                walk(cid)
            else:
                index.setdefault(name.lower().replace(" ", "_"), cid)
    for is_dir, cid, name in drive_ls(RU_DRIVE):
        if is_dir and name in RU_FOLDERS:
            walk(cid)
    p.write_text(json.dumps(index, ensure_ascii=False))
    return index


FFMPEG = ["ffmpeg"]
EXT = ".ogg"  # .mp3 when ffmpeg has no libvorbis (Godot plays both)


def pick_encoder(ffmpeg):
    """The ffmpeg to use and the file type: Ogg Vorbis (libvorbis), else MP3 (libmp3lame)."""
    global FFMPEG, EXT
    FFMPEG = [ffmpeg]
    r = subprocess.run(FFMPEG + ["-hide_banner", "-encoders"], capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"{ffmpeg} does not run (pass --ffmpeg): {r.stderr.strip()[:200]}")
    if " libvorbis " in r.stdout:
        EXT = ".ogg"
    elif " libmp3lame " in r.stdout:
        EXT = ".mp3"
    else:
        raise SystemExit(f"{ffmpeg} has neither libvorbis nor libmp3lame")


def fetch(src_url, raw, dst):
    """Downloads src_url to raw (once) and converts it to dst (.ogg or .mp3). True when dst exists."""
    dst = dst.with_suffix(EXT)
    if dst.exists():
        return True
    if not raw.exists():
        try:
            data = get(src_url, ua="Mozilla/5.0" if "drive.google" in src_url else UA)
        except Exception:
            return False
        if data[:4] != b"RIFF":
            return False
        raw.parent.mkdir(parents=True, exist_ok=True)
        raw.write_bytes(data)
    dst.parent.mkdir(parents=True, exist_ok=True)
    codec = ["-c:a", "libvorbis", "-q:a", "3"] if EXT == ".ogg" else ["-c:a", "libmp3lame", "-q:a", "5"]
    r = subprocess.run(FFMPEG + ["-v", "error", "-y", "-i", str(raw)] + codec + [str(dst)])
    return r.returncode == 0


def cards_of(game):
    if game == "classic":
        return [(c["id"], c["type"]) for c in json.loads((ROOT / "data/cards.json").read_text())]
    data = json.loads(get(HSJSON))
    return [(c["id"], c["type"]) for c in data if c["id"].startswith("FP1_") and c.get("set") == "NAXX"]


def run(game, out, ru):
    cache = out / "cache"
    cards = cards_of(game)
    rows = wiki_sounds([c for c, _ in cards])
    jobs = []  # (url, raw, dst, lang)
    for cid, ctype in cards:
        for kind, name, f in plan_card(cid, rows[cid], ctype):
            raw = cache / "wiki" / f
            if kind == "set":
                jobs.append((FILES + urllib.parse.quote(f), raw, out / game / "set" / f"{name}.ogg", "set"))
            else:
                jobs.append((FILES + urllib.parse.quote(f), raw, out / game / "voice" / "en" / f"{name}.ogg", "en"))
                if ru:
                    rid = ru.get(f.lower().replace(" ", "_")) or ru.get(f.lower().replace("wellplayed", "well_played"))
                    if rid and not f.endswith("_Original.wav"):
                        jobs.append(("https://drive.google.com/uc?export=download&id=" + rid, cache / "ru" / f,
                                     out / game / "voice" / "ru" / f"{name}.ogg", "ru"))
    if game == "classic":
        for name, f in GENERIC.items():
            jobs.append((FILES + urllib.parse.quote(f), cache / "wiki" / f, out / game / "set" / f"{name}.ogg", "set"))
        for el, (cast, hit) in ELEMENTS.items():
            for name, f in ((f"spell_{el}", cast), (f"hit_{el}", hit)):
                jobs.append((FILES + urllib.parse.quote(f), cache / "wiki" / f, out / game / "set" / f"{name}.ogg", "set"))
    counts, missing = {}, []
    with cf.ThreadPoolExecutor(6) as pool:
        for job, ok in zip(jobs, pool.map(lambda j: fetch(*j[:3]), jobs)):
            if ok:
                counts[job[3]] = counts.get(job[3], 0) + 1
            else:
                missing.append(job[0])
    lines = [f"# Original sounds: {game}", "", "Local only: Blizzard Entertainment's sounds. Never commit or distribute.",
             "", "| Part | Files |", "|---|---|"] + [f"| {k} | {v} |" for k, v in sorted(counts.items())]
    lines += ["", "Sources: hearthstone.wiki.gg (Cargo `Sound`, files), Russian: Google Drive " + RU_DRIVE, "",
              f"Not found: {len(missing)}"] + [f"- {m}" for m in missing]
    (out / game).mkdir(parents=True, exist_ok=True)
    (out / game / "SOURCES.md").write_text("\n".join(lines) + "\n")
    print(game, counts, "missing", len(missing))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default="~/ClassicHS-local/sounds")
    ap.add_argument("--only", choices=["classic", "naxx"])
    ap.add_argument("--no-ru", action="store_true", help="English only")
    ap.add_argument("--ffmpeg", default="ffmpeg", help="the ffmpeg binary (with libvorbis or libmp3lame)")
    a = ap.parse_args()
    pick_encoder(a.ffmpeg)
    out = Path(a.out).expanduser()
    if (ROOT in out.resolve().parents) or out.resolve() == ROOT:
        raise SystemExit("--out must be outside the repository (these files never go into git)")
    (out / "cache").mkdir(parents=True, exist_ok=True)
    ru = {} if a.no_ru else ru_index(out / "cache")
    for game in ([a.only] if a.only else ["classic", "naxx"]):
        run(game, out, ru)


if __name__ == "__main__":
    main()
