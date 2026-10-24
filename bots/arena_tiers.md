# Arena draft ratings (Classic, June 2014 set)

`arena_tiers.json` rates every card the Arena draft can offer: 382 cards — all collectible
`VAN_` cards of the `VANILLA` set (`packs/classic/rules.json` → `modes.arena.sets`; `rust/engine/src/arena_draft.rs`
offers the hero's class cards and neutrals of the rolled rarity tier, never champions). Scale 0–100, higher = better pick.

- **377** scores come from a tier list (5 of them adjusted, see below), **5** are heuristic (`"src": "heuristic"`).
- Neutral cards carry `score` (the list's neutral baseline) and, where the list rated them differently
  for a class, `by_class: {"ROGUE": 78, ...}` — a drafting bot should use `by_class[hero class]` when present.

## Source

**ADWCTA's Arena Tier List** (ADWCTA & Merps, published on HearthArena.com), the version of
2014-12-03 — Classic + Naxxramas, before Goblins vs Gnomes. One sheet per class (class cards and
class-adjusted neutrals) plus a "Base" sheet for neutrals; values are the list's own numbers
(Legendary/Beyond Great ≈ 90–110 … Beyond Terrible ≈ 1), clamped to 0–100.
Retrieved from the Wayback Machine copy of the Google Sheet embedded on heartharena.com/tierlist:
`https://web.archive.org/web/20141203110805/https://docs.google.com/spreadsheets/d/16Djk1vJCsvDAuihHiwNG_5qzYH_XAA5XsPUYHlA9DEQ/htmlembed?gid=8`
(the live sheet is gone; HearthArena's current list covers today's cards only, and no
Classic-2021 / Lightforge per-card table was retrievable). Felstalker is rated under its 2014 name, Succubus.

### Adjustments to the list
The Dec-2014 sheet rated the post-September-2014 cards; this pool is the earlier (pre-nerf) set.

- Leeroy Jenkins: +10 — pre-nerf: 4 mana (sheet rated the 5-mana version)
- Starving Buzzard: heuristic — pre-nerf: 2-mana 2/1 (sheet rated the 5-mana 3/2)
- Hunter's Mark: +6 — pre-nerf: 0 mana (sheet rated the 1-mana version)
- Gadgetzan Auctioneer: +4 — pre-nerf: 5 mana (sheet rated the 6-mana version)
- Molten Giant: +6 — pre-nerf: base cost 20 (sheet rated 25)
- Abomination: +20 — raised by hand (not from a list): ADWCTA had it at 46, the brief wants it near the top

## Heuristic (cards no list rates)

Old Murk-Eye, Gelbin Mekkatorque, Captain's Parrot and Elite Tauren Chieftain were never in the
real Arena; Starving Buzzard's pre-nerf version was nerfed before the list. For them:

    score = 50 + 8 * (attack + health - (2*cost + 1))          # vanilla test: 4-mana 4/5 = 50
          + Taunt 5 / Divine Shield 8 / Charge 4 / Windfury 3 / Stealth 3
          + text value judged by hand (battlecry, deathrattle, removal, draw)
    clamped to 1..100

- Old Murk-Eye: 30 (text value +0)
- Gelbin Mekkatorque: 50 (text value +8)
- Captain's Parrot: 16 (text value -10)
- Elite Tauren Chieftain: 42 (text value +0)
- Starving Buzzard: 38 (text value +4)

## Sanity check: top 15 / bottom 15 per class

Class cards and neutrals, neutrals at their class-adjusted score.

### Druid (182 cards; * = class card)

| # | Top | Bottom |
|---|---|---|
| 1 | Ancient of Lore * 98 | Young Dragonhawk 1 |
| 2 | Ysera 98 | Secretkeeper 1 |
| 3 | Ragnaros the Firelord 96 | Murloc Tidecaller 1 |
| 4 | Ancient of War * 94 | Lightwarden 1 |
| 5 | Cairne Bloodhoof 94 | Grimscale Oracle 1 |
| 6 | Swipe * 94 | Angry Chicken 1 |
| 7 | Azure Drake 92 | Wisp 2 |
| 8 | The Black Knight 92 | Southsea Deckhand 2 |
| 9 | Cenarius * 90 | Murloc Raider 2 |
| 10 | Sylvanas Windrunner 90 | Hungry Crab 2 |
| 11 | Onyxia 88 | Goldshire Footman 2 |
| 12 | Argent Commander 86 | Ancient Watcher 2 |
| 13 | Sea Giant 86 | Silverback Patriarch 4 |
| 14 | Starfall * 86 | Alarm-o-Bot 4 |
| 15 | Baron Geddon 84 | Magma Rager 6 |

### Hunter (182 cards; * = class card)

| # | Top | Bottom |
|---|---|---|
| 1 | Ragnaros the Firelord 98 | Murloc Tidecaller 1 |
| 2 | Explosive Shot * 96 | Lightwarden 1 |
| 3 | Savannah Highmane * 96 | Grimscale Oracle 1 |
| 4 | Ysera 96 | Young Dragonhawk 2 |
| 5 | Cairne Bloodhoof 94 | Wisp 2 |
| 6 | The Black Knight 92 | Secretkeeper 2 |
| 7 | Azure Drake 90 | Murloc Raider 2 |
| 8 | Argent Commander 88 | Hungry Crab 2 |
| 9 | Onyxia 88 | Goldshire Footman 2 |
| 10 | Sylvanas Windrunner 88 | Angry Chicken 2 |
| 11 | Baron Geddon 86 | Ancient Watcher 2 |
| 12 | Gladiator's Longbow * 86 | Southsea Deckhand 4 |
| 13 | King Krush * 86 | Alarm-o-Bot 4 |
| 14 | Sea Giant 86 | Thrallmar Farseer 6 |
| 15 | Chillwind Yeti 84 | Magma Rager 6 |

### Mage (182 cards; * = class card)

| # | Top | Bottom |
|---|---|---|
| 1 | Ysera 98 | Young Dragonhawk 1 |
| 2 | Ragnaros the Firelord 96 | Murloc Tidecaller 1 |
| 3 | Cairne Bloodhoof 94 | Lightwarden 1 |
| 4 | Fireball * 94 | Grimscale Oracle 1 |
| 5 | Flamestrike * 92 | Angry Chicken 1 |
| 6 | The Black Knight 92 | Wisp 2 |
| 7 | Azure Drake 90 | Southsea Deckhand 2 |
| 8 | Archmage Antonidas * 88 | Secretkeeper 2 |
| 9 | Blizzard * 88 | Murloc Raider 2 |
| 10 | Onyxia 88 | Hungry Crab 2 |
| 11 | Sylvanas Windrunner 88 | Goldshire Footman 2 |
| 12 | Water Elemental * 88 | Ancient Watcher 2 |
| 13 | Argent Commander 86 | Silverback Patriarch 4 |
| 14 | Sea Giant 86 | Alarm-o-Bot 4 |
| 15 | Baron Geddon 84 | Thrallmar Farseer 6 |

### Paladin (182 cards; * = class card)

| # | Top | Bottom |
|---|---|---|
| 1 | Tirion Fordring * 100 | Young Dragonhawk 1 |
| 2 | Ysera 98 | Murloc Tidecaller 1 |
| 3 | Ragnaros the Firelord 96 | Lightwarden 1 |
| 4 | Aldor Peacekeeper * 94 | Grimscale Oracle 1 |
| 5 | Cairne Bloodhoof 94 | Angry Chicken 1 |
| 6 | Truesilver Champion * 94 | Wisp 2 |
| 7 | The Black Knight 92 | Secretkeeper 2 |
| 8 | Azure Drake 90 | Murloc Raider 2 |
| 9 | Consecration * 90 | Hungry Crab 2 |
| 10 | Sea Giant 90 | Goldshire Footman 2 |
| 11 | Onyxia 88 | Eye for an Eye * 2 |
| 12 | Sylvanas Windrunner 88 | Ancient Watcher 2 |
| 13 | Argent Commander 86 | Silverback Patriarch 4 |
| 14 | Avenging Wrath * 86 | Alarm-o-Bot 4 |
| 15 | Lay on Hands * 86 | Magma Rager 6 |

### Priest (182 cards; * = class card)

| # | Top | Bottom |
|---|---|---|
| 1 | Ysera 98 | Young Dragonhawk 1 |
| 2 | Ragnaros the Firelord 96 | Secretkeeper 1 |
| 3 | Cairne Bloodhoof 94 | Murloc Tidecaller 1 |
| 4 | Holy Nova * 92 | Grimscale Oracle 1 |
| 5 | The Black Knight 92 | Angry Chicken 1 |
| 6 | Azure Drake 90 | Wisp 2 |
| 7 | Cabal Shadow Priest * 90 | Southsea Deckhand 2 |
| 8 | Argent Commander 88 | Murloc Raider 2 |
| 9 | Onyxia 88 | Hungry Crab 2 |
| 10 | Sylvanas Windrunner 88 | Goldshire Footman 2 |
| 11 | Sea Giant 86 | Ancient Watcher 2 |
| 12 | Shadow Word: Pain * 86 | Silverback Patriarch 4 |
| 13 | Temple Enforcer * 86 | Mind Blast * 4 |
| 14 | Baron Geddon 84 | Alarm-o-Bot 4 |
| 15 | Chillwind Yeti 84 | Thrallmar Farseer 6 |

### Rogue (182 cards; * = class card)

| # | Top | Bottom |
|---|---|---|
| 1 | Ysera 98 | Young Dragonhawk 1 |
| 2 | Ragnaros the Firelord 96 | Secretkeeper 1 |
| 3 | Cairne Bloodhoof 94 | Murloc Tidecaller 1 |
| 4 | Azure Drake 92 | Lightwarden 1 |
| 5 | SI:7 Agent * 92 | Grimscale Oracle 1 |
| 6 | The Black Knight 92 | Angry Chicken 1 |
| 7 | Eviscerate * 90 | Murloc Raider 2 |
| 8 | Backstab * 88 | Hungry Crab 2 |
| 9 | Onyxia 88 | Goldshire Footman 2 |
| 10 | Sylvanas Windrunner 88 | Ancient Watcher 2 |
| 11 | Argent Commander 86 | Sinister Strike * 4 |
| 12 | Deadly Poison * 86 | Silverback Patriarch 4 |
| 13 | Sea Giant 86 | Alarm-o-Bot 4 |
| 14 | Chillwind Yeti 84 | Wisp 6 |
| 15 | Sunwalker 84 | Magma Rager 6 |

### Shaman (182 cards; * = class card)

| # | Top | Bottom |
|---|---|---|
| 1 | Ysera 98 | Young Dragonhawk 1 |
| 2 | Fire Elemental * 96 | Secretkeeper 1 |
| 3 | Lightning Storm * 96 | Murloc Tidecaller 1 |
| 4 | Ragnaros the Firelord 96 | Grimscale Oracle 1 |
| 5 | Cairne Bloodhoof 94 | Angry Chicken 1 |
| 6 | Earth Elemental * 94 | Wisp 2 |
| 7 | Azure Drake 92 | Murloc Raider 2 |
| 8 | The Black Knight 92 | Hungry Crab 2 |
| 9 | Hex * 90 | Goldshire Footman 2 |
| 10 | Sea Giant 90 | Dust Devil * 2 |
| 11 | Stormforged Axe * 90 | Ancient Watcher 2 |
| 12 | Onyxia 88 | Silverback Patriarch 4 |
| 13 | Sylvanas Windrunner 88 | Alarm-o-Bot 4 |
| 14 | Argent Commander 86 | Totemic Might * 6 |
| 15 | Chillwind Yeti 84 | Magma Rager 6 |

### Warlock (182 cards; * = class card)

| # | Top | Bottom |
|---|---|---|
| 1 | Lord Jaraxxus * 96 | Sacrificial Pact * 1 |
| 2 | Ragnaros the Firelord 96 | Young Dragonhawk 2 |
| 3 | Cairne Bloodhoof 94 | Wisp 2 |
| 4 | Ysera 94 | Secretkeeper 2 |
| 5 | The Black Knight 92 | Murloc Tidecaller 2 |
| 6 | Onyxia 88 | Lightwarden 2 |
| 7 | Soulfire * 88 | Grimscale Oracle 2 |
| 8 | Sylvanas Windrunner 88 | Angry Chicken 2 |
| 9 | Argent Commander 86 | Ancient Watcher 2 |
| 10 | Azure Drake 86 | Silverback Patriarch 4 |
| 11 | Deathwing 86 | Alarm-o-Bot 4 |
| 12 | Sea Giant 86 | Southsea Deckhand 6 |
| 13 | Chillwind Yeti 84 | Murloc Raider 6 |
| 14 | Doomguard * 84 | Magma Rager 6 |
| 15 | Sunwalker 84 | Hungry Crab 6 |

### Warrior (182 cards; * = class card)

| # | Top | Bottom |
|---|---|---|
| 1 | Gorehowl * 100 | Young Dragonhawk 1 |
| 2 | Ysera 98 | Secretkeeper 1 |
| 3 | Fiery War Axe * 96 | Murloc Tidecaller 1 |
| 4 | Ragnaros the Firelord 96 | Lightwarden 1 |
| 5 | Cairne Bloodhoof 94 | Grimscale Oracle 1 |
| 6 | Arathi Weaponsmith * 92 | Angry Chicken 1 |
| 7 | The Black Knight 92 | Wisp 2 |
| 8 | Azure Drake 90 | Murloc Raider 2 |
| 9 | Baron Geddon 88 | Hungry Crab 2 |
| 10 | Onyxia 88 | Goldshire Footman 2 |
| 11 | Sylvanas Windrunner 88 | Ancient Watcher 2 |
| 12 | Arcanite Reaper * 86 | Silverback Patriarch 4 |
| 13 | Argent Commander 86 | Alarm-o-Bot 4 |
| 14 | Sea Giant 86 | Magma Rager 6 |
| 15 | Chillwind Yeti 84 | Thrallmar Farseer 8 |
