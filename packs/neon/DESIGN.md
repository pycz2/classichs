# Neonfall — design

Pack id `neon`, name **Neonfall** (all languages). Phase A4 of
`docs/superpowers/plans/2026-10-16-game-packs.md`: an original cyberpunk pack for
the same engine that runs Classic. 3 champions, 60 collectible cards (13 per
class + 21 neutral), 7 tokens, 3 starter decks, 8 languages, own art, sounds and
music. Every name, card, picture and sound is new; nothing refers to an existing
game, book, film or brand.

The card tables, curves and deck lists below are generated from `cards.json`,
`locales/en.json` and `decks/*.json` by `python3 tools/neon_check.py --design`;
edit those files, not the tables.

## 1. Setting and tone

**Vesper Arc** is a vertical megacity of forty million people on stilts above a
drowned coastline. It has rained for eleven years. The light never goes out:
the rain is lit from inside by billboards, so the locals call it *neonfall*.

- **The Crown** — the dry upper tiers, glass towers above the clouds, owned by
  three megacorps. The biggest, **Sunvault Consolidated**, sells security,
  clones and "peace of mind".
- **The Undertow** — the flooded streets, night markets, chop shops and noodle
  stalls, run by gangs: the **Rust Saints** (chrome-armed brawlers), the
  **Glasshounds** (couriers and thieves in light-bending coats) and others.
- **The Lattice** — the city's net. Hackers called **ghosts** dive into it to
  steal, jam and erase. It is haunted by **daemons**: programs that kept running
  after their owners died, and a few minds that woke up.

Tone: wet, bright, a little absurd. Corporate euphemisms (Severance, Golden
Parachute, Retention Bonus), street slang (Shakedown, Fence the Goods) and
hacker shorthand (Zero-Day, Root Access) are the voice of the cards. Nobody is a
hero; everyone has a price. Humour over grimdark; no gore, no real brands.

A match is a **run**: two champions fight for control of a block of the city.

## 2. Champions

All three have 30 Health and a Champion Power built from existing engine
primitives (the Classic powers are 2-point effects; these started so, and the
balance pass (§9) moved Siphon to 3 mana and Shakedown to 2 damage).

| Champion | Class | Playstyle | Power |
|---|---|---|---|
| **Iris Null** — a freelance ghost who erases people from the Lattice for money | **Ghost** (`GHOST`) | Tempo-control with spells: cheap Jam and Wipe, Chain bonuses, card draw, steal and transform late. Daemon minions. | **Siphon** (3): Deal 1 damage to a minion. If it dies, draw a card. — `damage`, `draw` |
| **Mother Rust** — boss of the Rust Saints, half woman, half scrapyard | **Chromehead** (`CHROME`) | Aggro-midrange: weapons, Plating, Overclock and Heat for burst, Redline minions, discards for raw power. | **Shakedown** (2): Deal 2 damage to the enemy champion. Gain 1 Plating. — `damage`, `gain_armor` |
| **Director Vale** — Sunvault's head of security; everything is an asset | **Executive** (`EXEC`) | Control: Drone walls, Firewall and Hardlight, Protocols (traps), healing, Flatline value, sacrifices for removal. | **Deploy** (2): Summon a 0/2 Sentry Drone with Firewall. — `summon` |

Why these powers: Siphon cannot hit champions, so the Ghost never races with it;
it trades with 1-health minions and refills the hand. Shakedown is Steady
Shot plus a point of Armor Up: steady pressure that also keeps Mother Rust alive against
other aggro decks. Deploy gives a 0/2 wall every turn — weak against big
minions, strong against swarms, and it feeds every Drone card (Grid Overseer,
Field Auditor, ARCHON, Severance).

## 3. Mechanics: engine ids and the pack's names

Engine ids are the neutral vocabulary of the content-separation plan (§4.2);
`cards.json` uses them in `keywords` (the card's own) and `refs` (mentioned in
its text, for tooltips). The names below are the pack's (`locales/*.json`
`mechanics`).

| Engine id | Neonfall (en) | ru | Meaning |
|---|---|---|---|
| `GUARD` | **Firewall** | Файрвол | Enemies must attack it first |
| `HASTE` | **Overclock** | Разгон | Can attack the turn it is played |
| `BARRIER` | **Hardlight** | Твёрдый свет | Ignores the first damage |
| `DOUBLE_ATTACK` | **Dual-Core** | Два ядра | Attacks twice a turn |
| `STEALTH` | **Cloak** | Маскировка | Can't be attacked or targeted until it attacks |
| `SPELLPROOF` | **Encrypted** | Шифрование | Can't be targeted by spells or powers |
| `ON_PLAY` | **Boot** | Запуск | Effect when played from hand |
| `ON_DEATH` | **Flatline** | Отключение | Effect when it dies |
| `WOUNDED` | **Redline** | На пределе | Extra effect while damaged |
| `COMBO` | **Chain** | Цепочка | Bonus if you already played a card this turn |
| `MANA_LOCK` | **Heat (X)** | Перегрев | X Mana locked next turn |
| `TRAP` | **Protocol** | Протокол | Hidden, triggers on the opponent's turn |
| `CHOICE` | **Fork** | Развилка | Choose one of two |
| `SILENCE` | **Wipe** | Стирание | Remove all text and enchantments |
| `FREEZE` | **Jam** | Глушение | Misses its next attack |
| `SPELL_POWER` | **Bandwidth +X** | Канал | Spells deal X more damage |
| Armor | **Plating** | Обшивка | Absorbs damage before Health |
| Fatigue | **Data Rot** | Распад данных | Damage when drawing from an empty deck |
| Second player's card | **Jumpstart** (`jumpstart`) | Подзарядка | 0 mana: gain 1 Mana this turn |

Classes: Ghost / Chromehead / Executive / Neutral. Races (tribes): **Drone**
(machines; Executive synergy) and **Daemon** (rogue programs; Ghost minions).
Rarities: Common, Rare, Epic, Legendary (`unique`, one copy per deck); tokens
have none.

## 4. The effect spec in `cards.json` (for the Lua scripts)

