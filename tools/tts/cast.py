#!/usr/bin/env python3
"""Picks a voice and a style for a card (rules below), overridable in cast_overrides.json.

Usage: python3 tools/tts/cast.py          # self-check, then prints the cast of every minion
"""
import json
import os
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")

FEMALE = ("priestess", "queen", "lady", "sister", "maiden", "mistress", "huntress", "sorceress", "witch",
          "matron", "harpy", "sylvanas", "alexstrasza", "ysera", "onyxia", "keeper of the grove",
          "violet teacher", "sunwalker", "spiteful smith", "elven archer", "northshire cleric",
          "sunfury protector", "silvermoon guardian", "sorcerer's apprentice", "arathi weaponsmith",
          "armorsmith", "kirin tor mage", "ravenholdt assassin", "windspeaker", "cabal shadow priest")
SMALL = ("imp", "gnom", "kobold", "goblin", "whelp", "wyrm", "faerie", "wisp", "tinkmaster", "mekkatorque",
         "millhouse", "novice engineer", "auctioneer", "mad bomber", "parrot", "pint-sized", "mana addict")
GIANT = ("giant", "ogre", "gruul", "golem", "ancient of", "mogu'shan", "abomination", "yeti", "hogger",
         "ironbark", "protector of", "lord of the arena")
SPIRIT = ("ghoul", "wraith", "spirit", "banshee", "lich", "skeleton", "kidnapper", "lightspawn", "doomsayer",
          "faceless", "ancient watcher", "shade", "ethereal", "sylvanas")
ELEMENTAL = ("elemental", "ragnaros", "geddon", "al'akir", "dust devil", "magma", "infernal", "ooze", "totem")
MENACING = ("doom", "dread", "shadow", "cult", "dark iron", "void", "assassin", "nightblade", "blood", "cruel",
            "berserker", "raging", "deathwing", "black knight", "fel")
# Ordinary male humanoids by name, before the class/neutral default.
MALE_HINTS = ((("tauren", "grunt", "berserker", "warlord", "sergeant", "bodyguard", "mercenary", "brewmaster",
                "dwarf", "worgen", "hunter", "raider", "corsair", "captain", "rifleman", "commando"), "m_gruff"),
              (("knight", "champion", "commander", "defender", "guardian", "protector", "crusader", "leader",
                "squire", "footman", "warrior", "peacekeeper", "enforcer"), "m_hero"),
              (("mage", "priest", "cleric", "sage", "farseer", "oracle", "doctor", "alchemist", "teacher",
                "lorewalker", "prophet", "druid", "summoner"), "m_old"),
              (("assassin", "agent", "juggler", "disguise", "ringleader", "nightblade", "hoarder", "adventurer"),
               "m_rogue"))
MECH = ("bot", "-tron", "rocketeer", "demolisher", "harvest golem", "mech")
# Default speaker per class for ordinary humanoids: (male, female).
CLASS_VOICE = {"WARRIOR": ("m_hero", "f_hero"), "PALADIN": ("m_hero", "f_hero"), "MAGE": ("m_old", "f_mystic"),
               "PRIEST": ("m_old", "f_noble"), "DRUID": ("m_old", "f_noble"), "SHAMAN": ("m_old", "f_noble"),
               "WARLOCK": ("m_gruff", "f_mystic"), "HUNTER": ("m_gruff", "f_bright"), "ROGUE": ("m_rogue", "f_bright")}
NEUTRAL = {False: ("m_hero", "m_gruff", "m_old", "m_rogue"), True: ("f_hero", "f_mystic", "f_noble", "f_bright")}


def _has(name, words):
    return any(w in name for w in words)


def load_overrides():
    path = os.path.join(HERE, "cast_overrides.json")
    if not os.path.exists(path):
        return {}
    return {k: v for k, v in json.load(open(path, encoding="utf-8")).items() if not k.startswith("_")}


def cast(card, voices, overrides=None):
    """-> (voice_id, style). voices = the 'voices' dict of voices.json."""
    over = (overrides or {}).get(card["id"], {})
    voice, style = over.get("voice"), over.get("style")
    if voice is None:
        voice = _rule_voice(card)
    if style is None:
        name = card["name"]["enUS"].lower()
        style = voices[voice]["style"]
        if voice not in ("small", "small_f") and _has(name, MENACING):
            style = "menacing"
    return voice, style


def _rule_voice(card):
    name = card["name"]["enUS"].lower()
    race = card.get("race") or ""
    female = _has(name, FEMALE)
    if race == "MECHANICAL" or _has(name, MECH):
        return "mech"
    if race == "MURLOC" or _has(name, SMALL):
        return "small_f" if female else "small"
    if race == "DEMON":
        return "demon"
    if race == "DRAGON":
        return "dragon_f" if female else "dragon"
    if race == "UNDEAD" and female or _has(name, SPIRIT):
        return "spirit_f" if female else "spirit_m"
    if race == "TOTEM" or _has(name, ELEMENTAL):
        return "elemental"
    if _has(name, GIANT):
        return "giant"
    if race == "BEAST":
        return "beast"
    if race == "PIRATE":
        return "m_gruff"
    if not female:
        for words, v in MALE_HINTS:
            if _has(name, words):
                return v
    if card.get("cardClass") in CLASS_VOICE:
        return CLASS_VOICE[card["cardClass"]][female]
    if card.get("rarity") == "LEGENDARY" and not female:
        return "m_hero"
    return NEUTRAL[female][zlib.crc32(card["id"].encode()) % 4]  # stable spread


def load_cards():
    return {c["id"]: c for c in json.load(open(os.path.join(ROOT, "data", "cards.json"), encoding="utf-8"))}


if __name__ == "__main__":
    voices = json.load(open(os.path.join(HERE, "voices.json"), encoding="utf-8"))["voices"]
    cards = load_cards()
    over = load_overrides()
    expect = {"VAN_CS2_200": "giant", "VAN_EX1_313": "demon", "VAN_EX1_506": "small", "VAN_EX1_556": "mech",
              "VAN_EX1_016": "spirit_f", "VAN_EX1_572": "dragon_f", "VAN_NEW1_030": "dragon",
              "VAN_EX1_319": "small", "VAN_EX1_298": "elemental"}
    for cid, v in expect.items():
        got = cast(cards[cid], voices, over)[0]
        assert got == v, (cid, cards[cid]["name"]["enUS"], got, v)
    for o in over.values():
        assert o.get("voice", "m_hero") in voices, o
    for c in cards.values():
        if c["type"] == "MINION" and c.get("collectible"):
            v, s = cast(c, voices, over)
            assert v in voices, (c["id"], v)
            print(f"{c['id']:14} {c['name']['enUS']:28} {v:10} {s}")
