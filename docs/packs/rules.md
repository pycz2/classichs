# `rules.json`

Everything about a match, a deck, the Arena and the ladder that is not a card.
Schema: [schema/rules.schema.json](schema/rules.schema.json). Whole numbers only
(it is hashed canonically, [format.md](format.md) §3). Values below are the
Classic pack's (`packs/classic/rules.json`), which match what the game and the
server do today. The engine knows no game of its own: everything game-specific
it uses (the coin, champions and their powers, classes, rarities, starter decks,
the Arena) comes from here and from `cards.json`; an optional field the pack
leaves out takes the engine's default (the Classic value in these tables,
`champion_health` 30, `queue_steps` 5000, `champions_offered` 3, …; no coin,
no starter rarities).

## `limits`

| Field | Classic | Meaning |
|---|---|---|
| `champion_health` | 30 | Health of a champion whose card has none (a champion card's `health` wins). |
| `max_mana` | 10 | Mana crystals at most. |
| `hand` | 10 | Cards in hand; a card drawn into a full hand burns. |
| `board` | 7 | Minions per side. |
| `secrets` | 5 (default; not in the file) | Traps (Secrets) in play per side. At the limit a trap cannot be played from the hand, `g.put_trap` leaves it where it is and `g.take_control` destroys it. The same trap is never in play twice on one side. |
| `deck_size` | 30 | Cards in a constructed or Arena deck. |
| `copies` | 2 | Copies of one card in a constructed deck … |
| `copies_by_rarity` | `{"LEGENDARY": 1}` | … except these rarities. |
| `queue_steps` | 5000 | Engine safety limit on queued effects per action. |

## `start`

| Field | Classic | Meaning |
|---|---|---|
| `first_player` | `"random"` | Who goes first (the game seed decides). |
| `hand` | `[3, 4]` | Cards drawn by the first and the second player. |
| `coin` | `"GAME_005"` | The card the second player gets after the mulligan (null: none). |
| `mulligan` | true | Players may replace any of their opening cards once. |
| `first_player_draws` | true | The first player draws a card at the start of their first turn (false: only from the second turn on). |

These are the levers on the first player's advantage: more opening cards for
the second player (`hand`), the coin, and the first player's first draw.
Neonfall gives the second player five cards (`[3, 5]`): with `[3, 4]` the first
player won 56–60 % of bot games, with `[3, 5]` 47–53 % (packs/neon/DESIGN.md §9).

## `bot`

How the engine's bot (`rust/engine/src/bot.rs`, greedy: it takes the action
whose result it values most, until ending the turn is worth as much) plays
this pack. Optional; Classic leaves it out, and its bot stays the recorded one
(parity).

| Field | Classic | Meaning |
|---|---|---|
| `trap` | 0 | What the bot counts for each of its own traps in play (a card in hand counts 1). At 0 it never plays a trap; at 2 it plays one when nothing better is left to do (Neonfall). |
| `depth` | 1 | 2: before ending its turn, the bot also tries two actions in a row, so it plays a card that pays off only with the next one (the coin, then a minion; a spell to turn on a Chain). Turn ends cost about as many look-aheads as there are actions squared. |
| `brain` | (always) | true: the game's bot at a level (easy, medium, hard) thinks with `rust/brain` (Classic's bot: it guesses the hidden cards and looks ahead) instead of the engine's greedy bot. Classic gets it by its id; Naxxramas sets it. |

## `fatigue`

`{"enabled": true, "first": 1, "step": 1}`: drawing from an empty deck deals
`first` damage, then `step` more each time.

## `behaviour`

Rules Hearthstone changed over the years; a pack names the ones it plays by (all off when missing: Classic,
Naxxramas and Goblins vs Gnomes keep their recorded games; a later pack keeps the earlier pack's flags unless a patch
changed that behaviour).