Each card's logic is data a script can be written (or generated) from. Fields
beyond the format of `docs/packs/cards.md` are source-only: `effects`,
`target`, `combo_target`, `can_play`, `options`, `note` (balance note) and
`look` (art concept); the pack build drops them. The logic itself is in
`scripts/*.lua` (one file per class plus `neutral.lua` and `lib.lua`), written
by hand from `effects`; each card with `effects` (or `options`) has a `script`
field pointing at its hook set, and `rust/engine/tests/neon.rs` checks every
card's script in a scenario.

```json
"target": "minion" | "any" | "enemy_minion" | "friendly_minion" | "enemy_char" | {"base": "...", "race": "DRONE", "cost_le": 3}
"effects": {
  "play":   [actions],   // Boot of a minion/weapon, or the effect of a spell (spell damage gets Bandwidth)
  "combo":  [actions],   // Chain: runs INSTEAD of "play" when a card was played before it this turn
  "death":  [actions],   // Flatline
  "power":  [actions],   // Champion Power
  "on":     [{"event": "turn_end|turn_start|after_spell|attack|damage", "if": "<cond>", "do": [actions]}],
  "trap":   {"event": "after_summon|death", "if": "<cond>", "do": [actions]},
  "aura":   {"to": selector, "atk": n} | {"to": "self", "if": "damaged", "keywords": ["DOUBLE_ATTACK"]},
  "cost_aura": {"cards": {"from": "my_hand", "type": "SPELL"}, "delta": -1}
}
"options": ["card_a", "card_b"]   // Fork: two option cards (spells with their own effects)
```

Actions are arrays `[name, args...]`: `damage sel n`, `heal sel n`,
`draw me|enemy n`, `summon card n`, `summon_copy self`, `buff sel atk hp`,
`buff_turn sel atk hp` (until end of turn), `give sel KEYWORD`, `silence sel`,
`freeze sel`, `destroy sel`, `transform sel card`, `return_to_hand sel`,
`take_control sel`, `armor n`, `gain_mana n temp`, `discard_random n`,
`add_to_hand card|{"random": "class_card"}|{"copy_of": sel}`,
`swap_stats sel`, `if [cond, sel] [then]`. `n` may be `["health_of", sel]`.

Selectors: `target`, `self`, `my_champion`, `enemy_champion`, `my_chars`,
`enemy_minions`, `all_other_minions`, `adjacent_of_target`,
`random_enemy_minion`, `random_enemy` (any enemy character),
`random_friendly_minion`, `random_other_friendly_minion`,
`random_damaged_friendly`, `event_minion`, `enemy_weapon`, or
`{"from": "my_minions", "race": "DRONE", "other": true}`.

Conditions: `mine` (the event's player is the card's controller),
`target_is_self`, `my_champion_attacks`, `enemy_played_minion`,
`friendly_minion_died`, `enemy_minion_died`, `damaged`, `["dead", sel]`.

Every action maps to one engine primitive (`rust/engine/src/state.rs`):
`damage, heal, draw, summon, buff (eot), set_tag, silence, freeze, destroy,
transform, return_to_hand, take_control, gain_armor, gain_mana,
discard_random, add_to_hand, set_stats, aura_add`, the shared helper
`copy_minion` (cards/neutral.rs), random picks through the game RNG
(`random_choice`), and the hooks `battlecry/spell/combo/combo_target/
deathrattle/on/secret/aura/cost_aura/choose_one/hero_power/can_play`. The
"Engine primitives" column of the tables lists them per card. Nothing needs a
new engine feature; every effect has a Classic precedent (weapon Dual-Core and
Heat: a Classic weapon; swap Attack/Health: a Classic Boot; copy of a minion:
`copy_minion`; trap on death / on summon: Classic traps).

## 5. Balance rationale

**Stat budget.** A vanilla minion of cost *c* is worth **2c + 1** stat points
(1: 3, 2: 5, 3: 7, 4: 9, 5: 11, 6: 13, 7: 15 — the Classic curve: 2/1, 3/2,
3/4, 4/5…). Weapons: Attack × Durability ≈ **2c + 2**. Damage spells:
targeted damage ≈ **1.5 × cost + 0.5** (1: 2, 2: 3, 3: 5, 4: 6); one-sided AoE
of 2 at 4 mana.

**Keyword values** (in stat points):

| Keyword / effect | Value |
|---|---|
| Firewall | 1 (0 on 0-Attack walls) |
| Overclock | ≈ Attack (it is immediate damage) |
| Hardlight | ≈ Attack (one free trade) |
| Dual-Core | ≈ Attack − 1 |
| Cloak | 1 |
| Bandwidth +1 | 1 |
| Encrypted | 1 |
| Jam | 1 (2 on a big minion) |
| Wipe | 2 (situational) |
| Draw a card | 2.5 |
| Damage *n* (targeted) | 1.5 *n*; random: 0.75 *n* |
| Heal *n* | 0.5 *n* |
| Heat (X) | −2 per locked crystal |
| Discard a random card | −3 |
| Chain | the bonus counts half (it needs another card first) |

**Card advantage.** Cards that net +1 card cost about 2.5 points of tempo
(Cache Raid with Chain, Fence the Goods, Golden Parachute, Static Lock and
Ghostwalk replace themselves). The Ghost has the most card flow, the
Chromehead the most burst and the least card quality (random discards), the
Executive the most bodies and long-game value (Asset Seizure, Flatline).

**Per-class shape.**
- *Ghost*: 8 spells, 5 minions — it borrows bodies from the neutrals
  (Rooftop Sniper, Lattice Phantom, Bit-Rot Daemon). Few minions means Chain is
  turned on by cheap spells; Signal Leech + spells is its slow burn.
- *Chromehead*: 3 weapons and 3 Heat cards; Shakedown + weapons make the
  champion the main attacker; Plating offsets self-damage (Back-Alley Bomb).
- *Executive*: 4 Drones + Deploy + tokens; Firewall everywhere; 3 Protocols;
  Severance turns spare bodies into removal.

**Cards to watch in the phase E bot-vs-bot simulations** (target 45–55 % win
rate per champion): Deploy (0/2 Firewall every turn may be too strong against
aggro — fallback: 1/1 without Firewall), Packet Storm with Chain (3 one-sided
AoE for 4 — fallback: Chain only adds +1), ARCHON (snowball — fallback: no
Attack buff), Fence the Goods (fallback: draw 2), Varga (swing card; it can
kill 0-Attack walls by design), Root Access (random steal). What the
simulations found about them, and what changed instead: §9.

