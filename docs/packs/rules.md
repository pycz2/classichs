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

## `fatigue`

`{"enabled": true, "first": 1, "step": 1}`: drawing from an empty deck deals
`first` damage, then `step` more each time.

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
`HERO_SKINS`, `CORE`.

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

Rank names are texts: `locales/<lang>.json` `ranks` (`"25": "Angry Chicken"`,
`"1": "Innkeeper"`, `"0": "Legend"`). Matchmaking (stars below Legend, MMR at
Legend) stays the server's.