| Field | Classic | Meaning |
|---|---|---|
| `countered_no_after_spell` | false | true: a countered spell is not cast for "after you cast a spell" hooks (no `after_spell` event: Wild Pyromancer, Flamewaker; Hearthstone until patch 9.2.0.21517 of 2017: Kobolds & Catacombs sets it false again). "Whenever you cast a spell" (`play`) still sees it. |
| `full_hand_return_dies` | false | true: a minion returned to a full hand (Sap, Youthful Brewmaster…) dies as any other: its Deathrattle, the graveyard, `DIED_TURN` (Kel'Thuzad, Feugen and Stalagg, Resurrect; patch 2.4.0.8311). false: it is set aside. |
| `cost_in_order` | false | true: a card's cost changes apply in the order they came — its cost enchantments when given, the cost auras when their source came into play, its player's cost mods when made — after its own `cost_mod`, the `cost_first` auras before all (by rank: Summoning Portal 1); 0 at least at the end (the 2016 rulebook, rule M5: Emperor Thaurissan after Naga Sea Witch makes a card cost 4; from patch 9.0.0.20457 of 2017 Naga Sea Witch, Corpse Widow and Emerald Hive Queen come right after Summoning Portal: their scripts' `cost_first = 2` in Knights of the Frozen Throne). false: enchantments, then auras, then cost mods. |
| `after_spell_from_before` | false | true: a spell's `after_spell` event (its `since` field: the play order it was played at) is heard only by what was in play before the spell was played: a minion it summoned does not react to it (patch 9.2.0.21517 of 2017: "Wild Pyromancer no longer triggers from Mindgames"; Kobolds & Catacombs). false: by all in play when it resolved. |
| `lifesteal_one_heal` | false | true: the Lifesteal damage of one hook (a spell, a Battlecry, a Deathrattle…) heals its champion once, when the hook ends, for all it dealt, one heal per source (patch 10.0.0.22611 of 2017: "multi-target effects now apply healing as one heal"; Kobolds & Catacombs). false: each hit heals at once (Knights of the Frozen Throne). |
| `transform_drops_enchantments` | false | true: a card that transforms in a hand or a deck never keeps its enchantments (`g.transform`'s `keep` is ignored: patch 12.0.0.25770 of 2018, "whenever a card transforms it loses its enchantments": The Witchwood's worgen, Chameleos, Shifter Zerus; The Boomsday Project). false: `keep` keeps them. |
| `replaced_weapon_dies` | false | true: a weapon replaced by a new one is destroyed as any other: its Deathrattle and a `death` event (Death's Bite, Grave Shambler; hearthstone.wiki.gg, Weapon). false: it goes to the graveyard without them. |

## `player_hooks`

The name of a hook set of the pack's scripts (`"player:og"`) whose `on` hooks see every event once for each player,
`me` being that player's champion (a new champion takes over): the counts of a game no card in play keeps ("spells
you've cast this game", "Totems you've summoned this game"; `g.add_count`, `g.count`), and what happens "when the game
starts" (an `on.game_start` hook: after the mulligan, before the coin; api.md, events). Optional; none in Classic.
A list of names runs each set, in order, for every event (a pack adds its own set after its base's instead of copying
it: Rise of Shadows' `["player:trl", "player:dal"]`).

Its `aura` hook (optional) runs too, once for each player after the cards' auras, `me` being that player's champion: what a player has "for the rest of the game" (The Boomsday Project: Dr. Boom, Mad Genius's "your Mechs have Rush").

## `deck_recipes`

Card id → a list of decks `{about?, class, cards}`: a card that stands for a whole deck (The Boomsday Project's Whizbang the Wonderful). A deck of only that card is legal (`deck::Deck::validate_in`; nothing else can go with it), and a game starts it as one of these decks, picked at random by the game's seed before the opening hands, with that class's champion; the start logs `deck_recipe` (`player`, `card`, `hero`: the new champion) and never which deck. Such a card is never drafted in the Arena. `about` is for people. Optional.

## `every_race`

A race (of `races`) that is every race: a card of it counts as a Beast, a Murloc, a Pirate… for every script (`g.race`
and `g.info(card).race` give a value `==` to every race name, not to `""`; a cost mod of a race applies to it). Optional;
The Witchwood names `ALL` (Nightmare Amalgam: "This is an Elemental, Mech, Demon, Murloc, Dragon, Beast, Pirate and
Totem").

## `timers` (seconds)

| Field | Classic | Meaning |
|---|---|---|
| `turn` | 75 | A turn. |
| `fuse` | 15 | The burning fuse (rope) shows when this many seconds are left. |
| `mulligan` | 45 | The mulligan. |
| `grace` | 5 | After the deadline players see, before the server plays the timeout move. |
| `away` | 30 | How long a disconnected player is waited for. |

## `default_power`

The `POWER` card of a champion that has no `power` (Classic: `VAN_HERO_08bp`,
Fireblast, as the engine does today).

## `classes`, `races`, `rarities`, `no_rarity_tier`, `sets`

See [format.md](format.md) §5. Classic: nine playable classes (`DRUID` …
`WARRIOR`, champions `HERO_01` … `HERO_09`), `NEUTRAL` (neutral), `DREAM` and
`DEMONHUNTER` (special cards only); races `BEAST DEMON DRAGON MECHANICAL MURLOC
PIRATE TOTEM UNDEAD`; rarities `FREE` and `COMMON` (tier common), `RARE`, `EPIC`,
`LEGENDARY`; sets `VANILLA` (the collection), `MISSIONS`, `EXPERT1`, `LEGACY`,
`HERO_SKINS`, `CORE`. Naxxramas (`packs/naxx`): the same and `NAXX`, both collections (`VANILLA`, `NAXX`) in
its constructed and Arena modes.

## `mechanics`

Pack name → `{"engine": <engine id>}` ([format.md](format.md) §4). Classic maps
every Hearthstone mechanic and every state tag to the engine vocabulary while
keeping the Hearthstone names (D7).

## `modes`

### `constructed`

| Field | Classic | Meaning |
|---|---|---|
| `sets` | `["VANILLA"]` | Collectible cards of these sets can be put in a deck. |
| `class_cards` | `"own_and_neutral"` | A deck holds its champion's class cards and neutral ones. |
| `starter_rarities` | `["FREE"]` | A starter deck (the engine's `deck::basic_in`) takes two of every collectible class card of these rarities … |
| `starter_core` | 10 ids | … then these neutral cards, two each, up to `deck_size`. |

### `arena`

The draft as `rust/engine/src/arena_draft.rs` does it:

| Field | Classic | Meaning |
|---|---|---|
| `sets` | `["VANILLA"]` | Card pool (collectible, no champions). |
| `banned` | none | Cards of those sets that are never drafted (Hearthstone 2014–2019: Gelbin Mekkatorque, the C'Thun cards…). |
| `extra` | none | Cards drafted too though not collectible (Arena-only cards: the BlizzCon cards of 2018). |
| `champions_offered` | 3 | Champions of different classes to choose from. |
| `classes` | the nine | Classes that can be offered. |
| `picks` | 30 | Picks (the deck size). |
| `offer` | 3 | Different cards per pick, all of one tier. |
| `tier_weights` | common 765, rare 140, epic 75, legendary 20 | Chance of a pick's tier, per mille (engine: `weight / 1000.0`). |
| `special_picks` | `[1, 10, 20, 30]` | Pick numbers (1-based) that use `special_tier_weights`. |
| `special_tier_weights` | rare 650, epic 270, legendary 80 | |
| `class_weight`, `neutral_weight` | 3, 2 | Weight of a class card vs a neutral card within a tier (1.5 : 1). |
| `copies` | 0 | Copies limit of an Arena deck (0: none). |
| `wins`, `losses` | 12, 3 | A run ends at this many wins or losses. |

Draft algorithm (for the engine to keep): offer `champions_offered` champions,
each drawn uniformly (`randi_range`) from the classes left, in the listed order; for each pick, draw a tier by the
weights (`x = randf()`, subtract each tier's weight/1000 in the listed order,
the first that drops below 0; the last on rounding), then draw `offer` different
cards of that tier, each by weight among the remaining (`x = randf() * total`,
walk the list). The tier of a card is its rarity's `tier`; no rarity →
`no_rarity_tier`. All from the draft seed (`rng.rs`).

## `formats`

The game's formats (Hearthstone 2014–2019, `packs/eras`: `standard` and, from April 2016, `wild`); none: one format,
every collectible card of `modes.constructed`.

```json
"formats": {"standard": {"sets": ["VANILLA", "OG", "KARA", "GANGS", "UNGORO"], "exclude": ["VAN_EX1_016", "…"]},
            "wild": {"sets": ["VANILLA", "NAXX", "GVG", "BRM", "TGT", "LOE", "OG", "KARA", "GANGS", "UNGORO"]}}
```

A format's cards are the collectible cards of its `sets` without its `exclude` (Hall of Fame cards). A game made with
`"format": "standard"` (the engine's `new`, rust/engine/README.md) takes only decks of those cards and makes every
random card (Discover, "a random minion") from them, as the game did; a game without a format plays every card.

## `ranked`

The 2014 ladder (`server/src/ranked.rs`, `docs/superpowers/specs/2026-10-15-ranked-research.md`).

| Field | Classic | Meaning |
|---|---|---|
| `start` | `{rank: 25, stars: 0}` | Where a new player and a new season start. |
| `ranks` | 25 entries, 25 → 1 | `{rank, stars, loses_stars?, floor?, streak_bonus?, emblem?}`, from the lowest rank (N) down to 1. |
| `ranks[].stars` | 2 (25–21), 3 (20–16), 4 (15–11), 5 (10–1) | Stars to fill before the next rank. |
| `ranks[].loses_stars` | false at 25–21 (default true) | A loss takes a star (at 0 stars: back one rank with stars−1). |
| `ranks[].floor` | true at 20 (default false) | A loss at 0 stars does not drop below this rank. |
| `ranks[].streak_bonus` | true at 25–6 (default false) | The streak bonus applies at this rank. |
| `ranks[].emblem` | `{card: id}` / `{image: "ui/…"}` / null | The emblem: a card's art in a ring (Classic: the rank's namesake card, as `ui/server_view.gd` RANK_CARDS), a picture, or the client's crest. |
| `streak` | `{wins: 3, bonus_stars: 1}` | The 3rd and later wins in a row give one more star. |
| `legend` | `{after_rank: 1, keep_for_season: true, numbered_top: 10000, emblem: null}` | The top rank after rank 1: never lost within a season; the best `numbered_top` players see their place. null: no Legend. |
| `season.length` | `"month"` | Calendar months. |
| `season.reset` | `{to_rank: 25, stars_per_rank_above: 1, legend_counts_as: 0}` | At a new season: rank 25 plus one star per rank above 25 held at the end (Legend counts as rank 0 → 25 stars). |
| `season.reset.basis` | `"end"` (default) / `"best"` | The rank the reset counts: the one at the season's end, or the season's best (from August 2015). |
| `season.reset.ranks_down` | — (2018: 4) | The reset of March 2018 on instead: this many ranks below the basis, its stars kept (no more than the new rank holds); Legend goes to `legend_to` (4) with 0 stars; never below `lowest` (25); a player in a rank below `lowest` (the New Player Ranks 50…26) keeps it. |
| `season.reset.career_floor` | — (2018-12: `{reached: 15, rank: 20}`) | Who ever reached rank `reached` starts no lower than `rank`. |
| `season.reset.shed_excess_stars` | — (2019: true) | Stars above the new rank's are dropped (the server always does: before 2019 every rank had 5). |

packs/eras gives each version the ladder of its time (packs/eras/ranked.json, packs/eras/README.md). The server keeps
the season's best rank in each standing for `basis: "best"`.

Rank names are texts: `locales/<lang>.json` `ranks` (`"25": "Angry Chicken"`,
`"1": "Innkeeper"`, `"0": "Legend"`). Matchmaking (stars below Legend, MMR at
Legend) stays the server's.