Value notes per card are in the tables (`note` in `cards.json`).

## 6. Originality

The cards are new combinations, not renamed Classic cards. Effects that would
have copied a Classic card exactly were changed: Corrupt turns a minion into a
0/3 *Firewall* wall (the opponent keeps a blocker), Severance sacrifices your
own minion, Root Access steals at random and pays the opponent 2 cards, Packet
Storm and Zero-Day scale with Chain, Asset Seizure copies the *enemy's* dead
minion, Lockout punishes the next minion played. No IP names: no class or
mechanic words from Hearthstone (the content-separation rename table), and no
cyberpunk trademarks (no "netrunner", "ICE", "ripperdoc", "Night City" or
similar terms; the hackers are *ghosts*, the net is *the Lattice*).

<!-- cards:begin -->

### Ghost (GHOST)

Curve: 0: 0 | 1: 2 | 2: 3 | 3: 3 | 4: 2 | 5: 1 | 6: 1 | 7+: 1 | total 13

| Card | Type | Rarity | Cost | Stats | Text | Engine primitives | Value note |
|---|---|---|---|---|---|---|---|
| **Ghostwalk** `ghostwalk` | Spell | Rare | 1 | - | Give a friendly minion +1/+1 and **Cloak**. **Chain:** Also draw a card. | buff, combo, draw, set_tag, spell, targets | +1/+1 (2) + Cloak (1) = 3 for 1; Chain adds a card. |
| **Zero-Day** `zero_day` | Spell | Common | 1 | - | Deal 1 damage to a minion and **Jam** it. **Chain:** Deal 3 damage instead. | combo, damage, freeze, spell, targets | 1 damage + Jam (~2.5) for 1; Chain makes it 3 + Jam (~4.5), premium only after another card. |
| **Cache Raid** `cache_raid` | Spell | Common | 2 | - | Draw a card. **Chain:** Draw 2 cards instead. | combo, draw, spell | Alone it only replaces itself (weak on purpose); with Chain +1 card for 2 mana. |
| **Signal Leech** `signal_leech` | Minion (Daemon) | Common | 2 | 1/2 | **Bandwidth +1**. After you cast a spell, deal 1 damage to the enemy champion. | SPELL_POWER, damage, on:after_spell | 1/2 (3) + Bandwidth (1) + 1 face damage per spell (~1) = 5 = budget. |
| **Static Lock** `static_lock` | Spell | Common | 3 | - | **Jam** a minion and the minions next to it. Draw a card. | draw, freeze, spell, targets | Jam up to 3 minions (~2) and replace itself (2). |
| **Corrupt** `corrupt` | Spell | Common | 3 | - | Transform an enemy minion into a 0/3 Glitch with **Firewall**. | spell, targets, transform | Hard removal at 3, but leaves the opponent a 0/3 Firewall wall that costs you tempo. |
| **Firmware Rot** `firmware_rot` | Spell | Rare | 3 | - | **Wipe** a minion, then deal 2 damage to it. | damage, silence, spell, targets | Wipe (2) + 2 damage (3) = 5; answers buffed or Firewall minions. |
| **Lattice Diver** `lattice_diver` | Minion | Common | 3 | 3/2 | **Cloak**. **Chain:** Return an enemy minion that costs (3) or less to its owner's hand. | STEALTH, combo, return_to_hand, targets | 3/3 (6) + Cloak (1) = 7 = budget (balance pass: 3/2); Chain bounce (~2) for tempo turns. |
| **Packet Storm** `packet_storm` | Spell | Rare | 4 | - | Deal 2 damage to all enemy minions. **Chain:** Deal 3 damage instead. | combo, damage, spell | One-sided 2 AoE for 4 (fair), 3 with Chain (strong, needs 5+ mana in practice). |
| **Recursive Hound** `recursive_hound` | Minion (Daemon) | Rare | 4 | 4/3 | **Flatline:** Add a 2/1 Hound Shard to your hand. | add_to_hand, on_death | 4/3 (7) + a 2/1 in hand (~2) = 9 = budget. |
| **Root Access** `root_access` | Spell | Epic | 5 | - | Take control of a random enemy minion. Your opponent draws 2 cards. | draw, random, spell, take_control | Steal a random minion (~6-10) but give 2 cards (-5): a swing card, not a value card. |
| **Compiler Wyrm** `compiler_wyrm` | Minion (Daemon) | Epic | 6 | 4/5 | Your spells cost (1) less. | cost_aura | 4/5 (9) + spells cost (1) less (~2-3) = 11-12 of 13 (4/6 before the second balance pass). |
| **SABLE, the Unwritten** `sable` | Minion (Daemon) | Legendary | 7 | 6/6 | **Boot:** **Wipe** all enemy minions. | on_play, silence | 6/6 (12) of 15; mass Wipe of the enemy board pays the rest when they have buffs, Firewall or Flatline. |

### Chromehead (CHROME)

Curve: 0: 0 | 1: 3 | 2: 3 | 3: 3 | 4: 1 | 5: 1 | 6: 1 | 7+: 1 | total 13

| Card | Type | Rarity | Cost | Stats | Text | Engine primitives | Value note |
|---|---|---|---|---|---|---|---|
| **Nitro Shot** `nitro_shot` | Spell | Common | 1 | - | Give a friendly minion +2 Attack and **Overclock**. **Heat (1)** | MANA_LOCK, buff, set_tag, spell, targets | +2 Attack (2) + Overclock (~2) - Heat 1 (-1.5) = 2.5 for 1. |
| **Rust Shiv** `rust_shiv` | Weapon | Common | 1 | 1/3 | After your champion attacks, gain 1 Plating. | gain_armor, on:attack | 1x3 = 3 weapon points + up to 3 Plating; a slow but sticky opener. |
| **Stim Junkie** `stim_junkie` | Minion | Common | 1 | 1/3 | **Redline:** **Dual-Core** | aura, aura_add | 1/3 (4) of 3; Redline: Dual-Core (~1). Wants Scrap Bruiser. |
| **Chrome Up** `chrome_up` | Spell | Common | 2 | - | Gain 3 Plating. Your champion gets +2 Attack this turn. | buff(eot), gain_armor, spell | 3 Plating (1.5) + 2 Attack this turn (2) = 3.5 for 2. |
| **Fence the Goods** `fence_the_goods` | Spell | Rare | 2 | - | Discard a random card. Draw 3 cards. | discard_random, draw, spell | Net +1 card for 2 mana (as good as it gets), paid with a random discard. |
| **Hot Courier** `hot_courier` | Minion | Common | 2 | 3/1 | **Overclock**. **Heat (1)** | HASTE, MANA_LOCK | 3/1 (4) + Overclock (3) - Heat 1 (-2) = 5 = budget. |
| **Back-Alley Bomb** `back_alley_bomb` | Spell | Rare | 3 | - | Deal 5 damage to a minion. Deal 2 damage to your champion. | damage, spell, targets | 5 damage (7) - 2 to yourself (-1) = 6 for 3; Plating covers the cost. |
| **Chain Whip** `chain_whip` | Weapon | Rare | 3 | 2/2 | **Dual-Core**. **Heat (1)** | DOUBLE_ATTACK, MANA_LOCK | 2x2 (4) attacking twice a turn (~4) - Heat 1 (-2) = 6 of 8. |
| **Scrap Bruiser** `scrap_bruiser` | Minion | Common | 3 | 2/3 | **Boot:** Deal 1 damage to all other minions. | damage, on_play | 2/3 (5) + 1 damage to every other minion (~2): kills 1-health tokens and turns on Redline. |
| **Pawn Shark** `pawn_shark` | Minion | Rare | 4 | 3/3 | **Boot:** Discard a random card. Gain +3/+3. | buff, discard_random, on_play | Becomes 6/6 (12) for a random card (-3) = 9 = budget; better with an empty hand. |
| **Hydraulic Maul** `hydraulic_maul` | Weapon | Epic | 5 | 5/2 | **Boot:** Gain 5 Plating. | gain_armor, on_play | 5x2 (10) + 5 Plating (2.5) = 12.5 of 12. |
| **Ramraider** `ramraider` | Minion | Epic | 6 | 6/5 | **Overclock**. **Heat (2)** | HASTE, MANA_LOCK | 6/5 (11) + Overclock (6) - Heat 2 (-4) = 13 = budget; a finisher. |
| **Vulka, the Scrap Saint** `vulka` | Minion | Legendary | 7 | 5/7 | **Firewall**. Whenever this takes damage, gain 2 Plating. | GUARD, gain_armor, on:damage | 5/7 (12) + Firewall (1) + 2 Plating per hit (~2-4) = 15-17 of 15. |

### Executive (EXEC)

Curve: 0: 0 | 1: 5 | 2: 4 | 3: 0 | 4: 1 | 5: 1 | 6: 1 | 7+: 1 | total 13

| Card | Type | Rarity | Cost | Stats | Text | Engine primitives | Value note |
|---|---|---|---|---|---|---|---|
| **Executive Decision** `executive_decision` | Spell | Rare | 1 | - | **Fork:** **Wipe** a minion; or give a minion +2 Health and **Firewall**. | options | Either a Wipe (2) or +2 Health and Firewall (2) for (1) (balance pass: at 2 it was rarely worth the card). |
| **Field Auditor** `field_auditor` | Minion | Common | 1 | 2/2 | **Boot:** Give a friendly Drone **Hardlight**. | on_play, set_tag, targets | 2/2 (4) + Hardlight on a Drone when you have one (~1) = 5 of 3 (balance pass: 1/2 was too weak; Executive bodies need Attack). |
| **Protocol: Lockout** `lockout` | Spell | Common | 1 | - | **Protocol:** When your opponent plays a minion, deal 1 damage to it and **Jam** it. | damage, freeze, trap:after_summon | Delays their next minion a turn (~2) and kills 1-health ones; (1) after the balance pass. |
| **Patch Job** `patch_job` | Spell | Common | 1 | - | Restore 3 Health to a minion and give it **Firewall**. | heal, set_tag, spell, targets | Heal 3 (1.5) + Firewall (1) for 1: protect a key minion or wall off a fresh one. |
| **Severance** `severance` | Spell | Rare | 1 | - | Destroy a friendly minion. Deal damage equal to its Health to a random enemy minion. | damage, destroy, random, spell, targets | Turns a body into random removal; best with Sentry Drones (2) and Riot Sentinel (5). |
| **Protocol: Asset Seizure** `asset_seizure` | Spell | Epic | 2 | - | **Protocol:** When an enemy minion dies, add a copy of it to your hand. | add_to_hand, trap:death | A copy of their dead minion (~3-5) for (2) (balance pass); card advantage for the long game. |
| **Protocol: Golden Parachute** `golden_parachute` | Spell | Rare | 2 | - | **Protocol:** When a friendly minion dies, draw 2 cards. | draw, trap:death | 2 cards (5) for 2 mana once something dies on their turn. |
| **Grid Overseer** `grid_overseer` | Minion | Rare | 2 | 2/4 | Your Drones have +1 Attack. | aura, aura_add | 2/4 (6) + Drones +1 Attack (~1-2) at (2) (balance pass): Sentry Drones become 1/2 Firewalls early. |
| **Medic Drone** `medic_drone` | Minion (Drone) | Common | 2 | 2/3 | At the end of your turn, restore 2 Health to a random damaged friendly character. | heal, on:turn_end, random | 2/3 (5) + 2 healing per turn (~1+) = 6 of 5 (balance pass: 1/3 did not pressure). |
| **Riot Sentinel** `riot_sentinel` | Minion (Drone) | Common | 4 | 2/5 | **Firewall**. **Hardlight** | BARRIER, GUARD | 2/5 (7) + Firewall (1) + Hardlight (2) = 10 of 9: the class's best wall, low Attack. |
| **Vat-Grown Clone** `vat_clone` | Minion | Common | 5 | 3/3 | **Boot:** Summon a copy of this minion. | copy_minion, on_play | Two 3/3 bodies (12) for 5: spreads value, weak to AoE. |
| **Enforcement Mech** `enforcement_mech` | Minion (Drone) | Epic | 6 | 5/4 | **Firewall**. **Flatline:** Summon two 0/2 Sentry Drones with **Firewall**. | GUARD, on_death, summon | 5/4 (9) + Firewall (1) + two 0/2 Firewalls (3) = 13 = budget. |
| **ARCHON, Executive Intelligence** `archon` | Minion (Drone) | Legendary | 8 | 6/8 | At the end of your turn, summon a 0/2 Sentry Drone with **Firewall** and give your other Drones +1 Attack. | buff, on:turn_end, summon | 6/8 (14) of 17; must be answered at once or the Drone wall grows every turn. |

### Neutral (NEUTRAL)

Curve: 0: 0 | 1: 3 | 2: 4 | 3: 4 | 4: 3 | 5: 3 | 6: 2 | 7+: 2 | total 21

| Card | Type | Rarity | Cost | Stats | Text | Engine primitives | Value note |
|---|---|---|---|---|---|---|---|
| **Courier Drone** `courier_drone` | Minion (Drone) | Common | 1 | 1/1 | **Flatline:** Add a Jumpstart to your hand. | add_to_hand, on_death | 1/1 (2) + a Jumpstart (~1) = 3 = budget; helps ramp to a big turn. |
| **Neon Moth** `neon_moth` | Minion | Common | 1 | 1/1 | **Cloak**. **Dual-Core** | DOUBLE_ATTACK, STEALTH | 1/1 (2) + Cloak (1) + Dual-Core (1) = 4 of 3, but frail; loves Attack buffs. |
| **Signal Jammer** `signal_jammer` | Minion (Drone) | Common | 1 | 0/3 | **Boot:** **Jam** an enemy minion. | freeze, on_play, targets | 0/3 (3) + Jam (1) = 4 of 3, but 0 Attack: purely defensive. |
| **Chrome Stray** `chrome_stray` | Minion | Common | 2 | 2/2 | **Flatline:** Deal 2 damage to a random enemy minion. | damage, on_death, random | 2/2 (4) + 2 random damage (~1.5) = 5.5 of 5. |
| **Club Bouncer** `club_bouncer` | Minion | Common | 2 | 1/3 | **Firewall**. **Flatline:** Give a random friendly minion **Firewall**. | GUARD, on_death, random, set_tag | 1/3 (4) + Firewall (1) + a Firewall passed on (~0.5) = 5.5 of 5. |
| **Holo Busker** `holo_busker` | Minion | Common | 2 | 1/3 | At the end of your turn, give another random friendly minion +1 Attack. | buff, on:turn_end, random | 1/3 (4) + +1 Attack each turn (~1.5) = 5.5 of 5. |
| **Knockoff Mech** `knockoff_mech` | Minion (Drone) | Common | 2 | 3/4 | **Heat (1)** | MANA_LOCK | 3/4 (7) - Heat 1 (-2) = 5 = budget. |
| **Bit-Rot Daemon** `bitrot_daemon` | Minion (Daemon) | Rare | 3 | 3/3 | At the start of your turn, deal 1 damage to a random enemy. | damage, on:turn_start, random | 3/3 (6) + 1 random damage per turn (~1.5) = 7.5 of 7. |
| **Black Market Broker** `black_market_broker` | Minion | Rare | 3 | 3/2 | **Boot:** Add a random class card to your hand. | add_to_hand, on_play, random | 3/2 (5) + a random class card (~2.5) = 7.5 of 7. |
| **Glasshound Runner** `glasshound_runner` | Minion | Common | 3 | 2/2 | **Hardlight**. **Cloak** | BARRIER, STEALTH | 2/2 (4) + Hardlight (2) + Cloak (1) = 7 = budget. |
| **Night Market Cook** `night_market_cook` | Minion | Common | 3 | 2/3 | **Boot:** Restore 3 Health to all friendly characters. | heal, on_play | 2/3 (5) + 3 healing to every friendly character (~2) = 7 = budget. |
| **Lattice Phantom** `lattice_phantom` | Minion (Daemon) | Epic | 4 | 4/3 | **Cloak**. At the end of your turn, **Jam** a random enemy minion. | STEALTH, freeze, on:turn_end, random | 4/3 (7) + Cloak (1) + a Jam every turn (~1.5) = 9.5 of 9. |
| **Rooftop Sniper** `rooftop_sniper` | Minion | Rare | 4 | 3/2 | **Cloak**. **Boot:** Deal 2 damage to a minion. | STEALTH, damage, on_play, targets | 3/2 (5) + Cloak (1) + 2 damage (3) = 9 = budget. |
| **Swarm Wrangler** `swarm_wrangler` | Minion | Common | 4 | 2/3 | **Boot:** Summon two 1/1 Scrap Drones. | on_play, summon | 2/3 (5) + two 1/1 Drones (4) = 9 = budget, spread over three bodies. |
| **Billboard Leviathan** `billboard_leviathan` | Minion | Rare | 5 | 2/6 | **Firewall**. At the end of your turn, deal 1 damage to all enemy minions. | GUARD, damage, on:turn_end | 2/6 (8) + Firewall (1) + 1 AoE per turn (~2.5) = 11.5 of 11. |
| **Rapid-Response Medic** `rapid_response_medic` | Minion | Rare | 5 | 3/4 | **Hardlight**. **Boot:** Restore 4 Health. | BARRIER, heal, on_play, targets | 3/4 (7) + Hardlight (3) + heal 4 (2) = 12 of 11. |
| **Repo Mech** `repo_mech` | Minion (Drone) | Rare | 5 | 5/5 | **Firewall**. **Boot:** Destroy your opponent's weapon. | GUARD, destroy, on_play | 5/5 (10) + Firewall (1) = 11 = budget; the weapon kill is a free tech bonus. |
| **Maglev Juggernaut** `maglev_juggernaut` | Minion (Drone) | Epic | 6 | 6/7 | **Encrypted** | SPELLPROOF | 6/7 (13) + Encrypted (1) = 14 of 13: only minions and weapons can answer it. |
| **Dr. Lucent Varga** `varga` | Minion | Legendary | 6 | 4/6 | **Boot:** Swap the Attack and Health of all other minions. | on_play, set_stats | 4/6 (10) of 13; the swap kills 0-Attack walls, turns Firewalls into glass cannons. Chaos by design. |
| **Seawall Colossus** `seawall_colossus` | Minion | Epic | 7 | 5/8 | **Firewall**. **Redline:** **Dual-Core** | GUARD, aura, aura_add | 5/8 (13) + Firewall (1) + Redline: Dual-Core (~2) = 16 of 15. |
| **The Last Free Mind** `last_free_mind` | Minion (Daemon) | Legendary | 9 | 7/7 | **Encrypted**. At the end of your turn, transform a random enemy minion into a 0/3 Glitch with **Firewall**. | SPELLPROOF, on:turn_end, random, transform | 7/7 (14) + Encrypted (1) + a transform every turn (~4) = 19 = budget. |

### Tokens, champions and powers

| Card | Type | Cost | Stats | Text | Engine primitives |
|---|---|---|---|---|---|
| **Iris Null** `iris_null` | Champion (GHOST) | - | 30 HP | Ghost. She rides the Lattice and leaves no trace. |  |
| **Mother Rust** `mother_rust` | Champion (CHROME) | - | 30 HP | Chromehead. Boss of the Rust Saints; her arm settles every argument. |  |
| **Director Vale** `director_vale` | Champion (EXEC) | - | 30 HP | Executive. Security chief of Sunvault Consolidated; everything is an asset. |  |
| **Siphon** `siphon` | Power (GHOST) | 3 | - | Deal 1 damage to a minion. If it dies, draw a card. | damage, draw, if, power, targets |
| **Shakedown** `shakedown` | Power (CHROME) | 2 | - | Deal 2 damage to the enemy champion. Gain 1 Plating. | damage, gain_armor, power |
| **Deploy** `deploy` | Power (EXEC) | 2 | - | Summon a 0/2 Sentry Drone with **Firewall**. | power, summon |
| **Jumpstart** `jumpstart` | Spell (NEUTRAL) | 0 | - | Gain 1 Mana this turn only. | gain_mana, spell |
| **Sentry Drone** `sentry_drone` | Minion (EXEC) | 1 | 0/2 | **Firewall** | GUARD |
| **Scrap Drone** `scrap_drone` | Minion (NEUTRAL) | 1 | 1/1 |  |  |
| **Glitch** `glitch` | Minion (NEUTRAL) | 1 | 0/3 | **Firewall** | GUARD |
| **Hound Shard** `hound_shard` | Minion (GHOST) | 1 | 2/1 |  |  |
| **Hard Reset** `hard_reset` | Spell (EXEC) | 2 | - | **Wipe** a minion. | silence, spell, targets |
| **Retention Bonus** `retention_bonus` | Spell (EXEC) | 2 | - | Give a minion +2 Health and **Firewall**. | buff, set_tag, spell, targets |

### Starter decks

**Hostile Merger** (`decks/hostile_merger.json`, Director Vale): 2x Executive Decision (1), 2x Field Auditor (1), 1x Protocol: Lockout (1), 1x Patch Job (1), 2x Severance (1), 2x Signal Jammer (1), 1x Protocol: Asset Seizure (2), 1x Protocol: Golden Parachute (2), 2x Grid Overseer (2), 2x Medic Drone (2), 2x Club Bouncer (2), 1x Night Market Cook (3), 2x Riot Sentinel (4), 2x Swarm Wrangler (4), 2x Vat-Grown Clone (5), 1x Rapid-Response Medic (5), 1x Repo Mech (5), 1x Enforcement Mech (6), 1x Maglev Juggernaut (6), 1x ARCHON, Executive Intelligence (8)

Curve: 0: 0 | 1: 10 | 2: 8 | 3: 1 | 4: 4 | 5: 4 | 6: 2 | 7+: 1 | minions 22, spells 8, weapons 0

**Redline Rush** (`decks/redline_rush.json`, Mother Rust): 2x Nitro Shot (1), 2x Rust Shiv (1), 2x Stim Junkie (1), 2x Neon Moth (1), 1x Chrome Up (2), 2x Fence the Goods (2), 2x Hot Courier (2), 2x Chrome Stray (2), 2x Knockoff Mech (2), 2x Back-Alley Bomb (3), 2x Chain Whip (3), 1x Scrap Bruiser (3), 2x Glasshound Runner (3), 2x Pawn Shark (4), 1x Rooftop Sniper (4), 1x Hydraulic Maul (5), 1x Ramraider (6), 1x Vulka, the Scrap Saint (7)

Curve: 0: 0 | 1: 8 | 2: 9 | 3: 7 | 4: 3 | 5: 1 | 6: 1 | 7+: 1 | minions 18, spells 7, weapons 5

**Zero Trace** (`decks/zero_trace.json`, Iris Null): 1x Ghostwalk (1), 2x Zero-Day (1), 2x Courier Drone (1), 2x Cache Raid (2), 2x Signal Leech (2), 2x Static Lock (3), 2x Chrome Stray (2), 2x Corrupt (3), 1x Firmware Rot (3), 2x Lattice Diver (3), 2x Bit-Rot Daemon (3), 2x Packet Storm (4), 1x Recursive Hound (4), 1x Lattice Phantom (4), 2x Rooftop Sniper (4), 1x Root Access (5), 1x Billboard Leviathan (5), 1x Compiler Wyrm (6), 1x SABLE, the Unwritten (7)

Curve: 0: 0 | 1: 5 | 2: 6 | 3: 9 | 4: 6 | 5: 2 | 6: 1 | 7+: 1 | minions 17, spells 13, weapons 0

<!-- cards:end -->

## 7. Starter decks and game plans

- **Zero Trace** (Iris Null): control the board with Jam and cheap removal,
  turn on Chain with 1-mana spells, refill with Cache Raid and Siphon; close
  with Lattice Phantom, Billboard Leviathan, Compiler Wyrm and SABLE.
- **Redline Rush** (Mother Rust): cheap minions and weapons on turns 1–3,
  Nitro Shot / Hot Courier / Ramraider for reach, Shakedown every spare turn;
  Fence the Goods refuels, Hydraulic Maul and Vulka stabilise against aggro.
- **Hostile Merger** (Director Vale): Firewall walls and Protocols early,
  Drones + Grid Overseer mid-game, Enforcement Mech and ARCHON late; Severance
  and Executive Decision answer threats.

## 8. Art, sound and music

- One style for all pictures (`tools/neon_art.py` `STYLE`): a cyberpunk noir
  digital painting — rain-soaked neon megacity at night, wet reflective
  surfaces, chrome and glass, magenta / cyan / amber neon, haze and rain, high
  contrast, one clear subject, no text. Each card has its own concept (`look`).
- Pictures: every card, token, champion and power (73), plus `card_back`
  (2:3), `logo`, `board` (table) and `menu` backgrounds (16:9).
- Sounds: the client's event names (`game/sound.gd`), synthesized: FM bells,
  bit-crushed hits, detuned saws, filtered noise (`tools/neon_audio.py`).
- Music: three synthwave loops — `menu` (A minor, 96 bpm), `battle_1`
  (E minor, 118 bpm), `battle_2` (D minor, 126 bpm): four-on-the-floor drums,
  saw bass, kick-ducked pad, dotted-echo arpeggio, a generated lead motif.

## 9. Balance passes (phase E1, then the opening and the bot)

**How it was measured.** `rust/engine/tests/neon.rs` `simulate` plays the
engine's greedy bot (`rust/engine/src/bot.rs`, one-step look-ahead) against
itself, every pair of champions, both seat orders (each side goes first in
half the games), with the three starter decks and with random legal decks
(30 cards from the champion's class and the neutrals, at most 2 copies, 1
legendary). In this pass the bot's value counted a card in hand but not a
trap in play, so on its own it never played a Protocol; the simulation played
an affordable Protocol whenever the bot would end its turn. Since the second
pass (below) the simulation is the in-game bot with the pack's `bot` settings.
Mirrors are not played; a champion's rate is over its two matchups, a draw
counts half.

```sh
cd rust
NEON_SIM=1000 cargo test --release -p classichs-engine --test neon simulate -- --nocapture
# NEON_DECKS=starter|random|both, NEON_PAIR=iris_null,director_vale (one matchup),
# NEON_ALL=1 (every card's win rate when played), NEON_TRACE=1 (a game log)
```

1000 games per pairing and seat order, 6000 games per deck mode, ~55 s on
all cores.

| | Before: starter | Before: random | After: starter | After: random |
|---|---|---|---|---|
| Director Vale | 39.9 % | 41.9 % | 50.5 % | 48.0 % |
| Iris Null | **69.2 %** | **64.3 %** | 51.6 % | 53.2 % |
| Mother Rust | 40.9 % | 43.8 % | 47.9 % | 48.8 % |
| Vale vs Iris | **21.1 %** | **33.3 %** | 37.9 % | 44.5 % |
| Vale vs Rust | 58.8 % | 50.5 % | 63.1 % | 51.5 % |
| Iris vs Rust | 59.5 % | 62.0 % | 41.1 % | 51.0 % |
| Average length | 19.5 turns | 20.1 turns | 18.5 turns | 19.5 turns |
| First player wins | 61.4 % | 64.6 % | 63.4 % | 66.2 % |

Target met: every champion within 45–55 %, no matchup outside 35–65 %. The
starter decks keep a rock-paper-scissors shape (Vale's walls beat Rust's
aggro, Rust outraces Iris, Iris outvalues Vale); random decks are flatter.

**Changes** (each tried alone first, 500 games per pairing and seat; the
paired seeds make an untouched matchup repeat exactly, so small shifts are
real):

| Card | Before | After | Why (measured alone, starter decks) |
|---|---|---|---|
| Siphon (Iris power) | (2) | **(3)** | The draw on kill is a card every turn against Drones and 1-health bodies; without the draw Iris fell 10 points. At (3): Iris −6, Vale vs Iris +6, text unchanged. |
| Shakedown (Rust power) | 1 damage, 1 Plating | **2 damage**, 1 Plating | Rust lost to Firewall walls; damage that ignores Firewall: Rust +11, Vale vs Rust −8 (text changed in all 8 locales). |
| Field Auditor | 1/2 | **2/2** | Executive bodies had no Attack: Vale vs Iris +3, Vale vs Rust −2. |
| Medic Drone | 1/3 | **2/3** | Vale vs Iris +4. |
| Grid Overseer | (3) | **(2)** | Drones with Attack early; with the two above: Vale vs Iris +5. |
| Executive Decision | (2) | **(1)** | Rarely worth a card at (2) (33 % when played, random decks). |
| Protocol: Lockout | (2) | **(1)** | Weakest Executive cards in random decks (34 %, 31 %); together with Executive Decision: random Vale +3. |
| Protocol: Asset Seizure | (3) | **(2)** | |
| Lattice Diver | 3/2 | **3/3** | After the Siphon nerf Iris lost too much to Rust: Iris vs Rust +3, Vale vs Iris −4. |

**The risky cards of §5** were tested and left as designed: Deploy's Sentry
Drone at 1/2 lifts Vale vs Rust by 14 points (the 0/2 wall is not too strong
for the bot; a stronger one would be); Root Access at (6) moved Iris by only
1 point; Packet Storm at (5), or no Packet Storm at all, made Iris *stronger*
(the bot uses the slot better), so its Chain is not the problem; ARCHON at (7)
moved Vale by 1 point (it wins 54 % / 58 % when played, no snowball); Fence
the Goods and Varga are average or below (41–46 %, 50 %).
Other single changes tried and dropped: Corrupt (4), Static Lock (3),
Billboard Leviathan 2/5, Riot Sentinel 3/5, Vat-Grown Clone (4), Lattice
Phantom 3/3, Bit-Rot Daemon 2/3, Cache Raid (3), SABLE 5/5, Signal Leech 1/1,
Chain Whip without Heat, Signal Jammer 1/3 and Club Bouncer 2/3 (neutral
buffs that helped the starter Vale but left random Executive decks at 42 %).

**Win rate when played** (the player who played the card at least once;
biased toward cards played when already ahead, e.g. Jumpstart 80 %+ and
Sentry Drone 20 %, a Deploy that never got used is not counted).
After, starter decks: highest Billboard Leviathan 69 %, Static Lock 68 %,
Lattice Phantom 64 %, Cache Raid 60 %; lowest Asset Seizure 38 %, Fence the
Goods 41 %, Chain Whip 42 %, Scrap Bruiser 42 %. Random decks: highest
Seawall Colossus, Corrupt 61 %, Packet Storm, SABLE, Billboard Leviathan
59 %; lowest Asset Seizure 37 %, Severance 37 %, Chain Whip 41 %. Before, the
spread was 33–81 % (starter) and 31–71 % (random). Watch next: Billboard
Leviathan and Static Lock (Iris's best cards), and the Protocols, whose
numbers depend on how the bot plays them.

**Findings beyond the cards.** The first player wins 63–66 % of bot games
(Jumpstart is only one temporary Mana); a rules change (a second Jumpstart or
a card more) would be the next lever, not in this pass. The in-game bot never
plays a Protocol (see above). Both are the second pass below.

### Second pass: the opening and the bot

**The bot.** Two pack settings (`rules.json` `bot`, docs/packs/rules.md;
Classic leaves them out, so its bot and the parity fixtures stay as recorded):

- `trap: 2`: the bot counts each of its Protocols in play as 2 (a card in
  hand is 1), so it plays an affordable Protocol when nothing better is left,
  as the E1 simulation did by hand (same numbers to 0.1 point). The
  simulation's workaround is gone.
- `depth: 2`: before ending its turn the bot also tries two actions in a row.
  The one-step bot played the second player's Jumpstart in only 2–8 % of games
  (a card that pays off only with the next one looks like a lost card), and a
  spell only to turn on a Chain never. With `depth: 2` it plays Jumpstart in
  nearly every game it gets it, and Chains like a player would. The first
  player's 63–66 % was largely the bot wasting Jumpstart: with `depth: 2`
  alone it is 56–60 %.

**The opening.** The engine's levers (`start` in rules.json): opening hands,
the coin, and `first_player_draws` (new; true is Classic). Measured first
player win rates (starter / random decks, 1000 games per pairing and seat):

| Opening | One-step bot | `depth: 2` |
|---|---|---|
| `[3, 4]` + Jumpstart (E1) | 63.4 / 66.2 % | 55.8 / 60.2 % |
| `[3, 5]` + Jumpstart | 55.2 / 60.2 % | **46.8 / 52.9 %** |
| `[3, 5]`, no Jumpstart, first player skips the first draw | 43.4 / 48.4 % | |
| `[3, 6]` + Jumpstart | 49.0 / 54.6 % | (~40 / 46 %) |
| `[4, 6]` + Jumpstart | | 49.9 / 56.6 % |
| `[3, 4]` + Jumpstart, first player skips the first draw | 50.4 / 55.4 % | 43.2 / 47.6 % |
| `[4, 5]` + Jumpstart, first player skips the first draw | 56.3 / 60.0 % | |
| `[3, 4]` + Jumpstart, second player +1 Mana crystal | 27.8 / 27.3 % | |

(The `depth: 2` column for `[3, 6]` and the skipped draw is a bot that plays
Jumpstart when it pays for a play right away, the test that led to `depth`.)
Random decks always favour the first player by 5–6 points more than the
starter decks, so no opening puts both inside 48–55 %; `[3, 5]` is the one
closest to 50 % on average (49.6 %) and the second player's extra card is
the simplest rule to explain. A permanent Mana crystal is far too much, so
the engine has no such setting. Tuning the opening against the one-step bot
(`[3, 6]`) would have favoured the second player in real games, where
Jumpstart is always played.

**Cards.** A bot that plays Chain made Iris too strong (starter 57.3 %, Vale
vs Iris 32.6 %). Retuned (1000 games per pairing and seat each):

| Card | Before | After | Why (with `depth: 2`, `[3, 5]`) |
|---|---|---|---|
| Lattice Diver | 3/3 | **3/2** | Back to the E1 original: Iris starter 57.3 → 55.4 %, Vale vs Iris +3. |
| Compiler Wyrm | 4/6 | **4/5** | Iris −1, Vale vs Iris +1. |
| Static Lock | (2) | **(3)** | Iris's best card (64–68 % when played): Iris −0.6, Vale vs Iris +0.8 (Recursive Hound 3/3 instead did less: −0.2, −0.4). |

**Result** (`bot: {trap: 2, depth: 2}`, `start.hand: [3, 5]`, the cards above;
1000 games per pairing and seat order, ~50 s):

| | Before (E1): starter | Before (E1): random | After: starter | After: random |
|---|---|---|---|---|
| Director Vale | 50.5 % | 48.0 % | 46.9 % | 50.6 % |
| Iris Null | 51.6 % | 53.2 % | 53.8 % | 53.6 % |
| Mother Rust | 47.9 % | 48.8 % | 49.2 % | 45.8 % |
| Vale vs Iris | 37.9 % | 44.5 % | 36.8 % | 47.0 % |
| Vale vs Rust | 63.1 % | 51.5 % | 57.1 % | 54.2 % |
| Iris vs Rust | 41.1 % | 51.0 % | 44.4 % | 54.1 % |
| Average length | 18.5 turns | 19.5 turns | 18.6 turns | 19.5 turns |
| First player wins | **63.4 %** | **66.2 %** | 46.5 % | 52.6 % |

Champions 45.8–53.8 %, matchups 36.8–57.1 %; the first player wins 46.5 %
(starter) and 52.6 % (random). With 3000 games per pairing and seat (before
Static Lock) the numbers moved by up to 1.6 points.

Win rate when played, after: starter decks highest Billboard Leviathan 69 %,
Lattice Phantom 65 %, Static Lock 64 %; lowest Asset Seizure 34 %, Lockout
40 %, Golden Parachute 41 %. Random decks highest Packet Storm 61 %,
Billboard Leviathan 59 %; lowest Asset Seizure 37 %, Chrome Up 41 %. The
Protocols (Asset Seizure, Lockout, Golden Parachute: 34–43 %) are the weakest
cards as the bot plays them (leftover Mana, no timing); a person may find
them better. Watch next: Billboard Leviathan, Lattice Phantom, the Protocols.
